#!/usr/bin/env python
"""
Bridge between the Flutter desktop app and the local burst analyzer workflow.

This script intentionally keeps the contract small:
- `capture`: trigger a burst, analyze it, export artifacts, print a JSON result
- `calibrate`: trigger a burst, open the OpenCV calibration UI, print a JSON result
"""

from __future__ import annotations

import argparse
import contextlib
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import cv2


TOOL_DIR = Path(__file__).resolve().parent
FRONTEND_ROOT = TOOL_DIR.parent
RUNTIME_ROOT = TOOL_DIR / "camera_runtime"
ARTIFACT_ROOT = FRONTEND_ROOT / "camera_runs"
RESULT_PREFIX = "CAMERA_BRIDGE_RESULT="

if str(RUNTIME_ROOT) not in sys.path:
    sys.path.insert(0, str(RUNTIME_ROOT))

import burst_analyzer as ba  # noqa: E402


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def emit_result(payload: dict[str, Any]) -> None:
    print(RESULT_PREFIX + json.dumps(payload), flush=True)


def ensure_artifact_root() -> None:
    ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)


def render_export_frame(
    frame,
    result: dict[str, Any],
    metrics: dict[str, Any],
    index: int,
    total: int,
    manifest: dict[str, Any],
):
    debug = result["debug_frame"].copy()
    burst_mode = result.get("burst_track_mode", "raw")
    raw_mode = result.get("raw_tracking_mode", result.get("tracking_mode", "detect"))

    status = (
        "ball+line"
        if result.get("ball_found") and result.get("line_found")
        else "ball only"
        if result.get("ball_found")
        else "no detection"
    )
    angle_text = "angle n/a"
    if result.get("angle") is not None:
        angle_text = "angle {:.1f} deg".format(ba.math.degrees(result["angle"]))

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
        (12, 50),
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

    if result.get("ball_found"):
        cv2.circle(debug, (int(result["cx"]), int(result["cy"])), int(result["radius"]), (255, 255, 0), 2)
        cv2.circle(debug, (int(result["cx"]), int(result["cy"])), 2, (255, 255, 0), -1)
        cv2.putText(
            debug,
            "center=({}, {}) r={}".format(result["cx"], result["cy"], result["radius"]),
            (12, 76),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
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
            (12, 102),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 255),
            2,
        )

    cv2.putText(
        debug,
        "rotation {:.1f} deg/s | wobble {} {:.1f} deg".format(
            metrics.get("rotation_rate_deg_s", 0.0),
            "YES" if metrics.get("wobble_detected") else "NO",
            metrics.get("wobble_magnitude_deg", 0.0),
        ),
        (12, 128),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.52,
        (0, 200, 255),
        2,
    )
    cv2.putText(
        debug,
        angle_text,
        (12, 154),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.52,
        (255, 255, 0),
        2,
    )
    cv2.putText(
        debug,
        "capture {} frames @ {:.1f} fps".format(
            manifest.get("frame_count", total),
            ba.estimate_fps(manifest),
        ),
        (12, debug.shape[0] - 14),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (255, 255, 255),
        2,
    )
    return ba.resize_for_screen(debug)


def write_video(frames, manifest, run_dir: Path) -> str | None:
    if not frames:
        return None

    source_fps = max(float(ba.estimate_fps(manifest)), 1.0)
    output_fps = min(8.0, max(4.0, source_fps / 4.0))
    height, width = frames[0].shape[:2]

    mp4_path = run_dir / "slowmo_roll.mp4"
    avi_path = run_dir / "slowmo_roll.avi"

    for path, fourcc_name in ((mp4_path, "mp4v"), (avi_path, "MJPG")):
        writer = cv2.VideoWriter(
            str(path),
            cv2.VideoWriter_fourcc(*fourcc_name),
            output_fps,
            (width, height),
        )
        if not writer.isOpened():
            continue
        for frame in frames:
            writer.write(frame)
        writer.release()
        return str(path)

    return None


def summarize_metrics(metrics: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    valid_angles_deg = []
    for result in metrics.get("per_frame_results", []):
        angle = result.get("angle")
        if angle is not None:
            valid_angles_deg.append(float(ba.math.degrees(angle)))

    return {
        "frameCount": int(manifest.get("frame_count", metrics.get("total_frames", 0))),
        "preTriggerFrames": int(manifest.get("pre_frame_count", 0)),
        "fpsEstimate": float(ba.estimate_fps(manifest)),
        "finishReason": manifest.get("finish_reason", "unknown"),
        "angleDeg": round(sum(valid_angles_deg) / len(valid_angles_deg), 1) if valid_angles_deg else 0.0,
        "validFrames": int(metrics.get("valid_frames", 0)),
        "totalFrames": int(metrics.get("total_frames", 0)),
        "detectionRate": float(metrics.get("detection_rate", 0.0)),
        "rotationRateDegS": float(metrics.get("rotation_rate_deg_s", 0.0)),
        "wobbleDetected": bool(metrics.get("wobble_detected", False)),
        "wobbleMagnitudeDeg": float(metrics.get("wobble_magnitude_deg", 0.0)),
        "avgVelocityMph": float(metrics.get("avg_velocity_mph", 0.0)),
        "peakVelocityMph": float(metrics.get("peak_velocity_mph", 0.0)),
        "avgVelocityBallPerS": float(metrics.get("avg_velocity_ball_diam_s", 0.0)),
        "peakVelocityBallPerS": float(metrics.get("peak_velocity_ball_diam_s", 0.0)),
        "totalRollDistanceIn": float(metrics.get("total_roll_distance_in", 0.0)),
    }


def save_capture_artifacts(
    frames,
    metrics: dict[str, Any],
    manifest: dict[str, Any],
) -> dict[str, Any]:
    ensure_artifact_root()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_ROOT / timestamp
    frames_dir = run_dir / "frames"
    debug_dir = run_dir / "debug"
    frames_dir.mkdir(parents=True, exist_ok=True)
    debug_dir.mkdir(parents=True, exist_ok=True)

    exported_debug_frames = []
    frame_paths = []
    debug_paths = []

    results = metrics.get("per_frame_results", [])
    for index, frame in enumerate(frames):
        frame_path = frames_dir / "frame_{:03d}.jpg".format(index + 1)
        debug_frame = render_export_frame(frame, results[index], metrics, index, len(frames), manifest)
        debug_path = debug_dir / "debug_{:03d}.jpg".format(index + 1)
        cv2.imwrite(str(frame_path), frame)
        cv2.imwrite(str(debug_path), debug_frame)
        exported_debug_frames.append(debug_frame)
        frame_paths.append(str(frame_path))
        debug_paths.append(str(debug_path))

    video_path = write_video(exported_debug_frames, manifest, run_dir)
    summary = summarize_metrics(metrics, manifest)
    result_payload = {
        "ok": True,
        "action": "capture",
        "message": "Capture and analysis complete",
        "runDirectory": str(run_dir),
        "framesDirectory": str(frames_dir),
        "debugFramesDirectory": str(debug_dir),
        "videoPath": video_path,
        "calibrationPath": str(ba.CALIBRATION_PATH),
        "summary": summary,
        "framePaths": frame_paths,
        "debugFramePaths": debug_paths,
    }
    result_json_path = run_dir / "result.json"
    result_json_path.write_text(json.dumps(result_payload, indent=2), encoding="utf-8")
    result_payload["resultJsonPath"] = str(result_json_path)
    result_json_path.write_text(json.dumps(result_payload, indent=2), encoding="utf-8")
    return result_payload


def ensure_device_available() -> None:
    with contextlib.redirect_stdout(sys.stderr):
        ba.fetch_json(ba.STATUS_URL)


def run_capture() -> dict[str, Any]:
    ba.load_detector_settings()
    ensure_device_available()
    with contextlib.redirect_stdout(sys.stderr):
        trigger_response = ba.trigger_burst()
        if not trigger_response.get("accepted", True):
            raise RuntimeError("burst trigger was not accepted: {}".format(trigger_response))
        ba.wait_for_ready()
        manifest = ba.fetch_json(ba.MANIFEST_URL)
        fps = ba.estimate_fps(manifest)
        frames = ba.download_frames(manifest)
        metrics = ba.analyze_putt(frames, fps)
        ba.stabilize_burst_tracking(metrics, frames, manifest, fps)
        ba.attach_velocity_metrics(metrics, manifest, fps)
    return save_capture_artifacts(frames, metrics, manifest)


def run_calibrate() -> dict[str, Any]:
    ba.load_detector_settings()
    ensure_device_available()
    with contextlib.redirect_stdout(sys.stderr):
        trigger_response = ba.trigger_burst()
        if not trigger_response.get("accepted", True):
            raise RuntimeError("burst trigger was not accepted: {}".format(trigger_response))
        ba.wait_for_ready()
        manifest = ba.fetch_json(ba.MANIFEST_URL)
        saved = ba.run_calibration_session(manifest)
    return {
        "ok": saved,
        "action": "calibrate",
        "message": "Calibration saved" if saved else "Calibration cancelled",
        "calibrationPath": str(ba.CALIBRATION_PATH),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bridge local burst analyzer to Flutter app")
    parser.add_argument("action", choices=("capture", "calibrate"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.action == "capture":
            payload = run_capture()
        else:
            payload = run_calibrate()
        emit_result(payload)
        return 0
    except Exception as exc:  # noqa: BLE001
        emit_result(
            {
                "ok": False,
                "action": args.action,
                "message": str(exc),
            }
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
