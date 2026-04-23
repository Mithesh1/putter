import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class PracticeSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get wireSessionId => integer().unique()();

  TextColumn get status => text()();

  IntColumn get startedAtMs => integer()();

  IntColumn get endedAtMs => integer().nullable()();

  IntColumn get lastSeenPacketId => integer().withDefault(const Constant(0))();

  IntColumn get strokeCount => integer().withDefault(const Constant(0))();

  TextColumn get deviceId => text().nullable()();

  TextColumn get deviceName => text().nullable()();
}

class StoredStrokes extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get localSessionId => integer()();

  IntColumn get wireSessionId => integer()();

  IntColumn get packetId => integer()();

  TextColumn get dedupeKey => text()();

  BlobColumn get rawPacketBytes => blob()();

  IntColumn get captureStartMs => integer()();

  IntColumn get impactOffsetMs => integer()();

  RealColumn get faceAngleDeg => real()();

  TextColumn get faceAngleLabel => text()();

  TextColumn get impactLabel => text()();

  RealColumn get speedMps => real()();

  TextColumn get speedLabel => text()();

  RealColumn get tempoRatio => real()();

  TextColumn get tempoLabel => text()();

  RealColumn get smoothnessScore => real()();

  TextColumn get rollStatus => text()();

  IntColumn get motionStartMs => integer()();

  IntColumn get transitionMs => integer()();

  IntColumn get impactMs => integer()();

  IntColumn get followThroughEndMs => integer()();

  BoolColumn get weakImpact => boolean()();

  BoolColumn get poorSegmentation => boolean()();

  BoolColumn get quaternionMissing => boolean()();

  TextColumn get cloudSyncState => text()();

  IntColumn get syncAttempts => integer().withDefault(const Constant(0))();

  TextColumn get lastSyncError => text().nullable()();

  IntColumn get receivedAtMs => integer()();

  IntColumn get parsedAtMs => integer()();

  IntColumn get savedAtMs => integer()();

  IntColumn get renderedAtMs => integer().nullable()();

  IntColumn get syncedAtMs => integer().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {wireSessionId, packetId},
  ];
}

@DriftDatabase(tables: [PracticeSessions, StoredStrokes])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'putteriq.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
