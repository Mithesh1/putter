import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/data/mock_stroke_data.dart';
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';
import 'package:designcode/services/app_controller.dart';
import 'package:designcode/services/ball_data_service.dart';
import 'package:designcode/services/mock_ble_service.dart';
import 'package:designcode/services/packet_reassembler.dart';
import 'package:designcode/services/parser.dart';
import 'package:designcode/services/processing.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('packet pipeline', () {
    final codec = const PacketCodec();
    final parser = PacketParser(codec: codec);

    test('single-fragment parse', () {
      final packet = generateMockRawStrokePacket(
        packetId: 1,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.valid,
        maxFragmentPayloadBytes: payload.length,
        codec: codec,
      );

      final reassembler = PacketReassembler();
      final fragment = codec.decodeFragment(notifications.single);
      final reassembled = reassembler.addFragment(fragment);

      expect(reassembled, isNotNull);
      final parsed = parser.parsePayload(
        reassembled!.payload,
        expectedStrokeId: reassembled.strokeId,
      );
      expect(parsed.packetId, packet.packetId);
      expect(parsed.sessionId, packet.sessionId);
      expect(parsed.imuSampleCount, packet.imuSampleCount);
      expect(parsed.piezoSampleCount, packet.piezoSampleCount);
    });

    test('multi-fragment reassembly', () {
      final packet = generateMockRawStrokePacket(
        packetId: 2,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.valid,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      final reassembler = PacketReassembler();
      ReassembledPacket? reassembled;
      for (final notification in notifications) {
        reassembled = reassembler.addFragment(
          codec.decodeFragment(notification),
        );
      }

      expect(reassembled, isNotNull);
      expect(reassembled!.payload, orderedEquals(payload));
    });

    test('duplicate fragment rejection still reassembles successfully', () {
      final packet = generateMockRawStrokePacket(
        packetId: 3,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.duplicateFragment,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      final reassembler = PacketReassembler();
      ReassembledPacket? reassembled;
      for (final notification in notifications) {
        reassembled = reassembler.addFragment(
          codec.decodeFragment(notification),
        );
      }

      final diagnostics = reassembler.takeDiagnostics();
      expect(
        diagnostics.any(
          (diagnostic) => diagnostic.code == 'duplicate_fragment',
        ),
        isTrue,
      );
      expect(reassembled, isNotNull);
      expect(reassembled!.payload, orderedEquals(payload));
    });

    test('out-of-order fragments are handled', () {
      final packet = generateMockRawStrokePacket(
        packetId: 4,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.outOfOrder,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      final reassembler = PacketReassembler();
      ReassembledPacket? reassembled;
      for (final notification in notifications) {
        reassembled = reassembler.addFragment(
          codec.decodeFragment(notification),
        );
      }

      expect(reassembled, isNotNull);
      final parsed = parser.parsePayload(
        reassembled!.payload,
        expectedStrokeId: reassembled.strokeId,
      );
      expect(parsed.packetId, 4);
    });

    test('missing fragments time out and are discarded', () {
      final packet = generateMockRawStrokePacket(
        packetId: 5,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.missingFragment,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      final now = DateTime(2026, 1, 1, 12);
      final reassembler = PacketReassembler(
        timeout: const Duration(milliseconds: 10),
      );

      for (final notification in notifications) {
        reassembler.addFragment(codec.decodeFragment(notification), now: now);
      }

      reassembler.purgeExpired(now: now.add(const Duration(milliseconds: 20)));
      final diagnostics = reassembler.takeDiagnostics();
      expect(
        diagnostics.any((diagnostic) => diagnostic.code == 'fragment_timeout'),
        isTrue,
      );
    });

    test('malformed crc is rejected', () {
      final packet = generateMockRawStrokePacket(
        packetId: 6,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.malformedCrc,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      expect(
        () => codec.decodeFragment(notifications.first),
        throwsA(isA<FormatException>()),
      );
    });

    test('malformed length is rejected', () {
      final packet = generateMockRawStrokePacket(
        packetId: 7,
        sessionId: 42,
        codec: codec,
      );
      final payload = codec.encodeRawStrokePacket(packet);
      final notifications = fragmentPacketPayload(
        packet: packet,
        payload: payload,
        mode: MockFragmentMode.malformedLength,
        maxFragmentPayloadBytes: 64,
        codec: codec,
      );

      expect(
        () => codec.decodeFragment(notifications.first),
        throwsA(isA<FormatException>()),
      );
    });

    test('processing exposes pulse-derived impact offsets for charts', () {
      final packet = generateMockRawStrokePacket(
        packetId: 8,
        sessionId: 42,
        codec: codec,
      );

      final metrics = processStrokePacket(packet, codec: codec);

      expect(metrics.impactImuOffsetMs, greaterThan(0));
      expect(metrics.impactPiezoOffsetMs, greaterThan(0));
      expect(
        metrics.eventMarkers.impactMs,
        equals(packet.captureStartMs + metrics.impactImuOffsetMs),
      );
    });
  });

  group('repository and controller', () {
    late db.AppDatabase database;
    late SessionRepository repository;
    final codec = const PacketCodec();

    setUp(() {
      database = db.AppDatabase(executor: NativeDatabase.memory());
      repository = SessionRepository(database: database, codec: codec);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'session dedupe correctness and local persistence across 100+ strokes',
      () async {
        var session = await repository.startSession(wireSessionId: 9001);

        for (var packetId = 1; packetId <= 120; packetId++) {
          final packet = generateMockRawStrokePacket(
            packetId: packetId,
            sessionId: session.wireSessionId,
            codec: codec,
          );
          final metrics = processStrokePacket(packet, codec: codec);
          final stored = await repository.saveStroke(
            session: session,
            rawPacket: packet,
            rawPacketBytes: codec.encodeRawStrokePacket(packet),
            metrics: metrics,
            receivedAtMs: packet.captureStartMs,
            parsedAtMs: packet.captureStartMs + 1,
          );

          expect(stored, isNotNull);
          session = (await repository.getActiveSession())!;
        }

        final duplicatePacket = generateMockRawStrokePacket(
          packetId: 120,
          sessionId: session.wireSessionId,
          codec: codec,
        );
        final duplicateResult = await repository.saveStroke(
          session: session,
          rawPacket: duplicatePacket,
          rawPacketBytes: codec.encodeRawStrokePacket(duplicatePacket),
          metrics: processStrokePacket(duplicatePacket, codec: codec),
          receivedAtMs: duplicatePacket.captureStartMs,
          parsedAtMs: duplicatePacket.captureStartMs + 1,
        );

        final pending = await repository.loadPendingSyncStrokes();
        expect(duplicateResult, isNull);
        expect(pending.length, 120);
        expect((await repository.getActiveSession())!.lastSeenPacketId, 120);
      },
    );

    test(
      'active session resume after reconnect and controller restart',
      () async {
        final firstMock = MockBleService(
          strokeCadence: const Duration(days: 1),
        );
        final firstController = AppController(
          repository: repository,
          syncService: DisabledSyncService(),
          mockTransport: firstMock,
          ballDataStream: const Stream<BallData>.empty(),
        );

        await firstController.initialize();
        final started = await firstController.startSession();
        await firstController.connect();
        await firstMock.emitNextStroke();
        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(
          (await repository.getActiveSession())!.wireSessionId,
          started.wireSessionId,
        );
        expect((await repository.getActiveSession())!.lastSeenPacketId, 1);

        await firstController.dispose();

        final secondMock = MockBleService(
          strokeCadence: const Duration(days: 1),
        );
        final secondController = AppController(
          repository: repository,
          syncService: DisabledSyncService(),
          mockTransport: secondMock,
          ballDataStream: const Stream<BallData>.empty(),
        );

        await secondController.initialize();
        final resumed = await secondController.startSession();
        await secondController.connect();
        await secondMock.emitNextStroke();
        await Future<void>.delayed(const Duration(milliseconds: 250));

        final active = await repository.getActiveSession();
        expect(resumed.wireSessionId, started.wireSessionId);
        expect(active!.wireSessionId, started.wireSessionId);
        expect(active.lastSeenPacketId, 2);

        await secondController.dispose();
      },
    );

    test('cloud retry queue transitions from failed to synced', () async {
      var session = await repository.startSession(wireSessionId: 4444);
      final packet = generateMockRawStrokePacket(
        packetId: 1,
        sessionId: session.wireSessionId,
        codec: codec,
      );
      final stored = await repository.saveStroke(
        session: session,
        rawPacket: packet,
        rawPacketBytes: codec.encodeRawStrokePacket(packet),
        metrics: processStrokePacket(packet, codec: codec),
        receivedAtMs: packet.captureStartMs,
        parsedAtMs: packet.captureStartMs + 1,
      );
      session = (await repository.getActiveSession())!;

      expect(stored, isNotNull);
      final syncHarness = _FlakySyncHarness();
      await syncHarness.syncPending(repository);

      final failedPending = await repository.loadPendingSyncStrokes();
      expect(failedPending.single.cloudSyncState, CloudSyncState.failed);
      expect(failedPending.single.syncAttempts, 1);

      await syncHarness.syncPending(repository);
      final remainingPending = await repository.loadPendingSyncStrokes();
      expect(remainingPending, isEmpty);
      expect(session.lastSeenPacketId, 1);
    });
  });
}

class _FlakySyncHarness {
  bool _shouldFail = true;

  Future<void> syncPending(SessionRepository repository) async {
    final pending = await repository.loadPendingSyncStrokes();
    for (final stroke in pending) {
      if (stroke.localId == null) {
        continue;
      }

      if (_shouldFail) {
        await repository.markStrokeSyncFailed(
          stroke.localId!,
          attempts: stroke.syncAttempts + 1,
          error: 'offline',
        );
      } else {
        await repository.markStrokeSynced(
          stroke.localId!,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    _shouldFail = false;
  }
}
