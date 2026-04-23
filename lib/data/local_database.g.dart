// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $PracticeSessionsTable extends PracticeSessions
    with TableInfo<$PracticeSessionsTable, PracticeSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PracticeSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _wireSessionIdMeta = const VerificationMeta(
    'wireSessionId',
  );
  @override
  late final GeneratedColumn<int> wireSessionId = GeneratedColumn<int>(
    'wire_session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMsMeta = const VerificationMeta(
    'startedAtMs',
  );
  @override
  late final GeneratedColumn<int> startedAtMs = GeneratedColumn<int>(
    'started_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMsMeta = const VerificationMeta(
    'endedAtMs',
  );
  @override
  late final GeneratedColumn<int> endedAtMs = GeneratedColumn<int>(
    'ended_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenPacketIdMeta = const VerificationMeta(
    'lastSeenPacketId',
  );
  @override
  late final GeneratedColumn<int> lastSeenPacketId = GeneratedColumn<int>(
    'last_seen_packet_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _strokeCountMeta = const VerificationMeta(
    'strokeCount',
  );
  @override
  late final GeneratedColumn<int> strokeCount = GeneratedColumn<int>(
    'stroke_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    wireSessionId,
    status,
    startedAtMs,
    endedAtMs,
    lastSeenPacketId,
    strokeCount,
    deviceId,
    deviceName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'practice_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PracticeSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('wire_session_id')) {
      context.handle(
        _wireSessionIdMeta,
        wireSessionId.isAcceptableOrUnknown(
          data['wire_session_id']!,
          _wireSessionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wireSessionIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('started_at_ms')) {
      context.handle(
        _startedAtMsMeta,
        startedAtMs.isAcceptableOrUnknown(
          data['started_at_ms']!,
          _startedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtMsMeta);
    }
    if (data.containsKey('ended_at_ms')) {
      context.handle(
        _endedAtMsMeta,
        endedAtMs.isAcceptableOrUnknown(data['ended_at_ms']!, _endedAtMsMeta),
      );
    }
    if (data.containsKey('last_seen_packet_id')) {
      context.handle(
        _lastSeenPacketIdMeta,
        lastSeenPacketId.isAcceptableOrUnknown(
          data['last_seen_packet_id']!,
          _lastSeenPacketIdMeta,
        ),
      );
    }
    if (data.containsKey('stroke_count')) {
      context.handle(
        _strokeCountMeta,
        strokeCount.isAcceptableOrUnknown(
          data['stroke_count']!,
          _strokeCountMeta,
        ),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PracticeSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PracticeSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      wireSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wire_session_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_ms'],
      )!,
      endedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at_ms'],
      ),
      lastSeenPacketId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_packet_id'],
      )!,
      strokeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stroke_count'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      ),
    );
  }

  @override
  $PracticeSessionsTable createAlias(String alias) {
    return $PracticeSessionsTable(attachedDatabase, alias);
  }
}

class PracticeSession extends DataClass implements Insertable<PracticeSession> {
  final int id;
  final int wireSessionId;
  final String status;
  final int startedAtMs;
  final int? endedAtMs;
  final int lastSeenPacketId;
  final int strokeCount;
  final String? deviceId;
  final String? deviceName;
  const PracticeSession({
    required this.id,
    required this.wireSessionId,
    required this.status,
    required this.startedAtMs,
    this.endedAtMs,
    required this.lastSeenPacketId,
    required this.strokeCount,
    this.deviceId,
    this.deviceName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['wire_session_id'] = Variable<int>(wireSessionId);
    map['status'] = Variable<String>(status);
    map['started_at_ms'] = Variable<int>(startedAtMs);
    if (!nullToAbsent || endedAtMs != null) {
      map['ended_at_ms'] = Variable<int>(endedAtMs);
    }
    map['last_seen_packet_id'] = Variable<int>(lastSeenPacketId);
    map['stroke_count'] = Variable<int>(strokeCount);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || deviceName != null) {
      map['device_name'] = Variable<String>(deviceName);
    }
    return map;
  }

  PracticeSessionsCompanion toCompanion(bool nullToAbsent) {
    return PracticeSessionsCompanion(
      id: Value(id),
      wireSessionId: Value(wireSessionId),
      status: Value(status),
      startedAtMs: Value(startedAtMs),
      endedAtMs: endedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtMs),
      lastSeenPacketId: Value(lastSeenPacketId),
      strokeCount: Value(strokeCount),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      deviceName: deviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceName),
    );
  }

  factory PracticeSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PracticeSession(
      id: serializer.fromJson<int>(json['id']),
      wireSessionId: serializer.fromJson<int>(json['wireSessionId']),
      status: serializer.fromJson<String>(json['status']),
      startedAtMs: serializer.fromJson<int>(json['startedAtMs']),
      endedAtMs: serializer.fromJson<int?>(json['endedAtMs']),
      lastSeenPacketId: serializer.fromJson<int>(json['lastSeenPacketId']),
      strokeCount: serializer.fromJson<int>(json['strokeCount']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      deviceName: serializer.fromJson<String?>(json['deviceName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'wireSessionId': serializer.toJson<int>(wireSessionId),
      'status': serializer.toJson<String>(status),
      'startedAtMs': serializer.toJson<int>(startedAtMs),
      'endedAtMs': serializer.toJson<int?>(endedAtMs),
      'lastSeenPacketId': serializer.toJson<int>(lastSeenPacketId),
      'strokeCount': serializer.toJson<int>(strokeCount),
      'deviceId': serializer.toJson<String?>(deviceId),
      'deviceName': serializer.toJson<String?>(deviceName),
    };
  }

  PracticeSession copyWith({
    int? id,
    int? wireSessionId,
    String? status,
    int? startedAtMs,
    Value<int?> endedAtMs = const Value.absent(),
    int? lastSeenPacketId,
    int? strokeCount,
    Value<String?> deviceId = const Value.absent(),
    Value<String?> deviceName = const Value.absent(),
  }) => PracticeSession(
    id: id ?? this.id,
    wireSessionId: wireSessionId ?? this.wireSessionId,
    status: status ?? this.status,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    endedAtMs: endedAtMs.present ? endedAtMs.value : this.endedAtMs,
    lastSeenPacketId: lastSeenPacketId ?? this.lastSeenPacketId,
    strokeCount: strokeCount ?? this.strokeCount,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    deviceName: deviceName.present ? deviceName.value : this.deviceName,
  );
  PracticeSession copyWithCompanion(PracticeSessionsCompanion data) {
    return PracticeSession(
      id: data.id.present ? data.id.value : this.id,
      wireSessionId: data.wireSessionId.present
          ? data.wireSessionId.value
          : this.wireSessionId,
      status: data.status.present ? data.status.value : this.status,
      startedAtMs: data.startedAtMs.present
          ? data.startedAtMs.value
          : this.startedAtMs,
      endedAtMs: data.endedAtMs.present ? data.endedAtMs.value : this.endedAtMs,
      lastSeenPacketId: data.lastSeenPacketId.present
          ? data.lastSeenPacketId.value
          : this.lastSeenPacketId,
      strokeCount: data.strokeCount.present
          ? data.strokeCount.value
          : this.strokeCount,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PracticeSession(')
          ..write('id: $id, ')
          ..write('wireSessionId: $wireSessionId, ')
          ..write('status: $status, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('lastSeenPacketId: $lastSeenPacketId, ')
          ..write('strokeCount: $strokeCount, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    wireSessionId,
    status,
    startedAtMs,
    endedAtMs,
    lastSeenPacketId,
    strokeCount,
    deviceId,
    deviceName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PracticeSession &&
          other.id == this.id &&
          other.wireSessionId == this.wireSessionId &&
          other.status == this.status &&
          other.startedAtMs == this.startedAtMs &&
          other.endedAtMs == this.endedAtMs &&
          other.lastSeenPacketId == this.lastSeenPacketId &&
          other.strokeCount == this.strokeCount &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName);
}

class PracticeSessionsCompanion extends UpdateCompanion<PracticeSession> {
  final Value<int> id;
  final Value<int> wireSessionId;
  final Value<String> status;
  final Value<int> startedAtMs;
  final Value<int?> endedAtMs;
  final Value<int> lastSeenPacketId;
  final Value<int> strokeCount;
  final Value<String?> deviceId;
  final Value<String?> deviceName;
  const PracticeSessionsCompanion({
    this.id = const Value.absent(),
    this.wireSessionId = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAtMs = const Value.absent(),
    this.endedAtMs = const Value.absent(),
    this.lastSeenPacketId = const Value.absent(),
    this.strokeCount = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
  });
  PracticeSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int wireSessionId,
    required String status,
    required int startedAtMs,
    this.endedAtMs = const Value.absent(),
    this.lastSeenPacketId = const Value.absent(),
    this.strokeCount = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
  }) : wireSessionId = Value(wireSessionId),
       status = Value(status),
       startedAtMs = Value(startedAtMs);
  static Insertable<PracticeSession> custom({
    Expression<int>? id,
    Expression<int>? wireSessionId,
    Expression<String>? status,
    Expression<int>? startedAtMs,
    Expression<int>? endedAtMs,
    Expression<int>? lastSeenPacketId,
    Expression<int>? strokeCount,
    Expression<String>? deviceId,
    Expression<String>? deviceName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wireSessionId != null) 'wire_session_id': wireSessionId,
      if (status != null) 'status': status,
      if (startedAtMs != null) 'started_at_ms': startedAtMs,
      if (endedAtMs != null) 'ended_at_ms': endedAtMs,
      if (lastSeenPacketId != null) 'last_seen_packet_id': lastSeenPacketId,
      if (strokeCount != null) 'stroke_count': strokeCount,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
    });
  }

  PracticeSessionsCompanion copyWith({
    Value<int>? id,
    Value<int>? wireSessionId,
    Value<String>? status,
    Value<int>? startedAtMs,
    Value<int?>? endedAtMs,
    Value<int>? lastSeenPacketId,
    Value<int>? strokeCount,
    Value<String?>? deviceId,
    Value<String?>? deviceName,
  }) {
    return PracticeSessionsCompanion(
      id: id ?? this.id,
      wireSessionId: wireSessionId ?? this.wireSessionId,
      status: status ?? this.status,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
      lastSeenPacketId: lastSeenPacketId ?? this.lastSeenPacketId,
      strokeCount: strokeCount ?? this.strokeCount,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (wireSessionId.present) {
      map['wire_session_id'] = Variable<int>(wireSessionId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAtMs.present) {
      map['started_at_ms'] = Variable<int>(startedAtMs.value);
    }
    if (endedAtMs.present) {
      map['ended_at_ms'] = Variable<int>(endedAtMs.value);
    }
    if (lastSeenPacketId.present) {
      map['last_seen_packet_id'] = Variable<int>(lastSeenPacketId.value);
    }
    if (strokeCount.present) {
      map['stroke_count'] = Variable<int>(strokeCount.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PracticeSessionsCompanion(')
          ..write('id: $id, ')
          ..write('wireSessionId: $wireSessionId, ')
          ..write('status: $status, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('lastSeenPacketId: $lastSeenPacketId, ')
          ..write('strokeCount: $strokeCount, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName')
          ..write(')'))
        .toString();
  }
}

class $StoredStrokesTable extends StoredStrokes
    with TableInfo<$StoredStrokesTable, StoredStroke> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredStrokesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localSessionIdMeta = const VerificationMeta(
    'localSessionId',
  );
  @override
  late final GeneratedColumn<int> localSessionId = GeneratedColumn<int>(
    'local_session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wireSessionIdMeta = const VerificationMeta(
    'wireSessionId',
  );
  @override
  late final GeneratedColumn<int> wireSessionId = GeneratedColumn<int>(
    'wire_session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packetIdMeta = const VerificationMeta(
    'packetId',
  );
  @override
  late final GeneratedColumn<int> packetId = GeneratedColumn<int>(
    'packet_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dedupeKeyMeta = const VerificationMeta(
    'dedupeKey',
  );
  @override
  late final GeneratedColumn<String> dedupeKey = GeneratedColumn<String>(
    'dedupe_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawPacketBytesMeta = const VerificationMeta(
    'rawPacketBytes',
  );
  @override
  late final GeneratedColumn<Uint8List> rawPacketBytes =
      GeneratedColumn<Uint8List>(
        'raw_packet_bytes',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _captureStartMsMeta = const VerificationMeta(
    'captureStartMs',
  );
  @override
  late final GeneratedColumn<int> captureStartMs = GeneratedColumn<int>(
    'capture_start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _impactOffsetMsMeta = const VerificationMeta(
    'impactOffsetMs',
  );
  @override
  late final GeneratedColumn<int> impactOffsetMs = GeneratedColumn<int>(
    'impact_offset_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _faceAngleDegMeta = const VerificationMeta(
    'faceAngleDeg',
  );
  @override
  late final GeneratedColumn<double> faceAngleDeg = GeneratedColumn<double>(
    'face_angle_deg',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _faceAngleLabelMeta = const VerificationMeta(
    'faceAngleLabel',
  );
  @override
  late final GeneratedColumn<String> faceAngleLabel = GeneratedColumn<String>(
    'face_angle_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _impactLabelMeta = const VerificationMeta(
    'impactLabel',
  );
  @override
  late final GeneratedColumn<String> impactLabel = GeneratedColumn<String>(
    'impact_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedLabelMeta = const VerificationMeta(
    'speedLabel',
  );
  @override
  late final GeneratedColumn<String> speedLabel = GeneratedColumn<String>(
    'speed_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tempoRatioMeta = const VerificationMeta(
    'tempoRatio',
  );
  @override
  late final GeneratedColumn<double> tempoRatio = GeneratedColumn<double>(
    'tempo_ratio',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tempoLabelMeta = const VerificationMeta(
    'tempoLabel',
  );
  @override
  late final GeneratedColumn<String> tempoLabel = GeneratedColumn<String>(
    'tempo_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _smoothnessScoreMeta = const VerificationMeta(
    'smoothnessScore',
  );
  @override
  late final GeneratedColumn<double> smoothnessScore = GeneratedColumn<double>(
    'smoothness_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rollStatusMeta = const VerificationMeta(
    'rollStatus',
  );
  @override
  late final GeneratedColumn<String> rollStatus = GeneratedColumn<String>(
    'roll_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _motionStartMsMeta = const VerificationMeta(
    'motionStartMs',
  );
  @override
  late final GeneratedColumn<int> motionStartMs = GeneratedColumn<int>(
    'motion_start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transitionMsMeta = const VerificationMeta(
    'transitionMs',
  );
  @override
  late final GeneratedColumn<int> transitionMs = GeneratedColumn<int>(
    'transition_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _impactMsMeta = const VerificationMeta(
    'impactMs',
  );
  @override
  late final GeneratedColumn<int> impactMs = GeneratedColumn<int>(
    'impact_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _followThroughEndMsMeta =
      const VerificationMeta('followThroughEndMs');
  @override
  late final GeneratedColumn<int> followThroughEndMs = GeneratedColumn<int>(
    'follow_through_end_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weakImpactMeta = const VerificationMeta(
    'weakImpact',
  );
  @override
  late final GeneratedColumn<bool> weakImpact = GeneratedColumn<bool>(
    'weak_impact',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("weak_impact" IN (0, 1))',
    ),
  );
  static const VerificationMeta _poorSegmentationMeta = const VerificationMeta(
    'poorSegmentation',
  );
  @override
  late final GeneratedColumn<bool> poorSegmentation = GeneratedColumn<bool>(
    'poor_segmentation',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("poor_segmentation" IN (0, 1))',
    ),
  );
  static const VerificationMeta _quaternionMissingMeta = const VerificationMeta(
    'quaternionMissing',
  );
  @override
  late final GeneratedColumn<bool> quaternionMissing = GeneratedColumn<bool>(
    'quaternion_missing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("quaternion_missing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cloudSyncStateMeta = const VerificationMeta(
    'cloudSyncState',
  );
  @override
  late final GeneratedColumn<String> cloudSyncState = GeneratedColumn<String>(
    'cloud_sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncAttemptsMeta = const VerificationMeta(
    'syncAttempts',
  );
  @override
  late final GeneratedColumn<int> syncAttempts = GeneratedColumn<int>(
    'sync_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSyncErrorMeta = const VerificationMeta(
    'lastSyncError',
  );
  @override
  late final GeneratedColumn<String> lastSyncError = GeneratedColumn<String>(
    'last_sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedAtMsMeta = const VerificationMeta(
    'receivedAtMs',
  );
  @override
  late final GeneratedColumn<int> receivedAtMs = GeneratedColumn<int>(
    'received_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parsedAtMsMeta = const VerificationMeta(
    'parsedAtMs',
  );
  @override
  late final GeneratedColumn<int> parsedAtMs = GeneratedColumn<int>(
    'parsed_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMsMeta = const VerificationMeta(
    'savedAtMs',
  );
  @override
  late final GeneratedColumn<int> savedAtMs = GeneratedColumn<int>(
    'saved_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _renderedAtMsMeta = const VerificationMeta(
    'renderedAtMs',
  );
  @override
  late final GeneratedColumn<int> renderedAtMs = GeneratedColumn<int>(
    'rendered_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localSessionId,
    wireSessionId,
    packetId,
    dedupeKey,
    rawPacketBytes,
    captureStartMs,
    impactOffsetMs,
    faceAngleDeg,
    faceAngleLabel,
    impactLabel,
    speedMps,
    speedLabel,
    tempoRatio,
    tempoLabel,
    smoothnessScore,
    rollStatus,
    motionStartMs,
    transitionMs,
    impactMs,
    followThroughEndMs,
    weakImpact,
    poorSegmentation,
    quaternionMissing,
    cloudSyncState,
    syncAttempts,
    lastSyncError,
    receivedAtMs,
    parsedAtMs,
    savedAtMs,
    renderedAtMs,
    syncedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_strokes';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredStroke> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_session_id')) {
      context.handle(
        _localSessionIdMeta,
        localSessionId.isAcceptableOrUnknown(
          data['local_session_id']!,
          _localSessionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localSessionIdMeta);
    }
    if (data.containsKey('wire_session_id')) {
      context.handle(
        _wireSessionIdMeta,
        wireSessionId.isAcceptableOrUnknown(
          data['wire_session_id']!,
          _wireSessionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wireSessionIdMeta);
    }
    if (data.containsKey('packet_id')) {
      context.handle(
        _packetIdMeta,
        packetId.isAcceptableOrUnknown(data['packet_id']!, _packetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_packetIdMeta);
    }
    if (data.containsKey('dedupe_key')) {
      context.handle(
        _dedupeKeyMeta,
        dedupeKey.isAcceptableOrUnknown(data['dedupe_key']!, _dedupeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dedupeKeyMeta);
    }
    if (data.containsKey('raw_packet_bytes')) {
      context.handle(
        _rawPacketBytesMeta,
        rawPacketBytes.isAcceptableOrUnknown(
          data['raw_packet_bytes']!,
          _rawPacketBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rawPacketBytesMeta);
    }
    if (data.containsKey('capture_start_ms')) {
      context.handle(
        _captureStartMsMeta,
        captureStartMs.isAcceptableOrUnknown(
          data['capture_start_ms']!,
          _captureStartMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_captureStartMsMeta);
    }
    if (data.containsKey('impact_offset_ms')) {
      context.handle(
        _impactOffsetMsMeta,
        impactOffsetMs.isAcceptableOrUnknown(
          data['impact_offset_ms']!,
          _impactOffsetMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_impactOffsetMsMeta);
    }
    if (data.containsKey('face_angle_deg')) {
      context.handle(
        _faceAngleDegMeta,
        faceAngleDeg.isAcceptableOrUnknown(
          data['face_angle_deg']!,
          _faceAngleDegMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_faceAngleDegMeta);
    }
    if (data.containsKey('face_angle_label')) {
      context.handle(
        _faceAngleLabelMeta,
        faceAngleLabel.isAcceptableOrUnknown(
          data['face_angle_label']!,
          _faceAngleLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_faceAngleLabelMeta);
    }
    if (data.containsKey('impact_label')) {
      context.handle(
        _impactLabelMeta,
        impactLabel.isAcceptableOrUnknown(
          data['impact_label']!,
          _impactLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_impactLabelMeta);
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    } else if (isInserting) {
      context.missing(_speedMpsMeta);
    }
    if (data.containsKey('speed_label')) {
      context.handle(
        _speedLabelMeta,
        speedLabel.isAcceptableOrUnknown(data['speed_label']!, _speedLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_speedLabelMeta);
    }
    if (data.containsKey('tempo_ratio')) {
      context.handle(
        _tempoRatioMeta,
        tempoRatio.isAcceptableOrUnknown(data['tempo_ratio']!, _tempoRatioMeta),
      );
    } else if (isInserting) {
      context.missing(_tempoRatioMeta);
    }
    if (data.containsKey('tempo_label')) {
      context.handle(
        _tempoLabelMeta,
        tempoLabel.isAcceptableOrUnknown(data['tempo_label']!, _tempoLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_tempoLabelMeta);
    }
    if (data.containsKey('smoothness_score')) {
      context.handle(
        _smoothnessScoreMeta,
        smoothnessScore.isAcceptableOrUnknown(
          data['smoothness_score']!,
          _smoothnessScoreMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_smoothnessScoreMeta);
    }
    if (data.containsKey('roll_status')) {
      context.handle(
        _rollStatusMeta,
        rollStatus.isAcceptableOrUnknown(data['roll_status']!, _rollStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_rollStatusMeta);
    }
    if (data.containsKey('motion_start_ms')) {
      context.handle(
        _motionStartMsMeta,
        motionStartMs.isAcceptableOrUnknown(
          data['motion_start_ms']!,
          _motionStartMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_motionStartMsMeta);
    }
    if (data.containsKey('transition_ms')) {
      context.handle(
        _transitionMsMeta,
        transitionMs.isAcceptableOrUnknown(
          data['transition_ms']!,
          _transitionMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transitionMsMeta);
    }
    if (data.containsKey('impact_ms')) {
      context.handle(
        _impactMsMeta,
        impactMs.isAcceptableOrUnknown(data['impact_ms']!, _impactMsMeta),
      );
    } else if (isInserting) {
      context.missing(_impactMsMeta);
    }
    if (data.containsKey('follow_through_end_ms')) {
      context.handle(
        _followThroughEndMsMeta,
        followThroughEndMs.isAcceptableOrUnknown(
          data['follow_through_end_ms']!,
          _followThroughEndMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_followThroughEndMsMeta);
    }
    if (data.containsKey('weak_impact')) {
      context.handle(
        _weakImpactMeta,
        weakImpact.isAcceptableOrUnknown(data['weak_impact']!, _weakImpactMeta),
      );
    } else if (isInserting) {
      context.missing(_weakImpactMeta);
    }
    if (data.containsKey('poor_segmentation')) {
      context.handle(
        _poorSegmentationMeta,
        poorSegmentation.isAcceptableOrUnknown(
          data['poor_segmentation']!,
          _poorSegmentationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_poorSegmentationMeta);
    }
    if (data.containsKey('quaternion_missing')) {
      context.handle(
        _quaternionMissingMeta,
        quaternionMissing.isAcceptableOrUnknown(
          data['quaternion_missing']!,
          _quaternionMissingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quaternionMissingMeta);
    }
    if (data.containsKey('cloud_sync_state')) {
      context.handle(
        _cloudSyncStateMeta,
        cloudSyncState.isAcceptableOrUnknown(
          data['cloud_sync_state']!,
          _cloudSyncStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudSyncStateMeta);
    }
    if (data.containsKey('sync_attempts')) {
      context.handle(
        _syncAttemptsMeta,
        syncAttempts.isAcceptableOrUnknown(
          data['sync_attempts']!,
          _syncAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_error')) {
      context.handle(
        _lastSyncErrorMeta,
        lastSyncError.isAcceptableOrUnknown(
          data['last_sync_error']!,
          _lastSyncErrorMeta,
        ),
      );
    }
    if (data.containsKey('received_at_ms')) {
      context.handle(
        _receivedAtMsMeta,
        receivedAtMs.isAcceptableOrUnknown(
          data['received_at_ms']!,
          _receivedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMsMeta);
    }
    if (data.containsKey('parsed_at_ms')) {
      context.handle(
        _parsedAtMsMeta,
        parsedAtMs.isAcceptableOrUnknown(
          data['parsed_at_ms']!,
          _parsedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parsedAtMsMeta);
    }
    if (data.containsKey('saved_at_ms')) {
      context.handle(
        _savedAtMsMeta,
        savedAtMs.isAcceptableOrUnknown(data['saved_at_ms']!, _savedAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMsMeta);
    }
    if (data.containsKey('rendered_at_ms')) {
      context.handle(
        _renderedAtMsMeta,
        renderedAtMs.isAcceptableOrUnknown(
          data['rendered_at_ms']!,
          _renderedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {wireSessionId, packetId},
  ];
  @override
  StoredStroke map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredStroke(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_session_id'],
      )!,
      wireSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wire_session_id'],
      )!,
      packetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}packet_id'],
      )!,
      dedupeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedupe_key'],
      )!,
      rawPacketBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}raw_packet_bytes'],
      )!,
      captureStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capture_start_ms'],
      )!,
      impactOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}impact_offset_ms'],
      )!,
      faceAngleDeg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}face_angle_deg'],
      )!,
      faceAngleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}face_angle_label'],
      )!,
      impactLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}impact_label'],
      )!,
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      )!,
      speedLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speed_label'],
      )!,
      tempoRatio: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tempo_ratio'],
      )!,
      tempoLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tempo_label'],
      )!,
      smoothnessScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}smoothness_score'],
      )!,
      rollStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roll_status'],
      )!,
      motionStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}motion_start_ms'],
      )!,
      transitionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transition_ms'],
      )!,
      impactMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}impact_ms'],
      )!,
      followThroughEndMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}follow_through_end_ms'],
      )!,
      weakImpact: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}weak_impact'],
      )!,
      poorSegmentation: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}poor_segmentation'],
      )!,
      quaternionMissing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}quaternion_missing'],
      )!,
      cloudSyncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_sync_state'],
      )!,
      syncAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_attempts'],
      )!,
      lastSyncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_sync_error'],
      ),
      receivedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at_ms'],
      )!,
      parsedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parsed_at_ms'],
      )!,
      savedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}saved_at_ms'],
      )!,
      renderedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rendered_at_ms'],
      ),
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
    );
  }

  @override
  $StoredStrokesTable createAlias(String alias) {
    return $StoredStrokesTable(attachedDatabase, alias);
  }
}

class StoredStroke extends DataClass implements Insertable<StoredStroke> {
  final int id;
  final int localSessionId;
  final int wireSessionId;
  final int packetId;
  final String dedupeKey;
  final Uint8List rawPacketBytes;
  final int captureStartMs;
  final int impactOffsetMs;
  final double faceAngleDeg;
  final String faceAngleLabel;
  final String impactLabel;
  final double speedMps;
  final String speedLabel;
  final double tempoRatio;
  final String tempoLabel;
  final double smoothnessScore;
  final String rollStatus;
  final int motionStartMs;
  final int transitionMs;
  final int impactMs;
  final int followThroughEndMs;
  final bool weakImpact;
  final bool poorSegmentation;
  final bool quaternionMissing;
  final String cloudSyncState;
  final int syncAttempts;
  final String? lastSyncError;
  final int receivedAtMs;
  final int parsedAtMs;
  final int savedAtMs;
  final int? renderedAtMs;
  final int? syncedAtMs;
  const StoredStroke({
    required this.id,
    required this.localSessionId,
    required this.wireSessionId,
    required this.packetId,
    required this.dedupeKey,
    required this.rawPacketBytes,
    required this.captureStartMs,
    required this.impactOffsetMs,
    required this.faceAngleDeg,
    required this.faceAngleLabel,
    required this.impactLabel,
    required this.speedMps,
    required this.speedLabel,
    required this.tempoRatio,
    required this.tempoLabel,
    required this.smoothnessScore,
    required this.rollStatus,
    required this.motionStartMs,
    required this.transitionMs,
    required this.impactMs,
    required this.followThroughEndMs,
    required this.weakImpact,
    required this.poorSegmentation,
    required this.quaternionMissing,
    required this.cloudSyncState,
    required this.syncAttempts,
    this.lastSyncError,
    required this.receivedAtMs,
    required this.parsedAtMs,
    required this.savedAtMs,
    this.renderedAtMs,
    this.syncedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_session_id'] = Variable<int>(localSessionId);
    map['wire_session_id'] = Variable<int>(wireSessionId);
    map['packet_id'] = Variable<int>(packetId);
    map['dedupe_key'] = Variable<String>(dedupeKey);
    map['raw_packet_bytes'] = Variable<Uint8List>(rawPacketBytes);
    map['capture_start_ms'] = Variable<int>(captureStartMs);
    map['impact_offset_ms'] = Variable<int>(impactOffsetMs);
    map['face_angle_deg'] = Variable<double>(faceAngleDeg);
    map['face_angle_label'] = Variable<String>(faceAngleLabel);
    map['impact_label'] = Variable<String>(impactLabel);
    map['speed_mps'] = Variable<double>(speedMps);
    map['speed_label'] = Variable<String>(speedLabel);
    map['tempo_ratio'] = Variable<double>(tempoRatio);
    map['tempo_label'] = Variable<String>(tempoLabel);
    map['smoothness_score'] = Variable<double>(smoothnessScore);
    map['roll_status'] = Variable<String>(rollStatus);
    map['motion_start_ms'] = Variable<int>(motionStartMs);
    map['transition_ms'] = Variable<int>(transitionMs);
    map['impact_ms'] = Variable<int>(impactMs);
    map['follow_through_end_ms'] = Variable<int>(followThroughEndMs);
    map['weak_impact'] = Variable<bool>(weakImpact);
    map['poor_segmentation'] = Variable<bool>(poorSegmentation);
    map['quaternion_missing'] = Variable<bool>(quaternionMissing);
    map['cloud_sync_state'] = Variable<String>(cloudSyncState);
    map['sync_attempts'] = Variable<int>(syncAttempts);
    if (!nullToAbsent || lastSyncError != null) {
      map['last_sync_error'] = Variable<String>(lastSyncError);
    }
    map['received_at_ms'] = Variable<int>(receivedAtMs);
    map['parsed_at_ms'] = Variable<int>(parsedAtMs);
    map['saved_at_ms'] = Variable<int>(savedAtMs);
    if (!nullToAbsent || renderedAtMs != null) {
      map['rendered_at_ms'] = Variable<int>(renderedAtMs);
    }
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    return map;
  }

  StoredStrokesCompanion toCompanion(bool nullToAbsent) {
    return StoredStrokesCompanion(
      id: Value(id),
      localSessionId: Value(localSessionId),
      wireSessionId: Value(wireSessionId),
      packetId: Value(packetId),
      dedupeKey: Value(dedupeKey),
      rawPacketBytes: Value(rawPacketBytes),
      captureStartMs: Value(captureStartMs),
      impactOffsetMs: Value(impactOffsetMs),
      faceAngleDeg: Value(faceAngleDeg),
      faceAngleLabel: Value(faceAngleLabel),
      impactLabel: Value(impactLabel),
      speedMps: Value(speedMps),
      speedLabel: Value(speedLabel),
      tempoRatio: Value(tempoRatio),
      tempoLabel: Value(tempoLabel),
      smoothnessScore: Value(smoothnessScore),
      rollStatus: Value(rollStatus),
      motionStartMs: Value(motionStartMs),
      transitionMs: Value(transitionMs),
      impactMs: Value(impactMs),
      followThroughEndMs: Value(followThroughEndMs),
      weakImpact: Value(weakImpact),
      poorSegmentation: Value(poorSegmentation),
      quaternionMissing: Value(quaternionMissing),
      cloudSyncState: Value(cloudSyncState),
      syncAttempts: Value(syncAttempts),
      lastSyncError: lastSyncError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncError),
      receivedAtMs: Value(receivedAtMs),
      parsedAtMs: Value(parsedAtMs),
      savedAtMs: Value(savedAtMs),
      renderedAtMs: renderedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(renderedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
    );
  }

  factory StoredStroke.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredStroke(
      id: serializer.fromJson<int>(json['id']),
      localSessionId: serializer.fromJson<int>(json['localSessionId']),
      wireSessionId: serializer.fromJson<int>(json['wireSessionId']),
      packetId: serializer.fromJson<int>(json['packetId']),
      dedupeKey: serializer.fromJson<String>(json['dedupeKey']),
      rawPacketBytes: serializer.fromJson<Uint8List>(json['rawPacketBytes']),
      captureStartMs: serializer.fromJson<int>(json['captureStartMs']),
      impactOffsetMs: serializer.fromJson<int>(json['impactOffsetMs']),
      faceAngleDeg: serializer.fromJson<double>(json['faceAngleDeg']),
      faceAngleLabel: serializer.fromJson<String>(json['faceAngleLabel']),
      impactLabel: serializer.fromJson<String>(json['impactLabel']),
      speedMps: serializer.fromJson<double>(json['speedMps']),
      speedLabel: serializer.fromJson<String>(json['speedLabel']),
      tempoRatio: serializer.fromJson<double>(json['tempoRatio']),
      tempoLabel: serializer.fromJson<String>(json['tempoLabel']),
      smoothnessScore: serializer.fromJson<double>(json['smoothnessScore']),
      rollStatus: serializer.fromJson<String>(json['rollStatus']),
      motionStartMs: serializer.fromJson<int>(json['motionStartMs']),
      transitionMs: serializer.fromJson<int>(json['transitionMs']),
      impactMs: serializer.fromJson<int>(json['impactMs']),
      followThroughEndMs: serializer.fromJson<int>(json['followThroughEndMs']),
      weakImpact: serializer.fromJson<bool>(json['weakImpact']),
      poorSegmentation: serializer.fromJson<bool>(json['poorSegmentation']),
      quaternionMissing: serializer.fromJson<bool>(json['quaternionMissing']),
      cloudSyncState: serializer.fromJson<String>(json['cloudSyncState']),
      syncAttempts: serializer.fromJson<int>(json['syncAttempts']),
      lastSyncError: serializer.fromJson<String?>(json['lastSyncError']),
      receivedAtMs: serializer.fromJson<int>(json['receivedAtMs']),
      parsedAtMs: serializer.fromJson<int>(json['parsedAtMs']),
      savedAtMs: serializer.fromJson<int>(json['savedAtMs']),
      renderedAtMs: serializer.fromJson<int?>(json['renderedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localSessionId': serializer.toJson<int>(localSessionId),
      'wireSessionId': serializer.toJson<int>(wireSessionId),
      'packetId': serializer.toJson<int>(packetId),
      'dedupeKey': serializer.toJson<String>(dedupeKey),
      'rawPacketBytes': serializer.toJson<Uint8List>(rawPacketBytes),
      'captureStartMs': serializer.toJson<int>(captureStartMs),
      'impactOffsetMs': serializer.toJson<int>(impactOffsetMs),
      'faceAngleDeg': serializer.toJson<double>(faceAngleDeg),
      'faceAngleLabel': serializer.toJson<String>(faceAngleLabel),
      'impactLabel': serializer.toJson<String>(impactLabel),
      'speedMps': serializer.toJson<double>(speedMps),
      'speedLabel': serializer.toJson<String>(speedLabel),
      'tempoRatio': serializer.toJson<double>(tempoRatio),
      'tempoLabel': serializer.toJson<String>(tempoLabel),
      'smoothnessScore': serializer.toJson<double>(smoothnessScore),
      'rollStatus': serializer.toJson<String>(rollStatus),
      'motionStartMs': serializer.toJson<int>(motionStartMs),
      'transitionMs': serializer.toJson<int>(transitionMs),
      'impactMs': serializer.toJson<int>(impactMs),
      'followThroughEndMs': serializer.toJson<int>(followThroughEndMs),
      'weakImpact': serializer.toJson<bool>(weakImpact),
      'poorSegmentation': serializer.toJson<bool>(poorSegmentation),
      'quaternionMissing': serializer.toJson<bool>(quaternionMissing),
      'cloudSyncState': serializer.toJson<String>(cloudSyncState),
      'syncAttempts': serializer.toJson<int>(syncAttempts),
      'lastSyncError': serializer.toJson<String?>(lastSyncError),
      'receivedAtMs': serializer.toJson<int>(receivedAtMs),
      'parsedAtMs': serializer.toJson<int>(parsedAtMs),
      'savedAtMs': serializer.toJson<int>(savedAtMs),
      'renderedAtMs': serializer.toJson<int?>(renderedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
    };
  }

  StoredStroke copyWith({
    int? id,
    int? localSessionId,
    int? wireSessionId,
    int? packetId,
    String? dedupeKey,
    Uint8List? rawPacketBytes,
    int? captureStartMs,
    int? impactOffsetMs,
    double? faceAngleDeg,
    String? faceAngleLabel,
    String? impactLabel,
    double? speedMps,
    String? speedLabel,
    double? tempoRatio,
    String? tempoLabel,
    double? smoothnessScore,
    String? rollStatus,
    int? motionStartMs,
    int? transitionMs,
    int? impactMs,
    int? followThroughEndMs,
    bool? weakImpact,
    bool? poorSegmentation,
    bool? quaternionMissing,
    String? cloudSyncState,
    int? syncAttempts,
    Value<String?> lastSyncError = const Value.absent(),
    int? receivedAtMs,
    int? parsedAtMs,
    int? savedAtMs,
    Value<int?> renderedAtMs = const Value.absent(),
    Value<int?> syncedAtMs = const Value.absent(),
  }) => StoredStroke(
    id: id ?? this.id,
    localSessionId: localSessionId ?? this.localSessionId,
    wireSessionId: wireSessionId ?? this.wireSessionId,
    packetId: packetId ?? this.packetId,
    dedupeKey: dedupeKey ?? this.dedupeKey,
    rawPacketBytes: rawPacketBytes ?? this.rawPacketBytes,
    captureStartMs: captureStartMs ?? this.captureStartMs,
    impactOffsetMs: impactOffsetMs ?? this.impactOffsetMs,
    faceAngleDeg: faceAngleDeg ?? this.faceAngleDeg,
    faceAngleLabel: faceAngleLabel ?? this.faceAngleLabel,
    impactLabel: impactLabel ?? this.impactLabel,
    speedMps: speedMps ?? this.speedMps,
    speedLabel: speedLabel ?? this.speedLabel,
    tempoRatio: tempoRatio ?? this.tempoRatio,
    tempoLabel: tempoLabel ?? this.tempoLabel,
    smoothnessScore: smoothnessScore ?? this.smoothnessScore,
    rollStatus: rollStatus ?? this.rollStatus,
    motionStartMs: motionStartMs ?? this.motionStartMs,
    transitionMs: transitionMs ?? this.transitionMs,
    impactMs: impactMs ?? this.impactMs,
    followThroughEndMs: followThroughEndMs ?? this.followThroughEndMs,
    weakImpact: weakImpact ?? this.weakImpact,
    poorSegmentation: poorSegmentation ?? this.poorSegmentation,
    quaternionMissing: quaternionMissing ?? this.quaternionMissing,
    cloudSyncState: cloudSyncState ?? this.cloudSyncState,
    syncAttempts: syncAttempts ?? this.syncAttempts,
    lastSyncError: lastSyncError.present
        ? lastSyncError.value
        : this.lastSyncError,
    receivedAtMs: receivedAtMs ?? this.receivedAtMs,
    parsedAtMs: parsedAtMs ?? this.parsedAtMs,
    savedAtMs: savedAtMs ?? this.savedAtMs,
    renderedAtMs: renderedAtMs.present ? renderedAtMs.value : this.renderedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
  );
  StoredStroke copyWithCompanion(StoredStrokesCompanion data) {
    return StoredStroke(
      id: data.id.present ? data.id.value : this.id,
      localSessionId: data.localSessionId.present
          ? data.localSessionId.value
          : this.localSessionId,
      wireSessionId: data.wireSessionId.present
          ? data.wireSessionId.value
          : this.wireSessionId,
      packetId: data.packetId.present ? data.packetId.value : this.packetId,
      dedupeKey: data.dedupeKey.present ? data.dedupeKey.value : this.dedupeKey,
      rawPacketBytes: data.rawPacketBytes.present
          ? data.rawPacketBytes.value
          : this.rawPacketBytes,
      captureStartMs: data.captureStartMs.present
          ? data.captureStartMs.value
          : this.captureStartMs,
      impactOffsetMs: data.impactOffsetMs.present
          ? data.impactOffsetMs.value
          : this.impactOffsetMs,
      faceAngleDeg: data.faceAngleDeg.present
          ? data.faceAngleDeg.value
          : this.faceAngleDeg,
      faceAngleLabel: data.faceAngleLabel.present
          ? data.faceAngleLabel.value
          : this.faceAngleLabel,
      impactLabel: data.impactLabel.present
          ? data.impactLabel.value
          : this.impactLabel,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      speedLabel: data.speedLabel.present
          ? data.speedLabel.value
          : this.speedLabel,
      tempoRatio: data.tempoRatio.present
          ? data.tempoRatio.value
          : this.tempoRatio,
      tempoLabel: data.tempoLabel.present
          ? data.tempoLabel.value
          : this.tempoLabel,
      smoothnessScore: data.smoothnessScore.present
          ? data.smoothnessScore.value
          : this.smoothnessScore,
      rollStatus: data.rollStatus.present
          ? data.rollStatus.value
          : this.rollStatus,
      motionStartMs: data.motionStartMs.present
          ? data.motionStartMs.value
          : this.motionStartMs,
      transitionMs: data.transitionMs.present
          ? data.transitionMs.value
          : this.transitionMs,
      impactMs: data.impactMs.present ? data.impactMs.value : this.impactMs,
      followThroughEndMs: data.followThroughEndMs.present
          ? data.followThroughEndMs.value
          : this.followThroughEndMs,
      weakImpact: data.weakImpact.present
          ? data.weakImpact.value
          : this.weakImpact,
      poorSegmentation: data.poorSegmentation.present
          ? data.poorSegmentation.value
          : this.poorSegmentation,
      quaternionMissing: data.quaternionMissing.present
          ? data.quaternionMissing.value
          : this.quaternionMissing,
      cloudSyncState: data.cloudSyncState.present
          ? data.cloudSyncState.value
          : this.cloudSyncState,
      syncAttempts: data.syncAttempts.present
          ? data.syncAttempts.value
          : this.syncAttempts,
      lastSyncError: data.lastSyncError.present
          ? data.lastSyncError.value
          : this.lastSyncError,
      receivedAtMs: data.receivedAtMs.present
          ? data.receivedAtMs.value
          : this.receivedAtMs,
      parsedAtMs: data.parsedAtMs.present
          ? data.parsedAtMs.value
          : this.parsedAtMs,
      savedAtMs: data.savedAtMs.present ? data.savedAtMs.value : this.savedAtMs,
      renderedAtMs: data.renderedAtMs.present
          ? data.renderedAtMs.value
          : this.renderedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredStroke(')
          ..write('id: $id, ')
          ..write('localSessionId: $localSessionId, ')
          ..write('wireSessionId: $wireSessionId, ')
          ..write('packetId: $packetId, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('rawPacketBytes: $rawPacketBytes, ')
          ..write('captureStartMs: $captureStartMs, ')
          ..write('impactOffsetMs: $impactOffsetMs, ')
          ..write('faceAngleDeg: $faceAngleDeg, ')
          ..write('faceAngleLabel: $faceAngleLabel, ')
          ..write('impactLabel: $impactLabel, ')
          ..write('speedMps: $speedMps, ')
          ..write('speedLabel: $speedLabel, ')
          ..write('tempoRatio: $tempoRatio, ')
          ..write('tempoLabel: $tempoLabel, ')
          ..write('smoothnessScore: $smoothnessScore, ')
          ..write('rollStatus: $rollStatus, ')
          ..write('motionStartMs: $motionStartMs, ')
          ..write('transitionMs: $transitionMs, ')
          ..write('impactMs: $impactMs, ')
          ..write('followThroughEndMs: $followThroughEndMs, ')
          ..write('weakImpact: $weakImpact, ')
          ..write('poorSegmentation: $poorSegmentation, ')
          ..write('quaternionMissing: $quaternionMissing, ')
          ..write('cloudSyncState: $cloudSyncState, ')
          ..write('syncAttempts: $syncAttempts, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('parsedAtMs: $parsedAtMs, ')
          ..write('savedAtMs: $savedAtMs, ')
          ..write('renderedAtMs: $renderedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    localSessionId,
    wireSessionId,
    packetId,
    dedupeKey,
    $driftBlobEquality.hash(rawPacketBytes),
    captureStartMs,
    impactOffsetMs,
    faceAngleDeg,
    faceAngleLabel,
    impactLabel,
    speedMps,
    speedLabel,
    tempoRatio,
    tempoLabel,
    smoothnessScore,
    rollStatus,
    motionStartMs,
    transitionMs,
    impactMs,
    followThroughEndMs,
    weakImpact,
    poorSegmentation,
    quaternionMissing,
    cloudSyncState,
    syncAttempts,
    lastSyncError,
    receivedAtMs,
    parsedAtMs,
    savedAtMs,
    renderedAtMs,
    syncedAtMs,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredStroke &&
          other.id == this.id &&
          other.localSessionId == this.localSessionId &&
          other.wireSessionId == this.wireSessionId &&
          other.packetId == this.packetId &&
          other.dedupeKey == this.dedupeKey &&
          $driftBlobEquality.equals(
            other.rawPacketBytes,
            this.rawPacketBytes,
          ) &&
          other.captureStartMs == this.captureStartMs &&
          other.impactOffsetMs == this.impactOffsetMs &&
          other.faceAngleDeg == this.faceAngleDeg &&
          other.faceAngleLabel == this.faceAngleLabel &&
          other.impactLabel == this.impactLabel &&
          other.speedMps == this.speedMps &&
          other.speedLabel == this.speedLabel &&
          other.tempoRatio == this.tempoRatio &&
          other.tempoLabel == this.tempoLabel &&
          other.smoothnessScore == this.smoothnessScore &&
          other.rollStatus == this.rollStatus &&
          other.motionStartMs == this.motionStartMs &&
          other.transitionMs == this.transitionMs &&
          other.impactMs == this.impactMs &&
          other.followThroughEndMs == this.followThroughEndMs &&
          other.weakImpact == this.weakImpact &&
          other.poorSegmentation == this.poorSegmentation &&
          other.quaternionMissing == this.quaternionMissing &&
          other.cloudSyncState == this.cloudSyncState &&
          other.syncAttempts == this.syncAttempts &&
          other.lastSyncError == this.lastSyncError &&
          other.receivedAtMs == this.receivedAtMs &&
          other.parsedAtMs == this.parsedAtMs &&
          other.savedAtMs == this.savedAtMs &&
          other.renderedAtMs == this.renderedAtMs &&
          other.syncedAtMs == this.syncedAtMs);
}

class StoredStrokesCompanion extends UpdateCompanion<StoredStroke> {
  final Value<int> id;
  final Value<int> localSessionId;
  final Value<int> wireSessionId;
  final Value<int> packetId;
  final Value<String> dedupeKey;
  final Value<Uint8List> rawPacketBytes;
  final Value<int> captureStartMs;
  final Value<int> impactOffsetMs;
  final Value<double> faceAngleDeg;
  final Value<String> faceAngleLabel;
  final Value<String> impactLabel;
  final Value<double> speedMps;
  final Value<String> speedLabel;
  final Value<double> tempoRatio;
  final Value<String> tempoLabel;
  final Value<double> smoothnessScore;
  final Value<String> rollStatus;
  final Value<int> motionStartMs;
  final Value<int> transitionMs;
  final Value<int> impactMs;
  final Value<int> followThroughEndMs;
  final Value<bool> weakImpact;
  final Value<bool> poorSegmentation;
  final Value<bool> quaternionMissing;
  final Value<String> cloudSyncState;
  final Value<int> syncAttempts;
  final Value<String?> lastSyncError;
  final Value<int> receivedAtMs;
  final Value<int> parsedAtMs;
  final Value<int> savedAtMs;
  final Value<int?> renderedAtMs;
  final Value<int?> syncedAtMs;
  const StoredStrokesCompanion({
    this.id = const Value.absent(),
    this.localSessionId = const Value.absent(),
    this.wireSessionId = const Value.absent(),
    this.packetId = const Value.absent(),
    this.dedupeKey = const Value.absent(),
    this.rawPacketBytes = const Value.absent(),
    this.captureStartMs = const Value.absent(),
    this.impactOffsetMs = const Value.absent(),
    this.faceAngleDeg = const Value.absent(),
    this.faceAngleLabel = const Value.absent(),
    this.impactLabel = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.speedLabel = const Value.absent(),
    this.tempoRatio = const Value.absent(),
    this.tempoLabel = const Value.absent(),
    this.smoothnessScore = const Value.absent(),
    this.rollStatus = const Value.absent(),
    this.motionStartMs = const Value.absent(),
    this.transitionMs = const Value.absent(),
    this.impactMs = const Value.absent(),
    this.followThroughEndMs = const Value.absent(),
    this.weakImpact = const Value.absent(),
    this.poorSegmentation = const Value.absent(),
    this.quaternionMissing = const Value.absent(),
    this.cloudSyncState = const Value.absent(),
    this.syncAttempts = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.receivedAtMs = const Value.absent(),
    this.parsedAtMs = const Value.absent(),
    this.savedAtMs = const Value.absent(),
    this.renderedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
  });
  StoredStrokesCompanion.insert({
    this.id = const Value.absent(),
    required int localSessionId,
    required int wireSessionId,
    required int packetId,
    required String dedupeKey,
    required Uint8List rawPacketBytes,
    required int captureStartMs,
    required int impactOffsetMs,
    required double faceAngleDeg,
    required String faceAngleLabel,
    required String impactLabel,
    required double speedMps,
    required String speedLabel,
    required double tempoRatio,
    required String tempoLabel,
    required double smoothnessScore,
    required String rollStatus,
    required int motionStartMs,
    required int transitionMs,
    required int impactMs,
    required int followThroughEndMs,
    required bool weakImpact,
    required bool poorSegmentation,
    required bool quaternionMissing,
    required String cloudSyncState,
    this.syncAttempts = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    required int receivedAtMs,
    required int parsedAtMs,
    required int savedAtMs,
    this.renderedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
  }) : localSessionId = Value(localSessionId),
       wireSessionId = Value(wireSessionId),
       packetId = Value(packetId),
       dedupeKey = Value(dedupeKey),
       rawPacketBytes = Value(rawPacketBytes),
       captureStartMs = Value(captureStartMs),
       impactOffsetMs = Value(impactOffsetMs),
       faceAngleDeg = Value(faceAngleDeg),
       faceAngleLabel = Value(faceAngleLabel),
       impactLabel = Value(impactLabel),
       speedMps = Value(speedMps),
       speedLabel = Value(speedLabel),
       tempoRatio = Value(tempoRatio),
       tempoLabel = Value(tempoLabel),
       smoothnessScore = Value(smoothnessScore),
       rollStatus = Value(rollStatus),
       motionStartMs = Value(motionStartMs),
       transitionMs = Value(transitionMs),
       impactMs = Value(impactMs),
       followThroughEndMs = Value(followThroughEndMs),
       weakImpact = Value(weakImpact),
       poorSegmentation = Value(poorSegmentation),
       quaternionMissing = Value(quaternionMissing),
       cloudSyncState = Value(cloudSyncState),
       receivedAtMs = Value(receivedAtMs),
       parsedAtMs = Value(parsedAtMs),
       savedAtMs = Value(savedAtMs);
  static Insertable<StoredStroke> custom({
    Expression<int>? id,
    Expression<int>? localSessionId,
    Expression<int>? wireSessionId,
    Expression<int>? packetId,
    Expression<String>? dedupeKey,
    Expression<Uint8List>? rawPacketBytes,
    Expression<int>? captureStartMs,
    Expression<int>? impactOffsetMs,
    Expression<double>? faceAngleDeg,
    Expression<String>? faceAngleLabel,
    Expression<String>? impactLabel,
    Expression<double>? speedMps,
    Expression<String>? speedLabel,
    Expression<double>? tempoRatio,
    Expression<String>? tempoLabel,
    Expression<double>? smoothnessScore,
    Expression<String>? rollStatus,
    Expression<int>? motionStartMs,
    Expression<int>? transitionMs,
    Expression<int>? impactMs,
    Expression<int>? followThroughEndMs,
    Expression<bool>? weakImpact,
    Expression<bool>? poorSegmentation,
    Expression<bool>? quaternionMissing,
    Expression<String>? cloudSyncState,
    Expression<int>? syncAttempts,
    Expression<String>? lastSyncError,
    Expression<int>? receivedAtMs,
    Expression<int>? parsedAtMs,
    Expression<int>? savedAtMs,
    Expression<int>? renderedAtMs,
    Expression<int>? syncedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localSessionId != null) 'local_session_id': localSessionId,
      if (wireSessionId != null) 'wire_session_id': wireSessionId,
      if (packetId != null) 'packet_id': packetId,
      if (dedupeKey != null) 'dedupe_key': dedupeKey,
      if (rawPacketBytes != null) 'raw_packet_bytes': rawPacketBytes,
      if (captureStartMs != null) 'capture_start_ms': captureStartMs,
      if (impactOffsetMs != null) 'impact_offset_ms': impactOffsetMs,
      if (faceAngleDeg != null) 'face_angle_deg': faceAngleDeg,
      if (faceAngleLabel != null) 'face_angle_label': faceAngleLabel,
      if (impactLabel != null) 'impact_label': impactLabel,
      if (speedMps != null) 'speed_mps': speedMps,
      if (speedLabel != null) 'speed_label': speedLabel,
      if (tempoRatio != null) 'tempo_ratio': tempoRatio,
      if (tempoLabel != null) 'tempo_label': tempoLabel,
      if (smoothnessScore != null) 'smoothness_score': smoothnessScore,
      if (rollStatus != null) 'roll_status': rollStatus,
      if (motionStartMs != null) 'motion_start_ms': motionStartMs,
      if (transitionMs != null) 'transition_ms': transitionMs,
      if (impactMs != null) 'impact_ms': impactMs,
      if (followThroughEndMs != null)
        'follow_through_end_ms': followThroughEndMs,
      if (weakImpact != null) 'weak_impact': weakImpact,
      if (poorSegmentation != null) 'poor_segmentation': poorSegmentation,
      if (quaternionMissing != null) 'quaternion_missing': quaternionMissing,
      if (cloudSyncState != null) 'cloud_sync_state': cloudSyncState,
      if (syncAttempts != null) 'sync_attempts': syncAttempts,
      if (lastSyncError != null) 'last_sync_error': lastSyncError,
      if (receivedAtMs != null) 'received_at_ms': receivedAtMs,
      if (parsedAtMs != null) 'parsed_at_ms': parsedAtMs,
      if (savedAtMs != null) 'saved_at_ms': savedAtMs,
      if (renderedAtMs != null) 'rendered_at_ms': renderedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
    });
  }

  StoredStrokesCompanion copyWith({
    Value<int>? id,
    Value<int>? localSessionId,
    Value<int>? wireSessionId,
    Value<int>? packetId,
    Value<String>? dedupeKey,
    Value<Uint8List>? rawPacketBytes,
    Value<int>? captureStartMs,
    Value<int>? impactOffsetMs,
    Value<double>? faceAngleDeg,
    Value<String>? faceAngleLabel,
    Value<String>? impactLabel,
    Value<double>? speedMps,
    Value<String>? speedLabel,
    Value<double>? tempoRatio,
    Value<String>? tempoLabel,
    Value<double>? smoothnessScore,
    Value<String>? rollStatus,
    Value<int>? motionStartMs,
    Value<int>? transitionMs,
    Value<int>? impactMs,
    Value<int>? followThroughEndMs,
    Value<bool>? weakImpact,
    Value<bool>? poorSegmentation,
    Value<bool>? quaternionMissing,
    Value<String>? cloudSyncState,
    Value<int>? syncAttempts,
    Value<String?>? lastSyncError,
    Value<int>? receivedAtMs,
    Value<int>? parsedAtMs,
    Value<int>? savedAtMs,
    Value<int?>? renderedAtMs,
    Value<int?>? syncedAtMs,
  }) {
    return StoredStrokesCompanion(
      id: id ?? this.id,
      localSessionId: localSessionId ?? this.localSessionId,
      wireSessionId: wireSessionId ?? this.wireSessionId,
      packetId: packetId ?? this.packetId,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      rawPacketBytes: rawPacketBytes ?? this.rawPacketBytes,
      captureStartMs: captureStartMs ?? this.captureStartMs,
      impactOffsetMs: impactOffsetMs ?? this.impactOffsetMs,
      faceAngleDeg: faceAngleDeg ?? this.faceAngleDeg,
      faceAngleLabel: faceAngleLabel ?? this.faceAngleLabel,
      impactLabel: impactLabel ?? this.impactLabel,
      speedMps: speedMps ?? this.speedMps,
      speedLabel: speedLabel ?? this.speedLabel,
      tempoRatio: tempoRatio ?? this.tempoRatio,
      tempoLabel: tempoLabel ?? this.tempoLabel,
      smoothnessScore: smoothnessScore ?? this.smoothnessScore,
      rollStatus: rollStatus ?? this.rollStatus,
      motionStartMs: motionStartMs ?? this.motionStartMs,
      transitionMs: transitionMs ?? this.transitionMs,
      impactMs: impactMs ?? this.impactMs,
      followThroughEndMs: followThroughEndMs ?? this.followThroughEndMs,
      weakImpact: weakImpact ?? this.weakImpact,
      poorSegmentation: poorSegmentation ?? this.poorSegmentation,
      quaternionMissing: quaternionMissing ?? this.quaternionMissing,
      cloudSyncState: cloudSyncState ?? this.cloudSyncState,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
      parsedAtMs: parsedAtMs ?? this.parsedAtMs,
      savedAtMs: savedAtMs ?? this.savedAtMs,
      renderedAtMs: renderedAtMs ?? this.renderedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localSessionId.present) {
      map['local_session_id'] = Variable<int>(localSessionId.value);
    }
    if (wireSessionId.present) {
      map['wire_session_id'] = Variable<int>(wireSessionId.value);
    }
    if (packetId.present) {
      map['packet_id'] = Variable<int>(packetId.value);
    }
    if (dedupeKey.present) {
      map['dedupe_key'] = Variable<String>(dedupeKey.value);
    }
    if (rawPacketBytes.present) {
      map['raw_packet_bytes'] = Variable<Uint8List>(rawPacketBytes.value);
    }
    if (captureStartMs.present) {
      map['capture_start_ms'] = Variable<int>(captureStartMs.value);
    }
    if (impactOffsetMs.present) {
      map['impact_offset_ms'] = Variable<int>(impactOffsetMs.value);
    }
    if (faceAngleDeg.present) {
      map['face_angle_deg'] = Variable<double>(faceAngleDeg.value);
    }
    if (faceAngleLabel.present) {
      map['face_angle_label'] = Variable<String>(faceAngleLabel.value);
    }
    if (impactLabel.present) {
      map['impact_label'] = Variable<String>(impactLabel.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (speedLabel.present) {
      map['speed_label'] = Variable<String>(speedLabel.value);
    }
    if (tempoRatio.present) {
      map['tempo_ratio'] = Variable<double>(tempoRatio.value);
    }
    if (tempoLabel.present) {
      map['tempo_label'] = Variable<String>(tempoLabel.value);
    }
    if (smoothnessScore.present) {
      map['smoothness_score'] = Variable<double>(smoothnessScore.value);
    }
    if (rollStatus.present) {
      map['roll_status'] = Variable<String>(rollStatus.value);
    }
    if (motionStartMs.present) {
      map['motion_start_ms'] = Variable<int>(motionStartMs.value);
    }
    if (transitionMs.present) {
      map['transition_ms'] = Variable<int>(transitionMs.value);
    }
    if (impactMs.present) {
      map['impact_ms'] = Variable<int>(impactMs.value);
    }
    if (followThroughEndMs.present) {
      map['follow_through_end_ms'] = Variable<int>(followThroughEndMs.value);
    }
    if (weakImpact.present) {
      map['weak_impact'] = Variable<bool>(weakImpact.value);
    }
    if (poorSegmentation.present) {
      map['poor_segmentation'] = Variable<bool>(poorSegmentation.value);
    }
    if (quaternionMissing.present) {
      map['quaternion_missing'] = Variable<bool>(quaternionMissing.value);
    }
    if (cloudSyncState.present) {
      map['cloud_sync_state'] = Variable<String>(cloudSyncState.value);
    }
    if (syncAttempts.present) {
      map['sync_attempts'] = Variable<int>(syncAttempts.value);
    }
    if (lastSyncError.present) {
      map['last_sync_error'] = Variable<String>(lastSyncError.value);
    }
    if (receivedAtMs.present) {
      map['received_at_ms'] = Variable<int>(receivedAtMs.value);
    }
    if (parsedAtMs.present) {
      map['parsed_at_ms'] = Variable<int>(parsedAtMs.value);
    }
    if (savedAtMs.present) {
      map['saved_at_ms'] = Variable<int>(savedAtMs.value);
    }
    if (renderedAtMs.present) {
      map['rendered_at_ms'] = Variable<int>(renderedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredStrokesCompanion(')
          ..write('id: $id, ')
          ..write('localSessionId: $localSessionId, ')
          ..write('wireSessionId: $wireSessionId, ')
          ..write('packetId: $packetId, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('rawPacketBytes: $rawPacketBytes, ')
          ..write('captureStartMs: $captureStartMs, ')
          ..write('impactOffsetMs: $impactOffsetMs, ')
          ..write('faceAngleDeg: $faceAngleDeg, ')
          ..write('faceAngleLabel: $faceAngleLabel, ')
          ..write('impactLabel: $impactLabel, ')
          ..write('speedMps: $speedMps, ')
          ..write('speedLabel: $speedLabel, ')
          ..write('tempoRatio: $tempoRatio, ')
          ..write('tempoLabel: $tempoLabel, ')
          ..write('smoothnessScore: $smoothnessScore, ')
          ..write('rollStatus: $rollStatus, ')
          ..write('motionStartMs: $motionStartMs, ')
          ..write('transitionMs: $transitionMs, ')
          ..write('impactMs: $impactMs, ')
          ..write('followThroughEndMs: $followThroughEndMs, ')
          ..write('weakImpact: $weakImpact, ')
          ..write('poorSegmentation: $poorSegmentation, ')
          ..write('quaternionMissing: $quaternionMissing, ')
          ..write('cloudSyncState: $cloudSyncState, ')
          ..write('syncAttempts: $syncAttempts, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('receivedAtMs: $receivedAtMs, ')
          ..write('parsedAtMs: $parsedAtMs, ')
          ..write('savedAtMs: $savedAtMs, ')
          ..write('renderedAtMs: $renderedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PracticeSessionsTable practiceSessions = $PracticeSessionsTable(
    this,
  );
  late final $StoredStrokesTable storedStrokes = $StoredStrokesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    practiceSessions,
    storedStrokes,
  ];
}

typedef $$PracticeSessionsTableCreateCompanionBuilder =
    PracticeSessionsCompanion Function({
      Value<int> id,
      required int wireSessionId,
      required String status,
      required int startedAtMs,
      Value<int?> endedAtMs,
      Value<int> lastSeenPacketId,
      Value<int> strokeCount,
      Value<String?> deviceId,
      Value<String?> deviceName,
    });
typedef $$PracticeSessionsTableUpdateCompanionBuilder =
    PracticeSessionsCompanion Function({
      Value<int> id,
      Value<int> wireSessionId,
      Value<String> status,
      Value<int> startedAtMs,
      Value<int?> endedAtMs,
      Value<int> lastSeenPacketId,
      Value<int> strokeCount,
      Value<String?> deviceId,
      Value<String?> deviceName,
    });

class $$PracticeSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $PracticeSessionsTable> {
  $$PracticeSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenPacketId => $composableBuilder(
    column: $table.lastSeenPacketId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get strokeCount => $composableBuilder(
    column: $table.strokeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PracticeSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PracticeSessionsTable> {
  $$PracticeSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenPacketId => $composableBuilder(
    column: $table.lastSeenPacketId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get strokeCount => $composableBuilder(
    column: $table.strokeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PracticeSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PracticeSessionsTable> {
  $$PracticeSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedAtMs =>
      $composableBuilder(column: $table.endedAtMs, builder: (column) => column);

  GeneratedColumn<int> get lastSeenPacketId => $composableBuilder(
    column: $table.lastSeenPacketId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get strokeCount => $composableBuilder(
    column: $table.strokeCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );
}

class $$PracticeSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PracticeSessionsTable,
          PracticeSession,
          $$PracticeSessionsTableFilterComposer,
          $$PracticeSessionsTableOrderingComposer,
          $$PracticeSessionsTableAnnotationComposer,
          $$PracticeSessionsTableCreateCompanionBuilder,
          $$PracticeSessionsTableUpdateCompanionBuilder,
          (
            PracticeSession,
            BaseReferences<
              _$AppDatabase,
              $PracticeSessionsTable,
              PracticeSession
            >,
          ),
          PracticeSession,
          PrefetchHooks Function()
        > {
  $$PracticeSessionsTableTableManager(
    _$AppDatabase db,
    $PracticeSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PracticeSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PracticeSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PracticeSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> wireSessionId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> startedAtMs = const Value.absent(),
                Value<int?> endedAtMs = const Value.absent(),
                Value<int> lastSeenPacketId = const Value.absent(),
                Value<int> strokeCount = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
              }) => PracticeSessionsCompanion(
                id: id,
                wireSessionId: wireSessionId,
                status: status,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                lastSeenPacketId: lastSeenPacketId,
                strokeCount: strokeCount,
                deviceId: deviceId,
                deviceName: deviceName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int wireSessionId,
                required String status,
                required int startedAtMs,
                Value<int?> endedAtMs = const Value.absent(),
                Value<int> lastSeenPacketId = const Value.absent(),
                Value<int> strokeCount = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
              }) => PracticeSessionsCompanion.insert(
                id: id,
                wireSessionId: wireSessionId,
                status: status,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                lastSeenPacketId: lastSeenPacketId,
                strokeCount: strokeCount,
                deviceId: deviceId,
                deviceName: deviceName,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PracticeSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PracticeSessionsTable,
      PracticeSession,
      $$PracticeSessionsTableFilterComposer,
      $$PracticeSessionsTableOrderingComposer,
      $$PracticeSessionsTableAnnotationComposer,
      $$PracticeSessionsTableCreateCompanionBuilder,
      $$PracticeSessionsTableUpdateCompanionBuilder,
      (
        PracticeSession,
        BaseReferences<_$AppDatabase, $PracticeSessionsTable, PracticeSession>,
      ),
      PracticeSession,
      PrefetchHooks Function()
    >;
typedef $$StoredStrokesTableCreateCompanionBuilder =
    StoredStrokesCompanion Function({
      Value<int> id,
      required int localSessionId,
      required int wireSessionId,
      required int packetId,
      required String dedupeKey,
      required Uint8List rawPacketBytes,
      required int captureStartMs,
      required int impactOffsetMs,
      required double faceAngleDeg,
      required String faceAngleLabel,
      required String impactLabel,
      required double speedMps,
      required String speedLabel,
      required double tempoRatio,
      required String tempoLabel,
      required double smoothnessScore,
      required String rollStatus,
      required int motionStartMs,
      required int transitionMs,
      required int impactMs,
      required int followThroughEndMs,
      required bool weakImpact,
      required bool poorSegmentation,
      required bool quaternionMissing,
      required String cloudSyncState,
      Value<int> syncAttempts,
      Value<String?> lastSyncError,
      required int receivedAtMs,
      required int parsedAtMs,
      required int savedAtMs,
      Value<int?> renderedAtMs,
      Value<int?> syncedAtMs,
    });
typedef $$StoredStrokesTableUpdateCompanionBuilder =
    StoredStrokesCompanion Function({
      Value<int> id,
      Value<int> localSessionId,
      Value<int> wireSessionId,
      Value<int> packetId,
      Value<String> dedupeKey,
      Value<Uint8List> rawPacketBytes,
      Value<int> captureStartMs,
      Value<int> impactOffsetMs,
      Value<double> faceAngleDeg,
      Value<String> faceAngleLabel,
      Value<String> impactLabel,
      Value<double> speedMps,
      Value<String> speedLabel,
      Value<double> tempoRatio,
      Value<String> tempoLabel,
      Value<double> smoothnessScore,
      Value<String> rollStatus,
      Value<int> motionStartMs,
      Value<int> transitionMs,
      Value<int> impactMs,
      Value<int> followThroughEndMs,
      Value<bool> weakImpact,
      Value<bool> poorSegmentation,
      Value<bool> quaternionMissing,
      Value<String> cloudSyncState,
      Value<int> syncAttempts,
      Value<String?> lastSyncError,
      Value<int> receivedAtMs,
      Value<int> parsedAtMs,
      Value<int> savedAtMs,
      Value<int?> renderedAtMs,
      Value<int?> syncedAtMs,
    });

class $$StoredStrokesTableFilterComposer
    extends Composer<_$AppDatabase, $StoredStrokesTable> {
  $$StoredStrokesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSessionId => $composableBuilder(
    column: $table.localSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get rawPacketBytes => $composableBuilder(
    column: $table.rawPacketBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get captureStartMs => $composableBuilder(
    column: $table.captureStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get impactOffsetMs => $composableBuilder(
    column: $table.impactOffsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get faceAngleDeg => $composableBuilder(
    column: $table.faceAngleDeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get faceAngleLabel => $composableBuilder(
    column: $table.faceAngleLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get impactLabel => $composableBuilder(
    column: $table.impactLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get speedLabel => $composableBuilder(
    column: $table.speedLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tempoRatio => $composableBuilder(
    column: $table.tempoRatio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tempoLabel => $composableBuilder(
    column: $table.tempoLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get smoothnessScore => $composableBuilder(
    column: $table.smoothnessScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rollStatus => $composableBuilder(
    column: $table.rollStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get motionStartMs => $composableBuilder(
    column: $table.motionStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transitionMs => $composableBuilder(
    column: $table.transitionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get impactMs => $composableBuilder(
    column: $table.impactMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get followThroughEndMs => $composableBuilder(
    column: $table.followThroughEndMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get weakImpact => $composableBuilder(
    column: $table.weakImpact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get poorSegmentation => $composableBuilder(
    column: $table.poorSegmentation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get quaternionMissing => $composableBuilder(
    column: $table.quaternionMissing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudSyncState => $composableBuilder(
    column: $table.cloudSyncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parsedAtMs => $composableBuilder(
    column: $table.parsedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get savedAtMs => $composableBuilder(
    column: $table.savedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get renderedAtMs => $composableBuilder(
    column: $table.renderedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredStrokesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredStrokesTable> {
  $$StoredStrokesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSessionId => $composableBuilder(
    column: $table.localSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get packetId => $composableBuilder(
    column: $table.packetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get rawPacketBytes => $composableBuilder(
    column: $table.rawPacketBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get captureStartMs => $composableBuilder(
    column: $table.captureStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get impactOffsetMs => $composableBuilder(
    column: $table.impactOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get faceAngleDeg => $composableBuilder(
    column: $table.faceAngleDeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get faceAngleLabel => $composableBuilder(
    column: $table.faceAngleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get impactLabel => $composableBuilder(
    column: $table.impactLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get speedLabel => $composableBuilder(
    column: $table.speedLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tempoRatio => $composableBuilder(
    column: $table.tempoRatio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tempoLabel => $composableBuilder(
    column: $table.tempoLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get smoothnessScore => $composableBuilder(
    column: $table.smoothnessScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rollStatus => $composableBuilder(
    column: $table.rollStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get motionStartMs => $composableBuilder(
    column: $table.motionStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transitionMs => $composableBuilder(
    column: $table.transitionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get impactMs => $composableBuilder(
    column: $table.impactMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get followThroughEndMs => $composableBuilder(
    column: $table.followThroughEndMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get weakImpact => $composableBuilder(
    column: $table.weakImpact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get poorSegmentation => $composableBuilder(
    column: $table.poorSegmentation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get quaternionMissing => $composableBuilder(
    column: $table.quaternionMissing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudSyncState => $composableBuilder(
    column: $table.cloudSyncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parsedAtMs => $composableBuilder(
    column: $table.parsedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get savedAtMs => $composableBuilder(
    column: $table.savedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get renderedAtMs => $composableBuilder(
    column: $table.renderedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredStrokesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredStrokesTable> {
  $$StoredStrokesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get localSessionId => $composableBuilder(
    column: $table.localSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wireSessionId => $composableBuilder(
    column: $table.wireSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get packetId =>
      $composableBuilder(column: $table.packetId, builder: (column) => column);

  GeneratedColumn<String> get dedupeKey =>
      $composableBuilder(column: $table.dedupeKey, builder: (column) => column);

  GeneratedColumn<Uint8List> get rawPacketBytes => $composableBuilder(
    column: $table.rawPacketBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get captureStartMs => $composableBuilder(
    column: $table.captureStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get impactOffsetMs => $composableBuilder(
    column: $table.impactOffsetMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get faceAngleDeg => $composableBuilder(
    column: $table.faceAngleDeg,
    builder: (column) => column,
  );

  GeneratedColumn<String> get faceAngleLabel => $composableBuilder(
    column: $table.faceAngleLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get impactLabel => $composableBuilder(
    column: $table.impactLabel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<String> get speedLabel => $composableBuilder(
    column: $table.speedLabel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get tempoRatio => $composableBuilder(
    column: $table.tempoRatio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tempoLabel => $composableBuilder(
    column: $table.tempoLabel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get smoothnessScore => $composableBuilder(
    column: $table.smoothnessScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rollStatus => $composableBuilder(
    column: $table.rollStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get motionStartMs => $composableBuilder(
    column: $table.motionStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transitionMs => $composableBuilder(
    column: $table.transitionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get impactMs =>
      $composableBuilder(column: $table.impactMs, builder: (column) => column);

  GeneratedColumn<int> get followThroughEndMs => $composableBuilder(
    column: $table.followThroughEndMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get weakImpact => $composableBuilder(
    column: $table.weakImpact,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get poorSegmentation => $composableBuilder(
    column: $table.poorSegmentation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get quaternionMissing => $composableBuilder(
    column: $table.quaternionMissing,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudSyncState => $composableBuilder(
    column: $table.cloudSyncState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parsedAtMs => $composableBuilder(
    column: $table.parsedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get savedAtMs =>
      $composableBuilder(column: $table.savedAtMs, builder: (column) => column);

  GeneratedColumn<int> get renderedAtMs => $composableBuilder(
    column: $table.renderedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );
}

class $$StoredStrokesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoredStrokesTable,
          StoredStroke,
          $$StoredStrokesTableFilterComposer,
          $$StoredStrokesTableOrderingComposer,
          $$StoredStrokesTableAnnotationComposer,
          $$StoredStrokesTableCreateCompanionBuilder,
          $$StoredStrokesTableUpdateCompanionBuilder,
          (
            StoredStroke,
            BaseReferences<_$AppDatabase, $StoredStrokesTable, StoredStroke>,
          ),
          StoredStroke,
          PrefetchHooks Function()
        > {
  $$StoredStrokesTableTableManager(_$AppDatabase db, $StoredStrokesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredStrokesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredStrokesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredStrokesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> localSessionId = const Value.absent(),
                Value<int> wireSessionId = const Value.absent(),
                Value<int> packetId = const Value.absent(),
                Value<String> dedupeKey = const Value.absent(),
                Value<Uint8List> rawPacketBytes = const Value.absent(),
                Value<int> captureStartMs = const Value.absent(),
                Value<int> impactOffsetMs = const Value.absent(),
                Value<double> faceAngleDeg = const Value.absent(),
                Value<String> faceAngleLabel = const Value.absent(),
                Value<String> impactLabel = const Value.absent(),
                Value<double> speedMps = const Value.absent(),
                Value<String> speedLabel = const Value.absent(),
                Value<double> tempoRatio = const Value.absent(),
                Value<String> tempoLabel = const Value.absent(),
                Value<double> smoothnessScore = const Value.absent(),
                Value<String> rollStatus = const Value.absent(),
                Value<int> motionStartMs = const Value.absent(),
                Value<int> transitionMs = const Value.absent(),
                Value<int> impactMs = const Value.absent(),
                Value<int> followThroughEndMs = const Value.absent(),
                Value<bool> weakImpact = const Value.absent(),
                Value<bool> poorSegmentation = const Value.absent(),
                Value<bool> quaternionMissing = const Value.absent(),
                Value<String> cloudSyncState = const Value.absent(),
                Value<int> syncAttempts = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                Value<int> receivedAtMs = const Value.absent(),
                Value<int> parsedAtMs = const Value.absent(),
                Value<int> savedAtMs = const Value.absent(),
                Value<int?> renderedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
              }) => StoredStrokesCompanion(
                id: id,
                localSessionId: localSessionId,
                wireSessionId: wireSessionId,
                packetId: packetId,
                dedupeKey: dedupeKey,
                rawPacketBytes: rawPacketBytes,
                captureStartMs: captureStartMs,
                impactOffsetMs: impactOffsetMs,
                faceAngleDeg: faceAngleDeg,
                faceAngleLabel: faceAngleLabel,
                impactLabel: impactLabel,
                speedMps: speedMps,
                speedLabel: speedLabel,
                tempoRatio: tempoRatio,
                tempoLabel: tempoLabel,
                smoothnessScore: smoothnessScore,
                rollStatus: rollStatus,
                motionStartMs: motionStartMs,
                transitionMs: transitionMs,
                impactMs: impactMs,
                followThroughEndMs: followThroughEndMs,
                weakImpact: weakImpact,
                poorSegmentation: poorSegmentation,
                quaternionMissing: quaternionMissing,
                cloudSyncState: cloudSyncState,
                syncAttempts: syncAttempts,
                lastSyncError: lastSyncError,
                receivedAtMs: receivedAtMs,
                parsedAtMs: parsedAtMs,
                savedAtMs: savedAtMs,
                renderedAtMs: renderedAtMs,
                syncedAtMs: syncedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int localSessionId,
                required int wireSessionId,
                required int packetId,
                required String dedupeKey,
                required Uint8List rawPacketBytes,
                required int captureStartMs,
                required int impactOffsetMs,
                required double faceAngleDeg,
                required String faceAngleLabel,
                required String impactLabel,
                required double speedMps,
                required String speedLabel,
                required double tempoRatio,
                required String tempoLabel,
                required double smoothnessScore,
                required String rollStatus,
                required int motionStartMs,
                required int transitionMs,
                required int impactMs,
                required int followThroughEndMs,
                required bool weakImpact,
                required bool poorSegmentation,
                required bool quaternionMissing,
                required String cloudSyncState,
                Value<int> syncAttempts = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                required int receivedAtMs,
                required int parsedAtMs,
                required int savedAtMs,
                Value<int?> renderedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
              }) => StoredStrokesCompanion.insert(
                id: id,
                localSessionId: localSessionId,
                wireSessionId: wireSessionId,
                packetId: packetId,
                dedupeKey: dedupeKey,
                rawPacketBytes: rawPacketBytes,
                captureStartMs: captureStartMs,
                impactOffsetMs: impactOffsetMs,
                faceAngleDeg: faceAngleDeg,
                faceAngleLabel: faceAngleLabel,
                impactLabel: impactLabel,
                speedMps: speedMps,
                speedLabel: speedLabel,
                tempoRatio: tempoRatio,
                tempoLabel: tempoLabel,
                smoothnessScore: smoothnessScore,
                rollStatus: rollStatus,
                motionStartMs: motionStartMs,
                transitionMs: transitionMs,
                impactMs: impactMs,
                followThroughEndMs: followThroughEndMs,
                weakImpact: weakImpact,
                poorSegmentation: poorSegmentation,
                quaternionMissing: quaternionMissing,
                cloudSyncState: cloudSyncState,
                syncAttempts: syncAttempts,
                lastSyncError: lastSyncError,
                receivedAtMs: receivedAtMs,
                parsedAtMs: parsedAtMs,
                savedAtMs: savedAtMs,
                renderedAtMs: renderedAtMs,
                syncedAtMs: syncedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredStrokesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoredStrokesTable,
      StoredStroke,
      $$StoredStrokesTableFilterComposer,
      $$StoredStrokesTableOrderingComposer,
      $$StoredStrokesTableAnnotationComposer,
      $$StoredStrokesTableCreateCompanionBuilder,
      $$StoredStrokesTableUpdateCompanionBuilder,
      (
        StoredStroke,
        BaseReferences<_$AppDatabase, $StoredStrokesTable, StoredStroke>,
      ),
      StoredStroke,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PracticeSessionsTableTableManager get practiceSessions =>
      $$PracticeSessionsTableTableManager(_db, _db.practiceSessions);
  $$StoredStrokesTableTableManager get storedStrokes =>
      $$StoredStrokesTableTableManager(_db, _db.storedStrokes);
}
