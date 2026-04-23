import 'dart:async';

import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/services/app_controller.dart';
import 'package:designcode/services/ble_service.dart';
import 'package:designcode/services/ble_transport.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PutterApp());
}

class PutterApp extends StatefulWidget {
  const PutterApp({super.key});

  @override
  State<PutterApp> createState() => _PutterAppState();
}

class _PutterAppState extends State<PutterApp> {
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
      title: 'PutterIQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
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
                    'Failed to initialize app:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return AppScaffold(controller: _controller);
        },
      ),
    );
  }
}

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(controller: widget.controller),
      SessionPage(controller: widget.controller),
      TrendsPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoredStroke?>(
      stream: controller.watchLatestStroke(),
      builder: (context, latestSnapshot) {
        final latestStroke = latestSnapshot.data;
        return StreamBuilder<PracticeSession?>(
          stream: controller.watchActiveSession(),
          builder: (context, sessionSnapshot) {
            final activeSession = sessionSnapshot.data;
            return StreamBuilder<BleConnectionState>(
              stream: controller.watchConnectionState(),
              initialData: controller.connectionState,
              builder: (context, connectionSnapshot) {
                return StreamBuilder<String>(
                  stream: controller.watchSyncStatus(),
                  initialData: 'Cloud sync disabled',
                  builder: (context, syncSnapshot) {
                    final metrics = [
                      MetricCardData(
                        title: 'Face Angle',
                        value:
                            latestStroke?.metrics.faceAngleLabel ?? 'No data',
                        subtitle: latestStroke == null
                            ? 'Waiting for stroke'
                            : 'Last putt',
                        icon: Icons.track_changes,
                      ),
                      MetricCardData(
                        title: 'Tempo',
                        value: latestStroke?.metrics.tempoLabel ?? 'No data',
                        subtitle: 'Back / through',
                        icon: Icons.timelapse,
                      ),
                      MetricCardData(
                        title: 'Impact',
                        value: latestStroke?.metrics.impact ?? 'No data',
                        subtitle: 'Contact location',
                        icon: Icons.center_focus_strong,
                      ),
                      MetricCardData(
                        title: 'Ball Roll',
                        value:
                            latestStroke?.metrics.rollStatus ?? 'Unavailable',
                        subtitle: 'Camera data not in v1',
                        icon: Icons.circle_outlined,
                      ),
                    ];

                    return SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HeaderSection(),
                            const SizedBox(height: 20),
                            LiveStatusCard(
                              connectionState:
                                  connectionSnapshot.data ??
                                  controller.connectionState,
                              transportName: controller.transportName,
                              activeSession: activeSession,
                              syncStatus:
                                  syncSnapshot.data ?? 'Cloud sync disabled',
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Last Putt Snapshot',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GridView.builder(
                              itemCount: metrics.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 1.18,
                                  ),
                              itemBuilder: (context, index) =>
                                  MetricCard(data: metrics[index]),
                            ),
                            const SizedBox(height: 24),
                            const SectionTitle(title: 'Session Summary'),
                            const SizedBox(height: 12),
                            SummaryCard(
                              activeSession: activeSession,
                              latestStroke: latestStroke,
                            ),
                            const SizedBox(height: 24),
                            const SectionTitle(title: 'Coach Notes'),
                            const SizedBox(height: 12),
                            CoachNotesCard(latestStroke: latestStroke),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class SessionPage extends StatelessWidget {
  const SessionPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PracticeSession?>(
      stream: controller.watchActiveSession(),
      builder: (context, sessionSnapshot) {
        final activeSession = sessionSnapshot.data;
        final sessionDetailStream = activeSession?.localId == null
            ? const Stream<SessionDetail?>.empty()
            : controller.watchSessionDetail(activeSession!.localId!);

        return StreamBuilder<SessionDetail?>(
          stream: sessionDetailStream,
          builder: (context, detailSnapshot) {
            final detail = detailSnapshot.data;
            final strokes =
                detail?.strokes.reversed.toList(growable: false) ??
                const <StoredStroke>[];
            final centerHits = strokes
                .where((stroke) => stroke.metrics.impact == 'Center')
                .length;
            final centerHitRate = strokes.isEmpty
                ? 0.0
                : (centerHits / strokes.length) * 100;
            final averageTempo = strokes.isEmpty
                ? 0.0
                : strokes
                          .map((stroke) => stroke.metrics.tempoRatio)
                          .reduce((a, b) => a + b) /
                      strokes.length;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Practice Session',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeSession == null
                          ? 'No session running'
                          : 'Session ${activeSession.wireSessionId} • ${strokes.length} stored stroke(s)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          MiniStat(title: 'Putts', value: '${strokes.length}'),
                          MiniStat(
                            title: 'Center Hits',
                            value: '${centerHitRate.toStringAsFixed(0)}%',
                          ),
                          MiniStat(
                            title: 'Avg Tempo',
                            value: averageTempo == 0
                                ? '--'
                                : averageTempo.toStringAsFixed(2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              if (activeSession == null) {
                                await controller.startSession();
                              } else {
                                await controller.endSession();
                              }
                            },
                            icon: Icon(
                              activeSession == null
                                  ? Icons.play_arrow
                                  : Icons.stop,
                            ),
                            label: Text(
                              activeSession == null
                                  ? 'Start Session'
                                  : 'End Session',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => controller.reconnect(),
                            icon: const Icon(Icons.bluetooth_searching),
                            label: const Text('Reconnect'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Recent Stroke Feed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: strokes.isEmpty
                          ? const EmptyStateCard(
                              title: 'No strokes yet',
                              subtitle:
                                  'Start a session to let the mock BLE pipeline stream fragmented strokes into the app.',
                            )
                          : ListView.separated(
                              itemCount: strokes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  StrokeListItem(stroke: strokes[index]),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class TrendsPage extends StatelessWidget {
  const TrendsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trends',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Live trend lines from stored strokes and app-computed metrics',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            const SectionTitle(title: 'Face Angle Consistency'),
            const SizedBox(height: 12),
            TrendChart(
              stream: controller.watchTrendSeries(
                'faceAngle',
                const Duration(days: 7),
              ),
              highlightColor: const Color(0xFF1B5E20),
            ),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Stroke Speed'),
            const SizedBox(height: 12),
            TrendChart(
              stream: controller.watchTrendSeries(
                'speed',
                const Duration(days: 7),
              ),
              highlightColor: const Color(0xFF1565C0),
            ),
            const SizedBox(height: 24),
            const SectionTitle(title: 'Center-Hit Rate'),
            const SizedBox(height: 12),
            TrendChart(
              stream: controller.watchTrendSeries(
                'centerHitRate',
                const Duration(days: 7),
              ),
              highlightColor: const Color(0xFF2E7D32),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PracticeSession>>(
      stream: controller.watchSessionHistory(),
      builder: (context, historySnapshot) {
        return StreamBuilder<BleConnectionState>(
          stream: controller.watchConnectionState(),
          initialData: controller.connectionState,
          builder: (context, connectionSnapshot) {
            return StreamBuilder<String>(
              stream: controller.watchSyncStatus(),
              initialData: 'Cloud sync disabled',
              builder: (context, syncSnapshot) {
                return StreamBuilder<String>(
                  stream: controller.watchDiagnostics(),
                  builder: (context, diagnosticsSnapshot) {
                    return SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Transport mode',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<TransportMode>(
                            segments: const [
                              ButtonSegment(
                                value: TransportMode.mock,
                                label: Text('Mock BLE'),
                                icon: Icon(Icons.memory),
                              ),
                              ButtonSegment(
                                value: TransportMode.real,
                                label: Text('Real BLE'),
                                icon: Icon(Icons.bluetooth),
                              ),
                            ],
                            selected: <TransportMode>{controller.transportMode},
                            onSelectionChanged: (selection) {
                              controller.setTransportMode(selection.first);
                            },
                          ),
                          const SizedBox(height: 18),
                          SettingsCard(
                            icon: Icons.bluetooth,
                            title: 'Bluetooth Device',
                            subtitle:
                                '${controller.transportName} • ${_connectionLabel(connectionSnapshot.data ?? controller.connectionState)}',
                          ),
                          const SizedBox(height: 10),
                          SettingsCard(
                            icon: Icons.cloud_outlined,
                            title: 'Cloud Sync',
                            subtitle:
                                syncSnapshot.data ?? 'Cloud sync disabled',
                          ),
                          const SizedBox(height: 10),
                          SettingsCard(
                            icon: Icons.storage_outlined,
                            title: 'Local Storage',
                            subtitle:
                                '${historySnapshot.data?.length ?? 0} persisted session(s) available offline',
                          ),
                          const SizedBox(height: 10),
                          SettingsCard(
                            icon: Icons.code_outlined,
                            title: 'Developer Note',
                            subtitle:
                                diagnosticsSnapshot.data ??
                                'Mock transport is exercising reassembly, parsing, processing, and persistence.',
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class HeaderSection extends StatelessWidget {
  const HeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.sports_golf, color: Color(0xFF1B5E20)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PutterIQ',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              Text('Sensor-integrated putting analytics'),
            ],
          ),
        ),
        Icon(Icons.notifications_none, color: Colors.grey.shade700),
      ],
    );
  }
}

class LiveStatusCard extends StatelessWidget {
  const LiveStatusCard({
    super.key,
    required this.connectionState,
    required this.transportName,
    required this.activeSession,
    required this.syncStatus,
  });

  final BleConnectionState connectionState;
  final String transportName;
  final PracticeSession? activeSession;
  final String syncStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Device Status',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                connectionState == BleConnectionState.connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _connectionLabel(connectionState),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$transportName • ${activeSession == null ? 'No active session' : 'Session ${activeSession!.wireSessionId}'} • $syncStatus',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class MetricCardData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const MetricCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.data});

  final MetricCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          Icon(data.icon, size: 28, color: const Color(0xFF1B5E20)),
          const Spacer(),
          Text(
            data.title,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            data.value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.activeSession,
    required this.latestStroke,
  });

  final PracticeSession? activeSession;
  final StoredStroke? latestStroke;

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
            activeSession == null
                ? 'No active session'
                : 'Session ${activeSession!.wireSessionId}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SummaryPill(
                  label: 'Putts',
                  value: '${activeSession?.strokeCount ?? 0}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SummaryPill(
                  label: 'Avg Face',
                  value: latestStroke == null
                      ? '--'
                      : '${latestStroke!.metrics.faceAngleDeg.abs().toStringAsFixed(1)}°',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SummaryPill(
                  label: 'Impact',
                  value: latestStroke?.metrics.impact ?? '--',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryPill extends StatelessWidget {
  const SummaryPill({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class CoachNotesCard extends StatelessWidget {
  const CoachNotesCard({super.key, required this.latestStroke});

  final StoredStroke? latestStroke;

  @override
  Widget build(BuildContext context) {
    final note = latestStroke == null
        ? 'Start a session to let the raw BLE packet pipeline produce real app-computed metrics.'
        : latestStroke!.metrics.qualityFlags.poorSegmentation
        ? 'Segmentation quality was low on the last stroke, so tempo and timing should be treated cautiously.'
        : 'Latest stroke processed successfully from raw IMU and piezo data. Ball-roll remains unavailable until camera data is added.';

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
      child: Text(note, style: const TextStyle(fontSize: 15, height: 1.45)),
    );
  }
}

class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class StrokeListItem extends StatelessWidget {
  const StrokeListItem({super.key, required this.stroke});

  final StoredStroke stroke;

  @override
  Widget build(BuildContext context) {
    final metrics = stroke.metrics;
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE8F5E9),
            child: Text(
              '${stroke.packetId}',
              style: const TextStyle(color: Color(0xFF1B5E20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stroke ${stroke.packetId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${metrics.faceAngleChangeLabel} change • ${metrics.impact} impact',
                ),
                const SizedBox(height: 4),
                Text(
                  'Setup ${metrics.setupFaceAngleLabel} • Impact ${metrics.faceAngleAtImpactLabel}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                _MetricWrap(
                  values: [
                    'Back ${_formatDurationMs(metrics.backstrokeDurationMs)}',
                    'Forward ${_formatDurationMs(metrics.forwardStrokeDurationMs)}',
                    'Follow ${_formatDurationMs(metrics.followThroughDurationMs)}',
                    'Total ${_formatDurationMs(metrics.totalStrokeDurationMs)}',
                    'Peak accel ${metrics.peakAccelerationLabel}',
                    'Peak gyro ${metrics.peakAngularVelocityLabel}',
                    'Rotation ${metrics.clubRotationLabel}',
                    'Strength ${metrics.impactStrengthLabel}',
                    'Setup stable ${metrics.setupStabilityLabel}',
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Setup ${metrics.eventMarkers.setupMs}ms • Start ${metrics.eventMarkers.motionStartMs}ms • Transition ${metrics.eventMarkers.transitionMs}ms • Impact ${metrics.eventMarkers.impactMs}ms • Follow ${metrics.eventMarkers.followThroughEndMs}ms',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(value, style: const TextStyle(fontSize: 11)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.stream,
    required this.highlightColor,
  });

  final Stream<List<StrokeTrendPoint>> stream;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StrokeTrendPoint>>(
      stream: stream,
      builder: (context, snapshot) {
        final points = snapshot.data ?? const <StrokeTrendPoint>[];
        if (points.isEmpty) {
          return const EmptyStateCard(
            title: 'Not enough data yet',
            subtitle: 'Complete a session to build trends from stored strokes.',
          );
        }

        final maxValue = points
            .map((point) => point.value.abs())
            .reduce((a, b) => a > b ? a : b);
        return Container(
          height: 230,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: points
                .take(7)
                .map((point) {
                  final normalized = maxValue == 0
                      ? 0.0
                      : point.value.abs() / maxValue;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(point.value.toStringAsFixed(1)),
                      const SizedBox(height: 8),
                      Container(
                        width: 24,
                        height: 40 + normalized * 90,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(point.label),
                    ],
                  );
                })
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1B5E20)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    );
  }
}

String _connectionLabel(BleConnectionState state) {
  return switch (state) {
    BleConnectionState.connected => 'Connected and streaming',
    BleConnectionState.connecting => 'Connecting…',
    BleConnectionState.scanning => 'Scanning for devices…',
    BleConnectionState.disconnected => 'Disconnected',
  };
}

String _formatDurationMs(int ms) {
  if (ms >= 1000) {
    return '${(ms / 1000.0).toStringAsFixed(2)}s';
  }
  return '${ms}ms';
}
