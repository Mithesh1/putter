import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';
import 'package:designcode/services/ble_transport.dart';
import 'package:designcode/services/mock_ble_service.dart';
import 'package:designcode/services/parser.dart';
import 'package:designcode/services/packet_reassembler.dart';
import 'package:designcode/services/processing.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';

enum TransportMode { mock, real }

class AppController {
  AppController({
    required SessionRepository repository,
    required SyncService syncService,
    required BleTransport mockTransport,
    BleTransport? realTransport,
    PacketCodec? codec,
    PacketParser? parser,
    PacketReassembler? reassembler,
    TransportMode initialTransportMode = TransportMode.mock,
  }) : _repository = repository,
       _syncService = syncService,
       _mockTransport = mockTransport,
       _realTransport = realTransport,
       _codec = codec ?? const PacketCodec(),
       _parser = parser ?? PacketParser(codec: codec ?? const PacketCodec()),
       _reassembler = reassembler ?? PacketReassembler(),
       _transportMode = initialTransportMode;

  final SessionRepository _repository;
  final SyncService _syncService;
  final BleTransport _mockTransport;
  final BleTransport? _realTransport;
  final PacketCodec _codec;
  final PacketParser _parser;
  final PacketReassembler _reassembler;

  final StreamController<BleConnectionState> _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<String> _syncStatusController =
      StreamController<String>.broadcast();
  final StreamController<String> _diagnosticController =
      StreamController<String>.broadcast();

  StreamSubscription<Uint8List>? _transportDataSubscription;
  StreamSubscription<BleConnectionState>? _transportStateSubscription;
  StreamSubscription<PracticeSession?>? _activeSessionSubscription;
  StreamSubscription<String>? _syncStatusSubscription;

  PracticeSession? _activeSession;
  TransportMode _transportMode;
  bool _isInitialized = false;

  BleTransport get _transport => switch (_transportMode) {
    TransportMode.mock => _mockTransport,
    TransportMode.real => _realTransport ?? _mockTransport,
  };

  TransportMode get transportMode => _transportMode;

  String get transportName => _transport.transportName;

  BleConnectionState get connectionState => _transport.connectionState;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    _activeSession = await _repository.getActiveSession();
    await _bindTransport(_transport);
    await _transport.attachSession(_activeSession?.wireSessionId);
    _seedMockTransportPacketCursor(_activeSession);

    _activeSessionSubscription = _repository.watchActiveSession().listen((
      PracticeSession? session,
    ) {
      _activeSession = session;
      unawaited(_transport.attachSession(session?.wireSessionId));
      _seedMockTransportPacketCursor(session);
    });

    _syncStatusController.add(_syncService.status);
    _syncStatusSubscription = _syncService.statusStream.listen(
      _syncStatusController.add,
    );
  }

  Stream<BleConnectionState> watchConnectionState() =>
      _connectionStateController.stream;

  Stream<StoredStroke?> watchLatestStroke() => _repository.watchLatestStroke();

  Stream<PracticeSession?> watchActiveSession() =>
      _repository.watchActiveSession();

  Stream<List<PracticeSession>> watchSessionHistory() =>
      _repository.watchSessionHistory();

  Stream<SessionDetail?> watchSessionDetail(int sessionId) =>
      _repository.watchSessionDetail(sessionId);

  Stream<List<StrokeTrendPoint>> watchTrendSeries(
    String metric,
    Duration range,
  ) => _repository.watchTrendSeries(metric, range);

  Stream<String> watchSyncStatus() => _syncStatusController.stream;

  Stream<String> watchDiagnostics() => _diagnosticController.stream;

  Future<void> setTransportMode(TransportMode mode) async {
    if (_transportMode == mode) {
      return;
    }

    await _transport.disconnect();
    _transportMode = mode;
    await _bindTransport(_transport);
    await _transport.attachSession(_activeSession?.wireSessionId);
    _seedMockTransportPacketCursor(_activeSession);
  }

  Future<void> connect() => _transport.connect();

  Future<void> reconnect() => _transport.reconnect();

  Future<void> disconnect() => _transport.disconnect();

  Future<PracticeSession> startSession() async {
    final existing = await _repository.getActiveSession();
    if (existing != null) {
      _activeSession = existing;
      await _transport.attachSession(existing.wireSessionId);
      _seedMockTransportPacketCursor(existing);
      if (_transport.connectionState == BleConnectionState.disconnected) {
        await _transport.connect();
      }
      return existing;
    }

    final session = await _repository.startSession(
      wireSessionId: _generateWireSessionId(),
      deviceId: _transport.connectedDeviceId ?? _transport.targetDeviceId,
      deviceName: _transport.transportName,
    );
    _activeSession = session;
    await _transport.attachSession(session.wireSessionId);
    _seedMockTransportPacketCursor(session);
    if (_transport.connectionState == BleConnectionState.disconnected) {
      await _transport.connect();
    }
    return session;
  }

  Future<void> endSession() async {
    final session = _activeSession ?? await _repository.getActiveSession();
    if (session == null || session.localId == null) {
      return;
    }

    await _repository.endSession(session.localId!);
    _activeSession = null;
    await _transport.attachSession(null);
  }

  Future<void> _bindTransport(BleTransport transport) async {
    await _transportDataSubscription?.cancel();
    await _transportStateSubscription?.cancel();

    _connectionStateController.add(transport.connectionState);
    _transportStateSubscription = transport.stateStream.listen(
      _connectionStateController.add,
    );
    _transportDataSubscription = transport.dataStream.listen(
      _handleRawNotification,
    );
  }

  Future<void> _handleRawNotification(Uint8List bytes) async {
    final receivedAtMs = DateTime.now().millisecondsSinceEpoch;

    try {
      final fragment = _codec.decodeFragment(bytes);
      final reassembled = _reassembler.addFragment(fragment);

      for (final diagnostic in _reassembler.takeDiagnostics()) {
        _diagnosticController.add(diagnostic.message);
      }

      if (reassembled == null) {
        return;
      }

      final parsedAtMs = DateTime.now().millisecondsSinceEpoch;
      final packet = _parser.parsePayload(
        reassembled.payload,
        expectedStrokeId: reassembled.strokeId,
      );

      final session = _activeSession ?? await _repository.getActiveSession();
      if (session == null) {
        _diagnosticController.add(
          'Received stroke ${packet.packetId} without an active session.',
        );
        return;
      }

      final metrics = processStrokePacket(packet, codec: _codec);
      final storedStroke = await _repository.saveStroke(
        session: session,
        rawPacket: packet,
        rawPacketBytes: reassembled.payload,
        metrics: metrics,
        receivedAtMs: receivedAtMs,
        parsedAtMs: parsedAtMs,
      );

      if (storedStroke?.localId != null) {
        await _repository.markStrokeRendered(
          storedStroke!.localId!,
          DateTime.now().millisecondsSinceEpoch,
        );
        unawaited(_syncService.syncPending(_repository));
      }
    } catch (error) {
      _diagnosticController.add(error.toString());
    }
  }

  int _generateWireSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
    final random = Random(now);
    return (now ^ random.nextInt(0x7FFFFFFF)) & 0xFFFFFFFF;
  }

  void _seedMockTransportPacketCursor(PracticeSession? session) {
    final transport = _transport;
    if (transport is MockBleService && session != null) {
      transport.seedPacketCounter(session.lastSeenPacketId + 1);
    }
  }

  Future<void> dispose() async {
    await _transportDataSubscription?.cancel();
    await _transportStateSubscription?.cancel();
    await _activeSessionSubscription?.cancel();
    await _syncStatusSubscription?.cancel();
    await _mockTransport.dispose();
    await _realTransport?.dispose();
    await _syncService.dispose();
    await _connectionStateController.close();
    await _syncStatusController.close();
    await _diagnosticController.close();
  }
}

AppController createDefaultAppController({
  required SessionRepository repository,
  required SyncService syncService,
  BleTransport? realTransport,
}) {
  return AppController(
    repository: repository,
    syncService: syncService,
    mockTransport: MockBleService(),
    realTransport: realTransport,
    initialTransportMode: realTransport == null
        ? TransportMode.mock
        : TransportMode.real,
  );
}
