"""
Higher-resolution burst capture client for the OV5640 ESP32-S3 setup.

This script talks to test_burst/test_burst.ino over HTTP:
1. Trigger a burst capture on the ESP32.
2. Download the saved JPEG frames after capture completes.
3. Reuse the existing ball analysis pipeline on those frames.
4. Push the processed metrics to Nathan's iPad via Bluetooth (BLE).
5. Let the user step through analyzed frames afterward.

Requires: pip install bless
"""

import asyncio
import json
import http.client
import math
import socket
import struct
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import cv2
import numpy as np

try:
    import msvcrt
except ImportError:
    msvcrt = None

SCRIPT_DIR = Path(__file__).resolve().parent
CAMERA_DIR = SCRIPT_DIR.parent / "camera"
if str(CAMERA_DIR) not in sys.path:
    sys.path.insert(0, str(CAMERA_DIR))

import ball_analyzer as ba
from ball_analyzer import analyze_putt, print_results


BASE_URL = "http://192.168.4.1"
STATUS_URL = BASE_URL + "/status"
TRIGGER_URL = BASE_URL + "/trigger"
MANIFEST_URL = BASE_URL + "/manifest"
FRAME_URL_TEMPLATE = BASE_URL + "/frame?id={index}"

REQUEST_TIMEOUT = 15
POLL_INTERVAL = 0.2
READY_TIMEOUT = 20.0
WINDOW_NAME = "Burst Analyzer Review"
CALIBRATION_WINDOW = "Burst Calibration"
CALIBRATION_PATH = Path(__file__).with_name("burst_calibration.json")
GOLF_BALL_DIAMETER_IN = 1.68
MIN_MOTION_DIAMETERS = 0.04
MAX_VELOCITY_GAP_S = 0.35
FRAME_DOWNLOAD_TIMEOUT = 20
FRAME_DOWNLOAD_RETRIES = 4
FRAME_DOWNLOAD_RETRY_DELAY_S = 0.35
MIN_JPEG_BYTES = 1024

# ── BLE peripheral (iPad notifications) ─────────────────────────────────────
BLE_DEVICE_NAME        = "BurstAnalyzer"
BALL_DATA_SERVICE_UUID = "12340000-0000-4b59-9000-000000000001"
BALL_DATA_CHAR_UUID    = "12340000-0000-4b59-9000-000000000002"
BALL_TRIGGER_CHAR_UUID = "12340000-0000-4b59-9000-000000000003"
TIMESERIES_CHAR_UUID   = "12340000-0000-4b59-9000-000000000004"
BLE_NOTIFY_RETRY_COUNT = 3
BLE_NOTIFY_RETRY_DELAY_S = 0.2
BLE_NOTIFY_INITIAL_DELAY_S = 0.15

_ble_available = False
_ble_loop      = None
_ble_server    = None
_ble_ready     = threading.Event()
_capture_lock = threading.Lock()
_capture_active = False

try:
    from bless import (
        BlessServer,
        GATTCharacteristicProperties,
        GATTAttributePermissions,
    )
    _ble_available = True
except Exception as _ble_import_error:
    print("BLE import failed: {}".format(_ble_import_error))
    print("  run: pip3 install bless")

DETECTOR_SETTING_KEYS = (
    "HOUGH_PARAM2",
    "HOUGH_MIN_RADIUS",
    "HOUGH_MAX_RADIUS",
    "WHITE_S_MAX",
    "WHITE_GRAY_MIN",
    "WHITE_GRAY_PERCENTILE",
    "MIN_BALL_SCORE",
    "LOW_LIGHT_THRESHOLD",
    "LOW_LIGHT_GRAY_MIN",
    "LOW_LIGHT_HOUGH_PARAM2_DELTA",
)


def fetch_json(url, timeout=REQUEST_TIMEOUT):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def normalize_detector_settings(settings):
    normalized = dict(settings)
    normalized["HOUGH_PARAM2"] = max(1, int(normalized["HOUGH_PARAM2"]))
    normalized["HOUGH_MIN_RADIUS"] = max(1, int(normalized["HOUGH_MIN_RADIUS"]))
    normalized["HOUGH_MAX_RADIUS"] = max(
        normalized["HOUGH_MIN_RADIUS"] + 1,
        int(normalized["HOUGH_MAX_RADIUS"]),
    )
    normalized["WHITE_S_MAX"] = int(np.clip(normalized["WHITE_S_MAX"], 0, 255))
    normalized["WHITE_GRAY_MIN"] = int(np.clip(normalized["WHITE_GRAY_MIN"], 0, 255))
    normalized["WHITE_GRAY_PERCENTILE"] = int(np.clip(normalized["WHITE_GRAY_PERCENTILE"], 1, 99))
    normalized["MIN_BALL_SCORE"] = round(float(np.clip(normalized["MIN_BALL_SCORE"], 0.1, 4.0)), 2)
    normalized["LOW_LIGHT_THRESHOLD"] = int(np.clip(normalized["LOW_LIGHT_THRESHOLD"], 0, 255))
    normalized["LOW_LIGHT_GRAY_MIN"] = int(np.clip(normalized["LOW_LIGHT_GRAY_MIN"], 0, 255))
    normalized["LOW_LIGHT_HOUGH_PARAM2_DELTA"] = int(
        np.clip(normalized["LOW_LIGHT_HOUGH_PARAM2_DELTA"], 0, 40)
    )
    return normalized


def collect_detector_settings():
    return normalize_detector_settings({key: getattr(ba, key) for key in DETECTOR_SETTING_KEYS})


def apply_detector_settings(settings):
    normalized = normalize_detector_settings(settings)
    for key, value in normalized.items():
        setattr(ba, key, value)
    return normalized


def load_detector_settings():
    if not CALIBRATION_PATH.exists():
        return None
    try:
        loaded = json.loads(CALIBRATION_PATH.read_text(encoding="utf-8"))
    except Exception:
        return None
    return apply_detector_settings(loaded)


def save_detector_settings(settings):
    normalized = normalize_detector_settings(settings)
    CALIBRATION_PATH.write_text(json.dumps(normalized, indent=2), encoding="utf-8")
    if not CALIBRATION_PATH.exists():
        raise RuntimeError("failed to create calibration file at {}".format(CALIBRATION_PATH))
    return normalized


def read_command():
    prompt = "Press Enter to capture, c to calibrate, or q to quit: "
    if msvcrt is None:
        return input(prompt).strip().lower()

    print(prompt, end="", flush=True)
    while True:
        key = msvcrt.getwch()
        if key in ("\r", "\n"):
            print("")
            return ""
        lowered = key.lower()
        if lowered in ("c", "q"):
            print(key)
            return lowered


def is_complete_jpeg(data):
    return bool(data) and len(data) >= MIN_JPEG_BYTES and data[:2] == b"\xff\xd8" and data[-2:] == b"\xff\xd9"


def fetch_bytes(url, timeout=FRAME_DOWNLOAD_TIMEOUT, retries=FRAME_DOWNLOAD_RETRIES):
    last_error = None
    request = urllib.request.Request(
        url,
        headers={
            "Connection": "close",
            "Cache-Control": "no-cache",
        },
    )

    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = response.read()
            if not is_complete_jpeg(payload):
                raise RuntimeError("incomplete jpeg payload ({} bytes)".format(len(payload)))
            return payload
        except (
            TimeoutError,
            socket.timeout,
            urllib.error.URLError,
            http.client.IncompleteRead,
            RuntimeError,
        ) as exc:
            last_error = exc
            if attempt + 1 >= retries:
                break
            time.sleep(FRAME_DOWNLOAD_RETRY_DELAY_S)

    raise last_error


def trigger_burst():
    try:
        with urllib.request.urlopen(TRIGGER_URL, timeout=REQUEST_TIMEOUT) as response:
            payload = response.read().decode("utf-8", errors="replace")
            if payload:
                return json.loads(payload)
            return {"accepted": response.status in (200, 202)}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError("burst trigger failed: HTTP {} {}".format(exc.code, body)) from exc


def wait_for_ready(timeout_s=READY_TIMEOUT):
    start = time.perf_counter()
    last_state = None

    while (time.perf_counter() - start) < timeout_s:
        status = fetch_json(STATUS_URL)
        state = status.get("state", "unknown")
        if state != last_state:
            print("device state: {}".format(state))
            last_state = state

        if state == "ready":
            return status
        if state == "error":
            raise RuntimeError("device reported error: {}".format(status.get("error", "unknown")))

        time.sleep(POLL_INTERVAL)

    raise RuntimeError("timed out waiting for burst capture")


def download_frames(manifest):
    frame_meta = manifest.get("frames", [])
    frames = []
    print("downloading {} frames...".format(len(frame_meta)))

    for idx, meta in enumerate(frame_meta):
        frame = download_frame(meta["index"])
        frames.append(frame)
        print("  frame {:02d}/{:02d}".format(idx + 1, len(frame_meta)))

    return frames


def estimate_fps(manifest):
    fps = float(manifest.get("fps_estimate", 0.0) or 0.0)
    if fps > 0.0:
        return fps

    frames = manifest.get("frames", [])
    if len(frames) >= 2:
        first_ms = frames[0]["t_ms"]
        last_ms = frames[-1]["t_ms"]
        if last_ms > first_ms:
            return (len(frames) - 1) * 1000.0 / float(last_ms - first_ms)

    duration_ms = manifest.get("capture_duration_ms", 0)
    if duration_ms and len(frames) >= 2:
        return (len(frames) - 1) * 1000.0 / float(duration_ms)

    return 10.0


def resize_for_screen(image, max_width=1700, max_height=950):
    h, w = image.shape[:2]
    scale = min(max_width / float(w), max_height / float(h), 1.0)
    if scale >= 1.0:
        return image
    resized = cv2.resize(image, (int(round(w * scale)), int(round(h * scale))), interpolation=cv2.INTER_AREA)
    return resized


def build_frame_times(manifest, total, fps):
    frame_meta = manifest.get("frames", [])
    if len(frame_meta) == total and total > 0:
        start_ms = frame_meta[0]["t_ms"]
        return [(frame["t_ms"] - start_ms) / 1000.0 for frame in frame_meta]
    step = 1.0 / max(float(fps), 0.001)
    return [index * step for index in range(total)]


def default_calibration_frame_index(manifest, total_frames):
    if total_frames <= 0:
        return 0
    pre = int(manifest.get("pre_frame_count", 0) or 0)
    if pre > 0:
        return min(pre - 1, total_frames - 1)
    return 0


def download_frame(frame_id):
    try:
        jpg = fetch_bytes(FRAME_URL_TEMPLATE.format(index=frame_id))
    except Exception as exc:
        raise RuntimeError("failed downloading frame {} after retries".format(frame_id)) from exc
    arr = np.frombuffer(jpg, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise RuntimeError("failed to decode frame {}".format(frame_id))
    return frame


def create_calibration_trackbars(total_frames, manifest):
    cv2.namedWindow(CALIBRATION_WINDOW, cv2.WINDOW_NORMAL)
    current = collect_detector_settings()
    cv2.createTrackbar("frame", CALIBRATION_WINDOW, default_calibration_frame_index(manifest, total_frames), max(total_frames - 1, 0), lambda x: None)
    cv2.createTrackbar("param2", CALIBRATION_WINDOW, int(current["HOUGH_PARAM2"]), 80, lambda x: None)
    cv2.createTrackbar("min radius", CALIBRATION_WINDOW, int(current["HOUGH_MIN_RADIUS"]), 60, lambda x: None)
    cv2.createTrackbar("max radius", CALIBRATION_WINDOW, int(current["HOUGH_MAX_RADIUS"]), 80, lambda x: None)
    cv2.createTrackbar("white sat", CALIBRATION_WINDOW, int(current["WHITE_S_MAX"]), 255, lambda x: None)
    cv2.createTrackbar("white gray", CALIBRATION_WINDOW, int(current["WHITE_GRAY_MIN"]), 255, lambda x: None)
    cv2.createTrackbar("gray pct", CALIBRATION_WINDOW, int(current["WHITE_GRAY_PERCENTILE"]), 99, lambda x: None)
    cv2.createTrackbar("min score x100", CALIBRATION_WINDOW, int(round(current["MIN_BALL_SCORE"] * 100)), 400, lambda x: None)
    cv2.createTrackbar("LL thresh", CALIBRATION_WINDOW, int(current["LOW_LIGHT_THRESHOLD"]), 255, lambda x: None)
    cv2.createTrackbar("LL gray", CALIBRATION_WINDOW, int(current["LOW_LIGHT_GRAY_MIN"]), 255, lambda x: None)
    cv2.createTrackbar("LL p2 delta", CALIBRATION_WINDOW, int(current["LOW_LIGHT_HOUGH_PARAM2_DELTA"]), 40, lambda x: None)


def read_calibration_trackbars():
    return normalize_detector_settings(
        {
            "HOUGH_PARAM2": cv2.getTrackbarPos("param2", CALIBRATION_WINDOW),
            "HOUGH_MIN_RADIUS": cv2.getTrackbarPos("min radius", CALIBRATION_WINDOW),
            "HOUGH_MAX_RADIUS": cv2.getTrackbarPos("max radius", CALIBRATION_WINDOW),
            "WHITE_S_MAX": cv2.getTrackbarPos("white sat", CALIBRATION_WINDOW),
            "WHITE_GRAY_MIN": cv2.getTrackbarPos("white gray", CALIBRATION_WINDOW),
            "WHITE_GRAY_PERCENTILE": cv2.getTrackbarPos("gray pct", CALIBRATION_WINDOW),
            "MIN_BALL_SCORE": cv2.getTrackbarPos("min score x100", CALIBRATION_WINDOW) / 100.0,
            "LOW_LIGHT_THRESHOLD": cv2.getTrackbarPos("LL thresh", CALIBRATION_WINDOW),
            "LOW_LIGHT_GRAY_MIN": cv2.getTrackbarPos("LL gray", CALIBRATION_WINDOW),
            "LOW_LIGHT_HOUGH_PARAM2_DELTA": cv2.getTrackbarPos("LL p2 delta", CALIBRATION_WINDOW),
        }
    )


def add_calibration_overlay(frame, result, frame_index, total_frames, manifest):
    preview = result["debug_frame"].copy()
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    mean_brightness = float(np.mean(gray))
    low_light = mean_brightness < ba.LOW_LIGHT_THRESHOLD
    pre = int(manifest.get("pre_frame_count", 0) or 0)
    phase = "pre-trigger" if frame_index < pre else "post-trigger"

    lines = [
        "frame {}/{} ({})".format(frame_index + 1, total_frames, phase),
        "mean brightness {:.1f} | low-light {}".format(mean_brightness, "ON" if low_light else "OFF"),
        "param2={} radius {}-{} score>={:.2f}".format(
            ba.HOUGH_PARAM2,
            ba.HOUGH_MIN_RADIUS,
            ba.HOUGH_MAX_RADIUS,
            ba.MIN_BALL_SCORE,
        ),
        "white sat<={} gray>={} pct={} LLth={} LLgray={} dP2={}".format(
            ba.WHITE_S_MAX,
            ba.WHITE_GRAY_MIN,
            ba.WHITE_GRAY_PERCENTILE,
            ba.LOW_LIGHT_THRESHOLD,
            ba.LOW_LIGHT_GRAY_MIN,
            ba.LOW_LIGHT_HOUGH_PARAM2_DELTA,
        ),
        "s save | q cancel | use trackbars to tune ball lock",
    ]

    y = 22
    for line in lines:
        cv2.putText(
            preview,
            line,
            (12, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (255, 255, 255),
            2,
        )
        y += 22

    if result.get("ball_found"):
        cv2.putText(
            preview,
            "ball center=({}, {}) r={} mode={}".format(
                result["cx"], result["cy"], result["radius"], result.get("tracking_mode", "detect")
            ),
            (12, y + 4),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (0, 255, 255),
            2,
        )
    else:
        cv2.putText(
            preview,
            "ball not found",
            (12, y + 4),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (0, 0, 255),
            2,
        )

    return resize_for_screen(preview)


def run_calibration_session(manifest):
    frame_meta = manifest.get("frames", [])
    total_frames = len(frame_meta)
    if not frame_meta:
        print("no frames available for calibration")
        return False

    original_settings = collect_detector_settings()
    create_calibration_trackbars(total_frames, manifest)
    print("calibration mode: adjust trackbars, press s to save, q to cancel")
    saved = False
    frame_cache = {}
    current_frame_index = None
    current_frame = None

    while True:
        if cv2.getWindowProperty(CALIBRATION_WINDOW, cv2.WND_PROP_VISIBLE) < 1:
            applied = apply_detector_settings(read_calibration_trackbars())
            save_detector_settings(applied)
            print("calibration window closed; saved detector calibration to {}".format(CALIBRATION_PATH))
            saved = True
            break

        frame_index = min(cv2.getTrackbarPos("frame", CALIBRATION_WINDOW), total_frames - 1)
        if frame_index != current_frame_index:
            frame_id = frame_meta[frame_index]["index"]
            if frame_id not in frame_cache:
                print("loading calibration frame {}/{}...".format(frame_index + 1, total_frames))
                frame_cache[frame_id] = download_frame(frame_id)
            current_frame = frame_cache[frame_id]
            current_frame_index = frame_index

        applied = apply_detector_settings(read_calibration_trackbars())
        result, _ = ba.process_frame(current_frame.copy())
        preview = add_calibration_overlay(current_frame, result, frame_index, total_frames, manifest)
        cv2.imshow(CALIBRATION_WINDOW, preview)

        key = cv2.waitKey(30) & 0xFF
        if key in (ord("q"), ord("Q"), 27):
            apply_detector_settings(original_settings)
            break
        if key in (ord("s"), ord("S"), 13, 32):
            save_detector_settings(applied)
            print("saved detector calibration to {}".format(CALIBRATION_PATH))
            saved = True
            break

    cv2.destroyWindow(CALIBRATION_WINDOW)
    return saved






def recompute_path_metrics(metrics):
    results = metrics.get("per_frame_results", [])

    moving_centers = []
    moving_radii = []
    for result in results:
        if result.get("ball_found"):
            moving_centers.append((float(result["cx"]), float(result["cy"])))
            moving_radii.append(float(result["radius"]))

    total = len(results)
    tracked = len(moving_centers)
    avg_r = float(sum(moving_radii) / max(len(moving_radii), 1))

    metrics["tracking_quality_pct"] = round(tracked / max(total, 1) * 100, 1)
    metrics["avg_radius_px"] = round(avg_r, 1)
    metrics["valid_frames"] = tracked
    metrics["total_frames"] = total

    if tracked < 3:
        metrics.setdefault("path_drift_deg", 0.0)
        metrics.setdefault("rms_lateral_px", 0.0)
        metrics.setdefault("max_lateral_px", 0.0)
        metrics.setdefault("total_path_px", 0.0)
        metrics.setdefault("direction_wobble_deg", 0.0)
        metrics.setdefault("lateral_deviations_px", [])
        metrics.setdefault("forward_positions_px", [])
        return metrics

    # Guard: if ball barely moved, fitLine is meaningless.
    xs = [c[0] for c in moving_centers]
    ys = [c[1] for c in moving_centers]
    span = math.hypot(max(xs) - min(xs), max(ys) - min(ys))
    if span < avg_r * 0.5:
        print("warning: ball moved only {:.1f} px — path metrics unreliable".format(span))
        metrics["path_drift_deg"] = 0.0
        metrics["rms_lateral_px"] = 0.0
        metrics["max_lateral_px"] = 0.0
        metrics["total_path_px"] = round(span, 1)
        metrics["direction_wobble_deg"] = 0.0
        metrics["lateral_deviations_px"] = []
        metrics["forward_positions_px"] = []
        return metrics

    pts = np.array(moving_centers, dtype=np.float32)
    line_fit = cv2.fitLine(pts.reshape(-1, 1, 2), cv2.DIST_L2, 0, 0.01, 0.01).reshape(-1)
    vx, vy, x0, y0 = [float(v) for v in line_fit]

    if vy < 0:
        vx, vy = -vx, -vy

    metrics["path_drift_deg"] = round(math.degrees(math.atan2(vx, vy)), 2)

    perp_x, perp_y = -vy, vx
    lateral = [(c[0] - x0) * perp_x + (c[1] - y0) * perp_y for c in moving_centers]
    forward = [(c[0] - x0) * vx + (c[1] - y0) * vy for c in moving_centers]
    fwd_offset = forward[0]
    forward = [p - fwd_offset for p in forward]

    rms_lat = math.sqrt(sum(d * d for d in lateral) / tracked)
    metrics["rms_lateral_px"] = round(rms_lat, 1)
    metrics["max_lateral_px"] = round(max(abs(d) for d in lateral), 1)
    metrics["total_path_px"] = round(sum(
        math.hypot(moving_centers[i][0] - moving_centers[i-1][0],
                   moving_centers[i][1] - moving_centers[i-1][1])
        for i in range(1, tracked)
    ), 1)
    metrics["lateral_deviations_px"] = [round(d, 1) for d in lateral]
    metrics["forward_positions_px"] = [round(p, 1) for p in forward]

    path_drift_deg = metrics["path_drift_deg"]
    min_forward_px = avg_r * 0.25
    frame_angles = []
    for i in range(1, tracked):
        dx = moving_centers[i][0] - moving_centers[i - 1][0]
        dy = moving_centers[i][1] - moving_centers[i - 1][1]
        forward = dx * vx + dy * vy
        if forward > min_forward_px:
            frame_angles.append(math.degrees(math.atan2(dx, dy)))
    if len(frame_angles) >= 2:
        residuals = [a - path_drift_deg for a in frame_angles]
        metrics["direction_wobble_deg"] = round(
            math.sqrt(sum(r * r for r in residuals) / len(residuals)), 2
        )
    else:
        metrics["direction_wobble_deg"] = 0.0

    return metrics




def attach_velocity_metrics(metrics, manifest, fps):
    results = metrics.get("per_frame_results", [])
    frame_times = build_frame_times(manifest, len(results), fps)
    mph_per_inch_s = 3600.0 / 63360.0

    for result in results:
        result["velocity_in_s"] = None
        result["velocity_mph"] = None
        result["velocity_ball_diam_s"] = None
        result["step_distance_in"] = None
        result["step_distance_ball_diam"] = None

    valid_speeds_mph = []
    valid_speeds_ball_diam_s = []
    total_distance_in = 0.0
    total_distance_ball_diam = 0.0
    prev_index = None

    for index, result in enumerate(results):
        if not result.get("ball_found"):
            continue

        if prev_index is not None:
            prev_result = results[prev_index]
            dt = frame_times[index] - frame_times[prev_index]
            if 0.0 < dt <= MAX_VELOCITY_GAP_S:
                avg_radius_px = max((prev_result["radius"] + result["radius"]) * 0.5, 1.0)
                avg_diameter_px = avg_radius_px * 2.0
                dx = float(result["cx"] - prev_result["cx"])
                dy = float(result["cy"] - prev_result["cy"])
                step_px = math.hypot(dx, dy)
                step_ball_diam = step_px / avg_diameter_px

                if step_ball_diam >= MIN_MOTION_DIAMETERS:
                    step_in = step_ball_diam * GOLF_BALL_DIAMETER_IN
                    speed_in_s = step_in / dt
                    speed_mph = speed_in_s * mph_per_inch_s
                    speed_ball_diam_s = step_ball_diam / dt

                    result["velocity_in_s"] = speed_in_s
                    result["velocity_mph"] = speed_mph
                    result["velocity_ball_diam_s"] = speed_ball_diam_s
                    result["step_distance_in"] = step_in
                    result["step_distance_ball_diam"] = step_ball_diam

                    valid_speeds_mph.append(speed_mph)
                    valid_speeds_ball_diam_s.append(speed_ball_diam_s)
                    total_distance_in += step_in
                    total_distance_ball_diam += step_ball_diam
                else:
                    result["velocity_in_s"] = 0.0
                    result["velocity_mph"] = 0.0
                    result["velocity_ball_diam_s"] = 0.0
                    result["step_distance_in"] = 0.0
                    result["step_distance_ball_diam"] = 0.0

        prev_index = index

    metrics["velocity_valid_frames"] = len(valid_speeds_mph)
    metrics["peak_velocity_mph"] = max(valid_speeds_mph) if valid_speeds_mph else 0.0
    metrics["avg_velocity_mph"] = (
        sum(valid_speeds_mph) / len(valid_speeds_mph) if valid_speeds_mph else 0.0
    )
    metrics["peak_velocity_ball_diam_s"] = (
        max(valid_speeds_ball_diam_s) if valid_speeds_ball_diam_s else 0.0
    )
    metrics["avg_velocity_ball_diam_s"] = (
        sum(valid_speeds_ball_diam_s) / len(valid_speeds_ball_diam_s)
        if valid_speeds_ball_diam_s
        else 0.0
    )
    metrics["total_roll_distance_in"] = total_distance_in
    metrics["total_roll_distance_ball_diam"] = total_distance_ball_diam
    return metrics


def print_velocity_results(metrics):
    print("  velocity frames:   {}".format(metrics.get("velocity_valid_frames", 0)))
    print("  avg velocity:      {:.2f} mph ({:.2f} ball/s)".format(
        metrics.get("avg_velocity_mph", 0.0),
        metrics.get("avg_velocity_ball_diam_s", 0.0),
    ))
    print("  peak velocity:     {:.2f} mph ({:.2f} ball/s)".format(
        metrics.get("peak_velocity_mph", 0.0),
        metrics.get("peak_velocity_ball_diam_s", 0.0),
    ))
    print("  roll distance:     {:.2f} in ({:.2f} ball diameters)".format(
        metrics.get("total_roll_distance_in", 0.0),
        metrics.get("total_roll_distance_ball_diam", 0.0),
    ))
    print("")


def build_review_panel(result, metrics, index, total, manifest):
    debug = result["debug_frame"].copy()
    track_mode = result.get("tracking_mode", "detect")
    status = "ball tracked" if result.get("ball_found") else "no detection"

    drift = metrics.get("path_drift_deg", 0.0)
    rms = metrics.get("rms_lateral_px", 0.0)
    avg_r = metrics.get("avg_radius_px", 1.0)
    wobble = metrics.get("direction_wobble_deg", 0.0)
    drift_dir = "R" if drift > 0 else "L"
    drift_abs = abs(drift)

    cv2.putText(
        debug,
        "frame {}/{}".format(index + 1, total),
        (12, 24),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (0, 255, 255),
        2,
    )
    if result.get("ball_found"):
        cv2.circle(debug, (int(result["cx"]), int(result["cy"])), int(result["radius"]), (255, 255, 0), 2)
        cv2.circle(debug, (int(result["cx"]), int(result["cy"])), 2, (255, 255, 0), -1)
        cv2.putText(
            debug,
            "center=({}, {})  r={}".format(result["cx"], result["cy"], result["radius"]),
            (12, 56),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (255, 255, 255),
            2,
        )
    drift_color = (0, 220, 0) if drift_abs < 2.0 else (0, 165, 255) if drift_abs < 5.0 else (0, 80, 255)
    cv2.putText(
        debug,
        "path drift {:.2f}deg {}".format(drift_abs, drift_dir),
        (12, 80),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        drift_color,
        2,
    )
    cv2.putText(
        debug,
        "RMS lateral {:.3f} diam".format(rms / max(avg_r * 2, 1)),
        (12, 104),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (0, 200, 255),
        2,
    )
    wobble_color = (0, 220, 0) if wobble < 2.0 else (0, 165, 255) if wobble < 5.0 else (0, 80, 255)
    cv2.putText(
        debug,
        "dir wobble {:.2f}deg".format(wobble),
        (12, 128),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        wobble_color,
        2,
    )
    cv2.putText(
        debug,
        "{} | {}".format(status, track_mode),
        (12, debug.shape[0] - 34),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (255, 255, 0),
        2,
    )
    cv2.putText(
        debug,
        "left/right or p/n to step | space next | q quit | {} frames @ {:.1f} fps".format(
            manifest.get("frame_count", total), estimate_fps(manifest)
        ),
        (12, debug.shape[0] - 14),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (255, 255, 255),
        2,
    )
    return resize_for_screen(debug)


def review_capture(frames, metrics, manifest):
    if not frames:
        print("no frames to review")
        return

    index = 0
    cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)

    while True:
        panel = build_review_panel(
            metrics["per_frame_results"][index],
            metrics,
            index,
            len(frames),
            manifest,
        )
        cv2.imshow(WINDOW_NAME, panel)

        key = cv2.waitKeyEx(0)
        if key in (ord("q"), 27):
            break
        if key in (ord(" "), ord("n"), 2555904):
            index = min(index + 1, len(frames) - 1)
            continue
        if key in (ord("p"), 2424832):
            index = max(index - 1, 0)
            continue

    cv2.destroyWindow(WINDOW_NAME)


def _ble_thread_main():
    global _ble_loop
    _ble_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_ble_loop)
    try:
        _ble_loop.run_until_complete(_ble_setup())
    except Exception as e:
        print("BLE setup error: {}".format(e))
        _ble_ready.set()
        return
    _ble_ready.set()
    _ble_loop.run_forever()


def _launch_capture_worker(trigger_label):
    global _capture_active
    with _capture_lock:
        if _capture_active:
            print("BLE trigger ignored - capture already running ({})".format(trigger_label))
            return
        _capture_active = True

    def worker():
        global _capture_active
        try:
            print("BLE trigger received: {}".format(trigger_label))
            run_capture_once(calibrate=False)
        except Exception as exc:
            print("BLE-triggered capture failed: {}".format(exc))
        finally:
            with _capture_lock:
                _capture_active = False

    threading.Thread(target=worker, daemon=True).start()


def handle_ble_write(characteristic, value, **kwargs):
    char_uuid = str(getattr(characteristic, "uuid", "")).lower()
    payload = bytes(value or b"")
    text = payload.decode("utf-8", errors="ignore").strip()
    print(
        "BLE write: {} -> {}".format(
            char_uuid or "(unknown characteristic)",
            text or payload,
        ),
    )
    if char_uuid != BALL_TRIGGER_CHAR_UUID.lower():
        return
    if text.startswith("FWD"):
        _launch_capture_worker(text)


async def _ble_setup():
    global _ble_server
    _ble_server = BlessServer(name=BLE_DEVICE_NAME, loop=_ble_loop)
    _ble_server.read_request_func = lambda char, **kwargs: char.value
    _ble_server.write_request_func = handle_ble_write

    await _ble_server.add_new_service(BALL_DATA_SERVICE_UUID)
    await _ble_server.add_new_characteristic(
        BALL_DATA_SERVICE_UUID,
        BALL_DATA_CHAR_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
        None,
        GATTAttributePermissions.readable,
    )
    await _ble_server.add_new_characteristic(
        BALL_DATA_SERVICE_UUID,
        BALL_TRIGGER_CHAR_UUID,
        GATTCharacteristicProperties.write
        | GATTCharacteristicProperties.write_without_response,
        None,
        GATTAttributePermissions.writeable,
    )
    await _ble_server.add_new_characteristic(
        BALL_DATA_SERVICE_UUID,
        TIMESERIES_CHAR_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
        None,
        GATTAttributePermissions.readable,
    )
    await _ble_server.start()
    print("BLE: advertising as '{}'".format(BLE_DEVICE_NAME))


def _start_ble_server():
    if not _ble_available:
        print("warning: bless not installed — BLE disabled")
        print("  run: pip3 install bless")
        return
    t = threading.Thread(target=_ble_thread_main, daemon=True)
    t.start()
    if not _ble_ready.wait(timeout=10):
        print("warning: BLE server did not start in time")


def _pack_metrics(metrics):
    # 39 bytes: 8×float32 + uint8 + uint16 + float32  (little-endian)
    #  0- 3  float32  path_drift_deg
    #  4- 7  float32  rms_lateral_px
    #  8-11  float32  direction_wobble_deg
    # 12-15  float32  total_path_px
    # 16-19  float32  avg_radius_px
    # 20-31  float32×3  reserved (0.0)
    # 32     uint8    tracking_quality_pct
    # 33-34  uint16   frame_count
    # 35-38  float32  fps
    return struct.pack(
        "<8fBHf",
        float(metrics.get("path_drift_deg", 0.0)),
        float(metrics.get("rms_lateral_px", 0.0)),
        float(metrics.get("direction_wobble_deg", 0.0)),
        float(metrics.get("total_path_px", 0.0)),
        float(metrics.get("avg_radius_px", 0.0)),
        0.0,
        0.0,
        0.0,
        int(metrics.get("tracking_quality_pct", 0)),
        int(metrics.get("total_frames", 0)),
        float(metrics.get("fps", 0.0)),
    )


async def _async_notify(data):
    if _ble_server is None:
        return
    char = _ble_server.get_characteristic(BALL_DATA_CHAR_UUID)
    if char is None:
        print("BLE: characteristic not found")
        return
    print("BLE: preparing to notify {} byte payload".format(len(data)))
    await asyncio.sleep(BLE_NOTIFY_INITIAL_DELAY_S)

    delivered = False
    for attempt in range(1, BLE_NOTIFY_RETRY_COUNT + 1):
        char.value = bytearray(data)
        notified = _ble_server.update_value(BALL_DATA_SERVICE_UUID, BALL_DATA_CHAR_UUID)
        print(
            "BLE: notify attempt {}/{} -> {}".format(
                attempt,
                BLE_NOTIFY_RETRY_COUNT,
                notified,
            ),
        )
        delivered = delivered or bool(notified)
        if attempt < BLE_NOTIFY_RETRY_COUNT:
            await asyncio.sleep(BLE_NOTIFY_RETRY_DELAY_S)

    if not delivered:
        print("BLE: no iPad subscribed - data not delivered")


def _notify_ipad(metrics):
    if not _ble_available or _ble_server is None or _ble_loop is None:
        print("BLE not available — skipping iPad notification")
        return
    data = _pack_metrics(metrics)
    try:
        asyncio.run_coroutine_threadsafe(
            _async_notify(data), _ble_loop
        ).result(timeout=5)
        print(
            "BLE: notify sequence finished ({} bytes, {} attempts)".format(
                len(data),
                BLE_NOTIFY_RETRY_COUNT,
            ),
        )
    except Exception as exc:
        print("warning: BLE notification failed: {}".format(exc))


def _pack_timeseries(metrics):
    """
    Pack per-frame lateral deviation and forward position into a compact BLE payload.
    Layout (little-endian):
      0     uint8    N  (sample count, up to 40)
      1     float32  fps
      5     N×int16  lateral_deviation_px × 100  (precision 0.01 px, range ±327 px)
      5+2N  N×int16  forward_position_px × 10    (precision 0.1 px, range ±3276 px)
    Total: 5 + 4N bytes (max 165 bytes for N=40)
    """
    lateral = metrics.get("lateral_deviations_px", [])
    forward = metrics.get("forward_positions_px", [])
    fps = float(metrics.get("fps", 13.0))

    N = min(len(lateral), len(forward), 40)
    if N == 0:
        return struct.pack("<Bf", 0, fps)

    lat_enc = [max(-32767, min(32767, int(round(v * 100)))) for v in lateral[:N]]
    fwd_enc = [max(-32767, min(32767, int(round(v * 10)))) for v in forward[:N]]

    fmt = "<Bf{}h{}h".format(N, N)
    return struct.pack(fmt, N, fps, *lat_enc, *fwd_enc)


async def _async_notify_timeseries(data):
    if _ble_server is None:
        return
    char = _ble_server.get_characteristic(TIMESERIES_CHAR_UUID)
    if char is None:
        print("BLE: time-series characteristic not found")
        return
    await asyncio.sleep(BLE_NOTIFY_INITIAL_DELAY_S)

    delivered = False
    for attempt in range(1, BLE_NOTIFY_RETRY_COUNT + 1):
        char.value = bytearray(data)
        notified = _ble_server.update_value(BALL_DATA_SERVICE_UUID, TIMESERIES_CHAR_UUID)
        print(
            "BLE: time-series attempt {}/{} -> {}".format(
                attempt,
                BLE_NOTIFY_RETRY_COUNT,
                notified,
            ),
        )
        delivered = delivered or bool(notified)
        if attempt < BLE_NOTIFY_RETRY_COUNT:
            await asyncio.sleep(BLE_NOTIFY_RETRY_DELAY_S)

    if not delivered:
        print("BLE: no iPad subscribed - time series not delivered")


def _notify_timeseries(metrics):
    if not _ble_available or _ble_server is None or _ble_loop is None:
        return
    data = _pack_timeseries(metrics)
    try:
        asyncio.run_coroutine_threadsafe(
            _async_notify_timeseries(data), _ble_loop
        ).result(timeout=5)
        print(
            "BLE: time-series sequence finished ({} bytes, {} frames, {} attempts)".format(
                len(data),
                data[0] if data else 0,
                BLE_NOTIFY_RETRY_COUNT,
            ),
        )
    except Exception as exc:
        print("warning: BLE time series failed: {}".format(exc))




def run_capture_once(calibrate=False):
    print("")
    print("triggering burst capture...")
    trigger_response = trigger_burst()
    if not trigger_response.get("accepted", True):
        raise RuntimeError("burst trigger was not accepted: {}".format(trigger_response))

    wait_for_ready()
    manifest = fetch_json(MANIFEST_URL)
    frame_count = manifest.get("frame_count", 0)
    fps = estimate_fps(manifest)

    print("")
    print("capture ready")
    print("  frames: {}".format(frame_count))
    print("  pre-trigger frames: {}".format(manifest.get("pre_frame_count", 0)))
    print("  fps estimate: {:.1f}".format(fps))
    print("  finish reason: {}".format(manifest.get("finish_reason", "unknown")))

    if calibrate:
        if not run_calibration_session(manifest):
            return
        print("calibration saved; run a normal capture to test it")
        return
    loaded_settings = load_detector_settings()
    if loaded_settings is not None:
        print("using detector calibration from {}".format(CALIBRATION_PATH.name))
    else:
        print("warning: no detector calibration file found, using built-in defaults")
    frames = download_frames(manifest)
    metrics = analyze_putt(frames, fps)
    recompute_path_metrics(metrics)
    metrics["fps"] = fps
    print_results(metrics)
    _notify_ipad(metrics)
    _notify_timeseries(metrics)

    review_capture(frames, metrics, manifest)


def main():
    loaded_settings = load_detector_settings()
    _start_ble_server()
    print("=" * 50)
    print("  OV5640 Burst Analyzer  (iPad BLE)")
    print("=" * 50)
    print("")
    print("  target:      {}".format(BASE_URL))
    print("  BLE name:    {}".format(BLE_DEVICE_NAME))
    print("  make sure the laptop is connected to Wi-Fi OV5640-Burst")
    print("  open Nathan's app — it will auto-connect to '{}'".format(BLE_DEVICE_NAME))
    if loaded_settings is not None:
        print("  detector calibration loaded from {}".format(CALIBRATION_PATH.name))
    print("")

    try:
        status = fetch_json(STATUS_URL)
        print("device online - state={}".format(status.get("state", "unknown")))
    except Exception as exc:
        raise RuntimeError(
            "could not reach burst camera at {} - connect to OV5640-Burst first".format(BASE_URL)
        ) from exc

    while True:
        command = read_command()
        if command == "q":
            break
        run_capture_once(calibrate=(command == "c"))


if __name__ == "__main__":
    main()
