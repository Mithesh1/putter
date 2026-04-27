import 'dart:async';
import 'dart:typed_data';

enum BleConnectionState { disconnected, scanning, connecting, connected }

abstract class BleTransport {
  Stream<Uint8List> get dataStream;
  Stream<BleConnectionState> get stateStream;

  BleConnectionState get connectionState;
  String? get connectedDeviceId;
  String? get targetDeviceId;
  String get transportName;

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect({String? deviceId});

  Future<void> reconnect();

  Future<void> disconnect();

  Future<void> attachSession(int? wireSessionId);

  Future<void> sendLatencyPing(int pingId);

  Future<void> dispose();
}
