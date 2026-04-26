import 'camera_bridge_models.dart';
import 'camera_bridge_service_base.dart';
import 'dart:typed_data';

CameraBridgeService createCameraBridgeService() => _StubCameraBridgeService();

class _StubCameraBridgeService implements CameraBridgeService {
  @override
  bool get supported => false;

  @override
  String get platformMessage =>
      'Camera bridge is only available for local desktop builds with Python and OpenCV installed.';

  @override
  Future<void> openPath(String path) {
    throw UnsupportedError(platformMessage);
  }

  @override
  Future<Uint8List> readBytes(String path) {
    throw UnsupportedError(platformMessage);
  }

  @override
  Future<CameraBridgeResult> runAction(
    CameraBridgeAction action, {
    CameraLogSink? onLog,
  }) {
    throw UnsupportedError(platformMessage);
  }
}
