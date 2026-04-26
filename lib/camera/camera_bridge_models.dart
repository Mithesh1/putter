class CameraRunSummary {
  const CameraRunSummary({
    required this.frameCount,
    required this.preTriggerFrames,
    required this.fpsEstimate,
    required this.finishReason,
    required this.angleDeg,
    required this.validFrames,
    required this.totalFrames,
    required this.detectionRate,
    required this.rotationRateDegS,
    required this.wobbleDetected,
    required this.wobbleMagnitudeDeg,
    required this.avgVelocityMph,
    required this.peakVelocityMph,
    required this.avgVelocityBallPerS,
    required this.peakVelocityBallPerS,
    required this.totalRollDistanceIn,
  });

  final int frameCount;
  final int preTriggerFrames;
  final double fpsEstimate;
  final String finishReason;
  final double angleDeg;
  final int validFrames;
  final int totalFrames;
  final double detectionRate;
  final double rotationRateDegS;
  final bool wobbleDetected;
  final double wobbleMagnitudeDeg;
  final double avgVelocityMph;
  final double peakVelocityMph;
  final double avgVelocityBallPerS;
  final double peakVelocityBallPerS;
  final double totalRollDistanceIn;

  factory CameraRunSummary.fromJson(Map<String, dynamic> json) {
    return CameraRunSummary(
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      preTriggerFrames: (json['preTriggerFrames'] as num?)?.toInt() ?? 0,
      fpsEstimate: (json['fpsEstimate'] as num?)?.toDouble() ?? 0,
      finishReason: json['finishReason'] as String? ?? 'unknown',
      angleDeg: (json['angleDeg'] as num?)?.toDouble() ?? 0,
      validFrames: (json['validFrames'] as num?)?.toInt() ?? 0,
      totalFrames: (json['totalFrames'] as num?)?.toInt() ?? 0,
      detectionRate: (json['detectionRate'] as num?)?.toDouble() ?? 0,
      rotationRateDegS: (json['rotationRateDegS'] as num?)?.toDouble() ?? 0,
      wobbleDetected: json['wobbleDetected'] as bool? ?? false,
      wobbleMagnitudeDeg: (json['wobbleMagnitudeDeg'] as num?)?.toDouble() ?? 0,
      avgVelocityMph: (json['avgVelocityMph'] as num?)?.toDouble() ?? 0,
      peakVelocityMph: (json['peakVelocityMph'] as num?)?.toDouble() ?? 0,
      avgVelocityBallPerS: (json['avgVelocityBallPerS'] as num?)?.toDouble() ?? 0,
      peakVelocityBallPerS: (json['peakVelocityBallPerS'] as num?)?.toDouble() ?? 0,
      totalRollDistanceIn: (json['totalRollDistanceIn'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CameraBridgeResult {
  const CameraBridgeResult({
    required this.ok,
    required this.action,
    required this.message,
    required this.runDirectory,
    required this.framesDirectory,
    required this.debugFramesDirectory,
    required this.videoPath,
    required this.calibrationPath,
    required this.resultJsonPath,
    required this.summary,
    required this.framePaths,
    required this.debugFramePaths,
  });

  final bool ok;
  final String action;
  final String message;
  final String? runDirectory;
  final String? framesDirectory;
  final String? debugFramesDirectory;
  final String? videoPath;
  final String? calibrationPath;
  final String? resultJsonPath;
  final CameraRunSummary? summary;
  final List<String> framePaths;
  final List<String> debugFramePaths;

  factory CameraBridgeResult.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(Object? value) {
      if (value is! List) {
        return const [];
      }
      return value.map((entry) => entry.toString()).toList(growable: false);
    }

    return CameraBridgeResult(
      ok: json['ok'] as bool? ?? false,
      action: json['action'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      runDirectory: json['runDirectory'] as String?,
      framesDirectory: json['framesDirectory'] as String?,
      debugFramesDirectory: json['debugFramesDirectory'] as String?,
      videoPath: json['videoPath'] as String?,
      calibrationPath: json['calibrationPath'] as String?,
      resultJsonPath: json['resultJsonPath'] as String?,
      summary: json['summary'] is Map<String, dynamic>
          ? CameraRunSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
      framePaths: parseStringList(json['framePaths']),
      debugFramePaths: parseStringList(json['debugFramePaths']),
    );
  }
}
