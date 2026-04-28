import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Aggregate packet (characteristic ...0002, 39 bytes, little-endian):
//   0  float32  path_drift_deg
//   4  float32  rms_lateral_px
//   8  float32  direction_wobble_deg
//  12  float32  total_path_px
//  16  float32  avg_radius_px
//  20  float32  reserved
//  24  float32  reserved
//  28  float32  reserved
//  32  uint8    tracking_quality_pct
//  33  uint16   frame_count
//  35  float32  fps

class BallData {
  final double pathDriftDeg;
  final double rmsLateralPx;
  final double directionWobbleDeg;
  final double totalPathPx;
  final double avgRadiusPx;
  final int trackingQualityPct;
  final int frameCount;
  final double fps;
  final DateTime receivedAt;

  const BallData({
    required this.pathDriftDeg,
    required this.rmsLateralPx,
    required this.directionWobbleDeg,
    required this.totalPathPx,
    required this.avgRadiusPx,
    required this.trackingQualityPct,
    required this.frameCount,
    required this.fps,
    required this.receivedAt,
  });

  double get rmsLateralBallDiams =>
      avgRadiusPx > 0 ? rmsLateralPx / (avgRadiusPx * 2) : 0.0;

  double get totalPathBallDiams =>
      avgRadiusPx > 0 ? totalPathPx / (avgRadiusPx * 2) : 0.0;

  String get driftDirection => pathDriftDeg > 0.2
      ? 'Right'
      : pathDriftDeg < -0.2
      ? 'Left'
      : 'Straight';

  factory BallData.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    return BallData(
      pathDriftDeg: bd.getFloat32(0, Endian.little),
      rmsLateralPx: bd.getFloat32(4, Endian.little),
      directionWobbleDeg: bd.getFloat32(8, Endian.little),
      totalPathPx: bd.getFloat32(12, Endian.little),
      avgRadiusPx: bd.getFloat32(16, Endian.little),
      trackingQualityPct: bytes[32],
      frameCount: bd.getUint16(33, Endian.little),
      fps: bd.getFloat32(35, Endian.little),
      receivedAt: DateTime.now(),
    );
  }
}

// Time-series packet (characteristic ...0004):
//   0     uint8    N
//   1-4   float32  fps
//   5     N×int16  lateral_deviation_px × 100
//   5+2N  N×int16  forward_position_px × 10

class BallTimeSeries {
  final double fps;
  final List<double> lateralPx;
  final List<double> forwardPx;
  final double avgRadiusPx;
  final DateTime receivedAt;

  const BallTimeSeries({
    required this.fps,
    required this.lateralPx,
    required this.forwardPx,
    required this.avgRadiusPx,
    required this.receivedAt,
  });

  int get frameCount => lateralPx.length;

  List<double> get lateralBallDiams => avgRadiusPx > 0
      ? lateralPx.map((value) => value / (avgRadiusPx * 2)).toList()
      : lateralPx;

  List<double> get forwardBallDiams => avgRadiusPx > 0
      ? forwardPx.map((value) => value / (avgRadiusPx * 2)).toList()
      : forwardPx;

  factory BallTimeSeries.fromBytes(Uint8List bytes, {double avgRadiusPx = 0.0}) {
    if (bytes.length < 5) {
      return BallTimeSeries(
        fps: 13.0,
        lateralPx: const <double>[],
        forwardPx: const <double>[],
        avgRadiusPx: avgRadiusPx,
        receivedAt: DateTime.now(),
      );
    }

    final bd = ByteData.sublistView(bytes);
    final count = bytes[0];
    final fps = bd.getFloat32(1, Endian.little);
    final expectedLength = 5 + (4 * count);
    if (bytes.length < expectedLength || count == 0) {
      return BallTimeSeries(
        fps: fps,
        lateralPx: const <double>[],
        forwardPx: const <double>[],
        avgRadiusPx: avgRadiusPx,
        receivedAt: DateTime.now(),
      );
    }

    final lateralPx = <double>[];
    final forwardPx = <double>[];
    var offset = 5;
    for (var index = 0; index < count; index++) {
      lateralPx.add(bd.getInt16(offset, Endian.little) / 100.0);
      offset += 2;
    }
    for (var index = 0; index < count; index++) {
      forwardPx.add(bd.getInt16(offset, Endian.little) / 10.0);
      offset += 2;
    }

    return BallTimeSeries(
      fps: fps,
      lateralPx: List<double>.unmodifiable(lateralPx),
      forwardPx: List<double>.unmodifiable(forwardPx),
      avgRadiusPx: avgRadiusPx,
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
  static const String _triggerCharUuid =
      '12340000-0000-4b59-9000-000000000003';
  static const String _timeseriesCharUuid =
      '12340000-0000-4b59-9000-000000000004';

  final _ble = FlutterReactiveBle();
  final _controller = StreamController<BallData>.broadcast();
  final _timeseriesController = StreamController<BallTimeSeries>.broadcast();
  final _historyController = StreamController<List<BallData>>.broadcast();
  final _debugController = StreamController<String>.broadcast();

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _timeseriesSub;
  bool _started = false;
  bool _disposed = false;
  BallData? _latestBallData;
  BallTimeSeries? _latestTimeSeries;
  final List<BallData> _history = <BallData>[];
  final Set<String> _seenScanIds = <String>{};
  String? _connectedDeviceId;
  static const int _maxHistoryPackets = 24;

  Stream<BallData> get stream => _controller.stream;
  Stream<BallTimeSeries> get timeseriesStream => _timeseriesController.stream;
  Stream<List<BallData>> get historyStream => _historyController.stream;
  BallData? get latestBallData => _latestBallData;
  BallTimeSeries? get latestTimeSeries => _latestTimeSeries;
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
    if (!_started &&
        _scanSub == null &&
        _connSub == null &&
        _notifySub == null &&
        _timeseriesSub == null) {
      return;
    }
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
    _connectedDeviceId = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _timeseriesSub?.cancel();
    _timeseriesSub = null;
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
        _connectedDeviceId = deviceId;
        _emitDebug('Ball device connected');
        _subscribe(deviceId);
        _subscribeTimeseries(deviceId);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _connectedDeviceId = null;
        _emitDebug('Ball device disconnected');
        _notifySub?.cancel();
        _notifySub = null;
        _timeseriesSub?.cancel();
        _timeseriesSub = null;
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
    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen(
          (bytes) {
        if (bytes.length >= 39) {
          final data = BallData.fromBytes(Uint8List.fromList(bytes));
          _latestBallData = data;
          _history.add(data);
          if (_history.length > _maxHistoryPackets) {
            _history.removeAt(0);
          }
          _emitDebug(
            'Ball packet ${bytes.length}B: '
                'drift ${data.pathDriftDeg.toStringAsFixed(2)}°, '
                '${data.frameCount} frames',
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

  void _subscribeTimeseries(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_timeseriesCharUuid),
      deviceId: deviceId,
    );
    _emitDebug('Subscribed to ball time series');
    _timeseriesSub = _ble.subscribeToCharacteristic(characteristic).listen(
          (bytes) {
        try {
          final timeSeries = BallTimeSeries.fromBytes(
            Uint8List.fromList(bytes),
            avgRadiusPx: _latestBallData?.avgRadiusPx ?? 0.0,
          );
          _latestTimeSeries = timeSeries;
          _emitDebug(
            'Ball time series ${bytes.length}B: '
                '${timeSeries.frameCount} samples @ ${timeSeries.fps.toStringAsFixed(1)} fps',
          );
          _timeseriesController.add(timeSeries);
        } catch (_) {
          _emitDebug('Malformed ball time-series packet: ${bytes.length}B');
        }
      },
      onError: (_) {
        _emitDebug('Ball time-series stream error');
      },
    );
  }

  Future<void> sendForwardTrigger(int forwardTriggerMs) async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      _emitDebug('Skipped ball trigger write; ball device not connected');
      return;
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_triggerCharUuid),
      deviceId: deviceId,
    );
    final payload = utf8.encode('FWD:$forwardTriggerMs');
    try {
      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: payload,
      );
      _emitDebug('Forward trigger sent to ball device: ${payload.length}B');
    } catch (error) {
      _emitDebug('Ball trigger write failed: $error');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _timeseriesController.close();
    await _historyController.close();
    await _debugController.close();
    await _controller.close();
  }
}
