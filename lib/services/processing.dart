import 'dart:math';

import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';

const double _gravityMps2 = 9.80665;
const double _backstrokeThresholdDps = 20.0;
const double _forwardStrokeThresholdDps = -10.0;
const double _followThroughEndThresholdDps = -1.0;
const double _accelImpactMinDeltaG = 0.35;
const double _accelImpactMinScore = 4.0;
const double _piezoImpactMinDelta = 12.0;
const double _piezoImpactAbsoluteThreshold = 300.0;
const double _piezoContactAverageDelta = 45.0;
const double _piezoContactRelativeDeltaThreshold = 0.20;
const double _piezoContactMinStrength = 35.0;
const double _piezoContactSinglePeakDelta = 120.0;
const double _piezoContactSinglePeakLowSideMax = 180.0;
const double _piezoContactPeakDelta = 120.0;
const double _piezoContactPeakRelativeDeltaThreshold = 0.45;
const int _piezoContactWindowRadius = 3;
const int _motionConfirmFrames = 3;
const int _followThroughConfirmFrames = 2;

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
  final calibrationIdx = packet.imuSampleCount > 0
      ? packet.reserved.clamp(0, packet.imuSampleCount - 1)
      : 0;
  final packetImpactImuIdx = packet.impactOffsetMs > 0
      ? ((packet.impactOffsetMs * imuHz) / 1000.0).round().clamp(
          0,
          imuSamples.length - 1,
        )
      : 0;
  final motion = _segmentMotion(imuSamples);
  final accelImpact = _findAccelImpact(
    imuSamples,
    transitionIdx: motion.transitionIdx,
    packetImpactIdx: packetImpactImuIdx,
  );
  final impactImuIdx = accelImpact.impactIdx;
  final segmentation = _segmentStroke(
    imuSamples,
    impactImuIdx,
    motionStartIdx: motion.motionStartIdx,
    transitionIdx: motion.transitionIdx,
  );
  final impactPiezoIdx = ((impactImuIdx * piezoHz) / imuHz).round();
  final piezo = _processPiezo(
    piezoChannels.isNotEmpty ? piezoChannels[0] : const <int>[],
    piezoChannels.length > 1 ? piezoChannels[1] : const <int>[],
    impactPiezoIdx,
    impactFound: accelImpact.found,
  );
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
    calibrationIdx: calibrationIdx,
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
    transitionIdx: segmentation.transitionIdx,
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
  final imuStartMs = packet.captureStartMs -
      (imuHz > 0 ? ((calibrationIdx * 1000.0) / imuHz).round() : 0);
  final impactMs = imuStartMs + impactMsFromIdx;
  final offsetMs = impactMs - impactMsFromIdx;
  final impactPiezoOffsetMs =
      piezoHz > 0 ? _idxToMs(piezo.impactIdx, piezoHz) : 0;

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
    impactImuOffsetMs: impactMsFromIdx,
    impactPiezoOffsetMs: impactPiezoOffsetMs,
    eventMarkers: StrokeEventMarkers(
      setupMs: 0,
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
  final bool weakImpact;
  final String impactLabel;
  final double impactStrength;
  final int impactIdx;

  const _PiezoResult({
    required this.weakImpact,
    required this.impactLabel,
    required this.impactStrength,
    required this.impactIdx,
  });
}

_PiezoResult _processPiezo(
  List<int> toePiezo,
  List<int> heelPiezo,
  int impactIdx, {
  required bool impactFound,
}) {
  if (toePiezo.isEmpty && heelPiezo.isEmpty) {
    return const _PiezoResult(
      weakImpact: true,
      impactLabel: 'Unknown',
      impactStrength: 0.0,
      impactIdx: 0,
    );
  }

  final toeAverage = toePiezo.isEmpty
      ? 0.0
      : _mean(toePiezo.map((value) => value.toDouble()).toList(growable: false));
  final heelAverage = heelPiezo.isEmpty
      ? 0.0
      : _mean(
          heelPiezo.map((value) => value.toDouble()).toList(growable: false),
        );
  final maxLength = max(toePiezo.length, heelPiezo.length);
  if (maxLength <= 0) {
    return const _PiezoResult(
      weakImpact: true,
      impactLabel: 'Unknown',
      impactStrength: 0.0,
      impactIdx: 0,
    );
  }

  final expectedIdx = impactIdx.clamp(0, maxLength - 1);
  final searchRadius = 12;
  final searchStart = max(0, expectedIdx - searchRadius);
  final searchEnd = min(maxLength - 1, expectedIdx + searchRadius);
  var bestImpactIdx = expectedIdx;
  var bestImpactStrength = -1.0;
  var bestAbsolutePeak = double.negativeInfinity;
  var bestToeRawAtImpact = 0.0;
  var bestHeelRawAtImpact = 0.0;
  var globalBestImpactIdx = expectedIdx;
  var globalBestAbsolutePeak = double.negativeInfinity;
  var globalBestToeRaw = 0.0;
  var globalBestHeelRaw = 0.0;
  var globalBestImpactStrength = -1.0;

  for (var idx = 0; idx < maxLength; idx++) {
    final toeRaw = idx < toePiezo.length ? toePiezo[idx].toDouble() : 0.0;
    final heelRaw = idx < heelPiezo.length ? heelPiezo[idx].toDouble() : 0.0;
    final toeDelta = idx < toePiezo.length
        ? max(0.0, toeRaw - toeAverage)
        : 0.0;
    final heelDelta = idx < heelPiezo.length
        ? max(0.0, heelRaw - heelAverage)
        : 0.0;
    final absolutePeak = max(toeRaw, heelRaw);
    final combinedStrength = max(toeDelta, heelDelta);
    if (absolutePeak > globalBestAbsolutePeak ||
        (absolutePeak == globalBestAbsolutePeak &&
            combinedStrength > globalBestImpactStrength)) {
      globalBestImpactIdx = idx;
      globalBestAbsolutePeak = absolutePeak;
      globalBestToeRaw = toeRaw;
      globalBestHeelRaw = heelRaw;
      globalBestImpactStrength = combinedStrength;
    }
  }

  for (var idx = searchStart; idx <= searchEnd; idx++) {
    final toeRaw = idx < toePiezo.length ? toePiezo[idx].toDouble() : 0.0;
    final heelRaw = idx < heelPiezo.length ? heelPiezo[idx].toDouble() : 0.0;
    final toeDelta = idx < toePiezo.length
        ? max(0.0, toeRaw - toeAverage)
        : 0.0;
    final heelDelta = idx < heelPiezo.length
        ? max(0.0, heelRaw - heelAverage)
        : 0.0;
    final absolutePeak = max(toeRaw, heelRaw);
    if (absolutePeak >= _piezoImpactAbsoluteThreshold &&
        absolutePeak > bestAbsolutePeak) {
      bestAbsolutePeak = absolutePeak;
      bestImpactStrength = max(toeDelta, heelDelta);
      bestImpactIdx = idx;
      bestToeRawAtImpact = toeRaw;
      bestHeelRawAtImpact = heelRaw;
      continue;
    }
    if (bestAbsolutePeak >= _piezoImpactAbsoluteThreshold) {
      continue;
    }
    final combinedStrength = max(toeDelta, heelDelta);
    if (combinedStrength > bestImpactStrength) {
      bestImpactStrength = combinedStrength;
      bestImpactIdx = idx;
      bestToeRawAtImpact = toeRaw;
      bestHeelRawAtImpact = heelRaw;
    }
  }

  final globalPeakDominatesLocal =
      globalBestAbsolutePeak >= _piezoImpactAbsoluteThreshold &&
      (bestAbsolutePeak < _piezoImpactAbsoluteThreshold ||
          globalBestAbsolutePeak > bestAbsolutePeak + 150.0);
  if (globalPeakDominatesLocal) {
    bestImpactIdx = globalBestImpactIdx;
    bestAbsolutePeak = globalBestAbsolutePeak;
    bestToeRawAtImpact = globalBestToeRaw;
    bestHeelRawAtImpact = globalBestHeelRaw;
    bestImpactStrength = globalBestImpactStrength;
  }

  final impactStrength = bestImpactStrength < 0.0 ? 0.0 : bestImpactStrength;
  final weakImpact = bestAbsolutePeak < _piezoImpactAbsoluteThreshold &&
      impactStrength < _piezoImpactMinDelta;

  final windowStart = max(0, bestImpactIdx - _piezoContactWindowRadius);
  final windowEnd = min(maxLength - 1, bestImpactIdx + _piezoContactWindowRadius);
  var toeWindowTotal = 0.0;
  var heelWindowTotal = 0.0;
  var windowSamples = 0;
  var toeWindowPeakRaw = 0.0;
  var heelWindowPeakRaw = 0.0;

  for (var idx = windowStart; idx <= windowEnd; idx++) {
    final toeRaw = idx < toePiezo.length ? toePiezo[idx].toDouble() : 0.0;
    final heelRaw = idx < heelPiezo.length ? heelPiezo[idx].toDouble() : 0.0;
    toeWindowTotal += toeRaw;
    heelWindowTotal += heelRaw;
    toeWindowPeakRaw = max(toeWindowPeakRaw, toeRaw);
    heelWindowPeakRaw = max(heelWindowPeakRaw, heelRaw);
    windowSamples++;
  }

  final toeWindowAverage =
      windowSamples == 0 ? 0.0 : toeWindowTotal / windowSamples;
  final heelWindowAverage =
      windowSamples == 0 ? 0.0 : heelWindowTotal / windowSamples;
  final windowPeakDifference = (toeWindowPeakRaw - heelWindowPeakRaw).abs();
  final windowPeakRelativeDifference =
      windowPeakDifference / (toeWindowPeakRaw + heelWindowPeakRaw + 1e-6);
  final averageDifference = (toeWindowAverage - heelWindowAverage).abs();
  final relativeDifference =
      averageDifference / (toeWindowAverage + heelWindowAverage + 1e-6);
  final peakDifference = (bestToeRawAtImpact - bestHeelRawAtImpact).abs();
  final peakRelativeDifference =
      peakDifference / (bestToeRawAtImpact + bestHeelRawAtImpact + 1e-6);
  final toeWindowPeakAbsolute =
      toeWindowPeakRaw >= _piezoImpactAbsoluteThreshold;
  final heelWindowPeakAbsolute =
      heelWindowPeakRaw >= _piezoImpactAbsoluteThreshold;
  final bothWindowPeaksAbsolute =
      toeWindowPeakAbsolute && heelWindowPeakAbsolute;
  final clearSingleWindowPeakDominance =
      (toeWindowPeakAbsolute &&
              heelWindowPeakRaw <= _piezoContactSinglePeakLowSideMax &&
              (toeWindowPeakRaw - heelWindowPeakRaw) >=
                  _piezoContactSinglePeakDelta) ||
          (heelWindowPeakAbsolute &&
              toeWindowPeakRaw <= _piezoContactSinglePeakLowSideMax &&
              (heelWindowPeakRaw - toeWindowPeakRaw) >=
                  _piezoContactSinglePeakDelta);
  final toePeakAbsolute = bestToeRawAtImpact >= _piezoImpactAbsoluteThreshold;
  final heelPeakAbsolute = bestHeelRawAtImpact >= _piezoImpactAbsoluteThreshold;
  final bothPeaksAbsolute =
      toePeakAbsolute && heelPeakAbsolute;
  final clearSinglePeakDominance =
      (toePeakAbsolute &&
              bestHeelRawAtImpact <= _piezoContactSinglePeakLowSideMax &&
              (bestToeRawAtImpact - bestHeelRawAtImpact) >=
                  _piezoContactSinglePeakDelta) ||
          (heelPeakAbsolute &&
              bestToeRawAtImpact <= _piezoContactSinglePeakLowSideMax &&
              (bestHeelRawAtImpact - bestToeRawAtImpact) >=
                  _piezoContactSinglePeakDelta);
  final clearSideSignal =
      bestAbsolutePeak >= _piezoImpactAbsoluteThreshold ||
      impactStrength >= _piezoContactMinStrength;
  final clearPeakDominance =
      bestAbsolutePeak >= _piezoImpactAbsoluteThreshold &&
      peakDifference >= _piezoContactPeakDelta &&
      peakRelativeDifference >= _piezoContactPeakRelativeDeltaThreshold;

  String impactLabel;
  final confidentPiezoImpact = bestAbsolutePeak >= _piezoImpactAbsoluteThreshold ||
      impactStrength >= _piezoContactMinStrength;

  if (!impactFound && !confidentPiezoImpact) {
    impactLabel = 'Unknown';
  } else if (weakImpact || !clearSideSignal) {
    impactLabel = 'Center';
  } else if (clearSingleWindowPeakDominance) {
    impactLabel = toeWindowPeakRaw > heelWindowPeakRaw ? 'Toe' : 'Heel';
  } else if (bothWindowPeaksAbsolute && windowPeakDifference > 0.0) {
    impactLabel = toeWindowPeakRaw > heelWindowPeakRaw ? 'Toe' : 'Heel';
  } else if (clearSinglePeakDominance) {
    impactLabel = bestToeRawAtImpact > bestHeelRawAtImpact ? 'Toe' : 'Heel';
  } else if (bothPeaksAbsolute && peakDifference > 0.0) {
    impactLabel = bestToeRawAtImpact > bestHeelRawAtImpact ? 'Toe' : 'Heel';
  } else if (clearPeakDominance) {
    impactLabel = bestToeRawAtImpact > bestHeelRawAtImpact ? 'Toe' : 'Heel';
  } else if (averageDifference < _piezoContactAverageDelta ||
      relativeDifference < _piezoContactRelativeDeltaThreshold) {
    impactLabel = 'Center';
  } else {
    impactLabel = toeWindowAverage > heelWindowAverage ? 'Toe' : 'Heel';
  }

  if ((impactFound || confidentPiezoImpact) &&
      impactLabel == 'Center' &&
      bestAbsolutePeak >= _piezoImpactAbsoluteThreshold) {
    print(
      'Piezo center fallback: idx=$bestImpactIdx '
      'toeRaw=${bestToeRawAtImpact.toStringAsFixed(0)} '
      'heelRaw=${bestHeelRawAtImpact.toStringAsFixed(0)} '
      'globalIdx=$globalBestImpactIdx '
      'globalPeak=${globalBestAbsolutePeak.toStringAsFixed(0)} '
      'toePeak=${toeWindowPeakRaw.toStringAsFixed(0)} '
      'heelPeak=${heelWindowPeakRaw.toStringAsFixed(0)} '
      'toeAvg=${toeWindowAverage.toStringAsFixed(1)} '
      'heelAvg=${heelWindowAverage.toStringAsFixed(1)} '
      'windowPeakRel=${windowPeakRelativeDifference.toStringAsFixed(2)} '
      'peakRel=${peakRelativeDifference.toStringAsFixed(2)} '
      'avgRel=${relativeDifference.toStringAsFixed(2)}',
    );
  }

  return _PiezoResult(
    weakImpact: weakImpact,
    impactLabel: impactLabel,
    impactStrength: impactStrength,
    impactIdx: bestImpactIdx,
  );
}

class _MotionSegmentation {
  final int motionStartIdx;
  final int transitionIdx;

  const _MotionSegmentation({
    required this.motionStartIdx,
    required this.transitionIdx,
  });
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

_MotionSegmentation _segmentMotion(List<ImuSample> samples) {
  final n = samples.length;
  final gy = samples.map((s) => s.gy).toList();
  final motionStart = _findConsecutiveIndex(
    gy,
    start: 0,
    endInclusive: n - 1,
    predicate: (value) => value >= _backstrokeThresholdDps,
    requiredFrames: _motionConfirmFrames,
  );
  final transition = _findConsecutiveIndex(
    gy,
    start: max(0, motionStart),
    endInclusive: n - 1,
    predicate: (value) => value <= _forwardStrokeThresholdDps,
    requiredFrames: _motionConfirmFrames,
  );

  return _MotionSegmentation(
    motionStartIdx: motionStart < 0 ? 0 : motionStart,
    transitionIdx: transition < 0 ? max(0, n ~/ 2) : transition,
  );
}

class _AccelImpactResult {
  final int impactIdx;
  final bool found;

  const _AccelImpactResult({
    required this.impactIdx,
    required this.found,
  });
}

_AccelImpactResult _findAccelImpact(
  List<ImuSample> samples, {
  required int transitionIdx,
  required int packetImpactIdx,
}) {
  if (samples.isEmpty) {
    return const _AccelImpactResult(impactIdx: 0, found: false);
  }

  final start = transitionIdx.clamp(0, samples.length - 1);
  final end = _findConsecutiveIndex(
    samples.map((s) => s.gy).toList(growable: false),
    start: min(samples.length - 1, start + 1),
    endInclusive: samples.length - 1,
    predicate: (value) => value >= _followThroughEndThresholdDps,
    requiredFrames: _followThroughConfirmFrames,
  );
  final searchEnd = end < 0 ? (samples.length - 1) : max(start, end - 1);
  final window = samples.sublist(start, searchEnd + 1);
  if (window.isEmpty) {
    return _AccelImpactResult(
      impactIdx: packetImpactIdx.clamp(0, samples.length - 1),
      found: false,
    );
  }

  final meanAx = _mean(window.map((sample) => sample.ax).toList(growable: false));
  final meanAy = _mean(window.map((sample) => sample.ay).toList(growable: false));
  final meanAz = _mean(window.map((sample) => sample.az).toList(growable: false));
  final stdAx = max(0.05, _std(window.map((sample) => sample.ax).toList(growable: false)));
  final stdAy = max(0.05, _std(window.map((sample) => sample.ay).toList(growable: false)));
  final stdAz = max(0.05, _std(window.map((sample) => sample.az).toList(growable: false)));

  var bestIdx = packetImpactIdx.clamp(start, searchEnd);
  var bestScore = 0.0;
  var bestDelta = 0.0;

  for (var i = start; i <= searchEnd; i++) {
    final sample = samples[i];
    final dx = (sample.ax - meanAx).abs();
    final dy = (sample.ay - meanAy).abs();
    final dz = (sample.az - meanAz).abs();
    final score = max(dx / stdAx, max(dy / stdAy, dz / stdAz));
    final delta = max(dx, max(dy, dz));
    if (score > bestScore || (score == bestScore && delta > bestDelta)) {
      bestScore = score;
      bestDelta = delta;
      bestIdx = i;
    }
  }

  final found = bestScore >= _accelImpactMinScore && bestDelta >= _accelImpactMinDeltaG;
  return _AccelImpactResult(
    impactIdx: bestIdx,
    found: found,
  );
}

_SegmentationResult _segmentStroke(
  List<ImuSample> samples,
  int impactIdx, {
  required int motionStartIdx,
  required int transitionIdx,
}) {
  final n = samples.length;
  final gy = samples.map((s) => s.gy).toList();
  final followThroughEnd = _findConsecutiveIndex(
    gy,
    start: min(n - 1, impactIdx + 1),
    endInclusive: n - 1,
    predicate: (value) => value >= _followThroughEndThresholdDps,
    requiredFrames: _followThroughConfirmFrames,
  );

  final poorSegmentation =
      followThroughEnd < 0 ||
      motionStartIdx >= transitionIdx ||
      transitionIdx >= impactIdx ||
      impactIdx >= followThroughEnd;

  return _SegmentationResult(
    motionStartIdx: motionStartIdx,
    transitionIdx: transitionIdx,
    followThroughEndIdx: followThroughEnd < 0 ? (n - 1) : followThroughEnd,
    dominantGyroAxis: 1,
    gDomSeries: gy,
    poorSegmentation: poorSegmentation,
  );
}

int _findConsecutiveIndex(
  List<double> values, {
  required int start,
  required int endInclusive,
  required bool Function(double value) predicate,
  required int requiredFrames,
}) {
  if (values.isEmpty || start > endInclusive) {
    return -1;
  }

  var consecutive = 0;
  for (var i = max(0, start); i <= min(endInclusive, values.length - 1); i++) {
    if (predicate(values[i])) {
      consecutive++;
      if (consecutive >= requiredFrames) {
        return i - requiredFrames + 1;
      }
    } else {
      consecutive = 0;
    }
  }
  return -1;
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
  required int calibrationIdx,
  required int motionStartIdx,
  required int transitionIdx,
  required int impactIdx,
  required int followThroughEndIdx,
  required bool hasQuaternionData,
  required double imuHz,
}) {
  if (hasQuaternionData &&
      samples[calibrationIdx.clamp(0, samples.length - 1)].hasQuaternion &&
      samples[impactIdx].hasQuaternion) {
    final calibrationSample = samples[calibrationIdx.clamp(0, samples.length - 1)];
    final setupRollDeg = _rollFromQuaternion(calibrationSample);
    final impactRollDeg = _rollFromQuaternion(samples[impactIdx]);
    final changeDeg = _wrapDegrees180(impactRollDeg - setupRollDeg);

    final start = motionStartIdx.clamp(0, samples.length - 1);
    final end = followThroughEndIdx.clamp(start, samples.length - 1);
    final angles = <double>[];
    for (var i = start; i <= end; i++) {
      if (samples[i].hasQuaternion) {
        angles.add(
          _wrapDegrees180(_rollFromQuaternion(samples[i]) - setupRollDeg),
        );
      }
    }

    return _FaceMetrics(
      setupDeg: 0.0,
      impactDeg: changeDeg,
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
      sample.gy.abs(),
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
  required int transitionIdx,
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
    final transition = transitionIdx.clamp(motionStartIdx, impactIdx);
    var forwardVx = 0.0;
    var forwardVy = 0.0;
    var peakForwardHorizontalSpeed = 0.0;
    var axisX = 0.0;
    var axisY = 0.0;

    for (var i = transition; i <= impactIdx && i < samples.length; i++) {
      final s = samples[i];
      final q = _normalizedQuatFromSample(s);
      final aWorld = _rotateVectorByQuat([
        s.ax * _gravityMps2,
        s.ay * _gravityMps2,
        s.az * _gravityMps2,
      ], q);
      final ax = aWorld[0];
      final ay = aWorld[1];
      final azNoG = aWorld[2] - _gravityMps2;

      forwardVx += ax * dt;
      forwardVy += ay * dt;
      final horizontalSpeed = sqrt(forwardVx * forwardVx + forwardVy * forwardVy);
      if (horizontalSpeed > peakForwardHorizontalSpeed) {
        peakForwardHorizontalSpeed = horizontalSpeed;
        axisX = forwardVx / horizontalSpeed;
        axisY = forwardVy / horizontalSpeed;
      }

      if (azNoG.isNaN) {
        return 0.0;
      }
    }

    if (peakForwardHorizontalSpeed < 1e-6) {
      return 0.0;
    }

    var projectedBias = 0.0;
    if (motionStartIdx > 0) {
      var biasSamples = 0;
      for (var i = 0; i < motionStartIdx && i < samples.length; i++) {
        final s = samples[i];
        if (!s.hasQuaternion) {
          continue;
        }
        final q = _normalizedQuatFromSample(s);
        final aWorld = _rotateVectorByQuat([
          s.ax * _gravityMps2,
          s.ay * _gravityMps2,
          s.az * _gravityMps2,
        ], q);
        projectedBias += (aWorld[0] * axisX) + (aWorld[1] * axisY);
        biasSamples++;
      }
      if (biasSamples > 0) {
        projectedBias /= biasSamples;
      }
    }

    var projectedVelocity = 0.0;
    for (var i = motionStartIdx; i <= impactIdx && i < samples.length; i++) {
      final s = samples[i];
      final q = _normalizedQuatFromSample(s);
      final aWorld = _rotateVectorByQuat([
        s.ax * _gravityMps2,
        s.ay * _gravityMps2,
        s.az * _gravityMps2,
      ], q);
      final projectedAccel = ((aWorld[0] * axisX) + (aWorld[1] * axisY)) - projectedBias;
      projectedVelocity += projectedAccel * dt;
    }

    return projectedVelocity.abs();
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

double _rollFromQuaternion(ImuSample sample) {
  final q = _normalizedQuatFromSample(sample);
  return _orientationFromQuat(q).rollDeg;
}

class _OrientationAngles {
  final double yawDeg;
  final double pitchDeg;
  final double rollDeg;

  const _OrientationAngles({
    required this.yawDeg,
    required this.pitchDeg,
    required this.rollDeg,
  });
}

_OrientationAngles _orientationFromQuat(List<double> q) {
  final qi = q[0];
  final qj = q[1];
  final qk = q[2];
  final qr = q[3];
  final qi2 = qi * qi;
  final qj2 = qj * qj;
  final qk2 = qk * qk;
  final qr2 = qr * qr;
  final denom = qi2 + qj2 + qk2 + qr2;
  if (denom == 0.0) {
    return const _OrientationAngles(yawDeg: 0.0, pitchDeg: 0.0, rollDeg: 0.0);
  }

  final yawDeg = atan2(
        2.0 * (qi * qj + qk * qr),
        (qi2 - qj2 - qk2 + qr2),
      ) *
      180.0 /
      pi;
  final pitchDeg = asin(
        (-2.0 * (qi * qk - qj * qr) / denom).clamp(-1.0, 1.0),
      ) *
      180.0 /
      pi;
  final rollDeg = atan2(
        2.0 * (qj * qk + qi * qr),
        (-qi2 - qj2 + qk2 + qr2),
      ) *
      180.0 /
      pi;

  return _OrientationAngles(
    yawDeg: yawDeg,
    pitchDeg: pitchDeg,
    rollDeg: rollDeg,
  );
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
