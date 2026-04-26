import 'camera_bridge_service_base.dart';
import 'camera_bridge_service_stub.dart'
    if (dart.library.io) 'camera_bridge_service_io.dart' as impl;

export 'camera_bridge_models.dart';
export 'camera_bridge_service_base.dart';

CameraBridgeService createCameraBridgeService() => impl.createCameraBridgeService();
