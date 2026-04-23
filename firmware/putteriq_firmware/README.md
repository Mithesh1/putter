# PutterIQ Firmware

This sketch targets the ESP32-S3 putter board and is designed to interoperate
with the Flutter app in this repository.

## Arduino Libraries

- `Adafruit_BNO08x`
- ESP32 Arduino core BLE libraries (`BLEDevice`, `BLEServer`, `BLEUtils`)

## BLE Contract

- Device name: `PutterIQ Putter`
- Service UUID: `f0d10000-0000-4d4f-9000-000000000001`
- Notify characteristic: `f0d10000-0000-4d4f-9000-000000000002`
- Write characteristic: `f0d10000-0000-4d4f-9000-000000000003`

The app writes one of these commands to the write characteristic:

- `0x01 + <uint32 little-endian session id>`: bind the current session id
- `0x02`: clear the bound session

The firmware sends stroke packets as BLE notifications using the fragment and
raw-packet layout defined in the Flutter app's `lib/packet_codec.dart`.
