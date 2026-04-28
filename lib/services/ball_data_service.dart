import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Binary packet layout sent by burst_wifi_switch.py (little-endian, 39 bytes):
//   0  float32  avg_velocity_mph
//   4  float32  peak_velocity_mph
//   8  float32  avg_velocity_ball_diam_s
//  12  float32  peak_velocity_ball_diam_s
//  16  float32  rotation_rate_deg_s
//  20  float32  wobble_magnitude_deg
//  24  float32  total_roll_distance_in
//  28  float32  total_roll_distance_ball_diam
//  32  uint8    wobble_detected (0 or 1)
//  33  uint16   frame_count
//  35  float32  fps

class BallData {
  final double avgVelocityMph;
  final double peakVelocityMph;
  final double avgVelocityBallDiamS;
  final double peakVelocityBallDiamS;
  final double rotationRateDegS;
  final double wobbleMagnitudeDeg;
  final double totalRollDistanceIn;
  final double totalRollDistanceBallDiam;
  final bool wobbleDetected;
  final int frameCount;
  final double fps;
  final DateTime receivedAt;

  const BallData({
    required this.avgVelocityMph,
    required this.peakVelocityMph,
    required this.avgVelocityBallDiamS,
    required this.peakVelocityBallDiamS,
    required this.rotationRateDegS,
    required this.wobbleMagnitudeDeg,
    required this.totalRollDistanceIn,
    required this.totalRollDistanceBallDiam,
    required this.wobbleDetected,
    required this.frameCount,
    required this.fps,
    required this.receivedAt,
  });

  factory BallData.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    return BallData(
      avgVelocityMph: bd.getFloat32(0, Endian.little),
      peakVelocityMph: bd.getFloat32(4, Endian.little),
      avgVelocityBallDiamS: bd.getFloat32(8, Endian.little),
      peakVelocityBallDiamS: bd.getFloat32(12, Endian.little),
      rotationRateDegS: bd.getFloat32(16, Endian.little),
      wobbleMagnitudeDeg: bd.getFloat32(20, Endian.little),
      totalRollDistanceIn: bd.getFloat32(24, Endian.little),
      totalRollDistanceBallDiam: bd.getFloat32(28, Endian.little),
      wobbleDetected: bytes[32] != 0,
      frameCount: bd.getUint16(33, Endian.little),
      fps: bd.getFloat32(35, Endian.little),
      receivedAt: DateTime.now(),
    );
  }
}

class BallDataService {
  static final BallDataService instance = BallDataService._();
  BallDataService._();

  static const String _targetDeviceName = 'BurstAnalyzer';
  static const String _serviceUuid = '12340000-0000-4b59-9000-000000000001';
  static const String _charUuid = '12340000-0000-4b59-9000-000000000002';

  final _ble = FlutterReactiveBle();
  final _controller = StreamController<BallData>.broadcast();
  final _historyController = StreamController<List<BallData>>.broadcast();
  final _debugController = StreamController<String>.broadcast();

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  bool _started = false;
  bool _disposed = false;
  BallData? _latestBallData;
  final List<BallData> _history = <BallData>[];
  final Set<String> _seenScanIds = <String>{};
  static const int _maxHistoryPackets = 24;

  Stream<BallData> get stream => _controller.stream;
  Stream<List<BallData>> get historyStream => _historyController.stream;
  BallData? get latestBallData => _latestBallData;
  List<BallData> get recentHistory => List<BallData>.unmodifiable(_history);
  Stream<String> get debugStream => _debugController.stream;
  String _latestDebugMessage = 'Idle';
  String get latestDebugMessage => _latestDebugMessage;

  void _emitDebug(String message) {
    _latestDebugMessage = message;
    debugPrint('[BallDataService] $message');
    if (!_debugController.isClosed) {
      _debugController.add(message);
    }
  }

  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _emitDebug('Ball service start requested');
    _statusSub = _ble.statusStream.listen(_handleStatus);
  }

  Future<void> stop() async {
    _started = false;
    _emitDebug('Ball service stopped');
    await _cancelTransientWork();
    await _statusSub?.cancel();
    _statusSub = null;
  }

  void _handleStatus(BleStatus status) {
    if (_disposed) {
      return;
    }

    _emitDebug('BLE status: $status');

    if (status == BleStatus.ready) {
      _scan();
      return;
    }

    if (status == BleStatus.poweredOff ||
        status == BleStatus.unauthorized ||
        status == BleStatus.unsupported) {
      unawaited(_cancelTransientWork());
    }
  }

  Future<void> _cancelTransientWork() async {
    _seenScanIds.clear();
    await _scanSub?.cancel();
    _scanSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
  }

  void _scan() {
    if (_disposed || _ble.status != BleStatus.ready || _scanSub != null) {
      return;
    }
    _seenScanIds.clear();
    _emitDebug('Scanning for ball service');
    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            if (_seenScanIds.add(device.id)) {
              final advertisedServices = device.serviceUuids
                  .map((uuid) => uuid.toString())
                  .join(', ');
              _emitDebug(
                'Saw BLE device: '
                '${device.name.isEmpty ? '(unnamed)' : device.name} '
                '[${device.id}] '
                'RSSI ${device.rssi} '
                '${advertisedServices.isEmpty ? '' : 'services: $advertisedServices'}',
              );
            }

            if (!_shouldConnect(device)) {
              return;
            }

            _emitDebug(
              'Ball device found: ${device.name.isEmpty ? device.id : device.name}',
            );
            final currentScan = _scanSub;
            _scanSub = null;
            currentScan?.cancel();
            _connect(device.id);
          },
          onError: (_) {
            _emitDebug('Ball scan error, retrying');
            _scanSub = null;
            if (!_disposed) {
              Future.delayed(const Duration(seconds: 5), _scan);
            }
          },
          onDone: () {
            _scanSub = null;
          },
        );
  }

  bool _shouldConnect(DiscoveredDevice device) {
    final normalizedName = device.name.trim().toLowerCase();
    if (normalizedName == _targetDeviceName.toLowerCase()) {
      return true;
    }

    return device.serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase() == _serviceUuid.toLowerCase(),
    );
  }

  void _connect(String deviceId) {
    if (_disposed || _ble.status != BleStatus.ready) {
      return;
    }
    _emitDebug('Connecting to ball device');
    _connSub?.cancel();
    _connSub = _ble.connectToDevice(id: deviceId).listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _emitDebug('Ball device connected');
        _subscribe(deviceId);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _emitDebug('Ball device disconnected');
        _notifySub?.cancel();
        _notifySub = null;
        _connSub = null;
        if (!_disposed) {
          Future.delayed(const Duration(seconds: 5), _scan);
        }
      }
    });
  }

  void _subscribe(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_charUuid),
      deviceId: deviceId,
    );
    _emitDebug('Subscribed to ball notifications');
    _notifySub = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          (bytes) {
            if (bytes.length >= 39) {
              final data = BallData.fromBytes(Uint8List.fromList(bytes));
              _latestBallData = data;
              _history.add(data);
              if (_history.length > _maxHistoryPackets) {
                _history.removeAt(0);
              }
              _emitDebug(
                'Ball packet ${bytes.length}B: ${data.avgVelocityMph.toStringAsFixed(1)} mph avg, ${data.frameCount} frames',
              );
              _controller.add(data);
              if (!_historyController.isClosed) {
                _historyController.add(List<BallData>.unmodifiable(_history));
              }
            } else {
              _emitDebug('Short ball packet received: ${bytes.length}B');
            }
          },
          onError: (_) {
            _emitDebug('Ball notification stream error');
          },
        );
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _historyController.close();
    await _debugController.close();
    await _controller.close();
  }
}
