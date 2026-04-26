import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'camera_bridge_service.dart';

class CameraLabPage extends StatefulWidget {
  const CameraLabPage({super.key});

  @override
  State<CameraLabPage> createState() => _CameraLabPageState();
}

class _CameraLabPageState extends State<CameraLabPage> {
  final CameraBridgeService _service = createCameraBridgeService();
  final ScrollController _logScrollController = ScrollController();

  final List<String> _logs = <String>[];
  CameraBridgeResult? _lastCaptureResult;
  String? _lastCalibrationPath;
  String? _statusMessage;
  String? _errorMessage;
  bool _isRunning = false;
  bool _showDebugFrames = true;
  int _selectedFrameIndex = 0;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _runAction(CameraBridgeAction action) async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _statusMessage = action.helperText;
      _logs
        ..clear()
        ..add('Starting ${action.label}...');
    });

    try {
      final result = await _service.runAction(
        action,
        onLog: _appendLog,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (result.calibrationPath != null &&
            result.calibrationPath!.isNotEmpty) {
          _lastCalibrationPath = result.calibrationPath;
        }
        if (action == CameraBridgeAction.capture && result.ok) {
          _lastCaptureResult = result;
          _selectedFrameIndex = 0;
          _showDebugFrames = true;
        }
        _statusMessage = result.message;
        _errorMessage = result.ok ? null : result.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _statusMessage = 'Camera bridge failed.';
      });
      _appendLog(error.toString());
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.add(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) {
        return;
      }
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openArtifact(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      await _service.openPath(path);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _stepFrame(int delta, int frameCount) {
    if (frameCount == 0) {
      return;
    }
    setState(() {
      final next = _selectedFrameIndex + delta;
      _selectedFrameIndex = next.clamp(0, frameCount - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final capture = _lastCaptureResult;
    final summary = capture?.summary;
    final calibrationPath = capture?.calibrationPath ?? _lastCalibrationPath;
    final selectedPaths = _showDebugFrames
        ? (capture?.debugFramePaths ?? const <String>[])
        : (capture?.framePaths ?? const <String>[]);
    final hasFrames = selectedPaths.isNotEmpty;
    final clampedIndex = hasFrames
        ? _selectedFrameIndex.clamp(0, selectedPaths.length - 1)
        : 0;
    final selectedFramePath = hasFrames ? selectedPaths[clampedIndex] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IntroCard(
                supported: _service.supported,
                platformMessage: _service.platformMessage,
                isRunning: _isRunning,
                onCapture: () => _runAction(CameraBridgeAction.capture),
                onCalibrate: () => _runAction(CameraBridgeAction.calibrate),
              ),
              if (_isRunning) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                _StatusCard(
                  title: _errorMessage == null ? 'Status' : 'Issue',
                  message: _errorMessage ?? _statusMessage!,
                  isError: _errorMessage != null,
                ),
              ],
              if (summary != null) ...[
                const SizedBox(height: 24),
                const _SectionLabel('Burst Stats'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(
                      title: 'Angle',
                      value: '${summary.angleDeg.toStringAsFixed(1)} deg',
                      subtitle: 'Average tracked line angle',
                    ),
                    _SummaryTile(
                      title: 'Velocity',
                      value: '${summary.peakVelocityMph.toStringAsFixed(2)} mph',
                      subtitle:
                          'Avg ${summary.avgVelocityMph.toStringAsFixed(2)} mph',
                    ),
                    _SummaryTile(
                      title: 'Rotation',
                      value: '${summary.rotationRateDegS.toStringAsFixed(1)} deg/s',
                      subtitle: summary.wobbleDetected
                          ? 'Wobble ${summary.wobbleMagnitudeDeg.toStringAsFixed(1)} deg'
                          : 'No wobble',
                    ),
                    _SummaryTile(
                      title: 'Frames',
                      value: '${summary.validFrames}/${summary.totalFrames}',
                      subtitle:
                          '${summary.frameCount} captured @ ${summary.fpsEstimate.toStringAsFixed(1)} fps',
                    ),
                    _SummaryTile(
                      title: 'Detection',
                      value: '${(summary.detectionRate * 100).toStringAsFixed(0)}%',
                      subtitle: 'Ball tracked',
                    ),
                    _SummaryTile(
                      title: 'Roll Distance',
                      value:
                          '${summary.totalRollDistanceIn.toStringAsFixed(2)} in',
                      subtitle:
                          'Peak ${summary.peakVelocityBallPerS.toStringAsFixed(2)} ball/s',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              _FrameViewerCard(
                hasFrames: hasFrames,
                showDebugFrames: _showDebugFrames,
                selectedIndex: clampedIndex,
                frameCount: selectedPaths.length,
                selectedFramePath: selectedFramePath,
                readBytes: _service.readBytes,
                onSelectDebug: () {
                  setState(() {
                    _showDebugFrames = true;
                  });
                },
                onSelectOriginal: () {
                  setState(() {
                    _showDebugFrames = false;
                  });
                },
                onPrevious: () => _stepFrame(-1, selectedPaths.length),
                onNext: () => _stepFrame(1, selectedPaths.length),
                onCalibrate: _isRunning
                    ? null
                    : () => _runAction(CameraBridgeAction.calibrate),
              ),
              if (capture != null || calibrationPath != null) ...[
                const SizedBox(height: 24),
                const _SectionLabel('Artifacts'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _ArtifactButton(
                      label: 'Slow-Mo Video',
                      icon: Icons.slow_motion_video_outlined,
                      enabled: capture?.videoPath != null,
                      onPressed: () => _openArtifact(capture?.videoPath),
                    ),
                    _ArtifactButton(
                      label: 'Debug Frames',
                      icon: Icons.bug_report_outlined,
                      enabled: capture?.debugFramesDirectory != null,
                      onPressed: () =>
                          _openArtifact(capture?.debugFramesDirectory),
                    ),
                    _ArtifactButton(
                      label: 'Original Frames',
                      icon: Icons.image_outlined,
                      enabled: capture?.framesDirectory != null,
                      onPressed: () => _openArtifact(capture?.framesDirectory),
                    ),
                    _ArtifactButton(
                      label: 'Run Folder',
                      icon: Icons.folder_open_outlined,
                      enabled: capture?.runDirectory != null,
                      onPressed: () => _openArtifact(capture?.runDirectory),
                    ),
                    _ArtifactButton(
                      label: 'Result JSON',
                      icon: Icons.data_object_outlined,
                      enabled: capture?.resultJsonPath != null,
                      onPressed: () => _openArtifact(capture?.resultJsonPath),
                    ),
                    _ArtifactButton(
                      label: 'Calibration File',
                      icon: Icons.tune_outlined,
                      enabled: calibrationPath != null,
                      onPressed: () => _openArtifact(calibrationPath),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const _SectionLabel('Bridge Log'),
              const SizedBox(height: 12),
              _LogCard(
                controller: _logScrollController,
                lines: _logs,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.supported,
    required this.platformMessage,
    required this.isRunning,
    required this.onCapture,
    required this.onCalibrate,
  });

  final bool supported;
  final String platformMessage;
  final bool isRunning;
  final VoidCallback onCapture;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Burst camera workflow',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'This page uses the local Python bridge to calibrate lighting, trigger the ESP32 burst capture, analyze the roll, and inspect the tracked frames.',
          ),
          const SizedBox(height: 8),
          Text(
            supported
                ? 'Prereqs: connect this PC to OV5640-Burst, keep Python/OpenCV installed, and recalibrate when lighting or camera distance changes.'
                : platformMessage,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: supported && !isRunning ? onCapture : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Capture + Analyze'),
              ),
              OutlinedButton.icon(
                onPressed: supported && !isRunning ? onCalibrate : null,
                icon: const Icon(Icons.tune),
                label: const Text('Calibrate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FrameViewerCard extends StatelessWidget {
  const _FrameViewerCard({
    required this.hasFrames,
    required this.showDebugFrames,
    required this.selectedIndex,
    required this.frameCount,
    required this.selectedFramePath,
    required this.readBytes,
    required this.onSelectDebug,
    required this.onSelectOriginal,
    required this.onPrevious,
    required this.onNext,
    required this.onCalibrate,
  });

  final bool hasFrames;
  final bool showDebugFrames;
  final int selectedIndex;
  final int frameCount;
  final String? selectedFramePath;
  final Future<Uint8List> Function(String path) readBytes;
  final VoidCallback onSelectDebug;
  final VoidCallback onSelectOriginal;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onCalibrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frame Review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Tracked Frame'),
                selected: showDebugFrames,
                onSelected: (_) => onSelectDebug(),
              ),
              ChoiceChip(
                label: const Text('Original Frame'),
                selected: !showDebugFrames,
                onSelected: (_) => onSelectOriginal(),
              ),
              OutlinedButton.icon(
                onPressed: onCalibrate,
                icon: const Icon(Icons.tune),
                label: const Text('Recalibrate'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasFrames)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6E8EC)),
              ),
              child: const Text(
                'No analyzed burst frames yet. Run Capture + Analyze to populate the viewer.',
              ),
            )
          else ...[
            Row(
              children: [
                Text(
                  'Frame ${selectedIndex + 1} of $frameCount',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: selectedIndex > 0 ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed: selectedIndex + 1 < frameCount ? onNext : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 280),
                color: const Color(0xFF0F172A),
                child: FutureBuilder<Uint8List>(
                  future: readBytes(selectedFramePath!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error?.toString() ?? 'Failed to load frame.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.message,
    required this.isError,
  });

  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF1F0) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isError ? const Color(0xFFFFCCC7) : const Color(0xFFE6E8EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isError ? const Color(0xFFB42318) : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(message),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}

class _ArtifactButton extends StatelessWidget {
  const _ArtifactButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.controller,
    required this.lines,
  });

  final ScrollController controller;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = lines.isEmpty ? 'No bridge output yet.' : lines.join('\n');
    return Container(
      width: double.infinity,
      height: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          child: SelectableText(
            text,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontFamily: 'Courier',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
