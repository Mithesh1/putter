import 'dart:math';

import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';

const double _gravityMps2 = 9.80665;

class ImuSample {
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final double? qi;
  final double? qj;
  final double? qk;
  final double? qr;

  const ImuSample({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    this.qi,
    this.qj,
    this.qk,
    this.qr,
  });

  bool get hasQuaternion =>
      qi != null && qj != null && qk != null && qr != null;
}

class _ParsedImuData {
  final List<ImuSample> samples;
  final bool hasQuaternionData;

  const _ParsedImuData({
    required this.samples,
    required this.hasQuaternionData,
  });
}

StrokeMetrics processStrokePacket(
  RawStrokePacket packet, {
  PacketCodec codec = const PacketCodec(),
}) {
  final imuHz = packet.imuSampleRateHz.toDouble();
  final piezoHz = packet.piezoSampleRateHz.toDouble();
  final imuData = _parseImuSamples(
    codec.decodeScaledImu(packet),
    packet.imuChannels,
  );
  final imuSamples = imuData.samples;

  if (imuSamples.isEmpty) {
    return StrokeMetrics.empty(
      impactMs: packet.impactTimeMs,
      quaternionMissing: !imuData.hasQuaternionData,
    );
  }

  final piezoChannels = codec.splitPiezoChannels(packet);
  final piezo = _processPiezo(
    piezoChannels.isNotEmpty ? piezoChannels[0] : const <int>[],
    piezoChannels.length > 1 ? piezoChannels[1] : const <int>[],
    piezoChannels.length > 2 ? piezoChannels[2] : const <int>[],
  );
  final impactImuIdx = (piezo.impactIdx * imuHz / piezoHz).round().clamp(
    0,
    imuSamples.length - 1,
  );

  final segmentation = _segmentStroke(imuSamples, impactImuIdx, imuHz: imuHz);
  final timing = _computeTiming(
    motionStartIdx: segmentation.motionStartIdx,
    transitionIdx: segmentation.transitionIdx,
    impactIdx: impactImuIdx,
    followThroughEndIdx: segmentation.followThroughEndIdx,
    imuHz: imuHz,
  );

  final tempo = _computeTempo(
    motionStartIdx: segmentation.motionStartIdx,
    transitionIdx: segmentation.transitionIdx,
    impactIdx: impactImuIdx,
    imuHz: imuHz,
  );

  final face = _computeFaceMetrics(
    samples: imuSamples,
    motionStartIdx: segmentation.motionStartIdx,
    transitionIdx: segmentation.transitionIdx,
    impactIdx: impactImuIdx,
    followThroughEndIdx: segmentation.followThroughEndIdx,
    hasQuaternionData: imuData.hasQuaternionData,
    imuHz: imuHz,
  );

  final dynamics = _computeDynamics(
    samples: imuSamples,
    motionStartIdx: segmentation.motionStartIdx,
    impactIdx: impactImuIdx,
    followThroughEndIdx: segmentation.followThroughEndIdx,
    hasQuaternionData: imuData.hasQuaternionData,
    dominantGyroAxis: segmentation.dominantGyroAxis,
    imuHz: imuHz,
  );

  final setupStability = _computeSetupStabilityScore(
    samples: imuSamples,
    endIdx: segmentation.motionStartIdx,
  );

  final speedMps = _computeSpeedMps(
    samples: imuSamples,
    motionStartIdx: segmentation.motionStartIdx,
    impactIdx: impactImuIdx,
    hasQuaternionData: imuData.hasQuaternionData,
    dominantGyroAxis: segmentation.dominantGyroAxis,
    imuHz: imuHz,
  );

  final smoothnessScore = _computeSmoothnessScore(
    series: segmentation.gDomSeries,
    startIdx: segmentation.motionStartIdx,
    endIdx: segmentation.followThroughEndIdx,
  );

  final impactMsFromIdx = _idxToMs(impactImuIdx, imuHz);
  final impactMs = packet.impactOffsetMs > 0
      ? packet.impactTimeMs
      : impactMsFromIdx;
  final offsetMs = impactMs - impactMsFromIdx;
  final setupMs = packet.captureStartMs;

  return StrokeMetrics(
    faceAngleDeg: face.changeDeg,
    faceAngleLabel: _faceAngleLabel(face.changeDeg),
    impact: piezo.impactLabel,
    impactStrength: piezo.impactStrength,
    impactStrengthLabel: piezo.impactStrength.toStringAsFixed(0),
    speedMps: speedMps,
    speedLabel: '${speedMps.toStringAsFixed(2)} m/s',
    tempoRatio: tempo.tempoRatio,
    tempoLabel: '${tempo.tempoRatio.toStringAsFixed(2)}:1',
    backstrokeDurationMs: timing.backstrokeMs,
    forwardStrokeDurationMs: timing.forwardStrokeMs,
    followThroughDurationMs: timing.followThroughMs,
    totalStrokeDurationMs: timing.totalMs,
    peakAccelerationMps2: dynamics.peakAccelerationMps2,
    peakAccelerationLabel:
        '${dynamics.peakAccelerationMps2.toStringAsFixed(1)} m/s²',
    peakAngularVelocityDps: dynamics.peakAngularVelocityDps,
    peakAngularVelocityLabel:
        '${dynamics.peakAngularVelocityDps.toStringAsFixed(0)}°/s',
    setupFaceAngleDeg: face.setupDeg,
    setupFaceAngleLabel: _faceAngleLabel(face.setupDeg),
    faceAngleAtImpactDeg: face.impactDeg,
    faceAngleAtImpactLabel: _faceAngleLabel(face.impactDeg),
    faceAngleChangeDeg: face.changeDeg,
    faceAngleChangeLabel: _faceAngleLabel(face.changeDeg),
    clubRotationDeg: face.clubRotationDeg,
    clubRotationLabel: '${face.clubRotationDeg.toStringAsFixed(1)}°',
    setupStabilityScore: setupStability,
    setupStabilityLabel: '${setupStability.toStringAsFixed(0)}%',
    smoothnessScore: smoothnessScore,
    rollStatus: 'Unavailable',
    eventMarkers: StrokeEventMarkers(
      setupMs: setupMs,
      motionStartMs: offsetMs + _idxToMs(segmentation.motionStartIdx, imuHz),
      transitionMs: offsetMs + _idxToMs(segmentation.transitionIdx, imuHz),
      impactMs: impactMs,
      followThroughEndMs:
          offsetMs + _idxToMs(segmentation.followThroughEndIdx, imuHz),
    ),
    qualityFlags: StrokeQualityFlags(
      weakImpact: piezo.weakImpact,
      poorSegmentation: segmentation.poorSegmentation || tempo.poorSegmentation,
      quaternionMissing: !imuData.hasQuaternionData,
    ),
  );
}

_ParsedImuData _parseImuSamples(List<double> rawImu, int imuChannels) {
  if (imuChannels >= 10 && rawImu.length % imuChannels == 0) {
    final samples = <ImuSample>[];
    for (var i = 0; i < rawImu.length; i += imuChannels) {
      samples.add(
        ImuSample(
          ax: rawImu[i],
          ay: rawImu[i + 1],
          az: rawImu[i + 2],
          gx: rawImu[i + 3],
          gy: rawImu[i + 4],
          gz: rawImu[i + 5],
          qi: rawImu[i + 6],
          qj: rawImu[i + 7],
          qk: rawImu[i + 8],
          qr: rawImu[i + 9],
        ),
      );
    }
    return _ParsedImuData(samples: samples, hasQuaternionData: true);
  }

  final stride = max(imuChannels, 6);
  final sampleCount = rawImu.length ~/ stride;
  final samples = <ImuSample>[];
  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final offset = sampleIndex * stride;
    samples.add(
      ImuSample(
        ax: rawImu[offset],
        ay: rawImu[offset + 1],
        az: rawImu[offset + 2],
        gx: rawImu[offset + 3],
        gy: rawImu[offset + 4],
        gz: rawImu[offset + 5],
      ),
    );
  }
  return _ParsedImuData(samples: samples, hasQuaternionData: false);
}

class _PiezoResult {
  final int impactIdx;
  final bool weakImpact;
  final String impactLabel;
  final double impactStrength;

  const _PiezoResult({
    required this.impactIdx,
    required this.weakImpact,
    required this.impactLabel,
    required this.impactStrength,
  });
}

_PiezoResult _processPiezo(List<int> p1, List<int> p2, List<int> p3) {
  final d1 = _analyzePiezoChannel(p1);
  final d2 = _analyzePiezoChannel(p2);
  final d3 = _analyzePiezoChannel(p3);

  var impactIdx = d1.peakIdx;
  var globalPeak = d1.peak;
  var globalThreshold = d1.threshold;

  if (d2.peak > globalPeak) {
    globalPeak = d2.peak;
    impactIdx = d2.peakIdx;
    globalThreshold = d2.threshold;
  }
  if (d3.peak > globalPeak) {
    globalPeak = d3.peak;
    impactIdx = d3.peakIdx;
    globalThreshold = d3.threshold;
  }

  final weakImpact = globalPeak < globalThreshold;

  String impactLabel;
  if (p3.isNotEmpty) {
    if (d2.peak >= d1.peak && d2.peak >= d3.peak) {
      impactLabel = 'Center';
    } else if (d1.peak >= d3.peak) {
      impactLabel = 'Heel';
    } else {
      impactLabel = 'Toe';
    }
  } else {
    final rho = (d2.peak - d1.peak) / (d2.peak + d1.peak + 1e-6);
    if (rho.abs() < 0.12) {
      impactLabel = 'Center';
    } else if (rho < -0.12) {
      impactLabel = 'Heel';
    } else {
      impactLabel = 'Toe';
    }
  }

  return _PiezoResult(
    impactIdx: impactIdx,
    weakImpact: weakImpact,
    impactLabel: impactLabel,
    impactStrength: globalPeak,
  );
}

class _PiezoChannelAnalysis {
  final double peak;
  final int peakIdx;
  final double threshold;

  const _PiezoChannelAnalysis({
    required this.peak,
    required this.peakIdx,
    required this.threshold,
  });
}

_PiezoChannelAnalysis _analyzePiezoChannel(List<int> channel) {
  if (channel.isEmpty) {
    return const _PiezoChannelAnalysis(peak: 0.0, peakIdx: 0, threshold: 20.0);
  }

  final n = channel.length;
  final preCount = max(1, (n * 0.2).round());
  final pre = channel.take(preCount).map((e) => e.toDouble()).toList();

  final baseline = _mean(pre);
  var peak = 0.0;
  var peakIdx = 0;

  for (var i = 0; i < n; i++) {
    final v = (channel[i] - baseline).abs();
    if (v > peak) {
      peak = v;
      peakIdx = i;
    }
  }

  final noiseStd = _std(pre);
  final threshold = max(20.0, 5.0 * noiseStd);

  return _PiezoChannelAnalysis(
    peak: peak,
    peakIdx: peakIdx,
    threshold: threshold,
  );
}

class _SegmentationResult {
  final int motionStartIdx;
  final int transitionIdx;
  final int followThroughEndIdx;
  final int dominantGyroAxis;
  final List<double> gDomSeries;
  final bool poorSegmentation;

  const _SegmentationResult({
    required this.motionStartIdx,
    required this.transitionIdx,
    required this.followThroughEndIdx,
    required this.dominantGyroAxis,
    required this.gDomSeries,
    required this.poorSegmentation,
  });
}

_SegmentationResult _segmentStroke(
  List<ImuSample> samples,
  int impactIdx, {
  required double imuHz,
}) {
  final n = samples.length;
  final preImpactEnd = max(1, impactIdx);

  final gx = samples.map((s) => s.gx).toList();
  final gy = samples.map((s) => s.gy).toList();
  final gz = samples.map((s) => s.gz).toList();

  final rmsX = _rms(gx.sublist(0, preImpactEnd));
  final rmsY = _rms(gy.sublist(0, preImpactEnd));
  final rmsZ = _rms(gz.sublist(0, preImpactEnd));

  var dominantAxis = 0;
  var bestRms = rmsX;
  if (rmsY > bestRms) {
    bestRms = rmsY;
    dominantAxis = 1;
  }
  if (rmsZ > bestRms) {
    dominantAxis = 2;
  }

  final gDom = dominantAxis == 0
      ? gx
      : dominantAxis == 1
      ? gy
      : gz;

  final quietCount = max(1, (n * 0.2).round());
  final quietAbs = gDom.take(quietCount).map((v) => v.abs()).toList();
  final threshold = _mean(quietAbs) + 3.0 * _std(quietAbs);

  var motionStart = 0;
  for (var i = 0; i <= impactIdx && i < n; i++) {
    if (gDom[i].abs() > threshold) {
      motionStart = i;
      break;
    }
  }

  var transition = motionStart;
  var hasSignChange = false;
  for (var i = motionStart + 1; i <= impactIdx && i < n; i++) {
    final prev = gDom[i - 1];
    final cur = gDom[i];
    if ((prev < 0 && cur > 0) || (prev > 0 && cur < 0)) {
      transition = i;
      hasSignChange = true;
    }
  }

  if (!hasSignChange) {
    transition = ((motionStart + impactIdx) / 2).round();
  }

  var followThroughEnd = n - 1;
  final settleWindow = max(3, (imuHz * 0.05).round());
  var foundSettle = false;

  for (var i = impactIdx + 1; i + settleWindow < n; i++) {
    var below = true;
    for (var j = i; j < i + settleWindow; j++) {
      if (gDom[j].abs() > threshold) {
        below = false;
        break;
      }
    }
    if (below) {
      followThroughEnd = i;
      foundSettle = true;
      break;
    }
  }

  final poorSegmentation =
      !hasSignChange ||
      !foundSettle ||
      motionStart >= transition ||
      transition >= impactIdx ||
      impactIdx >= followThroughEnd;

  return _SegmentationResult(
    motionStartIdx: motionStart,
    transitionIdx: transition,
    followThroughEndIdx: followThroughEnd,
    dominantGyroAxis: dominantAxis,
    gDomSeries: gDom,
    poorSegmentation: poorSegmentation,
  );
}

class _TempoResult {
  final double tempoRatio;
  final bool poorSegmentation;

  const _TempoResult({
    required this.tempoRatio,
    required this.poorSegmentation,
  });
}

class _TimingResult {
  final int backstrokeMs;
  final int forwardStrokeMs;
  final int followThroughMs;
  final int totalMs;

  const _TimingResult({
    required this.backstrokeMs,
    required this.forwardStrokeMs,
    required this.followThroughMs,
    required this.totalMs,
  });
}

_TimingResult _computeTiming({
  required int motionStartIdx,
  required int transitionIdx,
  required int impactIdx,
  required int followThroughEndIdx,
  required double imuHz,
}) {
  return _TimingResult(
    backstrokeMs: max(0, _idxToMs(transitionIdx - motionStartIdx, imuHz)),
    forwardStrokeMs: max(0, _idxToMs(impactIdx - transitionIdx, imuHz)),
    followThroughMs: max(0, _idxToMs(followThroughEndIdx - impactIdx, imuHz)),
    totalMs: max(0, _idxToMs(followThroughEndIdx - motionStartIdx, imuHz)),
  );
}

_TempoResult _computeTempo({
  required int motionStartIdx,
  required int transitionIdx,
  required int impactIdx,
  required double imuHz,
}) {
  final backswingTime = (transitionIdx - motionStartIdx) / imuHz;
  final downswingTime = (impactIdx - transitionIdx) / imuHz;

  if (backswingTime <= 0 || downswingTime <= 0) {
    return const _TempoResult(tempoRatio: 0.0, poorSegmentation: true);
  }

  return _TempoResult(
    tempoRatio: backswingTime / downswingTime,
    poorSegmentation: false,
  );
}

class _FaceMetrics {
  final double setupDeg;
  final double impactDeg;
  final double changeDeg;
  final double clubRotationDeg;

  const _FaceMetrics({
    required this.setupDeg,
    required this.impactDeg,
    required this.changeDeg,
    required this.clubRotationDeg,
  });
}

_FaceMetrics _computeFaceMetrics({
  required List<ImuSample> samples,
  required int motionStartIdx,
  required int transitionIdx,
  required int impactIdx,
  required int followThroughEndIdx,
  required bool hasQuaternionData,
  required double imuHz,
}) {
  if (hasQuaternionData &&
      samples[motionStartIdx].hasQuaternion &&
      samples[impactIdx].hasQuaternion) {
    final setupDeg = _faceAngleFromQuaternion(samples.first);
    final impactDeg = _faceAngleFromQuaternion(samples[impactIdx]);
    final changeDeg = _wrapDegrees180(impactDeg - setupDeg);

    final start = motionStartIdx.clamp(0, samples.length - 1);
    final end = followThroughEndIdx.clamp(start, samples.length - 1);
    final angles = <double>[];
    for (var i = start; i <= end; i++) {
      if (samples[i].hasQuaternion) {
        angles.add(_faceAngleFromQuaternion(samples[i]));
      }
    }

    return _FaceMetrics(
      setupDeg: setupDeg,
      impactDeg: impactDeg,
      changeDeg: changeDeg,
      clubRotationDeg: angles.isEmpty
          ? changeDeg.abs()
          : _angleRangeDeg(angles),
    );
  }

  var impactAngleDeg = 0.0;
  var clubRotationDeg = 0.0;
  final dt = 1.0 / imuHz;
  final start = motionStartIdx.clamp(0, samples.length - 1);
  final end = followThroughEndIdx.clamp(start, samples.length - 1);
  for (var i = start; i <= end; i++) {
    final deltaDeg = samples[i].gz * dt;
    if (i <= impactIdx) {
      impactAngleDeg += deltaDeg;
    }
    clubRotationDeg += deltaDeg.abs();
  }

  return _FaceMetrics(
    setupDeg: 0.0,
    impactDeg: impactAngleDeg,
    changeDeg: impactAngleDeg,
    clubRotationDeg: clubRotationDeg,
  );
}

class _DynamicsResult {
  final double peakAccelerationMps2;
  final double peakAngularVelocityDps;

  const _DynamicsResult({
    required this.peakAccelerationMps2,
    required this.peakAngularVelocityDps,
  });
}

_DynamicsResult _computeDynamics({
  required List<ImuSample> samples,
  required int motionStartIdx,
  required int impactIdx,
  required int followThroughEndIdx,
  required bool hasQuaternionData,
  required int dominantGyroAxis,
  required double imuHz,
}) {
  if (samples.isEmpty) {
    return const _DynamicsResult(
      peakAccelerationMps2: 0.0,
      peakAngularVelocityDps: 0.0,
    );
  }

  final start = motionStartIdx.clamp(0, samples.length - 1);
  final end = followThroughEndIdx.clamp(start, samples.length - 1);
  var peakAcceleration = 0.0;
  var peakAngularVelocity = 0.0;

  for (var i = start; i <= end; i++) {
    final sample = samples[i];
    peakAcceleration = max(
      peakAcceleration,
      _linearAccelerationMagnitudeMps2(
        sample,
        hasQuaternionData: hasQuaternionData,
      ),
    );
    peakAngularVelocity = max(
      peakAngularVelocity,
      sqrt(
        sample.gx * sample.gx + sample.gy * sample.gy + sample.gz * sample.gz,
      ),
    );
  }

  return _DynamicsResult(
    peakAccelerationMps2: peakAcceleration,
    peakAngularVelocityDps: peakAngularVelocity,
  );
}

double _computeSpeedMps({
  required List<ImuSample> samples,
  required int motionStartIdx,
  required int impactIdx,
  required bool hasQuaternionData,
  required int dominantGyroAxis,
  required double imuHz,
}) {
  if (impactIdx <= motionStartIdx) {
    return 0.0;
  }

  final dt = 1.0 / imuHz;

  if (hasQuaternionData &&
      samples[motionStartIdx].hasQuaternion &&
      samples[impactIdx].hasQuaternion) {
    var vx = 0.0;
    var vy = 0.0;

    for (var i = motionStartIdx; i <= impactIdx && i < samples.length; i++) {
      final s = samples[i];
      final q = _normalizedQuatFromSample(s);

      final aBody = [
        s.ax * _gravityMps2,
        s.ay * _gravityMps2,
        s.az * _gravityMps2,
      ];
      final aWorld = _rotateVectorByQuat(aBody, q);

      final ax = aWorld[0];
      final ay = aWorld[1];
      final azNoG = aWorld[2] - _gravityMps2;

      vx += ax * dt;
      vy += ay * dt;

      if (azNoG.isNaN) {
        return 0.0;
      }
    }

    return sqrt(vx * vx + vy * vy).abs();
  }

  final axisSeries = dominantGyroAxis == 0
      ? samples.map((s) => s.ax).toList()
      : dominantGyroAxis == 1
      ? samples.map((s) => s.ay).toList()
      : samples.map((s) => s.az).toList();

  var velocity = 0.0;
  for (var i = motionStartIdx; i <= impactIdx && i < axisSeries.length; i++) {
    velocity += axisSeries[i] * _gravityMps2 * dt;
  }

  return velocity.abs();
}

double _computeSetupStabilityScore({
  required List<ImuSample> samples,
  required int endIdx,
}) {
  if (samples.isEmpty) {
    return 0.0;
  }

  final end = endIdx.clamp(0, samples.length - 1);
  final setupWindow = samples.sublist(0, end + 1);
  final gyroMagnitudes = setupWindow
      .map((s) => sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz))
      .toList(growable: false);
  final accelMagnitudes = setupWindow
      .map((s) => sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az))
      .toList(growable: false);

  final gyroRms = _rms(gyroMagnitudes);
  final accelStd = _std(accelMagnitudes);
  final score = 100.0 - (gyroRms * 8.0) - (accelStd * 100.0);
  return score.clamp(0.0, 100.0);
}

double _computeSmoothnessScore({
  required List<double> series,
  required int startIdx,
  required int endIdx,
}) {
  if (series.isEmpty) {
    return 0.0;
  }

  final s = startIdx.clamp(0, series.length - 1);
  final e = endIdx.clamp(0, series.length - 1);
  if (e <= s) {
    return 0.0;
  }

  final window = series.sublist(s, e + 1);
  final variance = _variance(window);
  final score = 100.0 / (1.0 + variance);
  return score.clamp(0.0, 100.0);
}

String _faceAngleLabel(double angleDeg) {
  final direction = angleDeg >= 0 ? 'open' : 'closed';
  return '${angleDeg.abs().toStringAsFixed(1)}° $direction';
}

double _faceAngleFromQuaternion(ImuSample sample) {
  final q = _normalizedQuatFromSample(sample);
  final faceNormal = const [1.0, 0.0, 0.0];
  final targetLine = const [1.0, 0.0, 0.0];
  final upVector = const [0.0, 0.0, 1.0];

  final rotated = _rotateVectorByQuat(faceNormal, q);
  final faceProj = [rotated[0], rotated[1], 0.0];
  final norm = _norm3(faceProj);
  if (norm < 1e-8) {
    return 0.0;
  }

  final faceProjUnit = [faceProj[0] / norm, faceProj[1] / norm, 0.0];
  final cross = _cross3(targetLine, faceProjUnit);
  final angleRad = atan2(
    _dot3(cross, upVector),
    _dot3(targetLine, faceProjUnit),
  );
  return angleRad * 180.0 / pi;
}

double _linearAccelerationMagnitudeMps2(
  ImuSample sample, {
  required bool hasQuaternionData,
}) {
  if (hasQuaternionData && sample.hasQuaternion) {
    final q = _normalizedQuatFromSample(sample);
    final aWorld = _rotateVectorByQuat([
      sample.ax * _gravityMps2,
      sample.ay * _gravityMps2,
      sample.az * _gravityMps2,
    ], q);
    final ax = aWorld[0];
    final ay = aWorld[1];
    final az = aWorld[2] - _gravityMps2;
    return sqrt(ax * ax + ay * ay + az * az);
  }

  final accelG = sqrt(
    sample.ax * sample.ax + sample.ay * sample.ay + sample.az * sample.az,
  );
  return (accelG - 1.0).abs() * _gravityMps2;
}

double _angleRangeDeg(List<double> angles) {
  if (angles.length < 2) {
    return 0.0;
  }

  var minAngle = angles.first;
  var maxAngle = angles.first;
  var unwrapped = angles.first;
  var previous = angles.first;

  for (final angle in angles.skip(1)) {
    unwrapped += _wrapDegrees180(angle - previous);
    previous = angle;
    minAngle = min(minAngle, unwrapped);
    maxAngle = max(maxAngle, unwrapped);
  }

  return (maxAngle - minAngle).abs();
}

double _wrapDegrees180(double value) {
  var wrapped = value;
  while (wrapped > 180.0) {
    wrapped -= 360.0;
  }
  while (wrapped < -180.0) {
    wrapped += 360.0;
  }
  return wrapped;
}

int _idxToMs(int idx, double hz) => (idx * 1000.0 / hz).round();

double _mean(List<double> values) {
  if (values.isEmpty) {
    return 0.0;
  }
  final sum = values.fold<double>(0.0, (a, b) => a + b);
  return sum / values.length;
}

double _variance(List<double> values) {
  if (values.length < 2) {
    return 0.0;
  }
  final mu = _mean(values);
  var acc = 0.0;
  for (final v in values) {
    final d = v - mu;
    acc += d * d;
  }
  return acc / values.length;
}

double _std(List<double> values) => sqrt(_variance(values));

double _rms(List<double> values) {
  if (values.isEmpty) {
    return 0.0;
  }
  var acc = 0.0;
  for (final v in values) {
    acc += v * v;
  }
  return sqrt(acc / values.length);
}

List<double> _normalizedQuatFromSample(ImuSample s) {
  final q = [s.qr ?? 1.0, s.qi ?? 0.0, s.qj ?? 0.0, s.qk ?? 0.0];
  final n = sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
  if (n < 1e-8) {
    return [1.0, 0.0, 0.0, 0.0];
  }
  return [q[0] / n, q[1] / n, q[2] / n, q[3] / n];
}

List<double> _quatMultiply(List<double> a, List<double> b) {
  final aw = a[0], ax = a[1], ay = a[2], az = a[3];
  final bw = b[0], bx = b[1], by = b[2], bz = b[3];
  return [
    aw * bw - ax * bx - ay * by - az * bz,
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
  ];
}

List<double> _quatInverse(List<double> q) {
  final n2 = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
  if (n2 < 1e-10) {
    return [1.0, 0.0, 0.0, 0.0];
  }
  return [q[0] / n2, -q[1] / n2, -q[2] / n2, -q[3] / n2];
}

List<double> _rotateVectorByQuat(List<double> v, List<double> q) {
  final p = [0.0, v[0], v[1], v[2]];
  final qInv = _quatInverse(q);
  final qp = _quatMultiply(q, p);
  final qpqInv = _quatMultiply(qp, qInv);
  return [qpqInv[1], qpqInv[2], qpqInv[3]];
}

double _dot3(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

List<double> _cross3(List<double> a, List<double> b) {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
}

double _norm3(List<double> v) => sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
