import 'dart:async';

import 'package:designcode/camera/camera_bridge_service.dart';
import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/main.dart' as base;
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/services/app_controller.dart';
import 'package:designcode/services/ble_service.dart';
import 'package:designcode/services/ble_transport.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_lab_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DualFrontendApp());
}

class DualFrontendApp extends StatefulWidget {
  const DualFrontendApp({super.key});

  @override
  State<DualFrontendApp> createState() => _DualFrontendAppState();
}

class _DualFrontendAppState extends State<DualFrontendApp> {
  late final db.AppDatabase _database;
  late final SessionRepository _repository;
  late final AppController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _database = db.AppDatabase();
    _repository = SessionRepository(database: _database);
    _controller = createDefaultAppController(
      repository: _repository,
      syncService: DisabledSyncService(),
      realTransport: BleService(),
    );
    _initialization = _controller.initialize();
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    unawaited(_database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dual_frontend',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        useMaterial3: true,
      ),
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to initialize dual_frontend:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return DualFrontendScaffold(controller: _controller);
        },
      ),
    );
  }
}

class DualFrontendScaffold extends StatefulWidget {
  const DualFrontendScaffold({super.key, required this.controller});

  final AppController controller;

  @override
  State<DualFrontendScaffold> createState() => _DualFrontendScaffoldState();
}

class _DualFrontendScaffoldState extends State<DualFrontendScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DualControlPage(controller: widget.controller),
      base.DashboardPage(controller: widget.controller),
      base.SessionPage(controller: widget.controller),
      base.TrendsPage(controller: widget.controller),
      const CameraLabPage(),
      base.SettingsPage(controller: widget.controller),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Dual',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_golf_outlined),
            selectedIcon: Icon(Icons.sports_golf),
            label: 'Session',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Trends',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_camera_outlined),
            selectedIcon: Icon(Icons.photo_camera),
            label: 'Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DualControlPage extends StatefulWidget {
  const DualControlPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<DualControlPage> createState() => _DualControlPageState();
}

class _DualControlPageState extends State<DualControlPage> {
  final CameraBridgeService _cameraBridge = createCameraBridgeService();
  final List<String> _cameraLogs = <String>[];
  final ScrollController _cameraLogScrollController = ScrollController();

  CameraBridgeResult? _lastCameraResult;
  bool _combinedTriggerRunning = false;
  String? _combinedTriggerStatus;

  @override
  void dispose() {
    _cameraLogScrollController.dispose();
    super.dispose();
  }

  Future<void> _runCombinedTrigger() async {
    if (_combinedTriggerRunning) {
      return;
    }

    setState(() {
      _combinedTriggerRunning = true;
      _combinedTriggerStatus =
          'Starting dual trigger. This currently starts the putter session and camera burst workflow.';
      _cameraLogs
        ..clear()
        ..add('Dual trigger requested via space bar.');
    });

    try {
      await widget.controller.startSession();
      _appendCameraLog(
        'Putter session is active. BLE arming still depends on firmware support.',
      );

      final result = await _cameraBridge.runAction(
        CameraBridgeAction.capture,
        onLog: _appendCameraLog,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastCameraResult = result;
        _combinedTriggerStatus = result.ok
            ? 'Camera burst completed. Review combined data below.'
            : result.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _combinedTriggerStatus = 'Dual trigger failed: $error';
      });
      _appendCameraLog(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _combinedTriggerRunning = false;
        });
      }
    }
  }

  void _appendCameraLog(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraLogs.add(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_cameraLogScrollController.hasClients) {
        return;
      }
      _cameraLogScrollController.animateTo(
        _cameraLogScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _lastCameraResult?.summary;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): _runCombinedTrigger,
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: StreamBuilder<BleConnectionState>(
            stream: widget.controller.watchConnectionState(),
            initialData: widget.controller.connectionState,
            builder: (context, connectionSnapshot) {
              return StreamBuilder<String>(
                stream: widget.controller.watchLivePuttState(),
                initialData: widget.controller.livePuttState,
                builder: (context, liveStateSnapshot) {
                  return StreamBuilder<PracticeSession?>(
                    stream: widget.controller.watchActiveSession(),
                    builder: (context, sessionSnapshot) {
                      final connectionState =
                          connectionSnapshot.data ?? widget.controller.connectionState;
                      final liveState =
                          liveStateSnapshot.data ?? widget.controller.livePuttState;
                      final activeSession = sessionSnapshot.data;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'dual_frontend',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mac-hosted control surface for separate putter and camera ESP32 devices. Press space to run the current combined trigger flow.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _DeviceStatusCard(
                                    title: 'Putter Device',
                                    icon: Icons.bluetooth_connected,
                                    status: _connectionLabel(connectionState),
                                    detail: activeSession == null
                                        ? 'No active session yet'
                                        : 'Session ${activeSession.wireSessionId} active',
                                    accent: connectionState ==
                                            BleConnectionState.connected
                                        ? const Color(0xFF0B6E4F)
                                        : const Color(0xFF9E9E9E),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _DeviceStatusCard(
                                    title: 'Camera Device',
                                    icon: Icons.wifi_tethering,
                                    status: _combinedTriggerRunning
                                        ? 'Capture running'
                                        : (_lastCameraResult == null
                                              ? 'Idle'
                                              : 'Last capture ready'),
                                    detail: _cameraBridge.platformMessage,
                                    accent: _combinedTriggerRunning
                                        ? const Color(0xFF1565C0)
                                        : const Color(0xFF546E7A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _PrimaryActionCard(
                              isRunning: _combinedTriggerRunning,
                              liveState: liveState,
                              statusMessage: _combinedTriggerStatus,
                              onPressed: _runCombinedTrigger,
                            ),
                            const SizedBox(height: 20),
                            if (summary != null)
                              _CameraSummaryCard(summary: summary),
                            if (summary != null) const SizedBox(height: 20),
                            _CameraLogCard(
                              logs: _cameraLogs,
                              controller: _cameraLogScrollController,
                            ),
                            const SizedBox(height: 20),
                            _DiagnosticsMirror(controller: widget.controller),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({
    required this.title,
    required this.icon,
    required this.status,
    required this.detail,
    required this.accent,
  });

  final String title;
  final IconData icon;
  final String status;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.isRunning,
    required this.liveState,
    required this.statusMessage,
    required this.onPressed,
  });

  final bool isRunning;
  final String liveState;
  final String? statusMessage;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B6E4F), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Combined Trigger',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Space bar runs the current combined flow. Right now that means starting the putter session and launching the camera burst workflow from the Mac.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isRunning ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B6E4F),
                ),
                icon: Icon(isRunning ? Icons.sync : Icons.play_arrow),
                label: Text(isRunning ? 'Running...' : 'Run Combined Trigger'),
              ),
              Chip(
                label: Text('Live putt state: $liveState'),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                labelStyle: const TextStyle(color: Colors.white),
              ),
              const Chip(
                label: Text('Shortcut: Space'),
                backgroundColor: Color(0x26FFFFFF),
                labelStyle: TextStyle(color: Colors.white),
              ),
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              statusMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraSummaryCard extends StatelessWidget {
  const _CameraSummaryCard({required this.summary});

  final CameraRunSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = <({String title, String value, String subtitle})>[
      (
        title: 'Frames',
        value: '${summary.frameCount}',
        subtitle: '${summary.fpsEstimate.toStringAsFixed(1)} fps'
      ),
      (
        title: 'Detection',
        value: '${(summary.detectionRate * 100).toStringAsFixed(0)}%',
        subtitle: '${summary.validFrames}/${summary.totalFrames} valid'
      ),
      (
        title: 'Angle',
        value: '${summary.angleDeg.toStringAsFixed(1)} deg',
        subtitle: summary.finishReason
      ),
      (
        title: 'Peak Speed',
        value: '${summary.peakVelocityMph.toStringAsFixed(2)} mph',
        subtitle: '${summary.totalRollDistanceIn.toStringAsFixed(2)} in roll'
      ),
    ];

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
          Text(
            'Latest Camera Summary',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: tiles
                .map(
                  (tile) => SizedBox(
                    width: 180,
                    child: _SummaryTile(
                      title: tile.title,
                      value: tile.value,
                      subtitle: tile.subtitle,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CameraLogCard extends StatelessWidget {
  const _CameraLogCard({required this.logs, required this.controller});

  final List<String> logs;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101418),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera Bridge Log',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ListView.builder(
              controller: controller,
              itemCount: logs.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  logs[index],
                  style: const TextStyle(
                    color: Color(0xFFE0F2F1),
                    fontFamily: 'Menlo',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsMirror extends StatelessWidget {
  const _DiagnosticsMirror({required this.controller});

  final AppController controller;

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
          Text(
            'Putter Diagnostics',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: StreamBuilder<String>(
              stream: controller.watchDiagnostics(),
              builder: (context, snapshot) {
                return ListView(
                  children: [
                    Text(
                      snapshot.data ??
                          'Waiting for BLE diagnostics from the putter device.',
                      style: const TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _connectionLabel(BleConnectionState state) {
  return switch (state) {
    BleConnectionState.connected => 'Connected',
    BleConnectionState.connecting => 'Connecting',
    BleConnectionState.scanning => 'Scanning',
    BleConnectionState.disconnected => 'Disconnected',
  };
}
