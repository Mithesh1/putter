#include "camera_bridge.h"

#include "esp_camera.h"
#include "esp_heap_caps.h"

namespace {

constexpr framesize_t kBurstFrameSize = FRAMESIZE_QQVGA;
constexpr int kCameraFbCount = 1;
constexpr int kInitialSettleFrames = 5;

void writeUint16LE(uint8_t *buffer, size_t offset, uint16_t value) {
  buffer[offset + 0] = static_cast<uint8_t>(value & 0xFF);
  buffer[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
}

void writeInt16LE(uint8_t *buffer, size_t offset, int16_t value) {
  writeUint16LE(buffer, offset, static_cast<uint16_t>(value));
}

void writeUint32LE(uint8_t *buffer, size_t offset, uint32_t value) {
  buffer[offset + 0] = static_cast<uint8_t>(value & 0xFF);
  buffer[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
  buffer[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xFF);
  buffer[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xFF);
}

void applySensorDefaults(sensor_t *sensor) {
  if (sensor == nullptr) {
    return;
  }

  sensor->set_framesize(sensor, kBurstFrameSize);
  sensor->set_quality(sensor, 18);
  sensor->set_whitebal(sensor, 1);
  sensor->set_awb_gain(sensor, 1);
  sensor->set_exposure_ctrl(sensor, 1);
  sensor->set_gain_ctrl(sensor, 1);
  sensor->set_brightness(sensor, 0);
  sensor->set_contrast(sensor, 0);
  sensor->set_saturation(sensor, 0);
  sensor->set_hmirror(sensor, 0);
  sensor->set_vflip(sensor, 0);
}

}  // namespace

bool CameraBridge::begin(const CameraBridgePins &pins) {
  pins_ = pins;
  if (!psramFound()) {
    Serial.println("Camera disabled because PSRAM was not found");
    state_ = State::Disabled;
    return false;
  }

  state_ = State::Armed;
  Serial.println("Camera bridge ready");
  return true;
}

bool CameraBridge::initCameraHardware() {
  if (cameraInitialized_) {
    return true;
  }

  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = pins_.pin_d0;
  config.pin_d1 = pins_.pin_d1;
  config.pin_d2 = pins_.pin_d2;
  config.pin_d3 = pins_.pin_d3;
  config.pin_d4 = pins_.pin_d4;
  config.pin_d5 = pins_.pin_d5;
  config.pin_d6 = pins_.pin_d6;
  config.pin_d7 = pins_.pin_d7;
  config.pin_xclk = pins_.pin_xclk;
  config.pin_pclk = pins_.pin_pclk;
  config.pin_vsync = pins_.pin_vsync;
  config.pin_href = pins_.pin_href;
  config.pin_sccb_sda = pins_.pin_sccb_sda;
  config.pin_sccb_scl = pins_.pin_sccb_scl;
  config.pin_pwdn = pins_.pin_pwdn;
  config.pin_reset = pins_.pin_reset;
  config.xclk_freq_hz = 10000000UL;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = kBurstFrameSize;
  config.jpeg_quality = kJpegQuality;
  config.fb_count = kCameraFbCount;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;

  const esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera burst init failed: 0x%x\n", err);
    return false;
  }

  applySensorDefaults(esp_camera_sensor_get());
  for (int i = 0; i < kInitialSettleFrames; ++i) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (fb != nullptr) {
      esp_camera_fb_return(fb);
    }
    delay(40);
  }

  cameraInitialized_ = true;
  Serial.println("Camera hardware initialized");
  return true;
}

void CameraBridge::shutdownCameraHardware() {
  if (!cameraInitialized_) {
    return;
  }
  esp_camera_deinit();
  cameraInitialized_ = false;
  lastFrameAttemptMs_ = 0;
  Serial.println("Camera hardware deinitialized");
}

void CameraBridge::trigger() {
  if (state_ == State::Disabled) {
    return;
  }
  triggerPending_ = true;
}

bool CameraBridge::isAvailable() const { return state_ != State::Disabled; }

bool CameraBridge::hasReadyBurst() const { return state_ == State::Ready; }

void CameraBridge::clearReadyBurst() {
  clearBurst();
  triggerPending_ = false;
  lastFrameAttemptMs_ = 0;
  shutdownCameraHardware();
  if (state_ != State::Disabled) {
    state_ = State::Armed;
  }
}

uint16_t CameraBridge::frameCount() const {
  return static_cast<uint16_t>(burstFrameCount_);
}

uint32_t CameraBridge::triggerMs() const { return burstTriggerMs_; }

const char *CameraBridge::stateLabel() const {
  switch (state_) {
    case State::Disabled:
      return "disabled";
    case State::Armed:
      return "armed";
    case State::Capturing:
      return "capturing";
    case State::Ready:
      return "ready";
    case State::Error:
      return "error";
  }
  return "unknown";
}

void CameraBridge::freeFrame(StoredFrame &frame) {
  if (frame.data != nullptr) {
    heap_caps_free(frame.data);
  }
  frame = {};
}

void CameraBridge::clearFrames(StoredFrame *frames, size_t count) {
  for (size_t index = 0; index < count; ++index) {
    freeFrame(frames[index]);
  }
}

bool CameraBridge::copyFrame(StoredFrame &dst, const uint8_t *src, size_t len,
                             uint32_t timestampMs, uint16_t width,
                             uint16_t height) {
  freeFrame(dst);

  uint8_t *storage = static_cast<uint8_t *>(
      heap_caps_malloc(len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (storage == nullptr) {
    storage = static_cast<uint8_t *>(heap_caps_malloc(len, MALLOC_CAP_8BIT));
  }
  if (storage == nullptr) {
    return false;
  }

  memcpy(storage, src, len);
  dst.data = storage;
  dst.len = len;
  dst.timestampMs = timestampMs;
  dst.width = width;
  dst.height = height;
  return true;
}

bool CameraBridge::cloneFrame(StoredFrame &dst, const StoredFrame &src) {
  if (src.data == nullptr || src.len == 0) {
    return false;
  }
  return copyFrame(dst, src.data, src.len, src.timestampMs, src.width,
                   src.height);
}

void CameraBridge::clearBurst() {
  clearFrames(burstFrames_, kMaxBurstFrames);
  burstFrameCount_ = 0;
  burstTotalBytes_ = 0;
  burstTriggerMs_ = 0;
  width_ = 0;
  height_ = 0;
}

void CameraBridge::setError(const char *message) {
  state_ = State::Error;
  shutdownCameraHardware();
  Serial.print("Camera bridge error: ");
  Serial.println(message);
}

void CameraBridge::beginBurstCapture() {
  if (!initCameraHardware()) {
    setError("camera init failed");
    return;
  }
  clearBurst();
  burstTriggerMs_ = millis();
  state_ = State::Capturing;
  lastFrameAttemptMs_ = 0;
  Serial.println("Camera trigger accepted");
}

bool CameraBridge::storeBurstFrame(const uint8_t *src, size_t len,
                                   uint32_t timestampMs, uint16_t width,
                                   uint16_t height) {
  if (burstFrameCount_ >= kMaxBurstFrames) {
    finishBurstCapture("frame_limit");
    return false;
  }
  if ((burstTotalBytes_ + len) > kMaxCaptureBytes) {
    finishBurstCapture("byte_limit");
    return false;
  }
  if (!copyFrame(burstFrames_[burstFrameCount_], src, len, timestampMs, width,
                 height)) {
    setError("burst copy failed");
    return false;
  }

  burstTotalBytes_ += len;
  width_ = width;
  height_ = height;
  ++burstFrameCount_;
  return true;
}

void CameraBridge::finishBurstCapture(const char *reason) {
  if (burstFrameCount_ == 0) {
    setError("empty burst");
    return;
  }
  state_ = State::Ready;
  triggerPending_ = false;
  shutdownCameraHardware();
  Serial.printf("Camera burst ready: %u frames, %u bytes, fps=%.1f, reason=%s\n",
                static_cast<unsigned int>(burstFrameCount_),
                static_cast<unsigned int>(burstTotalBytes_), estimatedFps(),
                reason);
}

float CameraBridge::estimatedFps() const {
  if (burstFrameCount_ < 2) {
    return 0.0f;
  }

  const uint32_t firstMs = burstFrames_[0].timestampMs;
  const uint32_t lastMs = burstFrames_[burstFrameCount_ - 1].timestampMs;
  if (lastMs <= firstMs) {
    return 0.0f;
  }
  return (burstFrameCount_ - 1) * 1000.0f /
         static_cast<float>(lastMs - firstMs);
}

size_t CameraBridge::buildBlePayload(uint8_t *buffer, size_t bufferSize,
                                     uint32_t packetId,
                                     uint32_t sessionId) const {
  if (!hasReadyBurst()) {
    return 0;
  }

  const size_t manifestBytes = burstFrameCount_ * kBleFrameEntryLength;
  const size_t packetLength =
      kBleHeaderLength + manifestBytes + burstTotalBytes_;
  if (packetLength > bufferSize) {
    return 0;
  }

  writeUint32LE(buffer, 0, packetId);
  writeUint32LE(buffer, 4, sessionId);
  writeUint32LE(buffer, 8, burstTriggerMs_);
  writeUint16LE(buffer, 12, 0);
  buffer[14] = static_cast<uint8_t>(burstFrameCount_);
  buffer[15] = kJpegQuality;
  writeUint16LE(buffer, 16, width_);
  writeUint16LE(buffer, 18, height_);
  writeUint16LE(buffer, 20,
                static_cast<uint16_t>(lroundf(estimatedFps() * 100.0f)));
  writeUint16LE(buffer, 22, 0);

  size_t manifestOffset = kBleHeaderLength;
  size_t imageOffset = kBleHeaderLength + manifestBytes;
  for (size_t index = 0; index < burstFrameCount_; ++index) {
    const StoredFrame &frame = burstFrames_[index];
    const int32_t deltaMs =
        static_cast<int32_t>(frame.timestampMs) - static_cast<int32_t>(burstTriggerMs_);
    int32_t clampedDeltaMs = deltaMs;
    if (clampedDeltaMs < -32768L) {
      clampedDeltaMs = -32768L;
    } else if (clampedDeltaMs > 32767L) {
      clampedDeltaMs = 32767L;
    }
    size_t clampedFrameLen = frame.len;
    if (clampedFrameLen > 65535U) {
      clampedFrameLen = 65535U;
    }

    writeInt16LE(buffer, manifestOffset + 0,
                 static_cast<int16_t>(clampedDeltaMs));
    writeUint16LE(buffer, manifestOffset + 2,
                  static_cast<uint16_t>(clampedFrameLen));
    memcpy(buffer + imageOffset, frame.data, frame.len);
    manifestOffset += kBleFrameEntryLength;
    imageOffset += frame.len;
  }

  return imageOffset;
}

void CameraBridge::update() {
  if (state_ == State::Disabled || state_ == State::Error ||
      state_ == State::Ready) {
    return;
  }

  if (!triggerPending_ && state_ != State::Capturing) {
    return;
  }

  const uint32_t nowMs = millis();
  if ((nowMs - lastFrameAttemptMs_) < kCaptureFrameIntervalMs) {
    return;
  }
  lastFrameAttemptMs_ = nowMs;

  if (triggerPending_ && state_ != State::Capturing) {
    beginBurstCapture();
  }

  camera_fb_t *fb = esp_camera_fb_get();
  const uint32_t capturedAtMs = millis();
  if (fb == nullptr) {
    setError("frame capture failed");
    return;
  }

  if (state_ == State::Capturing) {
    if (storeBurstFrame(fb->buf, fb->len, capturedAtMs,
                        static_cast<uint16_t>(fb->width),
                        static_cast<uint16_t>(fb->height))) {
      if ((capturedAtMs - burstTriggerMs_) >= kPostTriggerMs) {
        finishBurstCapture("time_complete");
      }
    }
  }
  esp_camera_fb_return(fb);
}
