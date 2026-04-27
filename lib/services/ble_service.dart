import 'dart:async';
import 'dart:typed_data';

import 'package:designcode/ble_contract.dart';
import 'package:designcode/services/ble_transport.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleService implements BleTransport {
  BleService({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<DiscoveredDevice> _scanController =
      StreamController<DiscoveredDevice>.broadcast();
  final StreamController<ConnectionStateUpdate> _connectionUpdateController =
      StreamController<ConnectionStateUpdate>.broadcast();
  final StreamController<BleConnectionState> _stateController =
      StreamController<BleConnectionState>.broadcast();

  final Uuid _serviceUuid = Uuid.parse(BleContract.serviceUuid);
  final Uuid _notifyCharacteristicUuid = Uuid.parse(
    BleContract.notifyCharacteristicUuid,
  );
  final Uuid _writeCharacteristicUuid = Uuid.parse(
    BleContract.writeCharacteristicUuid,
  );

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  String? _targetDeviceId;
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  String? _notificationDeviceId;
  Map<Uuid, List<Uuid>>? _lastDiscoveryMap;
  int? _pendingSessionId;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  Stream<DiscoveredDevice> get scanStream => _scanController.stream;

  Stream<ConnectionStateUpdate> get connectionUpdates =>
      _connectionUpdateController.stream;

  @override
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  @override
  BleConnectionState get connectionState => _connectionState;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  String? get targetDeviceId => _targetDeviceId;

  @override
  String get transportName => _connectedDeviceName ?? BleContract.deviceName;

  bool get isConnected => _connectionState == BleConnectionState.connected;

  Stream<DiscoveredDevice> scanForDevices() {
    unawaited(startScan());
    return scanStream;
  }

  @override
  Future<void> startScan() async {
    await _cancelScanSubscription();

    if (_connectionState == BleConnectionState.connecting ||
        _connectionState == BleConnectionState.connected) {
      await disconnect();
    }

    _setState(BleConnectionState.scanning);

    _scanSubscription = _ble
        .scanForDevices(
          withServices: <Uuid>[_serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          _scanController.add,
          onError: (Object error, StackTrace stackTrace) {
            _scanController.addError(error, stackTrace);
            _setState(BleConnectionState.disconnected);
          },
          onDone: () {
            if (_connectionState == BleConnectionState.scanning) {
              _setState(BleConnectionState.disconnected);
            }
          },
          cancelOnError: false,
        );
  }

  @override
  Future<void> stopScan() async {
    await _cancelScanSubscription();
    if (_connectionState == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  Stream<ConnectionStateUpdate> connectToDevice(
    String deviceId, {
    Duration connectionTimeout = const Duration(seconds: 10),
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
  }) {
    unawaited(
      connectToDeviceId(
        deviceId,
        connectionTimeout: connectionTimeout,
        servicesWithCharacteristicsToDiscover:
            servicesWithCharacteristicsToDiscover,
      ),
    );
    return connectionUpdates;
  }

  @override
  Future<void> connect({String? deviceId}) async {
    final resolvedDeviceId =
        deviceId ?? _targetDeviceId ?? await _discoverCompatibleDeviceId();

    await connectToDeviceId(
      resolvedDeviceId,
      servicesWithCharacteristicsToDiscover: _lastDiscoveryMap,
    );
  }

  Future<void> connectToDeviceId(
    String deviceId, {
    Duration connectionTimeout = const Duration(seconds: 10),
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
  }) async {
    _targetDeviceId = deviceId;
    _lastDiscoveryMap =
        servicesWithCharacteristicsToDiscover ??
        <Uuid, List<Uuid>>{
          _serviceUuid: <Uuid>[
            _notifyCharacteristicUuid,
            _writeCharacteristicUuid,
          ],
        };

    await stopScan();
    await _cancelNotificationSubscription();
    await _cancelConnectionSubscription(emitDisconnectedState: false);

    _setState(BleConnectionState.connecting);

    _connectionSubscription = _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: _lastDiscoveryMap,
          connectionTimeout: connectionTimeout,
        )
        .listen(
          _handleConnectionUpdate,
          onError: (Object error, StackTrace stackTrace) {
            _connectionUpdateController.addError(error, stackTrace);
            unawaited(_handleDisconnect(deviceId));
          },
          cancelOnError: false,
        );
  }

  @override
  Future<void> reconnect() async {
    final deviceId = _targetDeviceId ?? _connectedDeviceId;
    if (deviceId == null) {
      throw StateError('No previous BLE device available for reconnect.');
    }

    await connectToDeviceId(
      deviceId,
      servicesWithCharacteristicsToDiscover: _lastDiscoveryMap,
    );
  }

  @override
  Future<void> disconnect() async {
    await _cancelNotificationSubscription();
    await _cancelConnectionSubscription(emitDisconnectedState: true);

    _connectedDeviceId = null;
    _connectedDeviceName = null;
    _notificationDeviceId = null;
    _setState(BleConnectionState.disconnected);
  }

  @override
  Future<void> attachSession(int? wireSessionId) async {
    _pendingSessionId = wireSessionId;
    final deviceId = _connectedDeviceId;
    if (deviceId != null && _connectionState == BleConnectionState.connected) {
      await _pushSessionBinding(deviceId);
    }
  }

  @override
  Future<void> sendLatencyPing(int pingId) async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null || _connectionState != BleConnectionState.connected) {
      return;
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _writeCharacteristicUuid,
      deviceId: deviceId,
    );
    final data = ByteData(5);
    data.setUint8(0, BleContract.commandLatencyPing);
    data.setUint32(1, pingId, Endian.little);
    await _ble.writeCharacteristicWithoutResponse(
      characteristic,
      value: data.buffer.asUint8List(),
    );
  }

  Future<void> subscribeToCharacteristic(String deviceId) async {
    if (_connectionState != BleConnectionState.connected ||
        _connectedDeviceId != deviceId) {
      throw StateError(
        'Cannot subscribe before a BLE connection is established.',
      );
    }

    await _ensureNotificationSubscription(deviceId);
  }

  void _handleConnectionUpdate(ConnectionStateUpdate update) {
    _targetDeviceId = update.deviceId;
    _connectionUpdateController.add(update);

    switch (update.connectionState) {
      case DeviceConnectionState.connecting:
        _setState(BleConnectionState.connecting);
        break;
      case DeviceConnectionState.connected:
        _connectedDeviceId = update.deviceId;
        _setState(BleConnectionState.connected);
        unawaited(_requestPreferredMtu(update.deviceId));
        unawaited(_ensureNotificationSubscription(update.deviceId));
        unawaited(_pushSessionBinding(update.deviceId));
        break;
      case DeviceConnectionState.disconnecting:
        break;
      case DeviceConnectionState.disconnected:
        unawaited(_handleDisconnect(update.deviceId));
        break;
    }
  }

  Future<void> _requestPreferredMtu(String deviceId) async {
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: BleContract.preferredMtu);
    } catch (_) {
      // MTU negotiation is a best-effort optimization and must never gate the connection flow.
    }
  }

  Future<void> _ensureNotificationSubscription(String deviceId) async {
    if (_notificationSubscription != null &&
        _notificationDeviceId == deviceId) {
      return;
    }

    await _cancelNotificationSubscription();

    final characteristic = QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _notifyCharacteristicUuid,
      deviceId: deviceId,
    );

    _notificationDeviceId = deviceId;
    _notificationSubscription = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          (bytes) {
            _dataController.add(Uint8List.fromList(bytes));
          },
          onError: (Object error, StackTrace stackTrace) {
            _dataController.addError(error, stackTrace);
          },
          cancelOnError: false,
        );
  }

  Future<String> _discoverCompatibleDeviceId({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _cancelScanSubscription();
    _setState(BleConnectionState.scanning);

    final completer = Completer<DiscoveredDevice>();
    _scanSubscription = _ble
        .scanForDevices(
          withServices: <Uuid>[_serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            _scanController.add(device);
            if (!completer.isCompleted) {
              completer.complete(device);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _scanController.addError(error, stackTrace);
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          cancelOnError: false,
        );

    try {
      final device = await completer.future.timeout(timeout);
      _targetDeviceId = device.id;
      _connectedDeviceName = device.name.isEmpty ? null : device.name;
      return device.id;
    } on TimeoutException {
      throw StateError(
        'Timed out scanning for a compatible PutterIQ BLE device.',
      );
    } finally {
      await stopScan();
    }
  }

  Future<void> _pushSessionBinding(String deviceId) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _writeCharacteristicUuid,
      deviceId: deviceId,
    );

    final bytes = _pendingSessionId == null
        ? Uint8List.fromList(<int>[BleContract.commandClearSession])
        : (() {
            final data = ByteData(5);
            data.setUint8(0, BleContract.commandAttachSession);
            data.setUint32(1, _pendingSessionId!, Endian.little);
            return data.buffer.asUint8List();
          })();

    await _ble.writeCharacteristicWithoutResponse(characteristic, value: bytes);
  }

  Future<void> _handleDisconnect(String deviceId) async {
    if (_connectedDeviceId == deviceId) {
      _connectedDeviceId = null;
      _connectedDeviceName = null;
    }

    if (_notificationDeviceId == deviceId) {
      await _cancelNotificationSubscription();
    }

    await _cancelConnectionSubscription(emitDisconnectedState: false);
    _setState(BleConnectionState.disconnected);
  }

  Future<void> _cancelScanSubscription() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> _cancelConnectionSubscription({
    required bool emitDisconnectedState,
  }) async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (emitDisconnectedState &&
        _connectionState != BleConnectionState.disconnected) {
      _connectionUpdateController.add(
        ConnectionStateUpdate(
          deviceId: _targetDeviceId ?? _connectedDeviceId ?? '',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
    }
  }

  Future<void> _cancelNotificationSubscription() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _notificationDeviceId = null;
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
    await _cancelScanSubscription();
    await _cancelNotificationSubscription();
    await _cancelConnectionSubscription(emitDisconnectedState: false);
    await _stateController.close();
    await _connectionUpdateController.close();
    await _scanController.close();
    await _dataController.close();
  }
}
