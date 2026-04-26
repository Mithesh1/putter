import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'camera_bridge_models.dart';
import 'camera_bridge_service_base.dart';

const _resultPrefix = 'CAMERA_BRIDGE_RESULT=';

CameraBridgeService createCameraBridgeService() => DesktopCameraBridgeService();

class DesktopCameraBridgeService implements CameraBridgeService {
  DesktopCameraBridgeService();

  _PythonCommand? _cachedPythonCommand;
  Directory? _cachedFrontendRoot;

  @override
  bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  String get platformMessage => supported
      ? 'Local desktop bridge available.'
      : 'Camera bridge is only available on desktop builds.';

  @override
  Future<void> openPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw StateError('No artifact path is available.');
    }

    final exists =
        await FileSystemEntity.type(trimmed) != FileSystemEntityType.notFound;
    if (!exists) {
      throw StateError('Artifact path not found: $trimmed');
    }

    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', trimmed], runInShell: true);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [trimmed]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [trimmed]);
      return;
    }

    throw UnsupportedError(platformMessage);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw StateError('No image path is available.');
    }

    final file = File(trimmed);
    if (!await file.exists()) {
      throw StateError('Image path not found: $trimmed');
    }

    return file.readAsBytes();
  }

  @override
  Future<CameraBridgeResult> runAction(
    CameraBridgeAction action, {
    CameraLogSink? onLog,
  }) async {
    if (!supported) {
      throw UnsupportedError(platformMessage);
    }

    final frontendRoot = await _resolveFrontendRoot();
    final scriptPath = p.join(frontendRoot.path, 'tool', 'camera_bridge.py');
    final python = await _resolvePythonCommand();
    final args = <String>[
      ...python.prefixArgs,
      scriptPath,
      action.cliName,
    ];

    onLog?.call('Running ${action.label}...');

    final process = await Process.start(
      python.executable,
      args,
      workingDirectory: frontendRoot.path,
    );

    final stderrLines = <String>[];
    final stdoutLines = <String>[];
    String? payloadLine;

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.startsWith(_resultPrefix)) {
            payloadLine = line.substring(_resultPrefix.length);
            return;
          }
          stdoutLines.add(line);
          onLog?.call(line);
        });

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          stderrLines.add(line);
          onLog?.call(line);
        });

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (payloadLine == null) {
      final combined = [...stderrLines, ...stdoutLines]
          .where((line) => line.trim().isNotEmpty)
          .join('\n');
      if (combined.isNotEmpty) {
        throw StateError(combined);
      }
      throw StateError(
        'Camera bridge exited with code $exitCode without returning a result.',
      );
    }

    final decoded = jsonDecode(payloadLine!) as Map<String, dynamic>;
    return CameraBridgeResult.fromJson(decoded);
  }

  Future<Directory> _resolveFrontendRoot() async {
    if (_cachedFrontendRoot != null) {
      return _cachedFrontendRoot!;
    }

    final seen = <String>{};
    final candidates = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final candidate in candidates) {
      Directory? cursor = candidate;
      while (cursor != null && seen.add(cursor.path)) {
        final hasPubspec = File(p.join(cursor.path, 'pubspec.yaml')).existsSync();
        final hasBridge = File(
          p.join(cursor.path, 'tool', 'camera_bridge.py'),
        ).existsSync();
        if (hasPubspec && hasBridge) {
          _cachedFrontendRoot = cursor;
          return cursor;
        }
        final parent = cursor.parent;
        if (parent.path == cursor.path) {
          break;
        }
        cursor = parent;
      }
    }

    throw StateError(
      'Could not locate the frontend project root containing tool/camera_bridge.py.',
    );
  }

  Future<_PythonCommand> _resolvePythonCommand() async {
    if (_cachedPythonCommand != null) {
      return _cachedPythonCommand!;
    }

    final candidates = Platform.isWindows
        ? const <_PythonCommand>[
            _PythonCommand('py', ['-3']),
            _PythonCommand('python'),
          ]
        : const <_PythonCommand>[
            _PythonCommand('python3'),
            _PythonCommand('python'),
          ];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate.executable,
          [...candidate.prefixArgs, '--version'],
        );
        if (result.exitCode == 0) {
          _cachedPythonCommand = candidate;
          return candidate;
        }
      } catch (_) {
        continue;
      }
    }

    throw StateError(
      'Python 3 was not found. Install Python and ensure it is available on PATH.',
    );
  }
}

class _PythonCommand {
  const _PythonCommand(this.executable, [this.prefixArgs = const []]);

  final String executable;
  final List<String> prefixArgs;
}
