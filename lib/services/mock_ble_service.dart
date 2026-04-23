import 'dart:async';
import 'dart:typed_data';

import 'package:designcode/ble_contract.dart';
import 'package:designcode/data/mock_stroke_data.dart';
import 'package:designcode/packet_codec.dart';
import 'package:designcode/services/ble_transport.dart';

class MockBleService implements BleTransport {
  MockBleService({
    PacketCodec? codec,
    List<MockFragmentMode>? scenarioModes,
    Duration? strokeCadence,
  }) : _codec = codec ?? const PacketCodec(),
       _scenarioModes =
           scenarioModes ??
           const <MockFragmentMode>[
             MockFragmentMode.valid,
             MockFragmentMode.outOfOrder,
             MockFragmentMode.duplicateFragment,
             MockFragmentMode.valid,
             MockFragmentMode.valid,
           ],
       _strokeCadence = strokeCadence ?? BleContract.mockStrokeCadence;

  final PacketCodec _codec;
  final List<MockFragmentMode> _scenarioModes;
  final Duration _strokeCadence;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();

  Timer? _strokeTimer;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  String? _targetDeviceId;
  String? _connectedDeviceId;
  int? _wireSessionId;
  int _nextPacketId = 1;
  int _modeIndex = 0;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  @override
  BleConnectionState get connectionState => _connectionState;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  String? get targetDeviceId => _targetDeviceId;

  @override
  String get transportName => 'Mock BLE';

  @override
  Future<void> startScan() async {
    _setState(BleConnectionState.scanning);
  }

  @override
  Future<void> stopScan() async {
    if (_connectionState == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> connect({String? deviceId}) async {
    _targetDeviceId = deviceId ?? BleContract.mockDeviceId;
    _setState(BleConnectionState.connecting);
    await Future<void>.delayed(BleContract.mockConnectDelay);
    _connectedDeviceId = _targetDeviceId;
    _setState(BleConnectionState.connected);
    _ensureEmitter();
  }

  @override
  Future<void> reconnect() async {
    await connect(deviceId: _targetDeviceId ?? BleContract.mockDeviceId);
  }

  @override
  Future<void> disconnect() async {
    _strokeTimer?.cancel();
    _strokeTimer = null;
    _connectedDeviceId = null;
    _setState(BleConnectionState.disconnected);
  }

  @override
  Future<void> attachSession(int? wireSessionId) async {
    if (_wireSessionId != wireSessionId) {
      _wireSessionId = wireSessionId;
      _nextPacketId = 1;
      _modeIndex = 0;
    }

    if (_wireSessionId == null) {
      _strokeTimer?.cancel();
      _strokeTimer = null;
      return;
    }

    _ensureEmitter();
  }

  Future<void> emitNextStroke({
    MockFragmentMode? mode,
    int piezoChannels = BleContract.defaultPiezoChannels,
  }) async {
    final sessionId = _wireSessionId;
    if (sessionId == null || _connectionState != BleConnectionState.connected) {
      return;
    }

    final fixture = generateMockStrokeFixtures(
      sessionId: sessionId,
      startPacketId: _nextPacketId,
      count: 1,
      piezoChannels: piezoChannels,
      modes: <MockFragmentMode>[mode ?? _nextMode()],
      codec: _codec,
    ).single;

    _nextPacketId += 1;

    for (final notification in fixture.notifications) {
      _dataController.add(notification);
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
  }

  void seedPacketCounter(int nextPacketId) {
    _nextPacketId = nextPacketId;
  }

  void _ensureEmitter() {
    if (_connectionState != BleConnectionState.connected ||
        _wireSessionId == null) {
      return;
    }
    _strokeTimer ??= Timer.periodic(_strokeCadence, (_) {
      unawaited(emitNextStroke());
    });
  }

  MockFragmentMode _nextMode() {
    final mode = _scenarioModes[_modeIndex % _scenarioModes.length];
    _modeIndex += 1;
    return mode;
  }

  void _setState(BleConnectionState nextState) {
    if (_connectionState == nextState) {
      return;
    }
    _connectionState = nextState;
    _stateController.add(nextState);
  }

  @override
  Future<void> dispose() async {
    _strokeTimer?.cancel();
    await _stateController.close();
    await _dataController.close();
  }
}
