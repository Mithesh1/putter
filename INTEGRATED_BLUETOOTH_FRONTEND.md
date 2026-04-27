# Integrated Bluetooth Frontend

This branch packages the ball-data Bluetooth frontend work that was debugged and validated locally on April 27, 2026.

## What changed

### Flutter app

- Added `lib/services/ball_data_service.dart`
  - Scans for the ball-data BLE peripheral
  - Connects and subscribes to the ball-data characteristic
  - Decodes a fixed 39-byte payload:
    - `8` little-endian `float32`
    - `1` byte wobble flag
    - `1` little-endian `uint16` frame count
    - `1` little-endian `float32` fps
  - Emits app-side debug messages
  - Caches the latest received packet for immediate UI display

- Updated `lib/main.dart`
  - Starts/stops `BallDataService` alongside the app BLE lifecycle
  - Adds a `Ball Data Debug` card to the Home screen
  - Replaces the old Ball Roll metric with a live Ball Speed metric
  - Adds a `Ball Roll Analysis` section showing roll, spin, wobble, frames, and fps

### Python sender

- Added `burst_run/burst_wifi_switch.py`
  - Runs the OV5640 burst analyzer workflow over Wi-Fi
  - Advertises as a BLE peripheral named `BurstAnalyzer`
  - Sends the processed ball metrics to the iPad over BLE
  - Uses the `bless` API variant that works with the locally installed package
  - Retries BLE notifications multiple times with short delays to improve delivery reliability

- Added `burst_run/ball_analyzer.py`
  - Local analysis dependency used by `burst_wifi_switch.py`

## Known working behavior

- The Mac script can:
  - connect to the ESP32 Wi-Fi AP
  - trigger burst capture
  - download frames
  - analyze the burst
  - advertise `BurstAnalyzer`
  - send the 39-byte BLE metrics payload

- The iPad app can:
  - discover the BLE peripheral
  - connect to it
  - subscribe to notifications
  - display received metrics in the Home screen UI

## How to run locally

1. Connect the Mac to the `OV5640-Burst` Wi-Fi network.
2. From the repo root, run:

```bash
cd /Users/ballae/dev/designcode/burst_run
/Users/ballae/dev/designcode/.venv-burst/bin/python burst_wifi_switch.py
```

3. Open the iPad app on the Home screen.
4. Watch the `Ball Data Debug` card for:
   - device discovery
   - connecting
   - subscription
   - packet receipt
5. Press `Enter` in the Python script to trigger a capture.

## Notes

- The local Python virtualenv `.venv-burst/` is intentionally ignored.
- The unrelated local firmware edit in `firmware/putteriq_firmware/putteriq_firmware.ino` is not included in this branch.
