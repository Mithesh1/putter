import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';
import 'package:designcode/services/processing.dart';
import 'package:drift/drift.dart';

class SessionRepository {
  SessionRepository({required db.AppDatabase database, PacketCodec? codec})
    : _database = database,
      _codec = codec ?? const PacketCodec();

  final db.AppDatabase _database;
  final PacketCodec _codec;

  Future<PracticeSession> startSession({
    required int wireSessionId,
    String? deviceId,
    String? deviceName,
  }) async {
    final existing = await getActiveSession();
    if (existing != null && existing.wireSessionId == wireSessionId) {
      return existing;
    }
    if (existing != null && existing.localId != null) {
      await endSession(existing.localId!);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final localId = await _database
        .into(_database.practiceSessions)
        .insert(
          db.PracticeSessionsCompanion.insert(
            wireSessionId: wireSessionId,
            status: PracticeSessionStatus.active.name,
            startedAtMs: nowMs,
            deviceId: Value(deviceId),
            deviceName: Value(deviceName),
          ),
          mode: InsertMode.insertOrReplace,
        );

    final row = await (_database.select(
      _database.practiceSessions,
    )..where((tbl) => tbl.id.equals(localId))).getSingle();
    return _mapSession(row);
  }

  Future<PracticeSession?> getActiveSession() {
    return (_database.select(_database.practiceSessions)
          ..where((tbl) => tbl.status.equals(PracticeSessionStatus.active.name))
          ..limit(1))
        .getSingleOrNull()
        .then((row) => row == null ? null : _mapSession(row));
  }

  Stream<PracticeSession?> watchActiveSession() {
    return (_database.select(_database.practiceSessions)
          ..where((tbl) => tbl.status.equals(PracticeSessionStatus.active.name))
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _mapSession(row));
  }

  Future<PracticeSession?> getSessionByLocalId(int localSessionId) {
    return (_database.select(_database.practiceSessions)
          ..where((tbl) => tbl.id.equals(localSessionId))
          ..limit(1))
        .getSingleOrNull()
        .then((row) => row == null ? null : _mapSession(row));
  }

  Stream<List<PracticeSession>> watchSessionHistory() {
    return (_database.select(_database.practiceSessions)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAtMs)]))
        .watch()
        .map((rows) => rows.map(_mapSession).toList(growable: false));
  }

  Stream<StoredStroke?> watchLatestStroke() {
    return (_database.select(_database.storedStrokes)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.savedAtMs)])
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _mapStoredStroke(row));
  }

  Stream<SessionDetail?> watchSessionDetail(int localSessionId) {
    return (_database.select(_database.storedStrokes)
          ..where((tbl) => tbl.localSessionId.equals(localSessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.packetId)]))
        .watch()
        .asyncMap((strokeRows) async {
          final sessionRow = await (_database.select(
            _database.practiceSessions,
          )..where((tbl) => tbl.id.equals(localSessionId))).getSingleOrNull();
          if (sessionRow == null) {
            return null;
          }
          return SessionDetail(
            session: _mapSession(sessionRow),
            strokes: strokeRows.map(_mapStoredStroke).toList(growable: false),
          );
        });
  }

  Stream<List<StrokeTrendPoint>> watchTrendSeries(
    String metric,
    Duration range,
  ) {
    final minImpactMs =
        DateTime.now().millisecondsSinceEpoch - range.inMilliseconds;

    return (_database.select(_database.storedStrokes)
          ..where((tbl) => tbl.impactMs.isBiggerOrEqualValue(minImpactMs))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.impactMs)]))
        .watch()
        .map(
          (rows) => rows
              .map((row) {
                final label = '#${row.packetId}';
                final value = switch (metric) {
                  'speed' => row.speedMps,
                  'centerHitRate' => row.impactLabel == 'Center' ? 100.0 : 0.0,
                  _ => row.faceAngleDeg.abs(),
                };
                return StrokeTrendPoint(label: label, value: value);
              })
              .toList(growable: false),
        );
  }

  Future<StoredStroke?> saveStroke({
    required PracticeSession session,
    required RawStrokePacket rawPacket,
    required Uint8List rawPacketBytes,
    required StrokeMetrics metrics,
    required int receivedAtMs,
    required int parsedAtMs,
  }) async {
    if (session.localId == null) {
      throw StateError('Cannot save a stroke without a persisted session id.');
    }
    if (!session.isActive) {
      throw StateError('Cannot save a stroke into an ended session.');
    }
    if (rawPacket.sessionId != session.wireSessionId) {
      throw StateError(
        'Packet session ${rawPacket.sessionId} does not match active session '
        '${session.wireSessionId}.',
      );
    }
    if (rawPacket.packetId <= session.lastSeenPacketId) {
      return null;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dedupeKey = '${session.wireSessionId}:${rawPacket.packetId}';

    await _database.transaction(() async {
      await _database
          .into(_database.storedStrokes)
          .insert(
            db.StoredStrokesCompanion.insert(
              localSessionId: session.localId!,
              wireSessionId: session.wireSessionId,
              packetId: rawPacket.packetId,
              dedupeKey: dedupeKey,
              rawPacketBytes: rawPacketBytes,
              captureStartMs: rawPacket.captureStartMs,
              impactOffsetMs: rawPacket.impactOffsetMs,
              faceAngleDeg: metrics.faceAngleDeg,
              faceAngleLabel: metrics.faceAngleLabel,
              impactLabel: metrics.impact,
              speedMps: metrics.speedMps,
              speedLabel: metrics.speedLabel,
              tempoRatio: metrics.tempoRatio,
              tempoLabel: metrics.tempoLabel,
              smoothnessScore: metrics.smoothnessScore,
              rollStatus: metrics.rollStatus,
              motionStartMs: metrics.eventMarkers.motionStartMs,
              transitionMs: metrics.eventMarkers.transitionMs,
              impactMs: metrics.eventMarkers.impactMs,
              followThroughEndMs: metrics.eventMarkers.followThroughEndMs,
              weakImpact: metrics.qualityFlags.weakImpact,
              poorSegmentation: metrics.qualityFlags.poorSegmentation,
              quaternionMissing: metrics.qualityFlags.quaternionMissing,
              cloudSyncState: CloudSyncState.pending.name,
              lastSyncError: const Value.absent(),
              receivedAtMs: receivedAtMs,
              parsedAtMs: parsedAtMs,
              savedAtMs: nowMs,
              renderedAtMs: const Value.absent(),
              syncedAtMs: const Value.absent(),
            ),
          );

      await (_database.update(
        _database.practiceSessions,
      )..where((tbl) => tbl.id.equals(session.localId!))).write(
        db.PracticeSessionsCompanion(
          lastSeenPacketId: Value(rawPacket.packetId),
          strokeCount: Value(session.strokeCount + 1),
        ),
      );
    });

    final row = await (_database.select(
      _database.storedStrokes,
    )..where((tbl) => tbl.dedupeKey.equals(dedupeKey))).getSingleOrNull();
    return row == null ? null : _mapStoredStroke(row);
  }

  Future<void> endSession(int localSessionId) async {
    final endedAtMs = DateTime.now().millisecondsSinceEpoch;
    await (_database.update(
      _database.practiceSessions,
    )..where((tbl) => tbl.id.equals(localSessionId))).write(
      db.PracticeSessionsCompanion(
        status: Value(PracticeSessionStatus.ended.name),
        endedAtMs: Value(endedAtMs),
      ),
    );
  }

  Future<List<StoredStroke>> loadPendingSyncStrokes() async {
    final rows =
        await (_database.select(_database.storedStrokes)
              ..where(
                (tbl) =>
                    tbl.cloudSyncState.isNotValue(CloudSyncState.synced.name),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.savedAtMs)]))
            .get();
    return rows.map(_mapStoredStroke).toList(growable: false);
  }

  Future<void> markStrokeRendered(int localStrokeId, int renderedAtMs) async {
    await (_database.update(_database.storedStrokes)
          ..where((tbl) => tbl.id.equals(localStrokeId)))
        .write(db.StoredStrokesCompanion(renderedAtMs: Value(renderedAtMs)));
  }

  Future<StoredStroke?> attachBallAnalysisToStroke({
    required int localStrokeId,
    required BallStrokeAnalysis ballAnalysis,
  }) async {
    final strokeRow =
        await (_database.select(_database.storedStrokes)
              ..where((tbl) => tbl.id.equals(localStrokeId))
              ..limit(1))
            .getSingleOrNull();
    if (strokeRow == null) {
      return null;
    }

    await (_database.update(_database.storedStrokes)
          ..where((tbl) => tbl.id.equals(localStrokeId)))
        .write(
          db.StoredStrokesCompanion(
            rollStatus: Value(ballAnalysis.toJsonString()),
          ),
        );

    final updatedRow =
        await (_database.select(_database.storedStrokes)
              ..where((tbl) => tbl.id.equals(localStrokeId))
              ..limit(1))
            .getSingleOrNull();
    return updatedRow == null ? null : _mapStoredStroke(updatedRow);
  }

  Future<void> markStrokeSyncing(int localStrokeId) async {
    await (_database.update(
      _database.storedStrokes,
    )..where((tbl) => tbl.id.equals(localStrokeId))).write(
      const db.StoredStrokesCompanion(cloudSyncState: Value('syncing')),
    );
  }

  Future<void> markStrokeSynced(int localStrokeId, int syncedAtMs) async {
    await (_database.update(
      _database.storedStrokes,
    )..where((tbl) => tbl.id.equals(localStrokeId))).write(
      db.StoredStrokesCompanion(
        cloudSyncState: Value(CloudSyncState.synced.name),
        syncedAtMs: Value(syncedAtMs),
        lastSyncError: const Value(null),
      ),
    );
  }

  Future<void> markStrokeSyncFailed(
    int localStrokeId, {
    required int attempts,
    required String error,
  }) async {
    await (_database.update(
      _database.storedStrokes,
    )..where((tbl) => tbl.id.equals(localStrokeId))).write(
      db.StoredStrokesCompanion(
        cloudSyncState: Value(CloudSyncState.failed.name),
        syncAttempts: Value(attempts),
        lastSyncError: Value(error),
      ),
    );
  }

  PracticeSession _mapSession(db.PracticeSession row) {
    return PracticeSession(
      localId: row.id,
      wireSessionId: row.wireSessionId,
      status: row.status == PracticeSessionStatus.active.name
          ? PracticeSessionStatus.active
          : PracticeSessionStatus.ended,
      startedAtMs: row.startedAtMs,
      endedAtMs: row.endedAtMs,
      lastSeenPacketId: row.lastSeenPacketId,
      strokeCount: row.strokeCount,
      deviceId: row.deviceId,
      deviceName: row.deviceName,
    );
  }

  StoredStroke _mapStoredStroke(db.StoredStroke row) {
    final rawBytes = Uint8List.fromList(row.rawPacketBytes);
    final rawPacket = _codec.decodeRawStrokePacket(rawBytes);
    final metrics = processStrokePacket(rawPacket, codec: _codec);
    final ballAnalysis = BallStrokeAnalysis.tryParse(row.rollStatus);
    return StoredStroke(
      localId: row.id,
      localSessionId: row.localSessionId,
      wireSessionId: row.wireSessionId,
      packetId: row.packetId,
      rawPacketBytes: rawBytes,
      rawPacket: rawPacket,
      metrics: metrics,
      cloudSyncState: switch (row.cloudSyncState) {
        'synced' => CloudSyncState.synced,
        'syncing' => CloudSyncState.syncing,
        'failed' => CloudSyncState.failed,
        _ => CloudSyncState.pending,
      },
      syncAttempts: row.syncAttempts,
      lastSyncError: row.lastSyncError,
      latency: StrokeLatencyTimestamps(
        receivedAtMs: row.receivedAtMs,
        parsedAtMs: row.parsedAtMs,
        savedAtMs: row.savedAtMs,
        renderedAtMs: row.renderedAtMs,
        syncedAtMs: row.syncedAtMs,
      ),
      ballAnalysis: ballAnalysis,
    );
  }
}
