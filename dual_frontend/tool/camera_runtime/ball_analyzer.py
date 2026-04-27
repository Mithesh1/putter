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

# ---- EQUATOR LINE DETECTION ----
MIN_LINE_RATIO = 0.4
MAX_LINE_GAP = 8
MAX_CENTER_DIST_RATIO = 0.45
WOBBLE_THRESHOLD_DEG = 5.0
LINE_BLACKHAT_PERCENTILE = 86
LINE_BLACKHAT_MIN_THRESHOLD = 10
LINE_DARK_PIXEL_PERCENTILE = 28
LINE_MIN_ELONGATION = 1.35
LINE_TRACK_MIN_FEATURES = 4
LINE_TRACK_MAX_ERROR = 20.0
LINE_TRACK_POINT_COUNT = 20
LINE_TRACK_POINT_QUALITY = 0.02
# --------------------------------

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


def build_line_band_mask(shape, line, thickness):
    """Create a thin mask around an inferred equator line."""
    mask = np.zeros(shape, dtype=np.uint8)
    lx1, ly1, lx2, ly2 = line
    cv2.line(mask, (lx1, ly1), (lx2, ly2), 255, max(int(thickness), 1))
    return mask


def refresh_line_tracker_points(gray_eq, roi_origin, line_mask, inner_r):
    """Pick trackable points on or near the equator stripe."""
    x1, y1 = roi_origin
    mask = np.zeros_like(gray_eq, dtype=np.uint8)
    roi_h, roi_w = line_mask.shape
    mask[y1:y1 + roi_h, x1:x1 + roi_w] = line_mask

    kernel_size = odd_clamped(inner_r * 0.4, 3, 7)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    mask = cv2.dilate(mask, kernel, iterations=1)

    points = cv2.goodFeaturesToTrack(
        gray_eq,
        maxCorners=LINE_TRACK_POINT_COUNT,
        qualityLevel=LINE_TRACK_POINT_QUALITY,
        minDistance=max(inner_r * 0.2, 2),
        blockSize=3,
        mask=mask,
    )
    if points is None or len(points) < LINE_TRACK_MIN_FEATURES:
        return None
    return points.astype(np.float32)


def initialize_line_tracker(gray_eq, roi_origin, line_mask, inner_r, line_angle):
    """Initialize optical-flow tracking for the equator line."""
    points = refresh_line_tracker_points(gray_eq, roi_origin, line_mask, inner_r)
    if points is None:
        return None

    return {
        "prev_gray": gray_eq.copy(),
        "points": points,
        "angle": float(line_angle),
    }


def track_line_motion(gray_eq, line_tracker_state, cx, cy, radius):
    """Propagate equator orientation using optical flow between frames."""
    if line_tracker_state is None or line_tracker_state.get("points") is None:
        return None, None

    prev_gray = line_tracker_state["prev_gray"]
    prev_points = line_tracker_state["points"]
    next_points, status, err = cv2.calcOpticalFlowPyrLK(
        prev_gray,
        gray_eq,
        prev_points,
        None,
        winSize=(13, 13),
        maxLevel=2,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 10, 0.03),
    )
    if next_points is None or status is None:
        return None, None

    status = status.reshape(-1).astype(bool)
    good_new = next_points.reshape(-1, 2)[status]
    if err is not None:
        good_err = err.reshape(-1)[status]
        good_new = good_new[good_err <= LINE_TRACK_MAX_ERROR]

    if len(good_new) < LINE_TRACK_MIN_FEATURES:
        return None, None

    center = np.array([cx, cy], dtype=np.float32)
    keep = np.linalg.norm(good_new - center, axis=1) <= radius * 1.35
    good_new = good_new[keep]
    if len(good_new) < LINE_TRACK_MIN_FEATURES:
        return None, None

    fit = cv2.fitLine(good_new.reshape(-1, 1, 2), cv2.DIST_L2, 0, 0.01, 0.01).reshape(-1)
    vx, vy, x0, y0 = [float(v) for v in fit]

    half_len = max(radius * 0.9, 6.0)
    lx1 = int(round(x0 - vx * half_len))
    ly1 = int(round(y0 - vy * half_len))
    lx2 = int(round(x0 + vx * half_len))
    ly2 = int(round(y0 + vy * half_len))
    angle = math.atan2(ly2 - ly1, lx2 - lx1)
    if angle < 0:
        angle += math.pi

    band_mask = build_line_band_mask(gray_eq.shape, (lx1, ly1, lx2, ly2), max(radius * 0.22, 2))
    ball_mask = build_tracking_mask(gray_eq.shape, cx, cy, radius)
    band_mask = cv2.bitwise_and(band_mask, ball_mask)
    refreshed_points = cv2.goodFeaturesToTrack(
        gray_eq,
        maxCorners=LINE_TRACK_POINT_COUNT,
        qualityLevel=LINE_TRACK_POINT_QUALITY,
        minDistance=max(radius * 0.18, 2),
        blockSize=3,
        mask=band_mask,
    )
    if refreshed_points is None or len(refreshed_points) < LINE_TRACK_MIN_FEATURES:
        refreshed_points = good_new.reshape(-1, 1, 2).astype(np.float32)

    new_state = {
        "prev_gray": gray_eq.copy(),
        "points": refreshed_points,
        "angle": angle,
    }
    return {
        "line": (lx1, ly1, lx2, ly2),
        "angle": angle,
        "source": "line_track",
    }, new_state


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


def detect_equator_line(roi_eq, roi_cx, roi_cy, inner_r):
    """Detect a dark equator stripe inside the already-detected ball ROI."""
    roi_h, roi_w = roi_eq.shape
    cmask = np.zeros((roi_h, roi_w), dtype=np.uint8)
    cv2.circle(cmask, (roi_cx, roi_cy), inner_r, 255, -1)

    inner_values = roi_eq[cmask > 0]
    if inner_values.size < 20:
        return None, cmask, None

    kernel_size = odd_clamped(inner_r * 0.7, 3, 9)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    blackhat = cv2.morphologyEx(roi_eq, cv2.MORPH_BLACKHAT, kernel)
    blackhat = cv2.bitwise_and(blackhat, blackhat, mask=cmask)

    line_mask = np.zeros_like(roi_eq, dtype=np.uint8)
    response_thresh = max(
        LINE_BLACKHAT_MIN_THRESHOLD,
        int(np.percentile(blackhat[cmask > 0], LINE_BLACKHAT_PERCENTILE)),
    )
    line_mask[blackhat >= response_thresh] = 255
    line_mask = cv2.bitwise_and(line_mask, cmask)

    if cv2.countNonZero(line_mask) < max(6, inner_r):
        dark_thresh = int(np.percentile(inner_values, LINE_DARK_PIXEL_PERCENTILE))
        line_mask = np.zeros_like(roi_eq, dtype=np.uint8)
        line_mask[roi_eq <= dark_thresh] = 255
        line_mask = cv2.bitwise_and(line_mask, cmask)

    kernel3 = np.ones((3, 3), dtype=np.uint8)
    line_mask = cv2.morphologyEx(line_mask, cv2.MORPH_OPEN, kernel3)
    line_mask = cv2.morphologyEx(line_mask, cv2.MORPH_CLOSE, kernel3)
    line_mask = cv2.bitwise_and(line_mask, cmask)

    contours, _ = cv2.findContours(line_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None, cmask, line_mask

    best = None
    best_score = -1.0
    max_center_dist = max(inner_r * MAX_CENTER_DIST_RATIO, 2.0)
    min_major = max(inner_r * MIN_LINE_RATIO, 5.0)

    for contour in contours:
        area = cv2.contourArea(contour)
        if area < 3.0:
            continue

        (_, _), (rw, rh), _ = cv2.minAreaRect(contour)
        major = max(rw, rh)
        minor = max(min(rw, rh), 1.0)
        if major < min_major:
            continue

        elongation = major / minor
        if elongation < LINE_MIN_ELONGATION:
            continue

        fit = cv2.fitLine(contour, cv2.DIST_L2, 0, 0.01, 0.01).reshape(-1)
        vx, vy, x0, y0 = [float(v) for v in fit]

        pts = contour.reshape(-1, 2).astype(np.float32)
        residual = float(np.mean(np.abs(vy * (pts[:, 0] - x0) - vx * (pts[:, 1] - y0))))
        center_dist = abs(vy * (roi_cx - x0) - vx * (roi_cy - y0))
        if center_dist > max_center_dist:
            continue

        score = major * min(elongation, 6.0) * (1.0 - center_dist / max_center_dist) / (1.0 + residual)
        if score > best_score:
            best_score = score
            best = (vx, vy, x0, y0, major)

    if best is None:
        return None, cmask, line_mask

    vx, vy, x0, y0, major = best
    half_len = max(inner_r * 0.95, major * 0.6)
    lx1 = int(round(x0 - vx * half_len))
    ly1 = int(round(y0 - vy * half_len))
    lx2 = int(round(x0 + vx * half_len))
    ly2 = int(round(y0 + vy * half_len))

    lx1 = int(np.clip(lx1, 0, roi_w - 1))
    ly1 = int(np.clip(ly1, 0, roi_h - 1))
    lx2 = int(np.clip(lx2, 0, roi_w - 1))
    ly2 = int(np.clip(ly2, 0, roi_h - 1))

    angle = math.atan2(ly2 - ly1, lx2 - lx1)
    if angle < 0:
        angle += math.pi

    return {
        "line": (lx1, ly1, lx2, ly2),
        "angle": angle,
        "source": "line_detect",
    }, cmask, line_mask


def process_frame(frame, hough_param2=None, tracking_hint=None, tracker_state=None, line_tracker_state=None):
    """
    Find the ball by shape, then find the equator line.

    Returns:
        ball_found  (bool)
        cx, cy, radius (int)
        line_found  (bool)
        angle       (float | None), normalized to [0, pi)
        debug_frame (ndarray)
    """
    if hough_param2 is None:
        hough_param2 = HOUGH_PARAM2

    debug = frame.copy()
    h, w = frame.shape[:2]

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
            "line_found": False,
            "angle": None,
            "debug_frame": debug,
            "tracking_mode": tracking_mode,
        }, None, None

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

    margin = 10
    x1 = max(0, cx - radius - margin)
    y1 = max(0, cy - radius - margin)
    x2 = min(w, cx + radius + margin)
    y2 = min(h, cy + radius + margin)
    roi_eq = gray_eq[y1:y2, x1:x2]

    if roi_eq.size == 0:
        return {
            "ball_found": True,
            "cx": cx,
            "cy": cy,
            "radius": radius,
            "line_found": False,
            "angle": None,
            "debug_frame": debug,
            "tracking_mode": tracking_mode,
        }, tracker_state, line_tracker_state

    roi_h, roi_w = roi_eq.shape
    roi_cx = cx - x1
    roi_cy = cy - y1
    inner_r = int(radius * 0.85)
    tracked_line_result, line_tracker_state = track_line_motion(
        gray_eq, line_tracker_state, cx, cy, radius
    )
    if tracked_line_result is not None:
        line_result = tracked_line_result
        cmask = build_tracking_mask((roi_h, roi_w), roi_cx, roi_cy, inner_r)
        local_line = (
            tracked_line_result["line"][0] - x1,
            tracked_line_result["line"][1] - y1,
            tracked_line_result["line"][2] - x1,
            tracked_line_result["line"][3] - y1,
        )
        line_mask = build_line_band_mask((roi_h, roi_w), local_line, max(inner_r * 0.18, 2))
    else:
        line_result, cmask, line_mask = detect_equator_line(roi_eq, roi_cx, roi_cy, inner_r)

    if line_mask is not None:
        line_overlay = np.zeros_like(debug[y1:y2, x1:x2])
        line_overlay[:, :, 2] = line_mask
        debug[y1:y2, x1:x2] = cv2.addWeighted(debug[y1:y2, x1:x2], 1.0, line_overlay, 0.18, 0)

    if line_result is None:
        roi_masked = cv2.bitwise_and(roi_eq, roi_eq, mask=cmask)
        roi_canny_lo = LOW_LIGHT_CANNY_LO if low_light else 40
        roi_canny_hi = LOW_LIGHT_CANNY_HI if low_light else 100
        edges = cv2.Canny(roi_masked, roi_canny_lo, roi_canny_hi)

        min_len = max(int(inner_r * MIN_LINE_RATIO), 8)
        lines = cv2.HoughLinesP(
            edges,
            1,
            np.pi / 180,
            threshold=12,
            minLineLength=min_len,
            maxLineGap=MAX_LINE_GAP,
        )

        if lines is None or len(lines) == 0:
            return {
                "ball_found": True,
                "cx": cx,
                "cy": cy,
                "radius": radius,
                "line_found": False,
                "angle": None,
                "debug_frame": debug,
                "tracking_mode": tracking_mode,
            }, tracker_state, None

        best_line = None
        best_score = -1.0
        max_dist = radius * MAX_CENTER_DIST_RATIO

        for line in lines:
            lx1, ly1, lx2, ly2 = line[0]
            length = math.hypot(lx2 - lx1, ly2 - ly1)

            a = ly2 - ly1
            b = lx1 - lx2
            c = lx2 * ly1 - lx1 * ly2
            denom = math.hypot(a, b)
            if denom == 0:
                continue

            dist = abs(a * roi_cx + b * roi_cy + c) / denom
            if dist > max_dist:
                continue

            score = length * (1.0 - dist / max_dist)
            if score > best_score:
                best_score = score
                best_line = line[0]

        if best_line is None:
            return {
                "ball_found": True,
                "cx": cx,
                "cy": cy,
                "radius": radius,
                "line_found": False,
                "angle": None,
                "debug_frame": debug,
                "tracking_mode": tracking_mode,
            }, tracker_state, None

        lx1, ly1, lx2, ly2 = best_line
        angle = math.atan2(ly2 - ly1, lx2 - lx1)
        if angle < 0:
            angle += math.pi
        line_source = "line_hough"
        fallback_mask = np.zeros((roi_h, roi_w), dtype=np.uint8)
        cv2.line(fallback_mask, (lx1, ly1), (lx2, ly2), 255, max(int(inner_r * 0.2), 2))
        line_tracker_state = initialize_line_tracker(gray_eq, (x1, y1), fallback_mask, inner_r, angle)
    else:
        lx1, ly1, lx2, ly2 = line_result["line"]
        angle = line_result["angle"]
        line_source = line_result.get("source", "line_detect")
        if tracked_line_result is None:
            line_tracker_state = initialize_line_tracker(
                gray_eq, (x1, y1), line_mask, inner_r, angle
            )

    if lx1 == lx2 and ly1 == ly2:
        return {
            "ball_found": True,
            "cx": cx,
            "cy": cy,
            "radius": radius,
            "line_found": False,
            "angle": None,
            "debug_frame": debug,
            "tracking_mode": tracking_mode,
        }, tracker_state, line_tracker_state

    cv2.line(debug, (lx1 + x1, ly1 + y1), (lx2 + x1, ly2 + y1), (0, 0, 255), 2)
    cv2.putText(
        debug,
        "angle: {:.1f} deg {}".format(math.degrees(angle), line_source),
        (10, 30),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (0, 0, 255),
        2,
    )

    return {
        "ball_found": True,
        "cx": cx,
        "cy": cy,
        "radius": radius,
        "line_found": True,
        "angle": angle,
        "debug_frame": debug,
        "tracking_mode": tracking_mode,
        "line_source": line_source,
    }, tracker_state, line_tracker_state


def analyze_putt(frames, fps):
    """Process all captured frames and compute rotation rate plus wobble."""
    results = []
    tracker_state = None
    line_tracker_state = None
    tracking_hint = None
    tracking_misses = 0
    for frame in frames:
        result, tracker_state, line_tracker_state = process_frame(
            frame,
            tracking_hint=tracking_hint,
            tracker_state=tracker_state,
            line_tracker_state=line_tracker_state,
        )
        results.append(result)
        if result["ball_found"]:
            tracking_hint = (result["cx"], result["cy"], result["radius"])
            tracking_misses = 0
        else:
            tracking_misses += 1
            if tracking_misses >= TRACK_MAX_MISSES:
                tracking_hint = None
                tracker_state = None
                line_tracker_state = None

    valid_angles = []
    valid_indices = []
    for i, result in enumerate(results):
        if result["ball_found"] and result["line_found"] and result["angle"] is not None:
            valid_angles.append(result["angle"])
            valid_indices.append(i)

    total = len(frames)
    valid = len(valid_angles)

    if valid < 2:
        return {
            "rotation_rate_deg_s": 0.0,
            "wobble_detected": False,
            "wobble_magnitude_deg": 0.0,
            "detection_rate": valid / max(total, 1),
            "valid_frames": valid,
            "total_frames": total,
            "per_frame_results": results,
        }

    dt = 1.0 / fps
    rotation_rates = []

    for i in range(1, valid):
        gap = valid_indices[i] - valid_indices[i - 1]
        actual_dt = gap * dt
        delta = valid_angles[i] - valid_angles[i - 1]

        if delta > math.pi / 2:
            delta -= math.pi
        if delta < -math.pi / 2:
            delta += math.pi

        rotation_rates.append(delta / actual_dt)

    avg_rad = sum(rotation_rates) / len(rotation_rates) if rotation_rates else 0.0
    avg_deg = math.degrees(avg_rad)

    if len(rotation_rates) >= 2:
        variance = sum((rate - avg_rad) ** 2 for rate in rotation_rates) / len(rotation_rates)
        wobble_deg = math.degrees(math.sqrt(variance))
    else:
        wobble_deg = 0.0

    return {
        "rotation_rate_deg_s": round(avg_deg, 1),
        "wobble_detected": wobble_deg > WOBBLE_THRESHOLD_DEG,
        "wobble_magnitude_deg": round(wobble_deg, 1),
        "detection_rate": round(valid / total, 2),
        "valid_frames": valid,
        "total_frames": total,
        "per_frame_results": results,
    }


def print_results(metrics):
    print("\n" + "=" * 50)
    print("  PUTT ANALYSIS RESULTS")
    print("=" * 50)
    print("  frames captured:   {}".format(metrics["total_frames"]))
    print(
        "  frames with line:  {} ({:.0f}%)".format(
            metrics["valid_frames"], metrics["detection_rate"] * 100
        )
    )
    print("")
    print("  rotation rate:     {:.1f} deg/s".format(metrics["rotation_rate_deg_s"]))
    print("  wobble detected:   {}".format("YES" if metrics["wobble_detected"] else "NO"))
    print("  wobble magnitude:  {:.1f} deg".format(metrics["wobble_magnitude_deg"]))
    print("=" * 50)
    if metrics["wobble_detected"]:
        print("  NOTE: wobble indicates off-center contact or unstable roll axis")
    else:
        print("  clean end-over-end roll detected")
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
    live_line_tracker_state = None
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
                        "ball+line"
                        if result["ball_found"] and result["line_found"]
                        else "ball only"
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
                result, live_tracker_state, live_line_tracker_state = process_frame(
                    frame,
                    tracking_hint=live_tracking_hint,
                    tracker_state=live_tracker_state,
                    line_tracker_state=live_line_tracker_state,
                )
                if result["ball_found"]:
                    live_tracking_hint = (result["cx"], result["cy"], result["radius"])
                    live_tracking_misses = 0
                else:
                    live_tracking_misses += 1
                    if live_tracking_misses >= TRACK_MAX_MISSES:
                        live_tracking_hint = None
                        live_tracker_state = None
                        live_line_tracker_state = None
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
            live_line_tracker_state = None
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
