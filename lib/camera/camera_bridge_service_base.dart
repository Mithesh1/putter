import 'camera_bridge_models.dart';
import 'dart:typed_data';

enum CameraBridgeAction { capture, calibrate }

extension CameraBridgeActionX on CameraBridgeAction {
  String get cliName => switch (this) {
    CameraBridgeAction.capture => 'capture',
    CameraBridgeAction.calibrate => 'calibrate',
  };

  String get label => switch (this) {
    CameraBridgeAction.capture => 'Capture + Analyze',
    CameraBridgeAction.calibrate => 'Calibrate',
  };

  String get helperText => switch (this) {
    CameraBridgeAction.capture =>
      'Trigger a burst, analyze the roll, and export frames plus slow motion.',
    CameraBridgeAction.calibrate =>
      'Trigger a burst and open the OpenCV calibration controls for current lighting.',
  };
}

typedef CameraLogSink = void Function(String line);

abstract class CameraBridgeService {
  bool get supported;
  String get platformMessage;

  Future<CameraBridgeResult> runAction(
    CameraBridgeAction action, {
    CameraLogSink? onLog,
  });

  Future<void> openPath(String path);

  Future<Uint8List> readBytes(String path);
}
