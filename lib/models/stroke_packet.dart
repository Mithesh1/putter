import 'dart:convert';
import 'dart:typed_data';

enum PracticeSessionStatus { active, ended }

enum CloudSyncState { pending, syncing, synced, failed }

class PracticeSession {
  final int? localId;
  final int wireSessionId;
  final PracticeSessionStatus status;
  final int startedAtMs;
  final int? endedAtMs;
  final int lastSeenPacketId;
  final int strokeCount;
  final String? deviceId;
  final String? deviceName;

  const PracticeSession({
    required this.localId,
    required this.wireSessionId,
    required this.status,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.lastSeenPacketId,
    required this.strokeCount,
    this.deviceId,
    this.deviceName,
  });

  bool get isActive => status == PracticeSessionStatus.active;

  PracticeSession copyWith({
    int? localId,
    int? wireSessionId,
    PracticeSessionStatus? status,
    int? startedAtMs,
    int? endedAtMs,
    int? lastSeenPacketId,
    int? strokeCount,
    String? deviceId,
    String? deviceName,
  }) {
    return PracticeSession(
      localId: localId ?? this.localId,
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
}

class RawStrokePacket {
  final int packetId;
  final int sessionId;
  final int captureStartMs;
  final int impactOffsetMs;
  final int flags;
  final int imuSampleRateHz;
  final int imuChannels;
  final int imuSampleCount;
  final int piezoSampleRateHz;
  final int piezoChannels;
  final int piezoSampleCount;
  final int imuEncoding;
  final int piezoEncoding;
  final int reserved;
  final List<int> imuData;
  final List<int> piezoData;

  const RawStrokePacket({
    required this.packetId,
    required this.sessionId,
    required this.captureStartMs,
    required this.impactOffsetMs,
    required this.flags,
    required this.imuSampleRateHz,
    required this.imuChannels,
    required this.imuSampleCount,
    required this.piezoSampleRateHz,
    required this.piezoChannels,
    required this.piezoSampleCount,
    required this.imuEncoding,
    required this.piezoEncoding,
    required this.reserved,
    required this.imuData,
    required this.piezoData,
  });

  int get impactTimeMs => captureStartMs + impactOffsetMs;
  double get impactToBleTxMs => flags / 10.0;
  int get expectedImuValueCount => imuChannels * imuSampleCount;
  int get expectedPiezoValueCount => piezoChannels * piezoSampleCount;
}

class StrokeEventMarkers {
  final int setupMs;
  final int motionStartMs;
  final int transitionMs;
  final int impactMs;
  final int followThroughEndMs;

  const StrokeEventMarkers({
    this.setupMs = 0,
    required this.motionStartMs,
    required this.transitionMs,
    required this.impactMs,
    required this.followThroughEndMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'setupMs': setupMs,
      'motionStartMs': motionStartMs,
      'transitionMs': transitionMs,
      'impactMs': impactMs,
      'followThroughEndMs': followThroughEndMs,
    };
  }
}

class StrokeQualityFlags {
  final bool weakImpact;
  final bool poorSegmentation;
  final bool quaternionMissing;

  const StrokeQualityFlags({
    required this.weakImpact,
    required this.poorSegmentation,
    required this.quaternionMissing,
  });

  Map<String, dynamic> toJson() {
    return {
      'weakImpact': weakImpact,
      'poorSegmentation': poorSegmentation,
      'quaternionMissing': quaternionMissing,
    };
  }
}

class StrokeMetrics {
  final double faceAngleDeg;
  final String faceAngleLabel;
  final String impact;
  final double impactStrength;
  final String impactStrengthLabel;
  final double speedMps;
  final String speedLabel;
  final double tempoRatio;
  final String tempoLabel;
  final int backstrokeDurationMs;
  final int forwardStrokeDurationMs;
  final int followThroughDurationMs;
  final int totalStrokeDurationMs;
  final double peakAccelerationMps2;
  final String peakAccelerationLabel;
  final double peakAngularVelocityDps;
  final String peakAngularVelocityLabel;
  final double setupFaceAngleDeg;
  final String setupFaceAngleLabel;
  final double faceAngleAtImpactDeg;
  final String faceAngleAtImpactLabel;
  final double faceAngleChangeDeg;
  final String faceAngleChangeLabel;
  final double clubRotationDeg;
  final String clubRotationLabel;
  final double setupStabilityScore;
  final String setupStabilityLabel;
  final double smoothnessScore;
  final String rollStatus;
  final int impactImuOffsetMs;
  final int impactPiezoOffsetMs;
  final StrokeEventMarkers eventMarkers;
  final StrokeQualityFlags qualityFlags;

  const StrokeMetrics({
    required this.faceAngleDeg,
    required this.faceAngleLabel,
    required this.impact,
    required this.impactStrength,
    required this.impactStrengthLabel,
    required this.speedMps,
    required this.speedLabel,
    required this.tempoRatio,
    required this.tempoLabel,
    required this.backstrokeDurationMs,
    required this.forwardStrokeDurationMs,
    required this.followThroughDurationMs,
    required this.totalStrokeDurationMs,
    required this.peakAccelerationMps2,
    required this.peakAccelerationLabel,
    required this.peakAngularVelocityDps,
    required this.peakAngularVelocityLabel,
    required this.setupFaceAngleDeg,
    required this.setupFaceAngleLabel,
    required this.faceAngleAtImpactDeg,
    required this.faceAngleAtImpactLabel,
    required this.faceAngleChangeDeg,
    required this.faceAngleChangeLabel,
    required this.clubRotationDeg,
    required this.clubRotationLabel,
    required this.setupStabilityScore,
    required this.setupStabilityLabel,
    required this.smoothnessScore,
    required this.rollStatus,
    required this.impactImuOffsetMs,
    required this.impactPiezoOffsetMs,
    required this.eventMarkers,
    required this.qualityFlags,
  });

  factory StrokeMetrics.empty({
    required int impactMs,
    required bool quaternionMissing,
  }) {
    return StrokeMetrics(
      faceAngleDeg: 0.0,
      faceAngleLabel: '0.0° open',
      impact: 'Center',
      impactStrength: 0.0,
      impactStrengthLabel: '0',
      speedMps: 0.0,
      speedLabel: '0.00 m/s',
      tempoRatio: 0.0,
      tempoLabel: '0.00:1',
      backstrokeDurationMs: 0,
      forwardStrokeDurationMs: 0,
      followThroughDurationMs: 0,
      totalStrokeDurationMs: 0,
      peakAccelerationMps2: 0.0,
      peakAccelerationLabel: '0.0 m/s²',
      peakAngularVelocityDps: 0.0,
      peakAngularVelocityLabel: '0°/s',
      setupFaceAngleDeg: 0.0,
      setupFaceAngleLabel: '0.0° open',
      faceAngleAtImpactDeg: 0.0,
      faceAngleAtImpactLabel: '0.0° open',
      faceAngleChangeDeg: 0.0,
      faceAngleChangeLabel: '0.0° open',
      clubRotationDeg: 0.0,
      clubRotationLabel: '0.0°',
      setupStabilityScore: 0.0,
      setupStabilityLabel: '0%',
      smoothnessScore: 0.0,
      rollStatus: 'Unavailable',
      impactImuOffsetMs: 0,
      impactPiezoOffsetMs: 0,
      eventMarkers: StrokeEventMarkers(
        setupMs: 0,
        motionStartMs: 0,
        transitionMs: 0,
        impactMs: impactMs,
        followThroughEndMs: 0,
      ),
      qualityFlags: StrokeQualityFlags(
        weakImpact: true,
        poorSegmentation: true,
        quaternionMissing: quaternionMissing,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'faceAngleDeg': faceAngleDeg,
      'faceAngleLabel': faceAngleLabel,
      'impact': impact,
      'impactStrength': impactStrength,
      'impactStrengthLabel': impactStrengthLabel,
      'speedMps': speedMps,
      'speedLabel': speedLabel,
      'tempoRatio': tempoRatio,
      'tempoLabel': tempoLabel,
      'backstrokeDurationMs': backstrokeDurationMs,
      'forwardStrokeDurationMs': forwardStrokeDurationMs,
      'followThroughDurationMs': followThroughDurationMs,
      'totalStrokeDurationMs': totalStrokeDurationMs,
      'peakAccelerationMps2': peakAccelerationMps2,
      'peakAccelerationLabel': peakAccelerationLabel,
      'peakAngularVelocityDps': peakAngularVelocityDps,
      'peakAngularVelocityLabel': peakAngularVelocityLabel,
      'setupFaceAngleDeg': setupFaceAngleDeg,
      'setupFaceAngleLabel': setupFaceAngleLabel,
      'faceAngleAtImpactDeg': faceAngleAtImpactDeg,
      'faceAngleAtImpactLabel': faceAngleAtImpactLabel,
      'faceAngleChangeDeg': faceAngleChangeDeg,
      'faceAngleChangeLabel': faceAngleChangeLabel,
      'clubRotationDeg': clubRotationDeg,
      'clubRotationLabel': clubRotationLabel,
      'setupStabilityScore': setupStabilityScore,
      'setupStabilityLabel': setupStabilityLabel,
      'smoothnessScore': smoothnessScore,
      'rollStatus': rollStatus,
      'impactImuOffsetMs': impactImuOffsetMs,
      'impactPiezoOffsetMs': impactPiezoOffsetMs,
      'eventMarkers': eventMarkers.toJson(),
      'qualityFlags': qualityFlags.toJson(),
    };
  }
}

class BallStrokeAnalysis {
  final double pathDriftDeg;
  final double rmsLateralPx;
  final double directionWobbleDeg;
  final double totalPathPx;
  final double avgRadiusPx;
  final int trackingQualityPct;
  final int frameCount;
  final double fps;
  final int linkedAtMs;

  const BallStrokeAnalysis({
    required this.pathDriftDeg,
    required this.rmsLateralPx,
    required this.directionWobbleDeg,
    required this.totalPathPx,
    required this.avgRadiusPx,
    required this.trackingQualityPct,
    required this.frameCount,
    required this.fps,
    required this.linkedAtMs,
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

  Map<String, dynamic> toJson() {
    return {
      'kind': 'ball_path_analysis_v1',
      'pathDriftDeg': pathDriftDeg,
      'rmsLateralPx': rmsLateralPx,
      'directionWobbleDeg': directionWobbleDeg,
      'totalPathPx': totalPathPx,
      'avgRadiusPx': avgRadiusPx,
      'trackingQualityPct': trackingQualityPct,
      'frameCount': frameCount,
      'fps': fps,
      'linkedAtMs': linkedAtMs,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static BallStrokeAnalysis? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['kind'] != 'ball_path_analysis_v1') {
        return null;
      }
      return BallStrokeAnalysis(
        pathDriftDeg: (decoded['pathDriftDeg'] as num?)?.toDouble() ?? 0.0,
        rmsLateralPx: (decoded['rmsLateralPx'] as num?)?.toDouble() ?? 0.0,
        directionWobbleDeg:
            (decoded['directionWobbleDeg'] as num?)?.toDouble() ?? 0.0,
        totalPathPx: (decoded['totalPathPx'] as num?)?.toDouble() ?? 0.0,
        avgRadiusPx: (decoded['avgRadiusPx'] as num?)?.toDouble() ?? 0.0,
        trackingQualityPct: (decoded['trackingQualityPct'] as num?)?.toInt() ?? 0,
        frameCount: (decoded['frameCount'] as num?)?.toInt() ?? 0,
        fps: (decoded['fps'] as num?)?.toDouble() ?? 0.0,
        linkedAtMs: (decoded['linkedAtMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class StrokeLatencyTimestamps {
  final int receivedAtMs;
  final int parsedAtMs;
  final int savedAtMs;
  final int? renderedAtMs;
  final int? syncedAtMs;

  const StrokeLatencyTimestamps({
    required this.receivedAtMs,
    required this.parsedAtMs,
    required this.savedAtMs,
    required this.renderedAtMs,
    required this.syncedAtMs,
  });

  StrokeLatencyTimestamps copyWith({
    int? receivedAtMs,
    int? parsedAtMs,
    int? savedAtMs,
    int? renderedAtMs,
    int? syncedAtMs,
  }) {
    return StrokeLatencyTimestamps(
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
      parsedAtMs: parsedAtMs ?? this.parsedAtMs,
      savedAtMs: savedAtMs ?? this.savedAtMs,
      renderedAtMs: renderedAtMs ?? this.renderedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
    );
  }
}

class StoredStroke {
  final int? localId;
  final int localSessionId;
  final int wireSessionId;
  final int packetId;
  final Uint8List rawPacketBytes;
  final RawStrokePacket rawPacket;
  final StrokeMetrics metrics;
  final CloudSyncState cloudSyncState;
  final int syncAttempts;
  final String? lastSyncError;
  final StrokeLatencyTimestamps latency;
  final BallStrokeAnalysis? ballAnalysis;

  const StoredStroke({
    required this.localId,
    required this.localSessionId,
    required this.wireSessionId,
    required this.packetId,
    required this.rawPacketBytes,
    required this.rawPacket,
    required this.metrics,
    required this.cloudSyncState,
    required this.syncAttempts,
    required this.lastSyncError,
    required this.latency,
    required this.ballAnalysis,
  });

  String get dedupeKey => '$wireSessionId:$packetId';

  StoredStroke copyWith({
    int? localId,
    int? localSessionId,
    int? wireSessionId,
    int? packetId,
    Uint8List? rawPacketBytes,
    RawStrokePacket? rawPacket,
    StrokeMetrics? metrics,
    CloudSyncState? cloudSyncState,
    int? syncAttempts,
    String? lastSyncError,
    StrokeLatencyTimestamps? latency,
    BallStrokeAnalysis? ballAnalysis,
  }) {
    return StoredStroke(
      localId: localId ?? this.localId,
      localSessionId: localSessionId ?? this.localSessionId,
      wireSessionId: wireSessionId ?? this.wireSessionId,
      packetId: packetId ?? this.packetId,
      rawPacketBytes: rawPacketBytes ?? this.rawPacketBytes,
      rawPacket: rawPacket ?? this.rawPacket,
      metrics: metrics ?? this.metrics,
      cloudSyncState: cloudSyncState ?? this.cloudSyncState,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      latency: latency ?? this.latency,
      ballAnalysis: ballAnalysis ?? this.ballAnalysis,
    );
  }
}

class StrokeTrendPoint {
  final String label;
  final double value;

  const StrokeTrendPoint({required this.label, required this.value});
}

class SessionDetail {
  final PracticeSession session;
  final List<StoredStroke> strokes;

  const SessionDetail({required this.session, required this.strokes});
}
