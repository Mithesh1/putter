#pragma once

#include <Arduino.h>
#include <stddef.h>
#include <stdint.h>

struct CameraBridgePins {
  int pin_d0;
  int pin_d1;
  int pin_d2;
  int pin_d3;
  int pin_d4;
  int pin_d5;
  int pin_d6;
  int pin_d7;
  int pin_xclk;
  int pin_pclk;
  int pin_vsync;
  int pin_href;
  int pin_sccb_sda;
  int pin_sccb_scl;
  int pin_pwdn;
  int pin_reset;
};

class CameraBridge {
 public:
  bool begin(const CameraBridgePins &pins);
  void update();
  void trigger();

  bool isAvailable() const;
  bool hasReadyBurst() const;
  void clearReadyBurst();

  uint16_t frameCount() const;
  uint32_t triggerMs() const;
  const char *stateLabel() const;

  size_t buildBlePayload(uint8_t *buffer, size_t bufferSize,
                         uint32_t packetId, uint32_t sessionId) const;

 private:
  struct StoredFrame {
    uint8_t *data = nullptr;
    size_t len = 0;
    uint32_t timestampMs = 0;
    uint16_t width = 0;
    uint16_t height = 0;
  };

  enum class State : uint8_t {
    Disabled,
    Armed,
    Capturing,
    Ready,
    Error,
  };

  static constexpr uint32_t kCameraXclkHz = 20000000UL;
  static constexpr uint32_t kPostTriggerMs = 850UL;
  static constexpr uint32_t kCaptureFrameIntervalMs = 55UL;
  static constexpr uint16_t kMaxBurstFrames = 8;
  static constexpr size_t kMaxCaptureBytes = 28000;
  static constexpr uint8_t kJpegQuality = 18;
  static constexpr size_t kBleHeaderLength = 24;
  static constexpr size_t kBleFrameEntryLength = 4;

  bool initCameraHardware();
  void shutdownCameraHardware();
  bool copyFrame(StoredFrame &dst, const uint8_t *src, size_t len,
                 uint32_t timestampMs, uint16_t width, uint16_t height);
  bool cloneFrame(StoredFrame &dst, const StoredFrame &src);
  void freeFrame(StoredFrame &frame);
  void clearFrames(StoredFrame *frames, size_t count);
  void clearBurst();
  void setError(const char *message);
  void beginBurstCapture();
  bool storeBurstFrame(const uint8_t *src, size_t len, uint32_t timestampMs,
                      uint16_t width, uint16_t height);
  void finishBurstCapture(const char *reason);
  float estimatedFps() const;

  StoredFrame burstFrames_[kMaxBurstFrames] = {};

  State state_ = State::Disabled;
  CameraBridgePins pins_ = {};
  bool cameraInitialized_ = false;
  bool triggerPending_ = false;
  size_t burstFrameCount_ = 0;
  size_t burstTotalBytes_ = 0;
  uint32_t burstTriggerMs_ = 0;
  uint32_t lastFrameAttemptMs_ = 0;
  uint16_t width_ = 0;
  uint16_t height_ = 0;
};
