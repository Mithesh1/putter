// OV5640 higher-resolution burst capture over Wi-Fi.
// This sketch keeps a short rolling pre-trigger buffer in PSRAM, then freezes
// a post-trigger burst that the Python analyzer can download frame-by-frame.

#include "esp_camera.h"
#include "esp_heap_caps.h"
#include <WiFi.h>
#include <WebServer.h>

#define CAM_XCLK   13
#define CAM_PCLK   39
#define CAM_VSYNC   9
#define CAM_HREF   11
#define CAM_D0     41
#define CAM_D1      2 //1
#define CAM_D2      1 //0
#define CAM_D3     42
#define CAM_D4     40
#define CAM_D5     21
#define CAM_D6     14
#define CAM_D7     12
#define CAM_SDA     4
#define CAM_SCL     5
#define CAM_RST    15
#define CAM_PWDN   10

constexpr uint32_t CAMERA_XCLK_HZ = 20000000;
constexpr framesize_t BURST_FRAME_SIZE = FRAMESIZE_VGA;
constexpr int BURST_JPEG_QUALITY = 14;
constexpr int CAMERA_FB_COUNT = 3;
constexpr int INITIAL_SETTLE_FRAMES = 8;

constexpr uint32_t PRE_TRIGGER_MS = 350;
constexpr uint32_t POST_TRIGGER_MS = 1400;
constexpr size_t PREBUFFER_SLOTS = 8;
constexpr size_t MAX_BURST_FRAMES = 40;
constexpr size_t MAX_CAPTURE_BYTES = 5 * 1024 * 1024;

const char* AP_SSID = "OV5640-Burst";
constexpr int AP_CHANNEL = 1;

struct StoredFrame {
  uint8_t* data = nullptr;
  size_t len = 0;
  uint32_t timestampMs = 0;
  uint16_t width = 0;
  uint16_t height = 0;
};

enum class BurstState : uint8_t {
  Armed,
  Capturing,
  Ready,
  Error,
};

WebServer server(80);
sensor_t* cameraSensor = nullptr;

StoredFrame prebuffer[PREBUFFER_SLOTS];
StoredFrame burstFrames[MAX_BURST_FRAMES];

size_t preWriteIndex = 0;
size_t preValidCount = 0;
size_t burstFrameCount = 0;
size_t burstPreFrameCount = 0;
size_t burstTotalBytes = 0;
uint32_t burstTriggerMs = 0;
uint32_t captureStopMs = 0;
uint32_t lastCaptureDurationMs = 0;
float lastBurstFps = 0.0f;
BurstState burstState = BurstState::Armed;
bool triggerPending = false;
String lastError;
String lastFinishReason = "armed";

const char* burstStateName(BurstState state) {
  switch (state) {
    case BurstState::Armed:
      return "armed";
    case BurstState::Capturing:
      return "capturing";
    case BurstState::Ready:
      return "ready";
    case BurstState::Error:
      return "error";
  }
  return "unknown";
}

String jsonEscape(const String& text) {
  String escaped;
  escaped.reserve(text.length() + 8);
  for (size_t i = 0; i < text.length(); ++i) {
    char c = text.charAt(i);
    if (c == '\\' || c == '"') {
      escaped += '\\';
    }
    if (c == '\n' || c == '\r') {
      escaped += ' ';
    } else {
      escaped += c;
    }
  }
  return escaped;
}

void freeStoredFrame(StoredFrame& frame) {
  if (frame.data) {
    heap_caps_free(frame.data);
  }
  frame = {};
}

void clearStoredFrames(StoredFrame* frames, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    freeStoredFrame(frames[i]);
  }
}

bool copyBufferIntoFrame(StoredFrame& dst,
                         const uint8_t* src,
                         size_t len,
                         uint32_t timestampMs,
                         uint16_t width,
                         uint16_t height) {
  freeStoredFrame(dst);

  uint8_t* storage = static_cast<uint8_t*>(
    heap_caps_malloc(len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (!storage) {
    storage = static_cast<uint8_t*>(heap_caps_malloc(len, MALLOC_CAP_8BIT));
  }
  if (!storage) {
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

bool copyCameraFrame(StoredFrame& dst, const camera_fb_t* fb, uint32_t timestampMs) {
  return copyBufferIntoFrame(
    dst,
    fb->buf,
    fb->len,
    timestampMs,
    static_cast<uint16_t>(fb->width),
    static_cast<uint16_t>(fb->height));
}

bool cloneStoredFrame(StoredFrame& dst, const StoredFrame& src) {
  if (!src.data || src.len == 0) {
    return false;
  }
  return copyBufferIntoFrame(dst, src.data, src.len, src.timestampMs, src.width, src.height);
}

void applyStableSensorDefaults(sensor_t* sensor) {
  if (!sensor) {
    return;
  }

  sensor->set_framesize(sensor, BURST_FRAME_SIZE);
  sensor->set_quality(sensor, BURST_JPEG_QUALITY);
  sensor->set_gainceiling(sensor, GAINCEILING_8X);
  sensor->set_whitebal(sensor, 1);
  sensor->set_awb_gain(sensor, 1);
  sensor->set_exposure_ctrl(sensor, 1);
  sensor->set_gain_ctrl(sensor, 1);
  sensor->set_brightness(sensor, 0);
  sensor->set_contrast(sensor, 0);
  sensor->set_saturation(sensor, 0);
  sensor->set_special_effect(sensor, 0);
  sensor->set_colorbar(sensor, 0);
  sensor->set_hmirror(sensor, 0);
  sensor->set_vflip(sensor, 0);
}

void clearBurstCapture() {
  clearStoredFrames(burstFrames, MAX_BURST_FRAMES);
  burstFrameCount = 0;
  burstPreFrameCount = 0;
  burstTotalBytes = 0;
  burstTriggerMs = 0;
  captureStopMs = 0;
  lastCaptureDurationMs = 0;
  lastBurstFps = 0.0f;
}

void setBurstError(const String& message) {
  burstState = BurstState::Error;
  lastError = message;
  lastFinishReason = "error";
  Serial.println("BURST ERROR: " + message);
}

void storeIntoPrebuffer(const camera_fb_t* fb, uint32_t timestampMs) {
  if (!copyCameraFrame(prebuffer[preWriteIndex], fb, timestampMs)) {
    setBurstError("failed to store pre-trigger frame");
    return;
  }

  preWriteIndex = (preWriteIndex + 1) % PREBUFFER_SLOTS;
  if (preValidCount < PREBUFFER_SLOTS) {
    ++preValidCount;
  }
}

void updateBurstFps() {
  if (burstFrameCount < 2) {
    lastBurstFps = 0.0f;
    return;
  }

  uint32_t firstMs = burstFrames[0].timestampMs;
  uint32_t lastMs = burstFrames[burstFrameCount - 1].timestampMs;
  if (lastMs <= firstMs) {
    lastBurstFps = 0.0f;
    return;
  }

  lastBurstFps = (burstFrameCount - 1) * 1000.0f / static_cast<float>(lastMs - firstMs);
}

void finishBurstCapture(const String& reason) {
  captureStopMs = millis();
  lastCaptureDurationMs = captureStopMs - burstTriggerMs;
  lastFinishReason = reason;
  updateBurstFps();

  if (burstFrameCount == 0) {
    setBurstError("burst ended without frames");
    return;
  }

  burstState = BurstState::Ready;
  lastError = "";
  Serial.printf("Burst ready: %u frames (%u pre-trigger), %.1f fps estimate, %u bytes, reason=%s\n",
                static_cast<unsigned int>(burstFrameCount),
                static_cast<unsigned int>(burstPreFrameCount),
                lastBurstFps,
                static_cast<unsigned int>(burstTotalBytes),
                reason.c_str());
}

void seedBurstFromPrebuffer(uint32_t triggerMs) {
  if (preValidCount == 0) {
    return;
  }

  size_t oldestIndex = preValidCount == PREBUFFER_SLOTS ? preWriteIndex : 0;
  for (size_t i = 0; i < preValidCount && burstFrameCount < MAX_BURST_FRAMES; ++i) {
    size_t idx = (oldestIndex + i) % PREBUFFER_SLOTS;
    const StoredFrame& candidate = prebuffer[idx];
    if (!candidate.data || candidate.len == 0) {
      continue;
    }
    if (triggerMs < candidate.timestampMs || (triggerMs - candidate.timestampMs) > PRE_TRIGGER_MS) {
      continue;
    }
    if ((burstTotalBytes + candidate.len) > MAX_CAPTURE_BYTES) {
      break;
    }
    if (!cloneStoredFrame(burstFrames[burstFrameCount], candidate)) {
      setBurstError("failed to clone pre-trigger frame");
      return;
    }
    burstTotalBytes += candidate.len;
    ++burstFrameCount;
    ++burstPreFrameCount;
  }
}

void beginBurstCapture() {
  clearBurstCapture();
  lastError = "";
  burstTriggerMs = millis();
  burstState = BurstState::Capturing;
  seedBurstFromPrebuffer(burstTriggerMs);
  Serial.printf("Burst trigger accepted. Seeded %u pre-trigger frames\n",
                static_cast<unsigned int>(burstPreFrameCount));
}

bool storeBurstFrame(const camera_fb_t* fb, uint32_t timestampMs) {
  if (burstFrameCount >= MAX_BURST_FRAMES) {
    finishBurstCapture("frame_limit");
    return false;
  }
  if ((burstTotalBytes + fb->len) > MAX_CAPTURE_BYTES) {
    finishBurstCapture("memory_limit");
    return false;
  }
  if (!copyCameraFrame(burstFrames[burstFrameCount], fb, timestampMs)) {
    setBurstError("failed to store burst frame");
    return false;
  }

  burstTotalBytes += fb->len;
  ++burstFrameCount;
  return true;
}

String buildStatusJson() {
  String json;
  json.reserve(512);
  json += "{";
  json += "\"state\":\"";
  json += burstStateName(burstState);
  json += "\",";
  json += "\"trigger_pending\":";
  json += triggerPending ? "true" : "false";
  json += ",";
  json += "\"prebuffer_frames\":";
  json += static_cast<unsigned int>(preValidCount);
  json += ",";
  json += "\"burst_frames\":";
  json += static_cast<unsigned int>(burstFrameCount);
  json += ",";
  json += "\"burst_pre_frames\":";
  json += static_cast<unsigned int>(burstPreFrameCount);
  json += ",";
  json += "\"burst_bytes\":";
  json += static_cast<unsigned int>(burstTotalBytes);
  json += ",";
  json += "\"pre_trigger_ms\":";
  json += static_cast<unsigned long>(PRE_TRIGGER_MS);
  json += ",";
  json += "\"post_trigger_ms\":";
  json += static_cast<unsigned long>(POST_TRIGGER_MS);
  json += ",";
  json += "\"fps_estimate\":";
  json += String(lastBurstFps, 2);
  json += ",";
  json += "\"last_capture_duration_ms\":";
  json += static_cast<unsigned long>(lastCaptureDurationMs);
  json += ",";
  json += "\"finish_reason\":\"";
  json += jsonEscape(lastFinishReason);
  json += "\",";
  json += "\"error\":\"";
  json += jsonEscape(lastError);
  json += "\"";
  json += "}";
  return json;
}

String buildManifestJson() {
  String json;
  json.reserve(2048 + burstFrameCount * 56);
  json += "{";
  json += "\"state\":\"";
  json += burstStateName(burstState);
  json += "\",";
  json += "\"frame_count\":";
  json += static_cast<unsigned int>(burstFrameCount);
  json += ",";
  json += "\"pre_frame_count\":";
  json += static_cast<unsigned int>(burstPreFrameCount);
  json += ",";
  json += "\"fps_estimate\":";
  json += String(lastBurstFps, 2);
  json += ",";
  json += "\"capture_duration_ms\":";
  json += static_cast<unsigned long>(lastCaptureDurationMs);
  json += ",";
  json += "\"frame_size\":\"VGA\",";
  json += "\"jpeg_quality\":";
  json += BURST_JPEG_QUALITY;
  json += ",";
  json += "\"xclk_hz\":";
  json += static_cast<unsigned long>(CAMERA_XCLK_HZ);
  json += ",";
  json += "\"finish_reason\":\"";
  json += jsonEscape(lastFinishReason);
  json += "\",";
  json += "\"frames\":[";

  for (size_t i = 0; i < burstFrameCount; ++i) {
    if (i > 0) {
      json += ",";
    }
    json += "{";
    json += "\"index\":";
    json += static_cast<unsigned int>(i);
    json += ",";
    json += "\"t_ms\":";
    json += static_cast<unsigned long>(burstFrames[i].timestampMs);
    json += ",";
    json += "\"size\":";
    json += static_cast<unsigned int>(burstFrames[i].len);
    json += ",";
    json += "\"width\":";
    json += static_cast<unsigned int>(burstFrames[i].width);
    json += ",";
    json += "\"height\":";
    json += static_cast<unsigned int>(burstFrames[i].height);
    json += "}";
  }

  json += "]";
  json += "}";
  return json;
}

void handleRoot() {
  String html = "<html><head><title>OV5640 Burst</title>";
  html += "<style>body{font-family:Arial,sans-serif;background:#111;color:#f2f2f2;margin:0;padding:24px}";
  html += "button{font-size:16px;padding:10px 14px;margin-right:12px;margin-bottom:12px}";
  html += "pre{background:#1d1d1d;padding:16px;border-radius:8px;overflow:auto}</style></head><body>";
  html += "<h2>OV5640 Burst Capture</h2>";
  html += "<button onclick=\"fetch('/trigger').then(update)\">Trigger Burst</button>";
  html += "<button onclick=\"fetch('/clear').then(update)\">Clear Burst</button>";
  html += "<button onclick=\"update()\">Refresh Status</button>";
  html += "<pre id='status'>loading...</pre>";
  html += "<script>";
  html += "function update(){fetch('/manifest').then(r=>r.text()).then(t=>document.getElementById('status').textContent=t);}";
  html += "update(); setInterval(update, 1000);";
  html += "</script></body></html>";
  server.send(200, "text/html", html);
}

void handleStatus() {
  server.send(200, "application/json", buildStatusJson());
}

void handleManifest() {
  server.send(200, "application/json", buildManifestJson());
}

void handleTrigger() {
  if (burstState == BurstState::Capturing) {
    server.send(409, "application/json", "{\"accepted\":false,\"reason\":\"capture_in_progress\"}");
    return;
  }
  triggerPending = true;
  server.send(202, "application/json", "{\"accepted\":true}");
}

void handleClear() {
  clearBurstCapture();
  lastError = "";
  lastFinishReason = "cleared";
  burstState = BurstState::Armed;
  server.send(200, "application/json", "{\"cleared\":true}");
}

void handleFrame() {
  if (!server.hasArg("id")) {
    server.send(400, "application/json", "{\"error\":\"missing id\"}");
    return;
  }

  int index = server.arg("id").toInt();
  if (index < 0 || static_cast<size_t>(index) >= burstFrameCount || !burstFrames[index].data) {
    server.send(404, "application/json", "{\"error\":\"frame not found\"}");
    return;
  }

  server.sendHeader("Cache-Control", "no-cache");
  server.send_P(200,
                "image/jpeg",
                reinterpret_cast<const char*>(burstFrames[index].data),
                burstFrames[index].len);
}

void configureCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = CAM_D0;
  config.pin_d1 = CAM_D1;
  config.pin_d2 = CAM_D2;
  config.pin_d3 = CAM_D3;
  config.pin_d4 = CAM_D4;
  config.pin_d5 = CAM_D5;
  config.pin_d6 = CAM_D6;
  config.pin_d7 = CAM_D7;
  config.pin_xclk = CAM_XCLK;
  config.pin_pclk = CAM_PCLK;
  config.pin_vsync = CAM_VSYNC;
  config.pin_href = CAM_HREF;
  config.pin_sccb_sda = CAM_SDA;
  config.pin_sccb_scl = CAM_SCL;
  config.pin_pwdn = CAM_PWDN;
  config.pin_reset = CAM_RST;
  config.xclk_freq_hz = CAMERA_XCLK_HZ;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = BURST_FRAME_SIZE;
  config.jpeg_quality = BURST_JPEG_QUALITY;
  config.fb_count = CAMERA_FB_COUNT;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("CAMERA INIT FAILED: 0x%x\n", err);
    while (true) {
      delay(1000);
    }
  }

  cameraSensor = esp_camera_sensor_get();
  applyStableSensorDefaults(cameraSensor);

  for (int i = 0; i < INITIAL_SETTLE_FRAMES; ++i) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) {
      esp_camera_fb_return(fb);
    }
    delay(40);
  }

  Serial.println("Camera ready for burst capture");
}

void configureNetwork() {
  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);

  if (!WiFi.softAP(AP_SSID, nullptr, AP_CHANNEL, 0, 1)) {
    Serial.println("SOFTAP FAILED");
    while (true) {
      delay(1000);
    }
  }

  IPAddress ip = WiFi.softAPIP();
  Serial.printf("Connect laptop to WiFi: %s\n", AP_SSID);
  Serial.print("Open control page: http://");
  Serial.println(ip);
}

void captureOneCameraFrame() {
  uint32_t captureStartMs = millis();
  camera_fb_t* fb = esp_camera_fb_get();
  uint32_t capturedAtMs = millis();
  if (!fb) {
    setBurstError("camera capture failed");
    return;
  }

  if (burstState == BurstState::Capturing) {
    if (!storeBurstFrame(fb, capturedAtMs)) {
      esp_camera_fb_return(fb);
      return;
    }

    if ((capturedAtMs - burstTriggerMs) >= POST_TRIGGER_MS) {
      esp_camera_fb_return(fb);
      finishBurstCapture("time_complete");
      return;
    }
  } else {
    storeIntoPrebuffer(fb, capturedAtMs);
  }

  esp_camera_fb_return(fb);

  if ((capturedAtMs - captureStartMs) > 80) {
    Serial.printf("Slow capture: %ums\n", static_cast<unsigned int>(capturedAtMs - captureStartMs));
  }
}

void setup() {
  Serial.begin(115200);
  delay(1500);
  Serial.println("\n=== OV5640 Burst Capture ===");

  if (!psramFound()) {
    Serial.println("PSRAM is required for higher-resolution burst capture.");
    while (true) {
      delay(1000);
    }
  }

  configureCamera();
  configureNetwork();

  Serial.printf("Free DRAM: %u bytes\n", static_cast<unsigned int>(heap_caps_get_free_size(MALLOC_CAP_8BIT)));
  Serial.printf("Free PSRAM: %u bytes\n", static_cast<unsigned int>(heap_caps_get_free_size(MALLOC_CAP_SPIRAM)));
  Serial.printf("Burst config: VGA, jpeg=%d, xclk=%luMHz, pre=%lums, post=%lums, frame cap=%u, byte cap=%u\n",
                BURST_JPEG_QUALITY,
                CAMERA_XCLK_HZ / 1000000UL,
                PRE_TRIGGER_MS,
                POST_TRIGGER_MS,
                static_cast<unsigned int>(MAX_BURST_FRAMES),
                static_cast<unsigned int>(MAX_CAPTURE_BYTES));

  server.on("/", handleRoot);
  server.on("/status", handleStatus);
  server.on("/manifest", handleManifest);
  server.on("/trigger", handleTrigger);
  server.on("/clear", handleClear);
  server.on("/frame", handleFrame);
  server.begin();

  Serial.println("HTTP API ready");
  Serial.println("  /trigger = start burst");
  Serial.println("  /manifest = capture metadata");
  Serial.println("  /frame?id=N = jpeg frame download");
}

void loop() {
  server.handleClient();

  if (triggerPending) {
    triggerPending = false;
    beginBurstCapture();
  }

  captureOneCameraFrame();
}
