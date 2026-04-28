"""
Ball Rotation & Wobble Analyzer
ECE 445 - Sensor Integrated Putter - Kyle Smith

Connects to the ESP32-S3 OV5640 WiFi stream.
Camera runs continuously. Press SPACE to simulate piezo trigger.
Captures 3 seconds of post-trigger frames and runs full analysis.

Install:
    pip install opencv-python numpy

Usage:
    python ball_analyzer.py

Controls:
    SPACE = simulate piezo impact trigger
    q     = quit
    c     = calibration mode (tune HoughCircles param2 live)
"""

import math
from collections import deque
import threading
import time
import urllib.request

import cv2
import numpy as np

# ---- CONFIG ----
STREAM_URL = "http://192.168.4.1:81/stream"
CAPTURE_DURATION = 3.0
PRE_TRIGGER_BUFFER_SEC = 0.35
CAMERA_FPS = 13.0  # fallback fps if timestamps are unavailable
STREAM_READ_CHUNK = 4096  # smaller reads reduce MJPEG buffering latency
LIVE_ANALYZE_EVERY_N_FRAMES = 2  # keep preview responsive without dropping analysis entirely
# ----------------

# ---- BALL DETECTION (shape-based, lighting independent) ----
HOUGH_DP = 1.2
HOUGH_PARAM1 = 60
HOUGH_PARAM2 = 28
HOUGH_MIN_RADIUS = 5
HOUGH_MAX_RADIUS = 15
WHITE_S_MAX = 105
WHITE_GRAY_MIN = 115
WHITE_GRAY_PERCENTILE = 65
CONTOUR_MIN_CIRCULARITY = 0.45
CONTOUR_MIN_FILL = 0.45
MIN_BALL_SCORE = 1.05
RING_CONTRAST_WEIGHT = 0.8
SURROUND_CONTRAST_WEIGHT = 0.55
TRACK_POSITION_WEIGHT = 0.95
TRACK_RADIUS_WEIGHT = 0.3
TRACK_MAX_MISSES = 6
TRACK_MIN_FEATURES = 5
TRACK_MIN_SCORE = 1.0
TRACK_MAX_ERROR = 24.0
TRACK_POINT_QUALITY = 0.03
TRACK_POINT_COUNT = 24
# -----------------------------------------------------------

DRIFT_THRESHOLD_DEG = 2.0   # path drift below this = "good" straight roll

# ---- LOW LIGHT ADAPTATION ----
LOW_LIGHT_THRESHOLD = 90          # mean raw brightness (0-255) below this = low-light mode
LOW_LIGHT_GAMMA = 0.55            # gamma < 1 brightens dark frames before processing
LOW_LIGHT_CLAHE_CLIP = 5.0        # more aggressive CLAHE clip limit in low light
LOW_LIGHT_GRAY_MIN = 50           # lower brightness floor for white mask in low light
LOW_LIGHT_CANNY_LO = 20           # Canny low threshold in low light
LOW_LIGHT_CANNY_HI = 60           # Canny high threshold in low light
LOW_LIGHT_HOUGH_PARAM1 = 40       # HoughCircles Canny threshold in low light
LOW_LIGHT_HOUGH_PARAM2_DELTA = 10 # subtract from param2 vote threshold in low light
LOW_LIGHT_CONTRAST_BOOST = 0.6    # extra weight added to contrast terms in low light
# --------------------------------

_clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
_clahe_low_light = cv2.createCLAHE(clipLimit=LOW_LIGHT_CLAHE_CLIP, tileGridSize=(6, 6))
_gamma_lut = np.array([((i / 255.0) ** LOW_LIGHT_GAMMA) * 255 for i in range(256)], dtype=np.uint8)


def open_stream():
    """Open a persistent HTTP connection to the ESP32 MJPEG stream."""
    return urllib.request.urlopen(STREAM_URL, timeout=10)


class StreamReader(threading.Thread):
    """
    Background thread that continuously reads and decodes MJPEG frames.
    The main loop calls get_frame() to get the latest decoded frame without
    blocking on network I/O. Older frames are overwritten automatically.
    """

    def __init__(self, stream):
        super().__init__(daemon=True)
        self._stream = stream
        self._frame = None
        self._frame_id = 0
        self._lock = threading.Lock()
        self._running = True
        self.error = None

    def run(self):
        buf = b""
        while self._running:
            try:
                chunk = self._stream.read(STREAM_READ_CHUNK)
                if not chunk:
                    self.error = "stream ended"
                    break
                buf += chunk

                while True:
                    cl_idx = buf.find(b"Content-Length:")
                    if cl_idx == -1:
                        break

                    eol = buf.find(b"\r\n", cl_idx)
                    if eol == -1:
                        break

                    try:
                        frame_len = int(buf[cl_idx + 15:eol].strip())
                    except ValueError:
                        buf = buf[cl_idx + 1:]
                        continue

                    header_end = buf.find(b"\r\n\r\n", cl_idx)
                    if header_end == -1:
                        break

                    data_start = header_end + 4
                    data_end = data_start + frame_len
                    if len(buf) < data_end:
                        break

                    jpg = buf[data_start:data_end]
                    buf = buf[data_end:]

                    arr = np.frombuffer(jpg, dtype=np.uint8)
                    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                    if frame is not None:
                        with self._lock:
                            self._frame = frame
                            self._frame_id += 1

                if len(buf) > 500000:
                    buf = b""

            except Exception as e:
                self.error = str(e)
                break

        self._running = False

    def get_frame(self):
        """Return (frame, frame_id). frame_id increments for each new frame."""
        with self._lock:
            return self._frame, self._frame_id

    def stop(self):
        self._running = False

    @property
    def alive(self):
        return self.is_alive() and self._running


def build_white_mask(gray_eq, hsv, low_light=False):
    """Highlight low-saturation bright regions, which fits a white golf ball."""
    floor_min = LOW_LIGHT_GRAY_MIN if low_light else WHITE_GRAY_MIN
    bright_floor = max(floor_min, int(np.percentile(gray_eq, WHITE_GRAY_PERCENTILE)))
    low_sat_mask = cv2.inRange(hsv, (0, 0, 0), (180, WHITE_S_MAX, 255))
    bright_mask = cv2.inRange(gray_eq, bright_floor, 255)
    white_mask = cv2.bitwise_and(low_sat_mask, bright_mask)

    kernel = np.ones((3, 3), dtype=np.uint8)
    white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_OPEN, kernel)
    white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_CLOSE, kernel)
    return white_mask


def add_candidate(candidates, cx, cy, radius):
    """Keep one copy of each nearby circle candidate."""
    cx = int(round(cx))
    cy = int(round(cy))
    radius = int(round(radius))

    if radius < HOUGH_MIN_RADIUS or radius > HOUGH_MAX_RADIUS:
        return

    for existing in candidates:
        if (
            abs(existing[0] - cx) <= 2
            and abs(existing[1] - cy) <= 2
            and abs(existing[2] - radius) <= 2
        ):
            return
    candidates.append((cx, cy, radius))


def build_tracking_mask(shape, cx, cy, radius):
    """Favor features on the ball body and equator, not the far background."""
    mask = np.zeros(shape, dtype=np.uint8)
    outer_r = max(int(radius * 0.95), 2)
    inner_r = max(int(radius * 0.25), 1)
    cv2.circle(mask, (cx, cy), outer_r, 255, -1)
    cv2.circle(mask, (cx, cy), inner_r, 0, -1)
    return mask


def refresh_tracker_points(gray_eq, cx, cy, radius):
    """Pick fresh trackable points from the current ball ROI."""
    mask = build_tracking_mask(gray_eq.shape, cx, cy, radius)
    points = cv2.goodFeaturesToTrack(
        gray_eq,
        maxCorners=TRACK_POINT_COUNT,
        qualityLevel=TRACK_POINT_QUALITY,
        minDistance=max(radius * 0.35, 3),
        blockSize=5,
        mask=mask,
    )

    if points is None or len(points) < TRACK_MIN_FEATURES:
        return None
    return points.astype(np.float32)


def initialize_ball_tracker(gray_eq, cx, cy, radius):
    """Initialize motion tracking from a confirmed ball detection."""
    points = refresh_tracker_points(gray_eq, cx, cy, radius)
    if points is None:
        return None

    return {
        "prev_gray": gray_eq.copy(),
        "points": points,
        "cx": int(cx),
        "cy": int(cy),
        "radius": int(radius),
    }


def odd_clamped(value, low, high):
    """Clamp a kernel size to an odd integer in [low, high]."""
    value = int(round(value))
    value = max(low, min(high, value))
    if value % 2 == 0:
        value += 1
    return min(value, high if high % 2 == 1 else high - 1)




def score_ball_candidate(gray_eq, hsv, white_mask, edge_map, cx, cy, radius, tracking_hint=None, low_light=False):
    """Score how much a candidate looks like a bright, circular golf ball."""
    h, w = gray_eq.shape

    if (
        cx - radius < 0
        or cy - radius < 0
        or cx + radius >= w
        or cy + radius >= h
    ):
        return -1.0

    inner_r = max(int(radius * 0.65), 2)
    ring_inner = max(int(radius * 0.85), inner_r + 1)
    ring_outer = max(int(radius * 1.15), ring_inner + 1)
    surround_outer = max(int(radius * 1.65), ring_outer + 1)

    if (
        cx - surround_outer < 0
        or cy - surround_outer < 0
        or cx + surround_outer >= w
        or cy + surround_outer >= h
    ):
        surround_outer = ring_outer

    inner_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(inner_mask, (cx, cy), inner_r, 255, -1)

    ring_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(ring_mask, (cx, cy), ring_outer, 255, -1)
    cv2.circle(ring_mask, (cx, cy), ring_inner, 0, -1)

    surround_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(surround_mask, (cx, cy), surround_outer, 255, -1)
    cv2.circle(surround_mask, (cx, cy), ring_outer, 0, -1)

    inner_pixels = cv2.countNonZero(inner_mask)
    ring_pixels = cv2.countNonZero(ring_mask)
    surround_pixels = cv2.countNonZero(surround_mask)
    if inner_pixels == 0 or ring_pixels == 0:
        return -1.0

    white_ratio = cv2.countNonZero(cv2.bitwise_and(white_mask, inner_mask)) / inner_pixels
    edge_ratio = cv2.countNonZero(cv2.bitwise_and(edge_map, ring_mask)) / ring_pixels
    mean_gray = cv2.mean(gray_eq, mask=inner_mask)[0] / 255.0
    mean_sat = cv2.mean(hsv[:, :, 1], mask=inner_mask)[0] / 255.0
    ring_gray = cv2.mean(gray_eq, mask=ring_mask)[0] / 255.0
    surround_gray = ring_gray
    if surround_pixels > 0:
        surround_gray = cv2.mean(gray_eq, mask=surround_mask)[0] / 255.0

    ring_contrast = max(0.0, mean_gray - ring_gray)
    surround_contrast = max(0.0, mean_gray - surround_gray)

    # In low light, absolute brightness is unreliable; rely more on local contrast.
    contrast_boost = LOW_LIGHT_CONTRAST_BOOST if low_light else 0.0
    gray_weight = 0.2 if low_light else 0.45
    score = (
        1.8 * white_ratio
        + 1.2 * edge_ratio
        + gray_weight * mean_gray
        + 0.25 * (1.0 - mean_sat)
        + (RING_CONTRAST_WEIGHT + contrast_boost) * ring_contrast
        + (SURROUND_CONTRAST_WEIGHT + contrast_boost) * surround_contrast
    )

    if tracking_hint is not None:
        prev_cx, prev_cy, prev_radius = tracking_hint
        prev_radius = max(prev_radius, 1)
        dist = math.hypot(cx - prev_cx, cy - prev_cy)
        pos_scale = max(prev_radius * 4.0, 14.0)
        pos_bonus = max(0.0, 1.0 - dist / pos_scale)
        radius_bonus = max(0.0, 1.0 - abs(radius - prev_radius) / max(prev_radius * 0.75, 2.0))
        score += TRACK_POSITION_WEIGHT * pos_bonus + TRACK_RADIUS_WEIGHT * radius_bonus

    return score


def find_best_ball_candidate(gray_eq, blurred, hsv, white_mask, edge_map, hough_param2, tracking_hint=None, hough_param1=None, low_light=False):
    """Combine Hough-circle and white-contour candidates, then rank them."""
    h, w = gray_eq.shape
    candidates = []
    effective_param1 = hough_param1 if hough_param1 is not None else HOUGH_PARAM1

    circles = cv2.HoughCircles(
        blurred,
        cv2.HOUGH_GRADIENT,
        dp=HOUGH_DP,
        minDist=w // 3,
        param1=effective_param1,
        param2=hough_param2,
        minRadius=HOUGH_MIN_RADIUS,
        maxRadius=HOUGH_MAX_RADIUS,
    )
    if circles is not None:
        for circle in np.round(circles[0]).astype(int):
            add_candidate(candidates, circle[0], circle[1], circle[2])

    contours, _ = cv2.findContours(white_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < 40:
            continue

        perimeter = cv2.arcLength(contour, True)
        if perimeter <= 0:
            continue

        circularity = 4.0 * math.pi * area / (perimeter * perimeter)
        if circularity < CONTOUR_MIN_CIRCULARITY:
            continue

        (cx, cy), radius = cv2.minEnclosingCircle(contour)
        if radius < HOUGH_MIN_RADIUS or radius > HOUGH_MAX_RADIUS:
            continue

        fill_ratio = area / max(math.pi * radius * radius, 1.0)
        if fill_ratio < CONTOUR_MIN_FILL:
            continue

        add_candidate(candidates, cx, cy, radius)

    scored_candidates = []
    for cx, cy, radius in candidates:
        score = score_ball_candidate(
            gray_eq,
            hsv,
            white_mask,
            edge_map,
            cx,
            cy,
            radius,
            tracking_hint=tracking_hint,
            low_light=low_light,
        )
        if score > 0:
            scored_candidates.append((cx, cy, radius, score))

    scored_candidates.sort(key=lambda item: item[3], reverse=True)
    if not scored_candidates or scored_candidates[0][3] < MIN_BALL_SCORE:
        return None, scored_candidates

    return scored_candidates[0], scored_candidates


def track_ball_motion(gray_eq, hsv, white_mask, edge_map, tracker_state, low_light=False):
    """Track the locked ball between frames using optical flow."""
    if tracker_state is None or tracker_state.get("points") is None:
        return None, None

    prev_gray = tracker_state["prev_gray"]
    prev_points = tracker_state["points"]
    if prev_points is None or len(prev_points) < TRACK_MIN_FEATURES:
        return None, None

    next_points, status, err = cv2.calcOpticalFlowPyrLK(
        prev_gray,
        gray_eq,
        prev_points,
        None,
        winSize=(15, 15),
        maxLevel=2,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 10, 0.03),
    )
    if next_points is None or status is None:
        return None, None

    status = status.reshape(-1).astype(bool)
    good_old = prev_points.reshape(-1, 2)[status]
    good_new = next_points.reshape(-1, 2)[status]
    if err is not None:
        good_err = err.reshape(-1)[status]
        keep = good_err <= TRACK_MAX_ERROR
        good_old = good_old[keep]
        good_new = good_new[keep]

    if len(good_new) < TRACK_MIN_FEATURES:
        return None, None

    displacement = np.median(good_new - good_old, axis=0)
    prev_cx = tracker_state["cx"]
    prev_cy = tracker_state["cy"]
    prev_radius = tracker_state["radius"]
    cx = int(round(prev_cx + displacement[0]))
    cy = int(round(prev_cy + displacement[1]))

    old_center = np.array([prev_cx, prev_cy], dtype=np.float32)
    new_center = np.array([cx, cy], dtype=np.float32)
    old_dist = np.linalg.norm(good_old - old_center, axis=1)
    new_dist = np.linalg.norm(good_new - new_center, axis=1)
    valid_scale = old_dist > 1.0
    radius = prev_radius
    if np.count_nonzero(valid_scale) >= TRACK_MIN_FEATURES:
        scales = np.clip(new_dist[valid_scale] / old_dist[valid_scale], 0.8, 1.25)
        radius = int(round(prev_radius * float(np.median(scales))))
    radius = int(np.clip(radius, HOUGH_MIN_RADIUS, HOUGH_MAX_RADIUS))

    score = score_ball_candidate(
        gray_eq,
        hsv,
        white_mask,
        edge_map,
        cx,
        cy,
        radius,
        tracking_hint=(prev_cx, prev_cy, prev_radius),
        low_light=low_light,
    )
    if score < TRACK_MIN_SCORE:
        return None, None

    refreshed_points = refresh_tracker_points(gray_eq, cx, cy, radius)
    if refreshed_points is None:
        refreshed_points = good_new.reshape(-1, 1, 2).astype(np.float32)
        if len(refreshed_points) < TRACK_MIN_FEATURES:
            return None, None

    new_tracker_state = {
        "prev_gray": gray_eq.copy(),
        "points": refreshed_points,
        "cx": cx,
        "cy": cy,
        "radius": radius,
    }
    tracked_candidate = (cx, cy, radius, score)
    tracked_points = good_new
    return (tracked_candidate, tracked_points), new_tracker_state




def process_frame(frame, hough_param2=None, tracking_hint=None, tracker_state=None, prev_center=None):
    """
    Find the ball and draw an orientation line in the direction of motion.

    Returns:
        result dict  (ball_found, cx, cy, radius, debug_frame, tracking_mode)
        tracker_state
    """
    if hough_param2 is None:
        hough_param2 = HOUGH_PARAM2

    debug = frame.copy()

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    mean_brightness = float(np.mean(gray))
    low_light = mean_brightness < LOW_LIGHT_THRESHOLD

    if low_light:
        gray = cv2.LUT(gray, _gamma_lut)
        gray_eq = _clahe_low_light.apply(gray)
        blurred = cv2.bilateralFilter(gray_eq, 9, 30, 30)
        canny_lo, canny_hi = LOW_LIGHT_CANNY_LO, LOW_LIGHT_CANNY_HI
        hough_p1 = LOW_LIGHT_HOUGH_PARAM1
        hough_p2 = max(hough_param2 - LOW_LIGHT_HOUGH_PARAM2_DELTA, 12)
    else:
        gray_eq = _clahe.apply(gray)
        blurred = cv2.GaussianBlur(gray_eq, (9, 9), 2)
        canny_lo, canny_hi = 45, 110
        hough_p1 = HOUGH_PARAM1
        hough_p2 = hough_param2

    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    white_mask = build_white_mask(gray_eq, hsv, low_light=low_light)
    edge_map = cv2.Canny(blurred, canny_lo, canny_hi)

    tracking_mode = "detect"
    tracked_points = None
    tracked_result, tracker_state = track_ball_motion(
        gray_eq, hsv, white_mask, edge_map, tracker_state, low_light=low_light
    )
    if tracked_result is not None:
        best_candidate, tracked_points = tracked_result
        scored_candidates = [best_candidate]
        tracking_mode = "track"
    else:
        if tracking_hint is None and tracker_state is not None:
            tracking_hint = (
                tracker_state["cx"],
                tracker_state["cy"],
                tracker_state["radius"],
            )
        best_candidate, scored_candidates = find_best_ball_candidate(
            gray_eq=gray_eq,
            blurred=blurred,
            hsv=hsv,
            white_mask=white_mask,
            edge_map=edge_map,
            hough_param2=hough_p2,
            tracking_hint=tracking_hint,
            hough_param1=hough_p1,
            low_light=low_light,
        )
        if best_candidate is not None:
            tracker_state = initialize_ball_tracker(
                gray_eq,
                best_candidate[0],
                best_candidate[1],
                best_candidate[2],
            )

    if best_candidate is None:
        return {
            "ball_found": False,
            "debug_frame": debug,
            "tracking_mode": tracking_mode,
        }, None

    cx, cy, radius, best_score = best_candidate

    if tracked_points is not None:
        for point in tracked_points[:12]:
            px, py = np.round(point).astype(int)
            cv2.circle(debug, (px, py), 1, (255, 200, 0), -1)

    for cand_cx, cand_cy, cand_radius, cand_score in scored_candidates[:4]:
        color = (0, 180, 255)
        if (cand_cx, cand_cy, cand_radius) == (cx, cy, radius):
            color = (0, 255, 0)
        cv2.circle(debug, (cand_cx, cand_cy), cand_radius, color, 1)
        cv2.putText(
            debug,
            "{:.2f}".format(cand_score),
            (cand_cx + cand_radius + 2, cand_cy - 4),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.35,
            color,
            1,
        )

    cv2.circle(debug, (cx, cy), radius, (0, 255, 0), 2)
    cv2.circle(debug, (cx, cy), 3, (0, 255, 0), -1)
    cv2.putText(
        debug,
        "r={} score={:.2f} {}{}".format(radius, best_score, tracking_mode, " [LL]" if low_light else ""),
        (cx + radius + 4, cy),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.4,
        (0, 255, 0),
        1,
    )

    # Draw orientation line through ball center in the direction of motion.
    if prev_center is not None:
        dx = cx - prev_center[0]
        dy = cy - prev_center[1]
        dist = math.hypot(dx, dy)
        if dist > 0.5:
            nx, ny = dx / dist, dy / dist
            half_len = max(radius * 1.4, 10.0)
            ox1 = int(round(cx - nx * half_len))
            oy1 = int(round(cy - ny * half_len))
            ox2 = int(round(cx + nx * half_len))
            oy2 = int(round(cy + ny * half_len))
            # Lateral deviation from vertical (ball always moves top-to-bottom).
            lateral_deg = math.degrees(math.atan2(dx, max(dy, 0.1)))
            lateral_abs = abs(lateral_deg)
            if lateral_abs < DRIFT_THRESHOLD_DEG:
                orient_color = (0, 220, 0)
            elif lateral_abs < 10.0:
                orient_color = (0, 165, 255)
            else:
                orient_color = (0, 0, 255)
            cv2.line(debug, (ox1, oy1), (ox2, oy2), orient_color, 2)
            drift_dir = "R" if lateral_deg > 0 else "L"
            cv2.putText(
                debug,
                "drift {:.1f}deg {}".format(lateral_abs, drift_dir),
                (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 255, 255),
                2,
            )

    return {
        "ball_found": True,
        "cx": cx,
        "cy": cy,
        "radius": radius,
        "debug_frame": debug,
        "tracking_mode": tracking_mode,
    }, tracker_state


def analyze_putt(frames, fps):
    """Process all captured frames and compute path drift and roll straightness."""
    results = []
    tracker_state = None
    tracking_hint = None
    tracking_misses = 0
    centers = []  # (cx, cy) for each frame where ball was found
    radii = []

    for i, frame in enumerate(frames):
        # Pass center from 2 frames ago as the orientation reference — averaging
        # over a 2-step window smooths out per-frame jitter from camera shake.
        prev_center = centers[-2] if len(centers) >= 2 else (centers[-1] if centers else None)
        result, tracker_state = process_frame(
            frame,
            tracking_hint=tracking_hint,
            tracker_state=tracker_state,
            prev_center=prev_center,
        )
        results.append(result)
        if result["ball_found"]:
            cx, cy, r = result["cx"], result["cy"], result["radius"]
            centers.append((cx, cy))
            radii.append(r)
            tracking_hint = (cx, cy, r)
            tracking_misses = 0
        else:
            tracking_misses += 1
            if tracking_misses >= TRACK_MAX_MISSES:
                tracking_hint = None
                tracker_state = None

    total = len(frames)
    tracked = len(centers)
    tracking_quality_pct = round(tracked / max(total, 1) * 100, 1)
    avg_radius_px = round(float(sum(radii) / max(len(radii), 1)), 1)

    empty = {
        "path_drift_deg": 0.0,
        "rms_lateral_px": 0.0,
        "max_lateral_px": 0.0,
        "total_path_px": 0.0,
        "direction_wobble_deg": 0.0,
        "avg_radius_px": avg_radius_px,
        "tracking_quality_pct": tracking_quality_pct,
        "valid_frames": tracked,
        "total_frames": total,
        "lateral_deviations_px": [],
        "forward_positions_px": [],
        "per_frame_results": results,
    }
    if tracked < 3:
        return empty

    # Guard: fitLine is meaningless if the ball barely moved (single cluster of points).
    xs = [c[0] for c in centers]
    ys = [c[1] for c in centers]
    span = math.hypot(max(xs) - min(xs), max(ys) - min(ys))
    if span < avg_radius_px * 0.5:
        return empty

    pts = np.array(centers, dtype=np.float32)
    line_fit = cv2.fitLine(pts.reshape(-1, 1, 2), cv2.DIST_L2, 0, 0.01, 0.01).reshape(-1)
    vx, vy, x0, y0 = [float(v) for v in line_fit]

    # Ensure direction is top-to-bottom (ball always moves toward higher y).
    if vy < 0:
        vx, vy = -vx, -vy

    # Path drift = angle of best-fit line from vertical.
    # atan2(vx, vy): positive = drifts right, negative = drifts left.
    path_drift_deg = round(math.degrees(math.atan2(vx, vy)), 2)

    # Perpendicular unit vector for lateral deviation measurement.
    perp_x, perp_y = -vy, vx

    lateral_deviations = [
        (c[0] - x0) * perp_x + (c[1] - y0) * perp_y for c in centers
    ]
    forward_positions = [
        (c[0] - x0) * vx + (c[1] - y0) * vy for c in centers
    ]
    fwd_offset = forward_positions[0]
    forward_positions = [p - fwd_offset for p in forward_positions]

    rms_lateral = math.sqrt(sum(d * d for d in lateral_deviations) / tracked)
    max_lateral = max(abs(d) for d in lateral_deviations)
    total_path_px = sum(
        math.hypot(centers[i][0] - centers[i - 1][0], centers[i][1] - centers[i - 1][1])
        for i in range(1, tracked)
    )

    # Direction wobble: RMS deviation of per-frame displacement angles from the
    # best-fit direction. Only includes frames where the ball moved meaningfully
    # forward — filters out pre-trigger stationary frames and early camera-shake
    # frames where near-zero or backwards apparent motion produces garbage angles.
    min_forward_px = avg_radius_px * 0.25
    frame_angles = []
    for i in range(1, tracked):
        dx = centers[i][0] - centers[i - 1][0]
        dy = centers[i][1] - centers[i - 1][1]
        forward = dx * vx + dy * vy  # projection onto best-fit direction
        if forward > min_forward_px:
            frame_angles.append(math.degrees(math.atan2(dx, dy)))

    if len(frame_angles) >= 2:
        residuals = [a - path_drift_deg for a in frame_angles]
        direction_wobble_deg = round(
            math.sqrt(sum(r * r for r in residuals) / len(residuals)), 2
        )
    else:
        direction_wobble_deg = 0.0

    return {
        "path_drift_deg": path_drift_deg,
        "rms_lateral_px": round(rms_lateral, 1),
        "max_lateral_px": round(max_lateral, 1),
        "total_path_px": round(total_path_px, 1),
        "direction_wobble_deg": direction_wobble_deg,
        "avg_radius_px": avg_radius_px,
        "tracking_quality_pct": tracking_quality_pct,
        "valid_frames": tracked,
        "total_frames": total,
        "lateral_deviations_px": [round(d, 1) for d in lateral_deviations],
        "forward_positions_px": [round(p, 1) for p in forward_positions],
        "per_frame_results": results,
    }


def print_results(metrics):
    tracked = metrics["valid_frames"]
    total = metrics["total_frames"]
    quality = metrics.get("tracking_quality_pct", round(tracked / max(total, 1) * 100, 1))
    drift = metrics.get("path_drift_deg", 0.0)
    rms = metrics.get("rms_lateral_px", 0.0)
    mx = metrics.get("max_lateral_px", 0.0)
    avg_r = metrics.get("avg_radius_px", 0.0)
    wobble = metrics.get("direction_wobble_deg", 0.0)

    print("\n" + "=" * 50)
    print("  PATH ANALYSIS RESULTS")
    print("=" * 50)
    print("  frames tracked:      {}/{} ({:.0f}%)".format(tracked, total, quality))
    print("")

    if tracked < 3:
        print("  path drift:          n/a (tracking insufficient)")
        print("  path straightness:   n/a")
        print("  direction wobble:    n/a")
    else:
        drift_dir = "right" if drift > 0 else "left"
        drift_label = (
            "GOOD" if abs(drift) < DRIFT_THRESHOLD_DEG
            else "MODERATE" if abs(drift) < 5.0
            else "SIGNIFICANT"
        )
        rms_diam = rms / (avg_r * 2) if avg_r > 0 else 0.0
        straight_label = "VERY STRAIGHT" if rms_diam < 0.05 else "STRAIGHT" if rms_diam < 0.12 else "WOBBLY"
        wobble_label = "SMOOTH" if wobble < 2.0 else "MODERATE" if wobble < 5.0 else "WOBBLY"
        print("  path drift:          {:.2f}° {} ({})".format(abs(drift), drift_dir, drift_label))
        print("  RMS lateral dev:     {:.3f} ball diameters  ← {}".format(rms_diam, straight_label))
        print("  direction wobble:    {:.2f}° RMS  ← {}".format(wobble, wobble_label))
    print("=" * 50)
    print("")


def run_calibration(reader):
    """
    Live HoughCircles tuner.
    Adjust trackbars until only the ball is circled, then press q to save.
    """
    global HOUGH_PARAM2, HOUGH_MIN_RADIUS, HOUGH_MAX_RADIUS

    cv2.namedWindow("calibration")
    cv2.createTrackbar("param2 (votes)", "calibration", HOUGH_PARAM2, 80, lambda x: None)
    cv2.createTrackbar("min radius", "calibration", HOUGH_MIN_RADIUS, 100, lambda x: None)
    cv2.createTrackbar("max radius", "calibration", HOUGH_MAX_RADIUS, 200, lambda x: None)

    print("CALIBRATION - lower param2 to detect more circles, raise to detect fewer")
    print("  target: only the golf ball is highlighted   |   'q' to exit")

    last_id = -1
    while True:
        frame, fid = reader.get_frame()
        if frame is None or fid == last_id:
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
            continue
        last_id = fid

        p2 = cv2.getTrackbarPos("param2 (votes)", "calibration")
        min_r = cv2.getTrackbarPos("min radius", "calibration")
        max_r = cv2.getTrackbarPos("max radius", "calibration")

        gray_eq = _clahe.apply(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
        blurred = cv2.GaussianBlur(gray_eq, (9, 9), 2)
        circles = cv2.HoughCircles(
            blurred,
            cv2.HOUGH_GRADIENT,
            dp=HOUGH_DP,
            minDist=frame.shape[1] // 3,
            param1=HOUGH_PARAM1,
            param2=max(p2, 1),
            minRadius=min_r,
            maxRadius=max_r,
        )

        vis = frame.copy()
        if circles is not None:
            for cx, cy, radius in np.round(circles[0]).astype(int):
                cv2.circle(vis, (cx, cy), radius, (0, 255, 0), 2)
                cv2.circle(vis, (cx, cy), 3, (0, 255, 0), -1)

        cv2.putText(
            vis,
            "param2={} min_r={} max_r={}".format(p2, min_r, max_r),
            (8, 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 255, 255),
            1,
        )
        cv2.imshow("calibration", vis)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            HOUGH_PARAM2 = p2
            HOUGH_MIN_RADIUS = min_r
            HOUGH_MAX_RADIUS = max_r
            print("calibration saved: param2={} min_r={} max_r={}".format(p2, min_r, max_r))
            break

    cv2.destroyWindow("calibration")


def main():
    print("=" * 50)
    print("  Ball Rotation & Wobble Analyzer")
    print("  ECE 445 - Sensor Integrated Putter")
    print("=" * 50)
    print("")
    print("  connecting to {}".format(STREAM_URL))
    print("  note: 192.168.4.1 only works while connected to Wi-Fi OV5640-Direct")
    print("  SPACE = trigger  |  c = calibrate  |  q = quit")
    print("")

    stream = None
    reader = None

    capturing = False
    capture_start = 0.0
    captured_frames = []
    frame_timestamps = []
    pre_trigger_buffer = deque()
    last_frame_id = -1
    live_frame_counter = 0
    live_tracker_state = None
    live_prev_centers = []  # ring buffer of last 2 found centers for smoothing
    live_tracking_hint = None
    live_tracking_misses = 0
    preview_fps = 0.0
    preview_window_start = time.perf_counter()
    preview_window_frames = 0

    while True:
        if reader is None or not reader.alive:
            if stream is not None:
                try:
                    stream.close()
                except Exception:
                    pass
            try:
                stream = open_stream()
                reader = StreamReader(stream)
                reader.start()
                last_frame_id = -1
                print("stream connected")
            except Exception as e:
                print("connection failed: {} - retrying in 2s".format(e))
                reader = None
                stream = None
                time.sleep(2)
                continue

        frame, fid = reader.get_frame()
        if frame is None or fid == last_frame_id:
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
            continue

        last_frame_id = fid
        now = time.perf_counter()
        pre_trigger_buffer.append((frame.copy(), now))
        while pre_trigger_buffer and now - pre_trigger_buffer[0][1] > PRE_TRIGGER_BUFFER_SEC:
            pre_trigger_buffer.popleft()
        preview_window_frames += 1
        preview_elapsed = now - preview_window_start
        if preview_elapsed >= 1.0:
            preview_fps = preview_window_frames / preview_elapsed
            preview_window_start = now
            preview_window_frames = 0

        if capturing:
            display = frame.copy()
            captured_frames.append(frame.copy())
            frame_timestamps.append(now)
            elapsed = now - capture_start

            cv2.putText(
                display,
                "RECORDING {:.1f}s".format(elapsed),
                (10, display.shape[0] - 20),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 0, 255),
                2,
            )

            if elapsed >= CAPTURE_DURATION:
                capturing = False
                print("\ncaptured {} frames in {:.1f}s".format(len(captured_frames), elapsed))

                if len(frame_timestamps) > 1:
                    span = frame_timestamps[-1] - frame_timestamps[0]
                    actual_fps = (len(frame_timestamps) - 1) / span if span > 0 else CAMERA_FPS
                    print("actual capture fps: {:.1f}".format(actual_fps))
                else:
                    actual_fps = CAMERA_FPS

                print("analyzing...")
                metrics = analyze_putt(captured_frames, actual_fps)
                print_results(metrics)

                print("step through frames: any key = next  |  q = skip")
                for i, result in enumerate(metrics["per_frame_results"]):
                    dbg = result["debug_frame"]
                    status = (
                        "ball tracked"
                        if result["ball_found"]
                        else "no detection"
                    )
                    cv2.putText(
                        dbg,
                        "frame {}/{} - {}".format(i + 1, len(captured_frames), status),
                        (10, dbg.shape[0] - 10),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (255, 255, 0),
                        1,
                    )
                    cv2.imshow("analysis", dbg)
                    if cv2.waitKey(0) & 0xFF == ord("q"):
                        break
                cv2.destroyWindow("analysis")

                captured_frames = []
                frame_timestamps = []
        else:
            should_analyze = (live_frame_counter % LIVE_ANALYZE_EVERY_N_FRAMES) == 0
            live_frame_counter += 1
            if should_analyze:
                prev_center = live_prev_centers[-2] if len(live_prev_centers) >= 2 else (live_prev_centers[-1] if live_prev_centers else None)
                result, live_tracker_state = process_frame(
                    frame,
                    tracking_hint=live_tracking_hint,
                    tracker_state=live_tracker_state,
                    prev_center=prev_center,
                )
                if result["ball_found"]:
                    live_tracking_hint = (result["cx"], result["cy"], result["radius"])
                    live_prev_centers.append((result["cx"], result["cy"]))
                    if len(live_prev_centers) > 3:
                        live_prev_centers.pop(0)
                    live_tracking_misses = 0
                else:
                    live_tracking_misses += 1
                    if live_tracking_misses >= TRACK_MAX_MISSES:
                        live_tracking_hint = None
                        live_tracker_state = None
                        live_prev_centers.clear()
                display = result["debug_frame"]
            else:
                display = frame.copy()

            cv2.putText(
                display,
                "LIVE - SPACE to trigger",
                (10, display.shape[0] - 20),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 255, 0),
                1,
            )

        cv2.putText(
            display,
            "preview {:.1f} fps".format(preview_fps),
            (10, 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (255, 255, 0),
            1,
        )
        cv2.imshow("Ball Analyzer", display)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        if key == ord(" ") and not capturing:
            print("\nTRIGGERED - capturing {:.0f}s with {:.0f}ms pre-roll...".format(
                CAPTURE_DURATION, PRE_TRIGGER_BUFFER_SEC * 1000.0
            ))
            capturing = True
            capture_start = time.perf_counter()
            captured_frames = [buf_frame.copy() for buf_frame, _ in pre_trigger_buffer]
            frame_timestamps = [timestamp for _, timestamp in pre_trigger_buffer]
            live_tracker_state = None
            live_prev_centers.clear()
            live_tracking_hint = None
            live_tracking_misses = 0
        if key == ord("c") and not capturing:
            run_calibration(reader)
            preview_window_start = time.perf_counter()
            preview_window_frames = 0

    if reader is not None:
        reader.stop()
    if stream is not None:
        try:
            stream.close()
        except Exception:
            pass
    cv2.destroyAllWindows()
    print("done")


if __name__ == "__main__":
    main()
