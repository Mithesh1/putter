"""
Higher-resolution burst capture client for the OV5640 ESP32-S3 setup.

This script talks to the burst camera board over HTTP:
1. Trigger a burst capture on the ESP32.
2. Download the saved JPEG frames after capture completes.
3. Reuse the existing local ball analysis pipeline on those frames.
4. Push the processed metrics to the frontend over Bluetooth (BLE).
5. Let the user step through analyzed frames afterward.

Requires:
    pip install bless
"""

import asyncio
import http.client
import json
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
STATIONARY_GATE_DIAMETERS = 0.45
POST_TRIGGER_ANCHOR_HOLD_FRAMES = 2
RELEASE_MIN_STEP_DIAMETERS = 0.30
RELEASE_CONFIRM_FRAMES = 2
MAX_TRACK_STEP_DIAMETERS = 2.20
MAX_PREDICTION_ERROR_DIAMETERS = 1.30
MAX_RADIUS_CHANGE_RATIO = 0.45
MAX_HOLD_FRAMES = 3
MAX_SIGNATURE_DISTANCE = 0.48
SIGNATURE_BLEND = 0.20

BLE_DEVICE_NAME = "BurstAnalyzer"
BALL_DATA_SERVICE_UUID = "12340000-0000-4b59-9000-000000000001"
BALL_DATA_CHAR_UUID = "12340000-0000-4b59-9000-000000000002"
BLE_NOTIFY_RETRY_COUNT = 3
BLE_NOTIFY_RETRY_DELAY_S = 0.2
BLE_NOTIFY_INITIAL_DELAY_S = 0.15

_ble_available = False
_ble_loop = None
_ble_server = None
_ble_ready = threading.Event()

try:
    from bless import (
        BlessServer,
        GATTAttributePermissions,
        GATTCharacteristicProperties,
    )

    _ble_available = True
except Exception as ble_import_error:
    print("BLE import failed: {}".format(ble_import_error))
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
    normalized["WHITE_GRAY_PERCENTILE"] = int(
        np.clip(normalized["WHITE_GRAY_PERCENTILE"], 1, 99),
    )
    normalized["MIN_BALL_SCORE"] = round(
        float(np.clip(normalized["MIN_BALL_SCORE"], 0.1, 4.0)),
        2,
    )
    normalized["LOW_LIGHT_THRESHOLD"] = int(
        np.clip(normalized["LOW_LIGHT_THRESHOLD"], 0, 255),
    )
    normalized["LOW_LIGHT_GRAY_MIN"] = int(
        np.clip(normalized["LOW_LIGHT_GRAY_MIN"], 0, 255),
    )
    normalized["LOW_LIGHT_HOUGH_PARAM2_DELTA"] = int(
        np.clip(normalized["LOW_LIGHT_HOUGH_PARAM2_DELTA"], 0, 40),
    )
    return normalized


def collect_detector_settings():
    return normalize_detector_settings(
        {key: getattr(ba, key) for key in DETECTOR_SETTING_KEYS},
    )


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
    CALIBRATION_PATH.write_text(
        json.dumps(normalized, indent=2),
        encoding="utf-8",
    )
    if not CALIBRATION_PATH.exists():
        raise RuntimeError(
            "failed to create calibration file at {}".format(CALIBRATION_PATH),
        )
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
    return (
        bool(data)
        and len(data) >= MIN_JPEG_BYTES
        and data[:2] == b"\xff\xd8"
        and data[-2:] == b"\xff\xd9"
    )


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
                raise RuntimeError(
                    "incomplete jpeg payload ({} bytes)".format(len(payload)),
                )
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
        raise RuntimeError(
            "burst trigger failed: HTTP {} {}".format(exc.code, body),
        ) from exc


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
            raise RuntimeError(
                "device reported error: {}".format(status.get("error", "unknown")),
            )

        time.sleep(POLL_INTERVAL)

    raise RuntimeError("timed out waiting for burst capture")


def download_frame(frame_id):
    try:
        jpg = fetch_bytes(FRAME_URL_TEMPLATE.format(index=frame_id))
    except Exception as exc:
        raise RuntimeError(
            "failed downloading frame {} after retries".format(frame_id),
        ) from exc
    arr = np.frombuffer(jpg, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise RuntimeError("failed to decode frame {}".format(frame_id))
    return frame


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
    height, width = image.shape[:2]
    scale = min(max_width / float(width), max_height / float(height), 1.0)
    if scale >= 1.0:
        return image
    return cv2.resize(
        image,
        (int(round(width * scale)), int(round(height * scale))),
        interpolation=cv2.INTER_AREA,
    )


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


def create_calibration_trackbars(total_frames, manifest):
    cv2.namedWindow(CALIBRATION_WINDOW, cv2.WINDOW_NORMAL)
    current = collect_detector_settings()
    cv2.createTrackbar(
        "frame",
        CALIBRATION_WINDOW,
        default_calibration_frame_index(manifest, total_frames),
        max(total_frames - 1, 0),
        lambda x: None,
    )
    cv2.createTrackbar(
        "param2",
        CALIBRATION_WINDOW,
        int(current["HOUGH_PARAM2"]),
        80,
        lambda x: None,
    )
    cv2.createTrackbar(
        "min radius",
        CALIBRATION_WINDOW,
        int(current["HOUGH_MIN_RADIUS"]),
        60,
        lambda x: None,
    )
    cv2.createTrackbar(
        "max radius",
        CALIBRATION_WINDOW,
        int(current["HOUGH_MAX_RADIUS"]),
        80,
        lambda x: None,
    )
    cv2.createTrackbar(
        "white sat",
        CALIBRATION_WINDOW,
        int(current["WHITE_S_MAX"]),
        255,
        lambda x: None,
    )
    cv2.createTrackbar(
        "white gray",
        CALIBRATION_WINDOW,
        int(current["WHITE_GRAY_MIN"]),
        255,
        lambda x: None,
    )
    cv2.createTrackbar(
        "gray pct",
        CALIBRATION_WINDOW,
        int(current["WHITE_GRAY_PERCENTILE"]),
        99,
        lambda x: None,
    )
    cv2.createTrackbar(
        "min score x100",
        CALIBRATION_WINDOW,
        int(round(current["MIN_BALL_SCORE"] * 100)),
        400,
        lambda x: None,
    )
    cv2.createTrackbar(
        "LL thresh",
        CALIBRATION_WINDOW,
        int(current["LOW_LIGHT_THRESHOLD"]),
        255,
        lambda x: None,
    )
    cv2.createTrackbar(
        "LL gray",
        CALIBRATION_WINDOW,
        int(current["LOW_LIGHT_GRAY_MIN"]),
        255,
        lambda x: None,
    )
    cv2.createTrackbar(
        "LL p2 delta",
        CALIBRATION_WINDOW,
        int(current["LOW_LIGHT_HOUGH_PARAM2_DELTA"]),
        40,
        lambda x: None,
    )


def read_calibration_trackbars():
    return normalize_detector_settings(
        {
            "HOUGH_PARAM2": cv2.getTrackbarPos("param2", CALIBRATION_WINDOW),
            "HOUGH_MIN_RADIUS": cv2.getTrackbarPos(
                "min radius",
                CALIBRATION_WINDOW,
            ),
            "HOUGH_MAX_RADIUS": cv2.getTrackbarPos(
                "max radius",
                CALIBRATION_WINDOW,
            ),
            "WHITE_S_MAX": cv2.getTrackbarPos("white sat", CALIBRATION_WINDOW),
            "WHITE_GRAY_MIN": cv2.getTrackbarPos(
                "white gray",
                CALIBRATION_WINDOW,
            ),
            "WHITE_GRAY_PERCENTILE": cv2.getTrackbarPos(
                "gray pct",
                CALIBRATION_WINDOW,
            ),
            "MIN_BALL_SCORE": cv2.getTrackbarPos(
                "min score x100",
                CALIBRATION_WINDOW,
            )
            / 100.0,
            "LOW_LIGHT_THRESHOLD": cv2.getTrackbarPos(
                "LL thresh",
                CALIBRATION_WINDOW,
            ),
            "LOW_LIGHT_GRAY_MIN": cv2.getTrackbarPos(
                "LL gray",
                CALIBRATION_WINDOW,
            ),
            "LOW_LIGHT_HOUGH_PARAM2_DELTA": cv2.getTrackbarPos(
                "LL p2 delta",
                CALIBRATION_WINDOW,
            ),
        },
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
        "mean brightness {:.1f} | low-light {}".format(
            mean_brightness,
            "ON" if low_light else "OFF",
        ),
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
                result["cx"],
                result["cy"],
                result["radius"],
                result.get("tracking_mode", "detect"),
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
            print(
                "calibration window closed; saved detector calibration to {}".format(
                    CALIBRATION_PATH,
                ),
            )
            saved = True
            break

        frame_index = min(
            cv2.getTrackbarPos("frame", CALIBRATION_WINDOW),
            total_frames - 1,
        )
        if frame_index != current_frame_index:
            frame_id = frame_meta[frame_index]["index"]
            if frame_id not in frame_cache:
                print(
                    "loading calibration frame {}/{}...".format(
                        frame_index + 1,
                        total_frames,
                    ),
                )
                frame_cache[frame_id] = download_frame(frame_id)
            current_frame = frame_cache[frame_id]
            current_frame_index = frame_index

        applied = apply_detector_settings(read_calibration_trackbars())
        result, _, _ = ba.process_frame(current_frame.copy())
        preview = add_calibration_overlay(
            current_frame,
            result,
            frame_index,
            total_frames,
            manifest,
        )
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


def result_candidate(result, raw=False):
    prefix = "raw_" if raw else ""
    if not result.get(prefix + "ball_found", False):
        return None
    return (
        float(result[prefix + "cx"]),
        float(result[prefix + "cy"]),
        float(result[prefix + "radius"]),
    )


def candidate_step_diameters(a, b):
    if a is None or b is None:
        return float("inf")
    avg_radius = max((float(a[2]) + float(b[2])) * 0.5, 1.0)
    return math.hypot(float(a[0]) - float(b[0]), float(a[1]) - float(b[1])) / (
        avg_radius * 2.0
    )


def candidate_radius_change(a, b):
    if a is None or b is None:
        return float("inf")
    avg_radius = max((float(a[2]) + float(b[2])) * 0.5, 1.0)
    return abs(float(a[2]) - float(b[2])) / avg_radius


def predicted_candidate(prev_candidate, prev_prev_candidate):
    if prev_candidate is None or prev_prev_candidate is None:
        return None
    return (
        float(prev_candidate[0])
        + (float(prev_candidate[0]) - float(prev_prev_candidate[0])),
        float(prev_candidate[1])
        + (float(prev_candidate[1]) - float(prev_prev_candidate[1])),
        float(prev_candidate[2]),
    )


def snapshot_raw_results(results):
    for result in results:
        result["raw_ball_found"] = bool(result.get("ball_found", False))
        result["raw_cx"] = result.get("cx")
        result["raw_cy"] = result.get("cy")
        result["raw_radius"] = result.get("radius")
        result["raw_line_found"] = bool(result.get("line_found", False))
        result["raw_angle"] = result.get("angle")
        result["raw_tracking_mode"] = result.get(
            "tracking_mode",
            "detect",
        )
        result["raw_line_source"] = result.get("line_source", "n/a")


def choose_anchor_candidate(results, pre_frame_count):
    window = max(int(pre_frame_count or 0), 1)
    candidates = [result_candidate(result, raw=True) for result in results[:window]]
    candidates = [candidate for candidate in candidates if candidate is not None]
    if not candidates:
        return None

    best_inliers = [candidates[0]]
    for candidate in candidates:
        inliers = [
            other
            for other in candidates
            if candidate_step_diameters(candidate, other) <= STATIONARY_GATE_DIAMETERS
            and candidate_radius_change(candidate, other) <= MAX_RADIUS_CHANGE_RATIO
        ]
        if len(inliers) > len(best_inliers):
            best_inliers = inliers

    if not best_inliers:
        best_inliers = candidates

    xs = [candidate[0] for candidate in best_inliers]
    ys = [candidate[1] for candidate in best_inliers]
    radii = [candidate[2] for candidate in best_inliers]
    return (
        float(np.median(xs)),
        float(np.median(ys)),
        float(np.median(radii)),
    )


def compute_ball_signature(frame, candidate):
    if frame is None or candidate is None:
        return None

    cx = int(round(candidate[0]))
    cy = int(round(candidate[1]))
    radius = max(int(round(candidate[2] * 0.85)), 2)
    height, width = frame.shape[:2]
    if cx - radius < 0 or cy - radius < 0 or cx + radius >= width or cy + radius >= height:
        return None

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.circle(mask, (cx, cy), radius, 255, -1)
    inside = mask > 0
    if not np.any(inside):
        return None

    local_gray = gray[inside]
    local_sat = hsv[..., 1][inside]
    bright_floor = max(100, int(np.percentile(local_gray, 55)))
    white_ratio = float(np.mean((local_gray >= bright_floor) & (local_sat <= 120)))
    return {
        "white_ratio": white_ratio,
        "mean_gray": float(np.mean(local_gray)) / 255.0,
        "mean_sat": float(np.mean(local_sat)) / 255.0,
    }


def build_anchor_signature(frames, anchor_candidate, pre_frame_count):
    window = max(int(pre_frame_count or 0), 1)
    signatures = []
    for frame in frames[:window]:
        signature = compute_ball_signature(frame, anchor_candidate)
        if signature is not None:
            signatures.append(signature)

    if not signatures:
        return None

    return {
        "white_ratio": float(np.median([sig["white_ratio"] for sig in signatures])),
        "mean_gray": float(np.median([sig["mean_gray"] for sig in signatures])),
        "mean_sat": float(np.median([sig["mean_sat"] for sig in signatures])),
    }


def signature_distance(signature, reference_signature):
    if signature is None or reference_signature is None:
        return 0.0
    return (
        1.7 * abs(signature["white_ratio"] - reference_signature["white_ratio"])
        + 1.1 * abs(signature["mean_sat"] - reference_signature["mean_sat"])
        + 0.25 * abs(signature["mean_gray"] - reference_signature["mean_gray"])
    )


def blend_signature(current_signature, new_signature):
    if current_signature is None:
        return new_signature
    if new_signature is None:
        return current_signature
    return {
        key: (1.0 - SIGNATURE_BLEND) * current_signature[key]
        + SIGNATURE_BLEND * new_signature[key]
        for key in current_signature
    }


def apply_stabilized_candidate(result, candidate, burst_mode, keep_raw_line=False):
    result["burst_track_mode"] = burst_mode
    if burst_mode == "raw":
        result["tracking_mode"] = result.get(
            "raw_tracking_mode",
            result.get("tracking_mode", "detect"),
        )
    else:
        result["tracking_mode"] = burst_mode

    if candidate is None:
        result["ball_found"] = False
        result["line_found"] = False
        result["angle"] = None
        result["line_source"] = "burst_none"
        for key in ("cx", "cy", "radius"):
            if key in result:
                del result[key]
        return

    result["ball_found"] = True
    result["cx"] = int(round(candidate[0]))
    result["cy"] = int(round(candidate[1]))
    result["radius"] = int(round(candidate[2]))

    if keep_raw_line and result.get("raw_line_found", False):
        result["line_found"] = True
        result["angle"] = result.get("raw_angle")
        result["line_source"] = result.get("raw_line_source", "n/a")
    else:
        result["line_found"] = False
        result["angle"] = None
        result["line_source"] = "burst_none"


def recompute_rotation_metrics(metrics, fps):
    results = metrics.get("per_frame_results", [])
    valid_angles = []
    valid_indices = []

    for index, result in enumerate(results):
        if (
            result.get("ball_found")
            and result.get("line_found")
            and result.get("angle") is not None
        ):
            valid_angles.append(result["angle"])
            valid_indices.append(index)

    total = len(results)
    valid = len(valid_angles)

    if valid < 2:
        metrics["rotation_rate_deg_s"] = 0.0
        metrics["wobble_detected"] = False
        metrics["wobble_magnitude_deg"] = 0.0
        metrics["detection_rate"] = valid / max(total, 1)
        metrics["valid_frames"] = valid
        metrics["total_frames"] = total
        return metrics

    dt = 1.0 / max(float(fps), 0.001)
    rotation_rates = []

    for index in range(1, valid):
        gap = valid_indices[index] - valid_indices[index - 1]
        actual_dt = gap * dt
        delta = valid_angles[index] - valid_angles[index - 1]

        if delta > math.pi / 2:
            delta -= math.pi
        if delta < -math.pi / 2:
            delta += math.pi

        rotation_rates.append(delta / actual_dt)

    avg_rad = sum(rotation_rates) / len(rotation_rates) if rotation_rates else 0.0
    avg_deg = math.degrees(avg_rad)

    if len(rotation_rates) >= 2:
        variance = (
            sum((rate - avg_rad) ** 2 for rate in rotation_rates)
            / len(rotation_rates)
        )
        wobble_deg = math.degrees(math.sqrt(variance))
    else:
        wobble_deg = 0.0

    metrics["rotation_rate_deg_s"] = round(avg_deg, 1)
    metrics["wobble_detected"] = wobble_deg > 5.0
    metrics["wobble_magnitude_deg"] = round(wobble_deg, 1)
    metrics["detection_rate"] = round(valid / max(total, 1), 2)
    metrics["valid_frames"] = valid
    metrics["total_frames"] = total
    return metrics


def stabilize_burst_tracking(metrics, frames, manifest, fps):
    results = metrics.get("per_frame_results", [])
    if not results:
      return metrics

    snapshot_raw_results(results)

    pre_frame_count = int(manifest.get("pre_frame_count", 0) or 0)
    anchor_candidate = choose_anchor_candidate(results, pre_frame_count)
    if anchor_candidate is None:
        return recompute_rotation_metrics(metrics, fps)

    anchor_signature = build_anchor_signature(frames, anchor_candidate, pre_frame_count)
    stable_signature = anchor_signature

    stable_prev = anchor_candidate
    stable_prev2 = None
    release_candidates = []
    released = False
    hold_frames = 0

    for index, result in enumerate(results):
        raw_candidate = result_candidate(result, raw=True)
        raw_signature = (
            compute_ball_signature(frames[index], raw_candidate)
            if raw_candidate is not None
            else None
        )
        radius_ok_to_anchor = (
            candidate_radius_change(raw_candidate, anchor_candidate)
            <= MAX_RADIUS_CHANGE_RATIO
        )

        if not released:
            if raw_candidate is not None and radius_ok_to_anchor:
                move_from_anchor = candidate_step_diameters(raw_candidate, anchor_candidate)
                if move_from_anchor >= RELEASE_MIN_STEP_DIAMETERS:
                    if not release_candidates:
                        release_candidates = [raw_candidate]
                    else:
                        release_step = candidate_step_diameters(
                            raw_candidate,
                            release_candidates[-1],
                        )
                        if release_step <= MAX_TRACK_STEP_DIAMETERS:
                            release_candidates.append(raw_candidate)
                        else:
                            release_candidates = [raw_candidate]
                else:
                    release_candidates = []
            else:
                release_candidates = []

            can_release_now = index >= (
                max(pre_frame_count, 0) + POST_TRIGGER_ANCHOR_HOLD_FRAMES - 1
            )
            if (
                can_release_now
                and raw_candidate is not None
                and len(release_candidates) >= RELEASE_CONFIRM_FRAMES
                and signature_distance(raw_signature, stable_signature)
                <= MAX_SIGNATURE_DISTANCE
            ):
                released = True
                stable_prev2 = stable_prev
                stable_prev = raw_candidate
                stable_signature = blend_signature(stable_signature, raw_signature)
                hold_frames = 0
                apply_stabilized_candidate(result, raw_candidate, "raw", keep_raw_line=True)
            else:
                apply_stabilized_candidate(
                    result,
                    anchor_candidate,
                    "burst_anchor",
                    keep_raw_line=False,
                )
            continue

        accept_raw = False
        if raw_candidate is not None:
            radius_ok = (
                candidate_radius_change(raw_candidate, stable_prev)
                <= MAX_RADIUS_CHANGE_RATIO
            )
            step_ok = (
                candidate_step_diameters(raw_candidate, stable_prev)
                <= MAX_TRACK_STEP_DIAMETERS
            )
            predicted = predicted_candidate(stable_prev, stable_prev2)
            prediction_ok = (
                predicted is not None
                and candidate_step_diameters(raw_candidate, predicted)
                <= MAX_PREDICTION_ERROR_DIAMETERS
            )
            signature_ok = (
                signature_distance(raw_signature, stable_signature)
                <= MAX_SIGNATURE_DISTANCE
            )
            accept_raw = radius_ok and signature_ok and (step_ok or prediction_ok)

        if accept_raw:
            stable_prev2 = stable_prev
            stable_prev = raw_candidate
            stable_signature = blend_signature(stable_signature, raw_signature)
            hold_frames = 0
            apply_stabilized_candidate(result, raw_candidate, "raw", keep_raw_line=True)
            continue

        if stable_prev is not None and hold_frames < MAX_HOLD_FRAMES:
            hold_frames += 1
            apply_stabilized_candidate(result, stable_prev, "burst_hold", keep_raw_line=False)
        else:
            apply_stabilized_candidate(result, None, "burst_lost", keep_raw_line=False)

    metrics["burst_anchor"] = {
        "cx": int(round(anchor_candidate[0])),
        "cy": int(round(anchor_candidate[1])),
        "radius": int(round(anchor_candidate[2])),
    }
    return recompute_rotation_metrics(metrics, fps)


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
    print(
        "  avg velocity:      {:.2f} mph ({:.2f} ball/s)".format(
            metrics.get("avg_velocity_mph", 0.0),
            metrics.get("avg_velocity_ball_diam_s", 0.0),
        ),
    )
    print(
        "  peak velocity:     {:.2f} mph ({:.2f} ball/s)".format(
            metrics.get("peak_velocity_mph", 0.0),
            metrics.get("peak_velocity_ball_diam_s", 0.0),
        ),
    )
    print(
        "  roll distance:     {:.2f} in ({:.2f} ball diameters)".format(
            metrics.get("total_roll_distance_in", 0.0),
            metrics.get("total_roll_distance_ball_diam", 0.0),
        ),
    )
    print("")


def build_review_panel(result, metrics, index, total, manifest):
    debug = result["debug_frame"].copy()
    burst_mode = result.get("burst_track_mode", "raw")
    raw_mode = result.get("raw_tracking_mode", result.get("tracking_mode", "detect"))

    status = (
        "ball+line"
        if result["ball_found"] and result["line_found"]
        else "ball only"
        if result["ball_found"]
        else "no detection"
    )
    angle_text = "angle n/a"
    if result["angle"] is not None:
        angle_text = "angle {:.1f} deg".format(math.degrees(result["angle"]))

    cv2.putText(
        debug,
        "frame {}/{}".format(index + 1, total),
        (12, 24),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (0, 255, 255),
        2,
    )
    cv2.putText(
        debug,
        "{} | burst {} | raw {}".format(status, burst_mode, raw_mode),
        (12, debug.shape[0] - 34),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (255, 255, 0),
        2,
    )
    if result.get("raw_ball_found"):
        raw_cx = int(result["raw_cx"])
        raw_cy = int(result["raw_cy"])
        raw_radius = int(result["raw_radius"])
        raw_matches_final = (
            result.get("ball_found")
            and raw_cx == int(result["cx"])
            and raw_cy == int(result["cy"])
            and raw_radius == int(result["radius"])
        )
        if not raw_matches_final:
            cv2.circle(debug, (raw_cx, raw_cy), raw_radius, (0, 0, 255), 1)
            cv2.putText(
                debug,
                "raw",
                (raw_cx + raw_radius + 4, raw_cy - 6),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.4,
                (0, 0, 255),
                1,
            )
    cv2.putText(
        debug,
        angle_text,
        (12, debug.shape[0] - 12),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (255, 255, 0),
        2,
    )
    if result.get("ball_found"):
        cv2.circle(
            debug,
            (int(result["cx"]), int(result["cy"])),
            int(result["radius"]),
            (255, 255, 0),
            2,
        )
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
    if result.get("velocity_mph") is not None:
        cv2.putText(
            debug,
            "speed {:.2f} mph | {:.2f} ball/s".format(
                result["velocity_mph"],
                result["velocity_ball_diam_s"],
            ),
            (12, 80),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 255),
            2,
        )
    cv2.putText(
        debug,
        "rotation {:.1f} deg/s".format(metrics.get("rotation_rate_deg_s", 0.0)),
        (12, 104),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (0, 200, 255),
        2,
    )
    cv2.putText(
        debug,
        "wobble {} | {:.1f} deg".format(
            "YES" if metrics.get("wobble_detected") else "NO",
            metrics.get("wobble_magnitude_deg", 0.0),
        ),
        (12, 128),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (0, 200, 255),
        2,
    )

    footer = "left/right or p/n to step | space next | q quit | capture {} frames @ {:.1f} fps".format(
        manifest.get("frame_count", total),
        estimate_fps(manifest),
    )
    cv2.putText(
        debug,
        footer,
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


def ble_thread_main():
    global _ble_loop
    _ble_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_ble_loop)
    try:
        _ble_loop.run_until_complete(ble_setup())
    except Exception as exc:
        print("BLE setup error: {}".format(exc))
        _ble_ready.set()
        return
    _ble_ready.set()
    _ble_loop.run_forever()


async def ble_setup():
    global _ble_server
    _ble_server = BlessServer(name=BLE_DEVICE_NAME, loop=_ble_loop)
    _ble_server.read_request_func = lambda char, **kwargs: char.value

    await _ble_server.add_new_service(BALL_DATA_SERVICE_UUID)
    await _ble_server.add_new_characteristic(
        BALL_DATA_SERVICE_UUID,
        BALL_DATA_CHAR_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
        None,
        GATTAttributePermissions.readable,
    )
    await _ble_server.start()
    print("BLE: advertising as '{}'".format(BLE_DEVICE_NAME))


def start_ble_server():
    if not _ble_available:
        print("warning: bless not installed - BLE disabled")
        print("  run: pip3 install bless")
        return
    thread = threading.Thread(target=ble_thread_main, daemon=True)
    thread.start()
    if not _ble_ready.wait(timeout=10):
        print("warning: BLE server did not start in time")


def pack_metrics(metrics):
    return struct.pack(
        "<8fBHf",
        float(metrics.get("avg_velocity_mph", 0.0)),
        float(metrics.get("peak_velocity_mph", 0.0)),
        float(metrics.get("avg_velocity_ball_diam_s", 0.0)),
        float(metrics.get("peak_velocity_ball_diam_s", 0.0)),
        float(metrics.get("rotation_rate_deg_s", 0.0)),
        float(metrics.get("wobble_magnitude_deg", 0.0)),
        float(metrics.get("total_roll_distance_in", 0.0)),
        float(metrics.get("total_roll_distance_ball_diam", 0.0)),
        int(bool(metrics.get("wobble_detected", False))),
        int(metrics.get("total_frames", 0)),
        float(metrics.get("fps", 0.0)),
    )


async def async_notify(data):
    if _ble_server is None:
        return
    characteristic = _ble_server.get_characteristic(BALL_DATA_CHAR_UUID)
    if characteristic is None:
        print("BLE: characteristic not found")
        return
    print("BLE: preparing to notify {} byte payload".format(len(data)))
    await asyncio.sleep(BLE_NOTIFY_INITIAL_DELAY_S)

    delivered = False
    for attempt in range(1, BLE_NOTIFY_RETRY_COUNT + 1):
        characteristic.value = bytearray(data)
        notified = _ble_server.update_value(
            BALL_DATA_SERVICE_UUID,
            BALL_DATA_CHAR_UUID,
        )
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


def notify_frontend(metrics):
    if not _ble_available or _ble_server is None or _ble_loop is None:
        print("BLE not available - skipping frontend notification")
        return
    data = pack_metrics(metrics)
    try:
        asyncio.run_coroutine_threadsafe(
            async_notify(data),
            _ble_loop,
        ).result(timeout=5)
        print(
            "BLE: notify sequence finished ({} bytes, {} attempts)".format(
                len(data),
                BLE_NOTIFY_RETRY_COUNT,
            ),
        )
    except Exception as exc:
        print("warning: BLE notification failed: {}".format(exc))


def run_capture_once(calibrate=False):
    print("")
    print("triggering burst capture...")
    trigger_response = trigger_burst()
    if not trigger_response.get("accepted", True):
        raise RuntimeError(
            "burst trigger was not accepted: {}".format(trigger_response),
        )

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
    stabilize_burst_tracking(metrics, frames, manifest, fps)
    attach_velocity_metrics(metrics, manifest, fps)
    metrics["fps"] = fps
    print_results(metrics)
    print_velocity_results(metrics)

    notify_frontend(metrics)
    review_capture(frames, metrics, manifest)


def main():
    loaded_settings = load_detector_settings()
    start_ble_server()
    print("=" * 50)
    print("  OV5640 Burst Analyzer  (frontend BLE)")
    print("=" * 50)
    print("")
    print("  target:      {}".format(BASE_URL))
    print("  BLE name:    {}".format(BLE_DEVICE_NAME))
    print("  make sure this computer is connected to Wi-Fi OV5640-Burst")
    print("  open the Flutter app Home screen to auto-connect to '{}'".format(BLE_DEVICE_NAME))
    if loaded_settings is not None:
        print("  detector calibration loaded from {}".format(CALIBRATION_PATH.name))
    print("")

    try:
        status = fetch_json(STATUS_URL)
        print("device online - state={}".format(status.get("state", "unknown")))
    except Exception as exc:
        raise RuntimeError(
            "could not reach burst camera at {} - connect to OV5640-Burst first".format(BASE_URL),
        ) from exc

    while True:
        command = read_command()
        if command == "q":
            break
        run_capture_once(calibrate=(command == "c"))


if __name__ == "__main__":
    main()
