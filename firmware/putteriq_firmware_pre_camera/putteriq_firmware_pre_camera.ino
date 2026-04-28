#include <Arduino.h>
#include <Wire.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_BNO08x.h>

/*
 * PutterIQ ESP32-S3 firmware
 *
 * This sketch keeps the putter-side sensing/state-machine logic from the
 * original prototype, then layers on:
 * - a BLE GATT service that matches the Flutter app UUIDs
 * - a tiny command channel for session binding from the phone
 * - stroke packet serialization that matches lib/packet_codec.dart
 * - BLE fragmentation that matches the app reassembler
 */

// ---------------------------------------------------------------------------
// Planned board mapping from the current custom PCB pinout
// ---------------------------------------------------------------------------

static const int PIN_I2C_SDA = 4;
static const int PIN_I2C_SCL = 5;

static const int PIN_PIEZO_1 = 6;
static const int PIN_READY_BUTTON = 44;
static const int PIN_PIEZO_3 = 8;
static const int PIN_IMU_INT = 17;
static const int PIN_IMU_RST = 18;

// ---------------------------------------------------------------------------
// BLE protocol contract shared with the Flutter app
// ---------------------------------------------------------------------------

static const char *BLE_DEVICE_NAME = "PutterIQ Putter";
static const char *BLE_SERVICE_UUID = "f0d10000-0000-4d4f-9000-000000000001";
static const char *BLE_NOTIFY_CHARACTERISTIC_UUID =
    "f0d10000-0000-4d4f-9000-000000000002";
static const char *BLE_WRITE_CHARACTERISTIC_UUID =
    "f0d10000-0000-4d4f-9000-000000000003";

static const uint16_t BLE_PREFERRED_MTU = 247;
static const uint16_t FRAGMENT_MAGIC = 0xB17E;
static const uint8_t PROTOCOL_VERSION = 1;
static const uint8_t MESSAGE_TYPE_STROKE = 0x01;

static const uint8_t COMMAND_ATTACH_SESSION = 0x01;
static const uint8_t COMMAND_CLEAR_SESSION = 0x02;
static const uint8_t COMMAND_LATENCY_PING = 0x03;

static const uint8_t IMU_ENCODING_INT16_SCALED = 1;
static const uint8_t PIEZO_ENCODING_INT16_RAW = 1;

static const uint16_t ACCEL_SCALE = 100;
static const uint16_t GYRO_SCALE = 100;
static const uint16_t QUATERNION_SCALE = 10000;

static const size_t FRAGMENT_HEADER_LENGTH = 16;
static const size_t RAW_STROKE_HEADER_LENGTH = 30;
static const size_t IMU_CHANNEL_COUNT = 10;
static const size_t PIEZO_CHANNEL_COUNT = 2;
static const size_t MAX_FRAGMENT_PAYLOAD_BYTES = 180;

// ---------------------------------------------------------------------------
// BNO configuration
// ---------------------------------------------------------------------------

static const uint32_t SERIAL_BAUD = 115200UL;
static const uint32_t BNO_REPORT_INTERVAL_US = 5000UL;
static const uint32_t DEBUG_PRINT_PERIOD_MS = 100UL;
static const uint32_t BLE_IDLE_NOTIFY_PERIOD_MS = 1000UL;
static const uint32_t IMU_STALE_TIMEOUT_MS = 500UL;
static const uint32_t PIEZO_SAMPLE_PERIOD_US = 500UL;
static const uint32_t IMU_CAPTURE_PERIOD_US = 5000UL;

#if defined(SH2_ARVR_STABILIZED_RV)
static const sh2_SensorId_t BNO_ROTATION_REPORT = SH2_ARVR_STABILIZED_RV;
#else
static const sh2_SensorId_t BNO_ROTATION_REPORT = SH2_ROTATION_VECTOR;
#endif

Adafruit_BNO08x bno08x(-1);
sh2_SensorValue_t sensorValue;

// ---------------------------------------------------------------------------
// Putter thresholds
// ---------------------------------------------------------------------------

static const float STABLE_GYRO_THRESHOLD_DPS = 4.0f;
static const float BACKSTROKE_RATE_THRESHOLD_DPS = 12.0f;
static const float FORWARD_STROKE_RATE_THRESHOLD_DPS = -10.0f;
static const float FORWARD_MOTION_END_RATE_DPS = 2.0f;
static const float PITCH_RETURN_TOLERANCE_DEG = 1.5f;

static const uint8_t MOTION_CONFIRM_FRAMES = 3;
static const uint8_t FOLLOW_THROUGH_CONFIRM_FRAMES = 2;
static const uint8_t IMPACT_GRACE_CONFIRM_FRAMES = 10;
static const uint16_t PRE_TAKEAWAY_SETUP_SAMPLES = 5;
static const uint32_t READY_BUTTON_DEBOUNCE_MS = 30UL;

static const int PIEZO_IMPACT_THRESHOLD = 200;
static const uint32_t PIEZO_REFRACTORY_MS = 60UL;

// ---------------------------------------------------------------------------
// Stroke capture sizing
// ---------------------------------------------------------------------------

static const size_t MAX_CAPTURE_IMU_SAMPLES = 1024;
static const size_t MAX_CAPTURE_PIEZO_SAMPLES = 6144;
static const uint16_t PRE_ROLL_IMU_SAMPLES = 96;
static const uint16_t PRE_ROLL_PIEZO_SAMPLES = 480;
static const uint16_t ABORT_DEBUG_IMU_SAMPLES = 64;
static const uint16_t ABORT_DEBUG_PIEZO_SAMPLES = 128;
static const size_t MAX_RAW_PACKET_BYTES =
    RAW_STROKE_HEADER_LENGTH +
    (MAX_CAPTURE_IMU_SAMPLES * IMU_CHANNEL_COUNT * sizeof(int16_t)) +
    (MAX_CAPTURE_PIEZO_SAMPLES * PIEZO_CHANNEL_COUNT * sizeof(int16_t));
static const size_t MAX_FRAGMENT_BYTES =
    FRAGMENT_HEADER_LENGTH + MAX_FRAGMENT_PAYLOAD_BYTES;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

struct EulerAngles {
  float yaw_deg;
  float pitch_deg;
  float roll_deg;
};

struct ImuSample {
  float yaw_deg;
  float pitch_deg;
  float roll_deg;

  float gyro_x_dps;
  float gyro_y_dps;
  float gyro_z_dps;

  float accel_x_g;
  float accel_y_g;
  float accel_z_g;

  float quat_i;
  float quat_j;
  float quat_k;
  float quat_r;

  bool orientation_valid;
  bool gyro_valid;
  bool accel_valid;
  bool fresh_data;

  uint32_t update_count;
  uint32_t last_update_ms;
};

struct PiezoState {
  int raw_1;
  int raw_3;

  float baseline_1;
  float baseline_3;

  int delta_1;
  int delta_3;
  int peak_delta;

  bool impact_detected;
  uint32_t last_impact_ms;
  uint32_t last_impact_us;
};

enum PuttState {
  PUTT_IDLE = 0,
  PUTT_READY_WINDOW,
  PUTT_BACKSTROKE,
  PUTT_FORWARD_STROKE,
  PUTT_IMPACT,
  PUTT_FOLLOW_THROUGH,
  PUTT_RESULT_READY,
  PUTT_ABORTED
};

struct PuttSession {
  PuttState state;
  bool full_backstroke_seen;
  bool full_forward_seen;
  bool impact_validated_by_piezo;
  uint32_t ready_pressed_ms;
  uint32_t stroke_start_ms;
  uint32_t forward_stroke_start_ms;
  uint32_t impact_ms;
  uint32_t follow_through_end_ms;
  uint8_t backstroke_confirm_frames;
  uint8_t forward_confirm_frames;
  uint8_t follow_through_confirm_frames;
  uint8_t impact_grace_frames;
  uint32_t previous_pitch_sample_ms;
  float ready_pitch_deg;
  float previous_pitch_delta_deg;
  float peak_pitch_delta_deg;

  EulerAngles setup_orientation;
  float peak_face_rotation_deg;
  float peak_stroke_rate_dps;
};

struct StrokeCapture {
  bool active;
  bool overflowed;
  uint32_t capture_start_ms;
  uint32_t capture_start_us;
  uint32_t impact_time_ms;
  uint32_t impact_time_us;
  uint16_t calibration_imu_index;
  uint16_t imu_sample_count;
  uint16_t piezo_sample_count;
  int16_t imu_data[MAX_CAPTURE_IMU_SAMPLES * IMU_CHANNEL_COUNT];
  int16_t piezo_data[MAX_CAPTURE_PIEZO_SAMPLES * PIEZO_CHANNEL_COUNT];
};

struct BufferedImuSample {
  bool valid;
  uint32_t sample_ms;
  float yaw_deg;
  float pitch_deg;
  float roll_deg;
  float gyro_x_dps;
  float gyro_y_dps;
  float gyro_z_dps;
  float accel_x_g;
  float accel_y_g;
  float accel_z_g;
  float quat_i;
  float quat_j;
  float quat_k;
  float quat_r;
  int16_t encoded[IMU_CHANNEL_COUNT];
};

struct BufferedPiezoSample {
  bool valid;
  uint32_t sample_ms;
  int16_t raw_1;
  int16_t raw_3;
};

ImuSample latestImu = {};
PiezoState latestPiezo = {};
PuttSession putt = {};
StrokeCapture strokeCapture = {};
BufferedImuSample preRollImu[PRE_ROLL_IMU_SAMPLES] = {};
BufferedPiezoSample preRollPiezo[PRE_ROLL_PIEZO_SAMPLES] = {};
uint16_t preRollImuWriteIndex = 0;
uint16_t preRollImuCount = 0;
uint16_t preRollPiezoWriteIndex = 0;
uint16_t preRollPiezoCount = 0;

uint32_t lastDebugPrintMs = 0;
uint32_t lastBleIdleNotifyMs = 0;
uint32_t stalePrintCount = 0;
bool freshDataSinceLastPrint = false;
uint32_t lastPiezoSampleUs = 0;
uint32_t lastImuCaptureUs = 0;
bool lastReadyButtonReading = HIGH;
bool readyButtonLatched = false;
uint32_t lastReadyButtonChangeMs = 0;

uint32_t activeBleSessionId = 1;
uint32_t nextPacketId = 1;
bool bleSessionBound = false;
bool bleClientConnected = false;

uint8_t rawPacketBuffer[MAX_RAW_PACKET_BYTES];
uint8_t fragmentBuffer[MAX_FRAGMENT_BYTES];

BLEServer *bleServer = nullptr;
BLECharacteristic *notifyCharacteristic = nullptr;
BLECharacteristic *writeCharacteristic = nullptr;

// ---------------------------------------------------------------------------
// Axis mapping placeholders
// ---------------------------------------------------------------------------

static float faceRotationDeg(const ImuSample &imu) {
  return imu.yaw_deg;
}

static float strokeMotionRateDps(const ImuSample &imu) {
  return imu.gyro_y_dps;
}

static float setupTiltDeg(const ImuSample &imu) {
  return imu.roll_deg;
}

static float pitchDeltaFromReadyDeg(const ImuSample &imu) {
  return imu.pitch_deg - putt.ready_pitch_deg;
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

static float wrapDegrees180(float value_deg) {
  while (value_deg > 180.0f) {
    value_deg -= 180.0f * 2.0f;
  }
  while (value_deg < -180.0f) {
    value_deg += 180.0f * 2.0f;
  }
  return value_deg;
}

static void quaternionToEuler(float qr, float qi, float qj, float qk,
                              EulerAngles *angles) {
  const float qi2 = qi * qi;
  const float qj2 = qj * qj;
  const float qk2 = qk * qk;
  const float qr2 = qr * qr;
  const float denom = qi2 + qj2 + qk2 + qr2;

  if (denom == 0.0f) {
    return;
  }

  angles->yaw_deg = atan2f(2.0f * (qi * qj + qk * qr),
                           (qi2 - qj2 - qk2 + qr2)) * RAD_TO_DEG;
  angles->pitch_deg = asinf(-2.0f * (qi * qk - qj * qr) / denom) * RAD_TO_DEG;
  angles->roll_deg = atan2f(2.0f * (qj * qk + qi * qr),
                            (-qi2 - qj2 + qk2 + qr2)) * RAD_TO_DEG;
}

static float gyroMagnitudeDps(const ImuSample &imu) {
  return sqrtf((imu.gyro_x_dps * imu.gyro_x_dps) +
               (imu.gyro_y_dps * imu.gyro_y_dps) +
               (imu.gyro_z_dps * imu.gyro_z_dps));
}

static float accelMagnitudeG(const ImuSample &imu) {
  return sqrtf((imu.accel_x_g * imu.accel_x_g) +
               (imu.accel_y_g * imu.accel_y_g) +
               (imu.accel_z_g * imu.accel_z_g));
}

static bool rateShowsBackstroke(float stroke_rate_dps) {
  return stroke_rate_dps >= BACKSTROKE_RATE_THRESHOLD_DPS;
}

static bool rateShowsForwardStroke(float stroke_rate_dps) {
  return stroke_rate_dps <= FORWARD_STROKE_RATE_THRESHOLD_DPS;
}

static bool rateStillMovingForward(float stroke_rate_dps) {
  return stroke_rate_dps <= FORWARD_MOTION_END_RATE_DPS;
}

static int16_t clampToInt16(int32_t value) {
  if (value > 32767) {
    return 32767;
  }
  if (value < -32768) {
    return -32768;
  }
  return (int16_t)value;
}

static void encodeImuSampleFromValues(
    float accel_x_g, float accel_y_g, float accel_z_g, float gyro_x_dps,
    float gyro_y_dps, float gyro_z_dps, float quat_i, float quat_j,
    float quat_k, float quat_r, int16_t *encoded) {
  encoded[0] = clampToInt16((int32_t)lroundf(accel_x_g * ACCEL_SCALE));
  encoded[1] = clampToInt16((int32_t)lroundf(accel_y_g * ACCEL_SCALE));
  encoded[2] = clampToInt16((int32_t)lroundf(accel_z_g * ACCEL_SCALE));
  encoded[3] = clampToInt16((int32_t)lroundf(gyro_x_dps * GYRO_SCALE));
  encoded[4] = clampToInt16((int32_t)lroundf(gyro_y_dps * GYRO_SCALE));
  encoded[5] = clampToInt16((int32_t)lroundf(gyro_z_dps * GYRO_SCALE));
  encoded[6] = clampToInt16((int32_t)lroundf(quat_i * QUATERNION_SCALE));
  encoded[7] = clampToInt16((int32_t)lroundf(quat_j * QUATERNION_SCALE));
  encoded[8] = clampToInt16((int32_t)lroundf(quat_k * QUATERNION_SCALE));
  encoded[9] = clampToInt16((int32_t)lroundf(quat_r * QUATERNION_SCALE));
}

static void markFreshUpdate() {
  latestImu.update_count++;
  latestImu.last_update_ms = millis();
  latestImu.fresh_data = true;
  freshDataSinceLastPrint = true;
}

// ---------------------------------------------------------------------------
// Little-endian and CRC helpers
// ---------------------------------------------------------------------------

static void writeUint16LE(uint8_t *buffer, size_t offset, uint16_t value) {
  buffer[offset + 0] = (uint8_t)(value & 0xFF);
  buffer[offset + 1] = (uint8_t)((value >> 8) & 0xFF);
}

static void writeInt16LE(uint8_t *buffer, size_t offset, int16_t value) {
  writeUint16LE(buffer, offset, (uint16_t)value);
}

static void writeUint32LE(uint8_t *buffer, size_t offset, uint32_t value) {
  buffer[offset + 0] = (uint8_t)(value & 0xFF);
  buffer[offset + 1] = (uint8_t)((value >> 8) & 0xFF);
  buffer[offset + 2] = (uint8_t)((value >> 16) & 0xFF);
  buffer[offset + 3] = (uint8_t)((value >> 24) & 0xFF);
}

static uint32_t readUint32LE(const uint8_t *buffer, size_t offset) {
  return ((uint32_t)buffer[offset + 0]) |
         ((uint32_t)buffer[offset + 1] << 8) |
         ((uint32_t)buffer[offset + 2] << 16) |
         ((uint32_t)buffer[offset + 3] << 24);
}

static uint16_t computeCrc16(const uint8_t *bytes, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t index = 0; index < length; index++) {
    crc ^= (uint16_t)bytes[index] << 8;
    for (uint8_t bit = 0; bit < 8; bit++) {
      if ((crc & 0x8000) != 0) {
        crc = (uint16_t)((crc << 1) ^ 0x1021);
      } else {
        crc <<= 1;
      }
    }
  }
  return crc;
}

// ---------------------------------------------------------------------------
// BNO setup and event handling
// ---------------------------------------------------------------------------

static bool enablePutterReports() {
  bool ok = true;

  if (!bno08x.enableReport(BNO_ROTATION_REPORT, BNO_REPORT_INTERVAL_US)) {
    Serial.println("Could not enable rotation report");
    ok = false;
  }

  if (!bno08x.enableReport(SH2_GYROSCOPE_CALIBRATED, BNO_REPORT_INTERVAL_US)) {
    Serial.println("Could not enable calibrated gyroscope");
    ok = false;
  }

  if (!bno08x.enableReport(SH2_ACCELEROMETER, BNO_REPORT_INTERVAL_US)) {
    Serial.println("Could not enable accelerometer");
    ok = false;
  }

  return ok;
}

static bool beginBno() {
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(400000UL);

  if (!bno08x.begin_I2C()) {
    return false;
  }

  return enablePutterReports();
}

static void recoverBnoStream() {
  Serial.println("BNO stream recovery");
  if (!enablePutterReports()) {
    Serial.println("BNO recovery failed");
  }
}

static void updateRotationFromEvent(const sh2_SensorValue_t &value) {
  EulerAngles angles = {};
  float qr = 0.0f;
  float qi = 0.0f;
  float qj = 0.0f;
  float qk = 0.0f;

  switch (value.sensorId) {
#if defined(SH2_ARVR_STABILIZED_RV)
    case SH2_ARVR_STABILIZED_RV:
      qr = value.un.arvrStabilizedRV.real;
      qi = value.un.arvrStabilizedRV.i;
      qj = value.un.arvrStabilizedRV.j;
      qk = value.un.arvrStabilizedRV.k;
      quaternionToEuler(qr, qi, qj, qk, &angles);
      break;
#endif
    case SH2_ROTATION_VECTOR:
      qr = value.un.rotationVector.real;
      qi = value.un.rotationVector.i;
      qj = value.un.rotationVector.j;
      qk = value.un.rotationVector.k;
      quaternionToEuler(qr, qi, qj, qk, &angles);
      break;
    default:
      return;
  }

  latestImu.yaw_deg = angles.yaw_deg;
  latestImu.pitch_deg = angles.pitch_deg;
  latestImu.roll_deg = angles.roll_deg;
  {
    const float swapped_yaw_deg = latestImu.roll_deg;
    latestImu.roll_deg = latestImu.yaw_deg;
    latestImu.yaw_deg = swapped_yaw_deg;
  }
  latestImu.quat_i = qi;
  latestImu.quat_j = qj;
  latestImu.quat_k = qk;
  latestImu.quat_r = qr;
  latestImu.orientation_valid = true;
  markFreshUpdate();
}

static void updateImuFromBnoEvent(const sh2_SensorValue_t &value) {
  switch (value.sensorId) {
    case SH2_ACCELEROMETER:
      latestImu.accel_x_g = value.un.accelerometer.x / 9.80665f;
      latestImu.accel_y_g = value.un.accelerometer.y / 9.80665f;
      latestImu.accel_z_g = value.un.accelerometer.z / 9.80665f;
      latestImu.accel_valid = true;
      markFreshUpdate();
      break;

    case SH2_GYROSCOPE_CALIBRATED:
      latestImu.gyro_x_dps = value.un.gyroscope.x * RAD_TO_DEG;
      latestImu.gyro_y_dps = value.un.gyroscope.y * RAD_TO_DEG;
      latestImu.gyro_z_dps = value.un.gyroscope.z * RAD_TO_DEG;
      latestImu.gyro_valid = true;
      markFreshUpdate();
      break;

#if defined(SH2_ARVR_STABILIZED_RV)
    case SH2_ARVR_STABILIZED_RV:
      updateRotationFromEvent(value);
      break;
#endif
    case SH2_ROTATION_VECTOR:
      updateRotationFromEvent(value);
      break;

    default:
      break;
  }
}

static void processBnoEvents() {
  if (bno08x.wasReset()) {
    Serial.println("BNO08x was reset, re-enabling reports");
    enablePutterReports();
  }

  while (bno08x.getSensorEvent(&sensorValue)) {
    updateImuFromBnoEvent(sensorValue);
  }
}

// ---------------------------------------------------------------------------
// Piezo handling
// ---------------------------------------------------------------------------

static void updatePiezoBaseline(PiezoState *piezo) {
  const float alpha = 0.05f;

  piezo->baseline_1 = (1.0f - alpha) * piezo->baseline_1 + alpha * piezo->raw_1;
  piezo->baseline_3 = (1.0f - alpha) * piezo->baseline_3 + alpha * piezo->raw_3;
}

static void readPiezos(PiezoState *piezo) {
  piezo->raw_1 = analogRead(PIN_PIEZO_1);
  piezo->raw_3 = analogRead(PIN_PIEZO_3);

  if (piezo->baseline_1 == 0.0f && piezo->baseline_3 == 0.0f) {
    piezo->baseline_1 = piezo->raw_1;
    piezo->baseline_3 = piezo->raw_3;
  }

  piezo->delta_1 = abs(piezo->raw_1 - (int)piezo->baseline_1);
  piezo->delta_3 = abs(piezo->raw_3 - (int)piezo->baseline_3);

  piezo->peak_delta = max(piezo->delta_1, piezo->delta_3);
  piezo->impact_detected = false;

  const uint32_t now_ms = millis();
  const uint32_t now_us = micros();
  if ((piezo->peak_delta >= PIEZO_IMPACT_THRESHOLD) &&
      ((now_ms - piezo->last_impact_ms) > PIEZO_REFRACTORY_MS)) {
    piezo->impact_detected = true;
    piezo->last_impact_ms = now_ms;
    piezo->last_impact_us = now_us;
  }
}

// ---------------------------------------------------------------------------
// Stroke capture and serialization
// ---------------------------------------------------------------------------

static void resetStrokeCapture() {
  strokeCapture.active = false;
  strokeCapture.overflowed = false;
  strokeCapture.capture_start_ms = 0;
  strokeCapture.capture_start_us = 0;
  strokeCapture.impact_time_ms = 0;
  strokeCapture.impact_time_us = 0;
  strokeCapture.calibration_imu_index = 0;
  strokeCapture.imu_sample_count = 0;
  strokeCapture.piezo_sample_count = 0;
}

static void resetPreRollBuffers() {
  preRollImuWriteIndex = 0;
  preRollImuCount = 0;
  preRollPiezoWriteIndex = 0;
  preRollPiezoCount = 0;
}

static void beginStrokeCapture() {
  resetStrokeCapture();
  strokeCapture.active = true;
  strokeCapture.capture_start_ms = millis();
  strokeCapture.capture_start_us = micros();
  lastImuCaptureUs = strokeCapture.capture_start_us;
  lastPiezoSampleUs = strokeCapture.capture_start_us;
}

static uint16_t preRollImuStartIndex() {
  if (preRollImuCount < PRE_ROLL_IMU_SAMPLES) {
    return 0;
  }
  return preRollImuWriteIndex;
}

static uint16_t preRollPiezoStartIndex() {
  if (preRollPiezoCount < PRE_ROLL_PIEZO_SAMPLES) {
    return 0;
  }
  return preRollPiezoWriteIndex;
}

static BufferedImuSample *preRollImuAt(uint16_t chronologicalIndex) {
  if (chronologicalIndex >= preRollImuCount) {
    return nullptr;
  }
  const uint16_t startIndex = preRollImuStartIndex();
  const uint16_t physicalIndex =
      (uint16_t)((startIndex + chronologicalIndex) % PRE_ROLL_IMU_SAMPLES);
  return &preRollImu[physicalIndex];
}

static BufferedPiezoSample *preRollPiezoAt(uint16_t chronologicalIndex) {
  if (chronologicalIndex >= preRollPiezoCount) {
    return nullptr;
  }
  const uint16_t startIndex = preRollPiezoStartIndex();
  const uint16_t physicalIndex =
      (uint16_t)((startIndex + chronologicalIndex) % PRE_ROLL_PIEZO_SAMPLES);
  return &preRollPiezo[physicalIndex];
}

static void bufferLatestImuSample() {
  if (!latestImu.accel_valid || !latestImu.gyro_valid || !latestImu.orientation_valid) {
    return;
  }

  BufferedImuSample &slot = preRollImu[preRollImuWriteIndex];
  slot.valid = true;
  slot.sample_ms = millis();
  slot.yaw_deg = latestImu.yaw_deg;
  slot.pitch_deg = latestImu.pitch_deg;
  slot.roll_deg = latestImu.roll_deg;
  slot.gyro_x_dps = latestImu.gyro_x_dps;
  slot.gyro_y_dps = latestImu.gyro_y_dps;
  slot.gyro_z_dps = latestImu.gyro_z_dps;
  slot.accel_x_g = latestImu.accel_x_g;
  slot.accel_y_g = latestImu.accel_y_g;
  slot.accel_z_g = latestImu.accel_z_g;
  slot.quat_i = latestImu.quat_i;
  slot.quat_j = latestImu.quat_j;
  slot.quat_k = latestImu.quat_k;
  slot.quat_r = latestImu.quat_r;
  encodeImuSampleFromValues(
      slot.accel_x_g, slot.accel_y_g, slot.accel_z_g, slot.gyro_x_dps,
      slot.gyro_y_dps, slot.gyro_z_dps, slot.quat_i, slot.quat_j, slot.quat_k,
      slot.quat_r, slot.encoded);

  preRollImuWriteIndex = (uint16_t)((preRollImuWriteIndex + 1) % PRE_ROLL_IMU_SAMPLES);
  if (preRollImuCount < PRE_ROLL_IMU_SAMPLES) {
    preRollImuCount++;
  }
}

static void bufferLatestPiezoSample() {
  BufferedPiezoSample &slot = preRollPiezo[preRollPiezoWriteIndex];
  slot.valid = true;
  slot.sample_ms = millis();
  slot.raw_1 = clampToInt16(latestPiezo.raw_1);
  slot.raw_3 = clampToInt16(latestPiezo.raw_3);

  preRollPiezoWriteIndex =
      (uint16_t)((preRollPiezoWriteIndex + 1) % PRE_ROLL_PIEZO_SAMPLES);
  if (preRollPiezoCount < PRE_ROLL_PIEZO_SAMPLES) {
    preRollPiezoCount++;
  }
}

static bool bufferedSampleIsStable(const BufferedImuSample &sample) {
  return fabsf(sample.gyro_x_dps) <= STABLE_GYRO_THRESHOLD_DPS &&
         fabsf(sample.gyro_y_dps) <= STABLE_GYRO_THRESHOLD_DPS &&
         fabsf(sample.gyro_z_dps) <= STABLE_GYRO_THRESHOLD_DPS;
}

static uint16_t findTakeawayStartImuIndex() {
  if (preRollImuCount == 0) {
    return 0;
  }

  for (uint16_t index = 0; index < preRollImuCount; index++) {
    BufferedImuSample *sample = preRollImuAt(index);
    if (sample == nullptr || !sample->valid) {
      continue;
    }
    if (fabsf(sample->gyro_y_dps) > STABLE_GYRO_THRESHOLD_DPS) {
      if (index >= PRE_TAKEAWAY_SETUP_SAMPLES) {
        return (uint16_t)(index - PRE_TAKEAWAY_SETUP_SAMPLES);
      }
      return 0;
    }
  }

  return (preRollImuCount > PRE_TAKEAWAY_SETUP_SAMPLES)
             ? (uint16_t)(preRollImuCount - PRE_TAKEAWAY_SETUP_SAMPLES)
             : 0;
}

static uint16_t findCalibrationImuIndex(uint16_t takeawayStartIndex) {
  if (preRollImuCount == 0) {
    return 0;
  }

  const uint16_t clampedTakeawayStart =
      min(takeawayStartIndex, (uint16_t)(preRollImuCount - 1));
  for (int32_t index = (int32_t)clampedTakeawayStart; index >= 0; index--) {
    BufferedImuSample *sample = preRollImuAt((uint16_t)index);
    if (sample != nullptr && sample->valid && bufferedSampleIsStable(*sample)) {
      return (uint16_t)index;
    }
  }

  return clampedTakeawayStart;
}

static void beginStrokeCaptureFromPreRoll(uint16_t captureStartIndex,
                                          uint16_t calibrationIndex) {
  beginStrokeCapture();
  strokeCapture.calibration_imu_index =
      calibrationIndex >= captureStartIndex
          ? (uint16_t)(calibrationIndex - captureStartIndex)
          : 0;

  BufferedImuSample *calibrationSample = preRollImuAt(calibrationIndex);
  if (calibrationSample != nullptr && calibrationSample->valid) {
    strokeCapture.capture_start_ms = calibrationSample->sample_ms;
    putt.ready_pitch_deg = calibrationSample->pitch_deg;
    putt.setup_orientation.yaw_deg = calibrationSample->yaw_deg;
    putt.setup_orientation.pitch_deg = calibrationSample->pitch_deg;
    putt.setup_orientation.roll_deg = calibrationSample->roll_deg;
  }

  for (uint16_t sampleIndex = captureStartIndex; sampleIndex < preRollImuCount;
       sampleIndex++) {
    if (strokeCapture.imu_sample_count >= MAX_CAPTURE_IMU_SAMPLES) {
      markCaptureOverflow();
      return;
    }
    BufferedImuSample *sample = preRollImuAt(sampleIndex);
    if (sample == nullptr || !sample->valid) {
      continue;
    }
    const size_t offset = strokeCapture.imu_sample_count * IMU_CHANNEL_COUNT;
    memcpy(strokeCapture.imu_data + offset, sample->encoded,
           sizeof(sample->encoded));
    strokeCapture.imu_sample_count++;
  }

  for (uint16_t sampleIndex = 0; sampleIndex < preRollPiezoCount; sampleIndex++) {
    if (strokeCapture.piezo_sample_count >= MAX_CAPTURE_PIEZO_SAMPLES) {
      markCaptureOverflow();
      return;
    }
    BufferedPiezoSample *sample = preRollPiezoAt(sampleIndex);
    if (sample == nullptr || !sample->valid ||
        sample->sample_ms < strokeCapture.capture_start_ms) {
      continue;
    }
    const size_t offset = strokeCapture.piezo_sample_count * PIEZO_CHANNEL_COUNT;
    strokeCapture.piezo_data[offset + 0] = sample->raw_1;
    strokeCapture.piezo_data[offset + 1] = sample->raw_3;
    strokeCapture.piezo_sample_count++;
  }
}

static void markCaptureOverflow() {
  strokeCapture.overflowed = true;
  putt.state = PUTT_ABORTED;
}

static void appendPiezoSample() {
  if (!strokeCapture.active) {
    return;
  }

  if (strokeCapture.piezo_sample_count >= MAX_CAPTURE_PIEZO_SAMPLES) {
    markCaptureOverflow();
    return;
  }

  const size_t offset = strokeCapture.piezo_sample_count * PIEZO_CHANNEL_COUNT;
  strokeCapture.piezo_data[offset + 0] = clampToInt16(latestPiezo.raw_1);
  strokeCapture.piezo_data[offset + 1] = clampToInt16(latestPiezo.raw_3);
  strokeCapture.piezo_sample_count++;
}

static void appendImuSample() {
  if (!strokeCapture.active) {
    return;
  }

  if (strokeCapture.imu_sample_count >= MAX_CAPTURE_IMU_SAMPLES) {
    markCaptureOverflow();
    return;
  }

  if (!latestImu.accel_valid || !latestImu.gyro_valid || !latestImu.orientation_valid) {
    return;
  }

  const size_t offset = strokeCapture.imu_sample_count * IMU_CHANNEL_COUNT;
  encodeImuSampleFromValues(
      latestImu.accel_x_g, latestImu.accel_y_g, latestImu.accel_z_g,
      latestImu.gyro_x_dps, latestImu.gyro_y_dps, latestImu.gyro_z_dps,
      latestImu.quat_i, latestImu.quat_j, latestImu.quat_k, latestImu.quat_r,
      strokeCapture.imu_data + offset);
  strokeCapture.imu_sample_count++;
}

static size_t buildRawStrokePacket(uint8_t *buffer, size_t bufferSize,
                                   uint32_t packetId, uint32_t sessionId) {
  const size_t imuValueCount =
      (size_t)strokeCapture.imu_sample_count * IMU_CHANNEL_COUNT;
  const size_t piezoValueCount =
      (size_t)strokeCapture.piezo_sample_count * PIEZO_CHANNEL_COUNT;
  const size_t expectedLength =
      RAW_STROKE_HEADER_LENGTH +
      (imuValueCount * sizeof(int16_t)) +
      (piezoValueCount * sizeof(int16_t));

  if (expectedLength > bufferSize) {
    return 0;
  }

  const uint32_t impactOffsetMs =
      strokeCapture.impact_time_ms > strokeCapture.capture_start_ms
          ? (strokeCapture.impact_time_ms - strokeCapture.capture_start_ms)
          : 0;
  const uint32_t impactToBleTxDeciMs =
      strokeCapture.impact_time_us > 0 && micros() > strokeCapture.impact_time_us
          ? ((micros() - strokeCapture.impact_time_us + 50UL) / 100UL)
          : 0;

  buffer[0] = 0;
  writeUint32LE(buffer, 0, packetId);
  writeUint32LE(buffer, 4, sessionId);
  writeUint32LE(buffer, 8, strokeCapture.capture_start_ms);
  writeUint16LE(buffer, 12, (uint16_t)min((uint32_t)65535, impactOffsetMs));
  writeUint16LE(buffer, 14, (uint16_t)min((uint32_t)65535, impactToBleTxDeciMs));
  writeUint16LE(buffer, 16, (uint16_t)(1000000UL / IMU_CAPTURE_PERIOD_US));
  buffer[18] = (uint8_t)IMU_CHANNEL_COUNT;
  writeUint16LE(buffer, 19, strokeCapture.imu_sample_count);
  writeUint16LE(buffer, 21, (uint16_t)(1000000UL / PIEZO_SAMPLE_PERIOD_US));
  buffer[23] = (uint8_t)PIEZO_CHANNEL_COUNT;
  writeUint16LE(buffer, 24, strokeCapture.piezo_sample_count);
  buffer[26] = IMU_ENCODING_INT16_SCALED;
  buffer[27] = PIEZO_ENCODING_INT16_RAW;
  writeUint16LE(buffer, 28, strokeCapture.calibration_imu_index);

  size_t offset = RAW_STROKE_HEADER_LENGTH;
  for (size_t index = 0; index < imuValueCount; index++) {
    writeInt16LE(buffer, offset, strokeCapture.imu_data[index]);
    offset += sizeof(int16_t);
  }
  for (size_t index = 0; index < piezoValueCount; index++) {
    writeInt16LE(buffer, offset, strokeCapture.piezo_data[index]);
    offset += sizeof(int16_t);
  }

  return offset;
}

static void sendFragment(uint8_t messageType, uint32_t packetId,
                         uint16_t fragmentIndex, uint16_t fragmentCount,
                         const uint8_t *payload, uint16_t payloadLength) {
  writeUint16LE(fragmentBuffer, 0, FRAGMENT_MAGIC);
  fragmentBuffer[2] = PROTOCOL_VERSION;
  fragmentBuffer[3] = messageType;
  writeUint32LE(fragmentBuffer, 4, packetId);
  writeUint16LE(fragmentBuffer, 8, fragmentIndex);
  writeUint16LE(fragmentBuffer, 10, fragmentCount);
  writeUint16LE(fragmentBuffer, 12, payloadLength);
  memcpy(fragmentBuffer + FRAGMENT_HEADER_LENGTH, payload, payloadLength);

  uint8_t crcBuffer[14 + MAX_FRAGMENT_PAYLOAD_BYTES];
  memcpy(crcBuffer, fragmentBuffer, 14);
  memcpy(crcBuffer + 14, payload, payloadLength);

  uint16_t crc = computeCrc16(crcBuffer, 14 + payloadLength);
  writeUint16LE(fragmentBuffer, 14, crc);

  notifyCharacteristic->setValue(fragmentBuffer,
                                 FRAGMENT_HEADER_LENGTH + payloadLength);
  notifyCharacteristic->notify();
}

static void sendStrokeCaptureOverBle() {
  if (!bleClientConnected || notifyCharacteristic == nullptr) {
    Serial.println("Skipping BLE stroke notify because no phone is connected");
    return;
  }

  if (strokeCapture.imu_sample_count == 0 || strokeCapture.piezo_sample_count == 0) {
    Serial.println("Skipping BLE stroke notify because the capture is empty");
    return;
  }

  const uint32_t packetId = nextPacketId++;
  const uint32_t sessionId = activeBleSessionId;
  const size_t packetLength =
      buildRawStrokePacket(rawPacketBuffer, sizeof(rawPacketBuffer), packetId, sessionId);
  if (packetLength == 0) {
    Serial.println("Failed to build raw stroke packet");
    return;
  }

  const uint16_t fragmentCount =
      (uint16_t)((packetLength + MAX_FRAGMENT_PAYLOAD_BYTES - 1) /
                 MAX_FRAGMENT_PAYLOAD_BYTES);

  for (uint16_t fragmentIndex = 0; fragmentIndex < fragmentCount; fragmentIndex++) {
    const size_t start = fragmentIndex * MAX_FRAGMENT_PAYLOAD_BYTES;
    const size_t remaining = packetLength - start;
    const uint16_t chunkLength =
        (uint16_t)min((size_t)MAX_FRAGMENT_PAYLOAD_BYTES, remaining);
    sendFragment(MESSAGE_TYPE_STROKE, packetId, fragmentIndex, fragmentCount,
                 rawPacketBuffer + start, chunkLength);
    delay(20);
  }

  Serial.print("Notified stroke packet ");
  Serial.print(packetId);
  Serial.print(" in ");
  Serial.print(fragmentCount);
  Serial.println(" BLE fragments");
}

static void sendWaitingForPuttOverBle() {
  if (!bleClientConnected || notifyCharacteristic == nullptr) {
    return;
  }

  const int len = snprintf((char *)rawPacketBuffer,
                           sizeof(rawPacketBuffer),
                           "Waiting for putt ts=%lu state=%d ready=%u",
                           (unsigned long)millis(),
                           (int)putt.state,
                           putt.state == PUTT_READY_WINDOW ? 1 : 0);
  if (len <= 0) {
    return;
  }

  const size_t payloadLength =
      min((size_t)len, sizeof(rawPacketBuffer) - 1U);
  notifyCharacteristic->setValue(rawPacketBuffer, payloadLength);
  notifyCharacteristic->notify();
}

static const char *puttStateLabel(PuttState state) {
  switch (state) {
    case PUTT_IDLE:
      return "IDLE";
    case PUTT_READY_WINDOW:
      return "READY";
    case PUTT_BACKSTROKE:
      return "BACKSTROKE";
    case PUTT_FORWARD_STROKE:
      return "FORWARD";
    case PUTT_IMPACT:
      return "IMPACT";
    case PUTT_FOLLOW_THROUGH:
      return "FOLLOW_THROUGH";
    case PUTT_RESULT_READY:
      return "RESULT_READY";
    case PUTT_ABORTED:
      return "ABORTED";
  }
  return "UNKNOWN";
}

static void sendPuttStateOverBle(PuttState state) {
  if (!bleClientConnected || notifyCharacteristic == nullptr) {
    return;
  }

  const int len = snprintf((char *)rawPacketBuffer,
                           sizeof(rawPacketBuffer),
                           "STATE:%s",
                           puttStateLabel(state));
  if (len <= 0) {
    return;
  }

  const size_t payloadLength =
      min((size_t)len, sizeof(rawPacketBuffer) - 1U);
  notifyCharacteristic->setValue(rawPacketBuffer, payloadLength);
  notifyCharacteristic->notify();
}

static void sendLatencyPingOverBle(uint32_t pingId) {
  if (!bleClientConnected || notifyCharacteristic == nullptr) {
    return;
  }

  const int len = snprintf((char *)rawPacketBuffer,
                           sizeof(rawPacketBuffer),
                           "PING:%lu",
                           (unsigned long)pingId);
  if (len <= 0) {
    return;
  }

  const size_t payloadLength =
      min((size_t)len, sizeof(rawPacketBuffer) - 1U);
  notifyCharacteristic->setValue(rawPacketBuffer, payloadLength);
  notifyCharacteristic->notify();
}

static void sendForwardTriggerOverBle(uint32_t triggerMs) {
  if (!bleClientConnected || notifyCharacteristic == nullptr) {
    return;
  }

  const int len = snprintf((char *)rawPacketBuffer,
                           sizeof(rawPacketBuffer),
                           "EVENT:FWD:%lu",
                           (unsigned long)triggerMs);
  if (len <= 0) {
    return;
  }

  const size_t payloadLength =
      min((size_t)len, sizeof(rawPacketBuffer) - 1U);
  notifyCharacteristic->setValue(rawPacketBuffer, payloadLength);
  notifyCharacteristic->notify();
}

static void transitionToState(PuttState nextState) {
  if (putt.state == nextState) {
    return;
  }
  putt.state = nextState;
  sendPuttStateOverBle(nextState);
}

// ---------------------------------------------------------------------------
// BLE setup and command handling
// ---------------------------------------------------------------------------

static void handleBleCommand(const uint8_t *data, size_t length) {
  if (length == 0) {
    return;
  }

  switch (data[0]) {
    case COMMAND_ATTACH_SESSION:
      if (length < 5) {
        Serial.println("Ignoring short attach-session command");
        return;
      }
      activeBleSessionId = readUint32LE(data, 1);
      bleSessionBound = true;
      Serial.print("Bound BLE session id ");
      Serial.println(activeBleSessionId);
      break;

    case COMMAND_CLEAR_SESSION:
      bleSessionBound = false;
      activeBleSessionId = millis() == 0 ? 1 : millis();
      Serial.println("Cleared BLE session binding");
      break;

    case COMMAND_LATENCY_PING:
      if (length < 5) {
        Serial.println("Ignoring short latency ping command");
        return;
      }
      sendLatencyPingOverBle(readUint32LE(data, 1));
      break;

    default:
      Serial.print("Unknown BLE command ");
      Serial.println((int)data[0]);
      break;
  }
}

class PutterServerCallbacks : public BLEServerCallbacks {
 public:
  void onConnect(BLEServer *server) override {
    bleClientConnected = true;
    server->updateConnParams(server->getConnId(), 6, 12, 0, 400);
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer *server) override {
    bleClientConnected = false;
    Serial.println("BLE client disconnected");
    BLEDevice::startAdvertising();
  }
};

class SessionCommandCallbacks : public BLECharacteristicCallbacks {
 public:
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    handleBleCommand((const uint8_t *)value.c_str(), value.length());
  }
};

static void beginBle() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(BLE_PREFERRED_MTU);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new PutterServerCallbacks());

  BLEService *service = bleServer->createService(BLE_SERVICE_UUID);

  notifyCharacteristic = service->createCharacteristic(
      BLE_NOTIFY_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  notifyCharacteristic->addDescriptor(new BLE2902());

  writeCharacteristic = service->createCharacteristic(
      BLE_WRITE_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR);
  writeCharacteristic->setCallbacks(new SessionCommandCallbacks());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE service advertising");
}

// ---------------------------------------------------------------------------
// Putter logic
// ---------------------------------------------------------------------------

static bool imuDataFreshEnough() {
  if (latestImu.last_update_ms == 0UL) {
    return false;
  }
  return (millis() - latestImu.last_update_ms) <= IMU_STALE_TIMEOUT_MS;
}

static bool clubIsStable() {
  if (!latestImu.gyro_valid || !latestImu.orientation_valid) {
    return false;
  }
  return gyroMagnitudeDps(latestImu) < STABLE_GYRO_THRESHOLD_DPS;
}

static void resetPuttSession() {
  putt = {};
  putt.state = PUTT_IDLE;
  sendPuttStateOverBle(PUTT_IDLE);
  resetPreRollBuffers();
}

static void armReadyWindow() {
  if (!latestImu.orientation_valid) {
    Serial.println("Ready button ignored because IMU orientation is not ready");
    return;
  }

  resetStrokeCapture();
  resetPuttSession();

  transitionToState(PUTT_READY_WINDOW);
  putt.ready_pressed_ms = millis();
  putt.previous_pitch_delta_deg = 0.0f;
  putt.peak_pitch_delta_deg = 0.0f;

  Serial.println("Ready window armed");
}

static bool impactPitchCrossedReady() {
  if (!latestImu.orientation_valid || !putt.full_forward_seen ||
      putt.state != PUTT_FORWARD_STROKE || !latestImu.gyro_valid) {
    return false;
  }

  const float current_delta_deg = pitchDeltaFromReadyDeg(latestImu);
  const float previous_delta_deg = putt.previous_pitch_delta_deg;
  const bool crossed_ready =
      ((previous_delta_deg < 0.0f) && (current_delta_deg >= 0.0f)) ||
      ((previous_delta_deg > 0.0f) && (current_delta_deg <= 0.0f));
  const bool within_ready_tolerance =
      fabsf(current_delta_deg) <= PITCH_RETURN_TOLERANCE_DEG;

  return crossed_ready || within_ready_tolerance;
}

static bool impactUsesCurrentSample() {
  const float current_delta_deg = pitchDeltaFromReadyDeg(latestImu);
  return fabsf(current_delta_deg) <= fabsf(putt.previous_pitch_delta_deg);
}

static void handleReadyButton() {
  const bool reading = digitalRead(PIN_READY_BUTTON);
  if (reading != lastReadyButtonReading) {
    lastReadyButtonReading = reading;
    lastReadyButtonChangeMs = millis();
  }

  if ((millis() - lastReadyButtonChangeMs) < READY_BUTTON_DEBOUNCE_MS) {
    return;
  }

  const bool pressed = (reading == LOW);
  if (pressed && !readyButtonLatched) {
    readyButtonLatched = true;
    armReadyWindow();
  } else if (!pressed) {
    readyButtonLatched = false;
  }
}

static void updatePuttStateMachine() {
  const uint32_t now_ms = millis();
  const float stroke_rate_dps =
      latestImu.gyro_valid ? strokeMotionRateDps(latestImu) : 0.0f;
  const float current_pitch_delta_deg =
      latestImu.orientation_valid ? pitchDeltaFromReadyDeg(latestImu) : 0.0f;

  if (putt.state != PUTT_IDLE && latestImu.orientation_valid) {
    const float face_delta = wrapDegrees180(
        faceRotationDeg(latestImu) - putt.setup_orientation.yaw_deg);
    putt.peak_face_rotation_deg =
        max(putt.peak_face_rotation_deg, fabsf(face_delta));
  }

  if (latestImu.gyro_valid) {
    putt.peak_stroke_rate_dps =
        max(putt.peak_stroke_rate_dps, fabsf(stroke_rate_dps));
  }

  if ((putt.state == PUTT_READY_WINDOW || putt.state == PUTT_BACKSTROKE) &&
      latestImu.orientation_valid &&
      fabsf(current_pitch_delta_deg) > fabsf(putt.peak_pitch_delta_deg)) {
    putt.peak_pitch_delta_deg = current_pitch_delta_deg;
  }

  switch (putt.state) {
    case PUTT_IDLE:
      break;

    case PUTT_READY_WINDOW:
      if (!latestImu.gyro_valid) {
        break;
      }
      if (rateShowsBackstroke(stroke_rate_dps)) {
        if (putt.backstroke_confirm_frames < 255) {
          putt.backstroke_confirm_frames++;
        }
      } else {
        putt.backstroke_confirm_frames = 0;
      }

      if (putt.backstroke_confirm_frames >= MOTION_CONFIRM_FRAMES) {
        const uint16_t takeawayStartIndex = findTakeawayStartImuIndex();
        const uint16_t calibrationIndex =
            findCalibrationImuIndex(takeawayStartIndex);
        beginStrokeCaptureFromPreRoll(takeawayStartIndex, calibrationIndex);
        if (putt.state == PUTT_ABORTED || !strokeCapture.active) {
          break;
        }
        putt.full_backstroke_seen = true;
        putt.stroke_start_ms = strokeCapture.capture_start_ms;
        putt.previous_pitch_delta_deg = pitchDeltaFromReadyDeg(latestImu);
        putt.previous_pitch_sample_ms = now_ms;
        BufferedImuSample *calibrationSample = preRollImuAt(calibrationIndex);
        if (calibrationSample != nullptr && calibrationSample->valid) {
          BufferedImuSample *captureStartSample =
              preRollImuAt(takeawayStartIndex);
          Serial.print("Calibration locked at pitch=");
          Serial.print(calibrationSample->pitch_deg, 2);
          Serial.print(" yaw=");
          Serial.print(calibrationSample->yaw_deg, 2);
          Serial.print(" roll=");
          Serial.print(calibrationSample->roll_deg, 2);
          Serial.print(" captureStartMs=");
          Serial.print(captureStartSample != nullptr && captureStartSample->valid
                           ? captureStartSample->sample_ms
                           : strokeCapture.capture_start_ms);
          Serial.print(" calibrationMs=");
          Serial.println(calibrationSample->sample_ms);
        }
        transitionToState(PUTT_BACKSTROKE);
      }
      break;

    case PUTT_BACKSTROKE:
      if (!latestImu.gyro_valid) {
        break;
      }
      if (rateShowsForwardStroke(stroke_rate_dps)) {
        if (putt.forward_confirm_frames < 255) {
          putt.forward_confirm_frames++;
        }
      } else {
        putt.forward_confirm_frames = 0;
      }

      if (putt.forward_confirm_frames >= MOTION_CONFIRM_FRAMES) {
        putt.full_forward_seen = true;
        putt.forward_stroke_start_ms = now_ms;
        sendForwardTriggerOverBle(now_ms);
        transitionToState(PUTT_FORWARD_STROKE);
      }
      break;

    case PUTT_FORWARD_STROKE:
      if (impactPitchCrossedReady()) {
        transitionToState(PUTT_IMPACT);
        putt.impact_validated_by_piezo = latestPiezo.impact_detected;
        const bool use_current_sample = impactUsesCurrentSample();
        const uint32_t impact_time_ms =
            use_current_sample ? now_ms : putt.previous_pitch_sample_ms;
        const uint32_t impact_time_us = micros();
        putt.impact_ms = impact_time_ms;
        strokeCapture.impact_time_ms = impact_time_ms;
        strokeCapture.impact_time_us = impact_time_us;
        Serial.print("Impact crossing ready pitch=");
        Serial.print(putt.ready_pitch_deg, 2);
        Serial.print(" prevPitch=");
        Serial.print(putt.ready_pitch_deg + putt.previous_pitch_delta_deg, 2);
        Serial.print(" currPitch=");
        Serial.print(latestImu.pitch_deg, 2);
        Serial.print(" prevDelta=");
        Serial.print(putt.previous_pitch_delta_deg, 2);
        Serial.print(" currDelta=");
        Serial.print(pitchDeltaFromReadyDeg(latestImu), 2);
        Serial.print(" impactSample=");
        Serial.println(use_current_sample ? "current" : "previous");
      } else if (latestImu.gyro_valid) {
        if (!rateStillMovingForward(stroke_rate_dps)) {
          if (putt.impact_grace_frames < 255) {
            putt.impact_grace_frames++;
          }
        } else {
          putt.impact_grace_frames = 0;
        }

        if (putt.impact_grace_frames >= IMPACT_GRACE_CONFIRM_FRAMES) {
          Serial.print("Abort before impact: grace window expired gyroY=");
          Serial.print(stroke_rate_dps, 2);
          Serial.print(" prevDelta=");
          Serial.print(putt.previous_pitch_delta_deg, 2);
          Serial.print(" currDelta=");
          Serial.println(pitchDeltaFromReadyDeg(latestImu), 2);
          transitionToState(PUTT_ABORTED);
        }
      }
      break;

    case PUTT_IMPACT:
      putt.follow_through_confirm_frames = 0;
      transitionToState(PUTT_FOLLOW_THROUGH);
      break;

    case PUTT_FOLLOW_THROUGH:
      if (!latestImu.gyro_valid) {
        break;
      }
      if (!rateStillMovingForward(stroke_rate_dps)) {
        if (putt.follow_through_confirm_frames < 255) {
          putt.follow_through_confirm_frames++;
        }
      } else {
        putt.follow_through_confirm_frames = 0;
      }

      Serial.print("Follow-through check gyroY=");
      Serial.print(stroke_rate_dps, 2);
      Serial.print(" frames=");
      Serial.println(putt.follow_through_confirm_frames);

      if (putt.follow_through_confirm_frames >= FOLLOW_THROUGH_CONFIRM_FRAMES) {
        Serial.println("Follow-through complete");
        putt.follow_through_end_ms = now_ms;
        transitionToState(PUTT_RESULT_READY);
      }
      break;

    case PUTT_RESULT_READY:
      Serial.println("Putt result ready");
      sendStrokeCaptureOverBle();
      resetStrokeCapture();
      resetPuttSession();
      break;

    case PUTT_ABORTED:
      Serial.println("Putt capture aborted");
      printAbortSnapshot("state_machine");
      printAbortWindowData();
      resetStrokeCapture();
      resetPuttSession();
      break;
  }

  if (putt.state != PUTT_IDLE && latestImu.orientation_valid) {
    putt.previous_pitch_sample_ms = now_ms;
    putt.previous_pitch_delta_deg = current_pitch_delta_deg;
  }
}

// ---------------------------------------------------------------------------
// Debug output
// ---------------------------------------------------------------------------

static void printCompactImuLine() {
  Serial.print("UPD[");
  Serial.print(latestImu.update_count);
  Serial.print("] F[");
  Serial.print(latestImu.fresh_data ? 1 : 0);
  Serial.print("] STALE[");
  Serial.print(stalePrintCount);
  Serial.print("] LIVE[");
  Serial.print(imuDataFreshEnough() ? 1 : 0);
  Serial.print("] ORI[");
  Serial.print(latestImu.orientation_valid ? 1 : 0);
  Serial.print("] Y=");
  Serial.print(latestImu.yaw_deg, 2);
  Serial.print(" P=");
  Serial.print(latestImu.pitch_deg, 2);
  Serial.print(" R=");
  Serial.print(latestImu.roll_deg, 2);

  Serial.print(" GYR[");
  Serial.print(latestImu.gyro_valid ? 1 : 0);
  Serial.print("] X=");
  Serial.print(latestImu.gyro_x_dps, 2);
  Serial.print(" Y=");
  Serial.print(latestImu.gyro_y_dps, 2);
  Serial.print(" Z=");
  Serial.print(latestImu.gyro_z_dps, 2);

  Serial.print(" ACC[");
  Serial.print(latestImu.accel_valid ? 1 : 0);
  Serial.print("] X=");
  Serial.print(latestImu.accel_x_g, 2);
  Serial.print(" Y=");
  Serial.print(latestImu.accel_y_g, 2);
  Serial.print(" Z=");
  Serial.print(latestImu.accel_z_g, 2);

  Serial.print(" | PIEZO peak=");
  Serial.print(latestPiezo.peak_delta);
  Serial.print(" impact=");
  Serial.print(latestPiezo.impact_detected ? 1 : 0);

  Serial.print(" | STATE=");
  Serial.print((int)putt.state);
  Serial.print(" | readyPitch=");
  Serial.print(putt.ready_pitch_deg, 2);
  Serial.print(" | face=");
  Serial.print(faceRotationDeg(latestImu), 2);
  Serial.print(" | rate=");
  Serial.print(strokeMotionRateDps(latestImu), 2);
  Serial.print(" | accMag=");
  Serial.print(accelMagnitudeG(latestImu), 2);
  Serial.print(" | tilt=");
  Serial.print(setupTiltDeg(latestImu), 2);
  Serial.print(" | cap[imu=");
  Serial.print(strokeCapture.imu_sample_count);
  Serial.print(" piezo=");
  Serial.print(strokeCapture.piezo_sample_count);
  Serial.print("] | session=");
  Serial.println(activeBleSessionId);
}

static void printAbortSnapshot(const char *reason) {
  Serial.print("ABORT SNAPSHOT reason=");
  Serial.print(reason);
  Serial.print(" state=");
  Serial.print((int)putt.state);
  Serial.print(" readyPitch=");
  Serial.print(putt.ready_pitch_deg, 2);
  Serial.print(" pitch=");
  Serial.print(latestImu.pitch_deg, 2);
  Serial.print(" pitchDelta=");
  Serial.print(pitchDeltaFromReadyDeg(latestImu), 2);
  Serial.print(" prevPitchDelta=");
  Serial.print(putt.previous_pitch_delta_deg, 2);
  Serial.print(" yaw=");
  Serial.print(latestImu.yaw_deg, 2);
  Serial.print(" roll=");
  Serial.print(latestImu.roll_deg, 2);
  Serial.print(" gyroX=");
  Serial.print(latestImu.gyro_x_dps, 2);
  Serial.print(" gyroY=");
  Serial.print(latestImu.gyro_y_dps, 2);
  Serial.print(" gyroZ=");
  Serial.print(latestImu.gyro_z_dps, 2);
  Serial.print(" accX=");
  Serial.print(latestImu.accel_x_g, 2);
  Serial.print(" accY=");
  Serial.print(latestImu.accel_y_g, 2);
  Serial.print(" accZ=");
  Serial.print(latestImu.accel_z_g, 2);
  Serial.print(" piezo1=");
  Serial.print(latestPiezo.raw_1);
  Serial.print(" piezo3=");
  Serial.print(latestPiezo.raw_3);
  Serial.print(" delta1=");
  Serial.print(latestPiezo.delta_1);
  Serial.print(" delta3=");
  Serial.print(latestPiezo.delta_3);
  Serial.print(" capImu=");
  Serial.print(strokeCapture.imu_sample_count);
  Serial.print(" capPiezo=");
  Serial.println(strokeCapture.piezo_sample_count);
}

static void printAbortWindowData() {
  Serial.println("ABORT WINDOW BEGIN");

  Serial.println(
      "IMU_WINDOW_HEADER,idx,t_ms,ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps,qi,qj,qk,qr");
  const uint16_t imuStartIndex =
      strokeCapture.imu_sample_count > ABORT_DEBUG_IMU_SAMPLES
          ? (strokeCapture.imu_sample_count - ABORT_DEBUG_IMU_SAMPLES)
          : 0;
  for (uint16_t sampleIndex = imuStartIndex;
       sampleIndex < strokeCapture.imu_sample_count;
       sampleIndex++) {
    const size_t offset = (size_t)sampleIndex * IMU_CHANNEL_COUNT;
    const uint32_t sampleTimeMs =
        strokeCapture.capture_start_ms +
        (uint32_t)(((uint64_t)sampleIndex * IMU_CAPTURE_PERIOD_US) / 1000ULL);

    Serial.print("IMU_WINDOW,");
    Serial.print(sampleIndex);
    Serial.print(",");
    Serial.print(sampleTimeMs);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 0] / ACCEL_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 1] / ACCEL_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 2] / ACCEL_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 3] / GYRO_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 4] / GYRO_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 5] / GYRO_SCALE, 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 6] / QUATERNION_SCALE,
                 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 7] / QUATERNION_SCALE,
                 4);
    Serial.print(",");
    Serial.print((float)strokeCapture.imu_data[offset + 8] / QUATERNION_SCALE,
                 4);
    Serial.print(",");
    Serial.println((float)strokeCapture.imu_data[offset + 9] /
                       QUATERNION_SCALE,
                   4);
  }

  Serial.println("PIEZO_WINDOW_HEADER,idx,t_ms,piezo1,piezo3");
  const uint16_t piezoStartIndex =
      strokeCapture.piezo_sample_count > ABORT_DEBUG_PIEZO_SAMPLES
          ? (strokeCapture.piezo_sample_count - ABORT_DEBUG_PIEZO_SAMPLES)
          : 0;
  for (uint16_t sampleIndex = piezoStartIndex;
       sampleIndex < strokeCapture.piezo_sample_count;
       sampleIndex++) {
    const size_t offset = (size_t)sampleIndex * PIEZO_CHANNEL_COUNT;
    const uint32_t sampleTimeMs =
        strokeCapture.capture_start_ms +
        (uint32_t)(((uint64_t)sampleIndex * PIEZO_SAMPLE_PERIOD_US) / 1000ULL);

    Serial.print("PIEZO_WINDOW,");
    Serial.print(sampleIndex);
    Serial.print(",");
    Serial.print(sampleTimeMs);
    Serial.print(",");
    Serial.print(strokeCapture.piezo_data[offset + 0]);
    Serial.print(",");
    Serial.println(strokeCapture.piezo_data[offset + 1]);
  }

  Serial.println("ABORT WINDOW END");
}

// ---------------------------------------------------------------------------
// Arduino setup / loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(SERIAL_BAUD);

  analogReadResolution(12);
  pinMode(PIN_READY_BUTTON, INPUT_PULLUP);

  Serial.println("Starting PutterIQ firmware");
  if (!beginBno()) {
    Serial.println("Failed to initialize BNO08x");
    while (true) {
      delay(100);
    }
  }

  beginBle();
  resetStrokeCapture();
  resetPuttSession();
  activeBleSessionId = 1;
  Serial.println("BNO08x ready");
}

void loop() {
  processBnoEvents();
  handleReadyButton();

  const uint32_t now_us = micros();

  if ((uint32_t)(now_us - lastPiezoSampleUs) >= PIEZO_SAMPLE_PERIOD_US) {
    lastPiezoSampleUs = now_us;
    readPiezos(&latestPiezo);
    if (putt.state == PUTT_READY_WINDOW && !strokeCapture.active) {
      bufferLatestPiezoSample();
    } else if (strokeCapture.active) {
      appendPiezoSample();
    }
  }

  if ((uint32_t)(now_us - lastImuCaptureUs) >= IMU_CAPTURE_PERIOD_US) {
    lastImuCaptureUs = now_us;
    if (putt.state == PUTT_READY_WINDOW && !strokeCapture.active) {
      bufferLatestImuSample();
    } else if (strokeCapture.active) {
      appendImuSample();
    }
  }

  if ((putt.state == PUTT_IDLE || putt.state == PUTT_READY_WINDOW) &&
      !latestPiezo.impact_detected) {
    updatePiezoBaseline(&latestPiezo);
  }

  updatePuttStateMachine();

  const uint32_t now_ms = millis();

  // if ((putt.state == PUTT_IDLE) && !strokeCapture.active &&
  //     ((now_ms - lastBleIdleNotifyMs) >= BLE_IDLE_NOTIFY_PERIOD_MS)) {
  //   lastBleIdleNotifyMs = now_ms;
  //   sendWaitingForPuttOverBle();
  // }

  if ((now_ms - lastDebugPrintMs) >= DEBUG_PRINT_PERIOD_MS) {
    lastDebugPrintMs = now_ms;
    latestImu.fresh_data = freshDataSinceLastPrint;
    if (latestImu.fresh_data) {
      stalePrintCount = 0UL;
    } else {
      stalePrintCount++;
      if (stalePrintCount == 3UL) {
        Serial.println("BNO stream stale");
      }
      if (stalePrintCount >= 10UL) {
        recoverBnoStream();
        stalePrintCount = 0UL;
      }
    }
    // printCompactImuLine();
    freshDataSinceLastPrint = false;
  }

  delay(1);
}
