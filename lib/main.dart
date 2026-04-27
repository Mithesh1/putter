import 'dart:async';
import 'dart:math' as math;

import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';
import 'package:designcode/services/app_controller.dart';
import 'package:designcode/services/ble_service.dart';
import 'package:designcode/services/ble_transport.dart';
import 'package:designcode/services/processing.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';
import 'package:flutter/material.dart';

const double _gravityMps2 = 9.80665;
const double _piezoImpactAbsoluteThreshold = 300.0;

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
                    return StreamBuilder<String>(
                      stream: controller.watchLivePuttState(),
                      initialData: controller.livePuttState,
                      builder: (context, liveStateSnapshot) {
                        return StreamBuilder<String>(
                          stream: controller.watchBleLatency(),
                          initialData: controller.bleLatencyLabel,
                          builder: (context, latencySnapshot) {
                            final latestPuttSeries = latestStroke == null
                                ? null
                                : _buildLatestPuttSeries(latestStroke);
                            final strokeMetrics = latestStroke?.metrics;
                            final showImpactWarning =
                                latestStroke?.metrics.impact == 'Unknown';
                            final metrics = [
                          MetricCardData(
                            title: 'Face Angle',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.gyroIntegratedFaceAnglePoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°',
                                  ),
                            subtitle: latestStroke == null
                                ? 'Waiting for stroke'
                                : 'Integrated gyro Z at impact',
                            icon: Icons.track_changes,
                            chart: latestPuttSeries == null
                                ? null
                                : MiniChartData(
                                    series: [
                                      MiniChartSeries(
                                        label: 'Face',
                                        color: const Color(0xFF1B5E20),
                                        points:
                                            latestPuttSeries.gyroIntegratedFaceAnglePoints,
                                      ),
                                    ],
                                    impactMs:
                                        latestPuttSeries.imuImpactOffsetMs.toDouble(),
                                    referenceValue: 0,
                                    minY: -30,
                                    maxY: 30,
                                    unitLabel: 'deg',
                                    markers: _strokePhaseMarkers(
                                      latestPuttSeries,
                                    ),
                                  ),
                          ),
                          MetricCardData(
                            title: 'Tempo Ratio',
                            value: strokeMetrics == null
                                ? 'No data'
                                : '${strokeMetrics.tempoRatio.toStringAsFixed(2)}:1',
                            subtitle: 'Backstroke to forward stroke',
                            icon: Icons.timelapse,
                          ),
                          MetricCardData(
                            title: 'Backstroke Duration',
                            value: strokeMetrics == null
                                ? 'No data'
                                : _formatDurationMs(
                                    strokeMetrics.backstrokeDurationMs,
                                  ),
                            subtitle: 'Backstroke start to forward start',
                            icon: Icons.arrow_back,
                          ),
                          MetricCardData(
                            title: 'Forward Duration',
                            value: strokeMetrics == null
                                ? 'No data'
                                : _formatDurationMs(
                                    strokeMetrics.forwardStrokeDurationMs,
                                  ),
                            subtitle: 'Forward start to impact',
                            icon: Icons.arrow_forward,
                          ),
                          MetricCardData(
                            title: 'Total Stroke Duration',
                            value: strokeMetrics == null
                                ? 'No data'
                                : _formatDurationMs(
                                    strokeMetrics.totalStrokeDurationMs,
                                  ),
                            subtitle: 'Backstroke start to follow-through end',
                            icon: Icons.schedule,
                          ),
                          MetricCardData(
                            title: 'Peak Stroke Angular Velocity',
                            value: strokeMetrics == null
                                ? 'No data'
                                : strokeMetrics.peakAngularVelocityLabel,
                            subtitle: 'Peak gyro Y rotation rate',
                            icon: Icons.speed,
                          ),
                          MetricCardData(
                            title: 'Stroke Speed',
                            value: strokeMetrics == null
                                ? 'No data'
                                : strokeMetrics.speedLabel,
                            subtitle: 'Impact speed along main putt axis',
                            icon: Icons.sports_score,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.speedPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF00695C),
                                    label: 'Stroke Speed',
                                    minY: -4.0,
                                    maxY: 4.0,
                                    unitLabel: 'm/s',
                                    markers: _strokePhaseMarkers(
                                      latestPuttSeries,
                                    ),
                                  ),
                          ),
                          MetricCardData(
                            title: 'Gyro X',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.gyroXPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°/s',
                                    digits: 1,
                                  ),
                            subtitle: 'Gyro X at impact',
                            icon: Icons.swap_horiz,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.gyroXPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF1565C0),
                                    label: 'Gyro X',
                                    minY: -60,
                                    maxY: 60,
                                    unitLabel: 'dps',
                                    markers: _gyroPhaseMarkers(
                                      latestPuttSeries,
                                    ),
                                  ),
                          ),
                          MetricCardData(
                            title: 'Push / Pull',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.gyroIntegratedXPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°',
                                  ),
                            subtitle: 'Integrated gyro X through impact',
                            icon: Icons.compare_arrows,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.gyroIntegratedXPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF0D47A1),
                                    label: 'Integrated Gyro X',
                                    minY: -25,
                                    maxY: 25,
                                    unitLabel: 'deg',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Gyro Y',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.gyroYPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°/s',
                                    digits: 1,
                                  ),
                            subtitle: 'Gyro Y at impact',
                            icon: Icons.swap_vert,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.gyroYPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF2E7D32),
                                    label: 'Gyro Y',
                                    minY: -60,
                                    maxY: 60,
                                    unitLabel: 'dps',
                                    markers: _gyroPhaseMarkers(
                                      latestPuttSeries,
                                    ),
                                  ),
                          ),
                          MetricCardData(
                            title: 'Gyro Z',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.gyroZPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°/s',
                                    digits: 1,
                                  ),
                            subtitle: 'Gyro Z at impact',
                            icon: Icons.screen_rotation_alt,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.gyroZPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF8E24AA),
                                    label: 'Gyro Z',
                                    minY: -60,
                                    maxY: 60,
                                    unitLabel: 'dps',
                                    markers: _gyroPhaseMarkers(
                                      latestPuttSeries,
                                    ),
                                  ),
                          ),
                          MetricCardData(
                            title: 'Impact',
                            value: strokeMetrics?.impact ?? 'No data',
                            subtitle: 'Contact location',
                            icon: Icons.center_focus_strong,
                          ),
                          MetricCardData(
                            title: 'Ball Roll',
                            value: strokeMetrics?.rollStatus ?? 'Unavailable',
                            subtitle: 'Camera data not in v1',
                            icon: Icons.circle_outlined,
                          ),
                          MetricCardData(
                            title: 'Yaw',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.yawPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°',
                                  ),
                            subtitle: 'Orientation over time',
                            icon: Icons.explore,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.yawPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF00897B),
                                    label: 'Yaw',
                                    minY: -30,
                                    maxY: 30,
                                    unitLabel: 'deg',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Pitch',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.pitchPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°',
                                  ),
                            subtitle: 'Orientation over time',
                            icon: Icons.show_chart,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.pitchPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF5E35B1),
                                    label: 'Pitch',
                                    minY: -30,
                                    maxY: 30,
                                    unitLabel: 'deg',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Roll',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.rollPoints,
                                    impactOffsetMs:
                                        latestPuttSeries.imuImpactOffsetMs,
                                    suffix: '°',
                                  ),
                            subtitle: 'Orientation over time',
                            icon: Icons.rotate_right,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.rollPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF6D4C41),
                                    label: 'Roll',
                                    minY: -30,
                                    maxY: 30,
                                    unitLabel: 'deg',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Accel X',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _peakAbsLabel(
                                    latestPuttSeries.accelXPoints,
                                    suffix: 'm/s²',
                                  ),
                            subtitle: 'Acceleration over time',
                            icon: Icons.trending_flat,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.accelXPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF3949AB),
                                    label: 'Accel X',
                                    minY: -10,
                                    maxY: 10,
                                    unitLabel: 'm/s²',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Accel Y',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _peakAbsLabel(
                                    latestPuttSeries.accelYPoints,
                                    suffix: 'm/s²',
                                  ),
                            subtitle: 'Acceleration over time',
                            icon: Icons.swap_vert,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.accelYPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFF00838F),
                                    label: 'Accel Y',
                                    minY: -10,
                                    maxY: 10,
                                    unitLabel: 'm/s²',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Accel Z',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _peakAbsLabel(
                                    latestPuttSeries.accelZPoints,
                                    suffix: 'm/s²',
                                  ),
                            subtitle: 'Acceleration over time',
                            icon: Icons.height,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.accelZPoints,
                                    impactOffsetMs: latestPuttSeries.imuImpactOffsetMs,
                                    color: const Color(0xFFE53935),
                                    label: 'Accel Z',
                                    minY: -10,
                                    maxY: 10,
                                    unitLabel: 'm/s²',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Piezo 1',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.piezo1Points,
                                    impactOffsetMs:
                                        latestPuttSeries.piezoImpactOffsetMs,
                                    suffix: '',
                                    digits: 0,
                                  ),
                            subtitle: 'Piezo channel over time',
                            icon: Icons.graphic_eq,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.piezo1Points,
                                    impactOffsetMs: latestPuttSeries.piezoImpactOffsetMs,
                                    color: const Color(0xFFFB8C00),
                                    label: 'Piezo 1',
                                    minY: 0,
                                    maxY: 500,
                                    unitLabel: 'raw',
                                  ),
                          ),
                          MetricCardData(
                            title: 'Piezo 2',
                            value: latestPuttSeries == null
                                ? 'No data'
                                : _impactValueLabel(
                                    latestPuttSeries.piezo2Points,
                                    impactOffsetMs:
                                        latestPuttSeries.piezoImpactOffsetMs,
                                    suffix: '',
                                    digits: 0,
                                  ),
                            subtitle: 'Piezo channel over time',
                            icon: Icons.multitrack_audio,
                            chart: latestPuttSeries == null
                                ? null
                                : _singleSeriesChart(
                                    points: latestPuttSeries.piezo2Points,
                                    impactOffsetMs: latestPuttSeries.piezoImpactOffsetMs,
                                    color: const Color(0xFF8E24AA),
                                    label: 'Piezo 2',
                                    minY: 0,
                                    maxY: 500,
                                    unitLabel: 'raw',
                                  ),
                          ),
                            ];

                            return SafeArea(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  24,
                                ),
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
                                      syncStatus: syncSnapshot.data ??
                                          'Cloud sync disabled',
                                      puttState: liveStateSnapshot.data ??
                                          controller.livePuttState,
                                      bleLatencyLabel: latencySnapshot.data ??
                                          controller.bleLatencyLabel,
                                    ),
                                    if (showImpactWarning) ...[
                                      const SizedBox(height: 16),
                                      const _ImpactWarningCard(),
                                    ],
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
                                      physics:
                                          const NeverScrollableScrollPhysics(),
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
                                    const SectionTitle(
                                      title: 'Session Summary',
                                    ),
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
    required this.puttState,
    required this.bleLatencyLabel,
  });

  final BleConnectionState connectionState;
  final String transportName;
  final PracticeSession? activeSession;
  final String syncStatus;
  final String puttState;
  final String bleLatencyLabel;

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
          const SizedBox(height: 8),
          Text(
            bleLatencyLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.sports_golf, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Putt Phase',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  puttState,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
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
  final MiniChartData? chart;

  const MetricCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.chart,
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
          const SizedBox(height: 10),
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
          if (data.chart != null) ...[
            const SizedBox(height: 10),
            Expanded(child: MiniMetricChart(data: data.chart!)),
            const SizedBox(height: 6),
            _MiniChartLegend(data: data.chart!),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class MiniChartData {
  final List<MiniChartSeries> series;
  final double impactMs;
  final double referenceValue;
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;
  final String unitLabel;
  final List<MiniChartMarker> markers;

  const MiniChartData({
    required this.series,
    required this.impactMs,
    required this.referenceValue,
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    required this.unitLabel,
    this.markers = const [],
  });
}

class MiniChartSeries {
  final String label;
  final Color color;
  final List<ChartPoint> points;

  const MiniChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });
}

class MiniChartMarker {
  final String label;
  final double ms;
  final Color color;

  const MiniChartMarker({
    required this.label,
    required this.ms,
    required this.color,
  });
}

class MiniMetricChart extends StatelessWidget {
  const MiniMetricChart({super.key, required this.data});

  final MiniChartData data;

  @override
  Widget build(BuildContext context) {
    final longestSeriesPoints = data.series.fold<int>(
      0,
      (best, series) => math.max(best, series.points.length),
    );
    if (longestSeriesPoints < 2) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Not enough samples',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F3),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _MiniMetricChartPainter(data),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MiniChartLegend extends StatelessWidget {
  const _MiniChartLegend({required this.data});

  final MiniChartData data;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(fontSize: 10, color: Colors.grey.shade600);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 1.5, color: const Color(0xFF90A4AE)),
            const SizedBox(width: 4),
            Text('Ref', style: labelStyle),
          ],
        ),
        for (final marker in data.markers)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 2, height: 10, color: marker.color),
              const SizedBox(width: 4),
              Text(marker.label, style: labelStyle),
            ],
          ),
        for (final series in data.series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 14, height: 1.8, color: series.color),
              const SizedBox(width: 4),
              Text(series.label, style: labelStyle),
            ],
          ),
      ],
    );
  }
}

class _MiniMetricChartPainter extends CustomPainter {
  _MiniMetricChartPainter(this.data);

  final MiniChartData data;

  String _formatYAxisValue(double value) {
    if (data.unitLabel == 'dps' || data.unitLabel == 'raw') {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 30.0;
    final topPad = 4.0;
    final rightPad = 4.0;
    final bottomPad = 18.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) {
      return;
    }

    final populatedSeries =
        data.series.where((series) => series.points.isNotEmpty).toList();
    if (populatedSeries.isEmpty) {
      return;
    }

    final minX = data.minX ?? populatedSeries.first.points.first.ms;
    final maxX = data.maxX ?? populatedSeries.first.points.last.ms;
    final minY = data.minY ??
        populatedSeries
        .expand((series) => series.points)
        .map((point) => point.value)
        .reduce(math.min);
    final maxY = data.maxY ??
        populatedSeries
        .expand((series) => series.points)
        .map((point) => point.value)
        .reduce(math.max);
    final plotMinY = minY;
    final plotMaxY = maxY;

    double xFor(double ms) {
      if (maxX <= minX) {
        return leftPad;
      }
      return leftPad + ((ms - minX) / (maxX - minX)) * chartWidth;
    }

    double yFor(double value) {
      final normalized = (value - plotMinY) / (plotMaxY - plotMinY);
      return topPad + (1.0 - normalized) * chartHeight;
    }

    final refPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 1.5;
    final referenceY = yFor(data.referenceValue);
    final axisLabelStyle = TextStyle(
      color: Colors.grey.shade600,
      fontSize: 9,
      fontWeight: FontWeight.w600,
    );
    final yAxisValues = <double>[
      plotMaxY,
      data.referenceValue.clamp(plotMinY, plotMaxY),
      plotMinY,
    ];
    final xAxisValues = <double>[minX, (minX + maxX) / 2.0, maxX];

    for (final axisValue in yAxisValues) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: _formatYAxisValue(axisValue),
          style: axisLabelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = (yFor(axisValue) - (labelPainter.height / 2)).clamp(
        topPad,
        topPad + chartHeight - labelPainter.height,
      );
      labelPainter.paint(canvas, Offset(2, y));
    }

    canvas.drawLine(
      Offset(leftPad, referenceY),
      Offset(leftPad + chartWidth, referenceY),
      refPaint,
    );

    for (final axisValue in xAxisValues) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: '${axisValue.round()}ms',
          style: axisLabelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (xFor(axisValue) - (labelPainter.width / 2)).clamp(
        leftPad,
        leftPad + chartWidth - labelPainter.width,
      );
      labelPainter.paint(canvas, Offset(x, topPad + chartHeight + 2));
    }

    final markerLabelPositions = <double>[];
    for (final marker in data.markers) {
      final markerPaint = Paint()
        ..color = marker.color
        ..strokeWidth = 2;
      final markerX = xFor(marker.ms.clamp(minX, maxX));
      canvas.drawLine(
        Offset(markerX, topPad),
        Offset(markerX, topPad + chartHeight),
        markerPaint,
      );

      final markerTextPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: marker.color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final markerLabelY = markerLabelPositions.isEmpty
          ? topPad
          : markerLabelPositions.last + 12;
      markerLabelPositions.add(markerLabelY);
      markerTextPainter.paint(
        canvas,
        Offset(
          (markerX + 4).clamp(
            leftPad,
            leftPad + chartWidth - markerTextPainter.width,
          ),
          markerLabelY,
        ),
      );
    }

    for (var seriesIndex = 0; seriesIndex < populatedSeries.length; seriesIndex++) {
      final series = populatedSeries[seriesIndex];
      final linePaint = Paint()
        ..color = series.color
        ..strokeWidth = seriesIndex == 1 ? 2.4 : 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()
        ..moveTo(xFor(series.points.first.ms), yFor(series.points.first.value));
      for (final point in series.points.skip(1)) {
        path.lineTo(xFor(point.ms), yFor(point.value));
      }
      canvas.drawPath(path, linePaint);

      final impactPoint = series.points.reduce((best, current) {
        final bestDelta = (best.ms - data.impactMs).abs();
        final currentDelta = (current.ms - data.impactMs).abs();
        return currentDelta < bestDelta ? current : best;
      });
      final impactOffset = Offset(
        xFor(impactPoint.ms),
        yFor(impactPoint.value),
      );
      canvas.drawCircle(
        impactOffset,
        3.0,
        Paint()..color = series.color,
      );
      if (seriesIndex == 1) {
        canvas.drawCircle(
          impactOffset,
          5.4,
          Paint()
            ..color = const Color(0xFFEF6C00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

  }

  @override
  bool shouldRepaint(covariant _MiniMetricChartPainter oldDelegate) {
    return oldDelegate.data != data;
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
        : latestStroke!.metrics.impact == 'Unknown'
        ? 'The last stroke did not show a confident ball-impact spike in acceleration, so the impact timing should be treated cautiously.'
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
                    'Speed ${metrics.speedLabel}',
                    'Back ${_formatDurationMs(metrics.backstrokeDurationMs)}',
                    'Forward ${_formatDurationMs(metrics.forwardStrokeDurationMs)}',
                    'Follow ${_formatDurationMs(metrics.followThroughDurationMs)}',
                    'Total ${_formatDurationMs(metrics.totalStrokeDurationMs)}',
                    'Peak accel ${metrics.peakAccelerationLabel}',
                    'Peak stroke ${metrics.peakAngularVelocityLabel}',
                    'Rotation ${metrics.clubRotationLabel}',
                    'Strength ${metrics.impactStrengthLabel}',
                    'Setup stable ${metrics.setupStabilityLabel}',
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Setup ${metrics.eventMarkers.setupMs}ms • Backstroke ${metrics.eventMarkers.motionStartMs}ms • Forward ${metrics.eventMarkers.transitionMs}ms • Impact ${metrics.eventMarkers.impactMs}ms • Follow ${metrics.eventMarkers.followThroughEndMs}ms',
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

class _ImpactWarningCard extends StatelessWidget {
  const _ImpactWarningCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFEF6C00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ball impact was not confidently found in the acceleration data for the last stroke.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
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

class ChartPoint {
  final double ms;
  final double value;

  const ChartPoint({required this.ms, required this.value});
}

class _LatestPuttSeries {
  final List<ChartPoint> faceAnglePoints;
  final List<ChartPoint> speedPoints;
  final List<ChartPoint> gyroIntegratedFaceAnglePoints;
  final List<ChartPoint> gyroIntegratedXPoints;
  final List<ChartPoint> gyroXPoints;
  final List<ChartPoint> gyroYPoints;
  final List<ChartPoint> gyroZPoints;
  final List<ChartPoint> yawPoints;
  final List<ChartPoint> pitchPoints;
  final List<ChartPoint> rollPoints;
  final List<ChartPoint> accelXPoints;
  final List<ChartPoint> accelYPoints;
  final List<ChartPoint> accelZPoints;
  final List<ChartPoint> piezo1Points;
  final List<ChartPoint> piezo2Points;
  final int setupOffsetMs;
  final int motionStartOffsetMs;
  final int transitionOffsetMs;
  final int imuImpactOffsetMs;
  final int piezoImpactOffsetMs;
  final int impactAbsoluteMs;

  const _LatestPuttSeries({
    required this.faceAnglePoints,
    required this.speedPoints,
    required this.gyroIntegratedFaceAnglePoints,
    required this.gyroIntegratedXPoints,
    required this.gyroXPoints,
    required this.gyroYPoints,
    required this.gyroZPoints,
    required this.yawPoints,
    required this.pitchPoints,
    required this.rollPoints,
    required this.accelXPoints,
    required this.accelYPoints,
    required this.accelZPoints,
    required this.piezo1Points,
    required this.piezo2Points,
    required this.setupOffsetMs,
    required this.motionStartOffsetMs,
    required this.transitionOffsetMs,
    required this.imuImpactOffsetMs,
    required this.piezoImpactOffsetMs,
    required this.impactAbsoluteMs,
  });
}

MiniChartData _singleSeriesChart({
  required List<ChartPoint> points,
  required int impactOffsetMs,
  required Color color,
  required String label,
  double? minX,
  double? maxX,
  double? minY,
  double? maxY,
  required String unitLabel,
  List<MiniChartMarker> markers = const [],
}) {
  return MiniChartData(
    series: [
      MiniChartSeries(
        label: label,
        color: color,
        points: points,
      ),
    ],
    impactMs: impactOffsetMs.toDouble(),
    referenceValue: 0,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    unitLabel: unitLabel,
    markers: markers.isEmpty
        ? [
            MiniChartMarker(
              label: 'Impact',
              ms: impactOffsetMs.toDouble(),
              color: const Color(0xFFEF6C00),
            ),
          ]
        : markers,
  );
}

String _impactValueLabel(
  List<ChartPoint> points, {
  required int impactOffsetMs,
  required String suffix,
  int digits = 2,
}) {
  if (points.isEmpty) {
    return 'No data';
  }

  final impactPoint = points.reduce((best, current) {
    final bestDelta = (best.ms - impactOffsetMs).abs();
    final currentDelta = (current.ms - impactOffsetMs).abs();
    return currentDelta < bestDelta ? current : best;
  });
  return '${impactPoint.value.toStringAsFixed(digits)}$suffix';
}

String _peakAbsLabel(
  List<ChartPoint> points, {
  String suffix = '',
  int digits = 2,
}) {
  if (points.isEmpty) {
    return 'No data';
  }
  final peak = points
      .map((point) => point.value.abs())
      .reduce(math.max);
  return '${peak.toStringAsFixed(digits)}$suffix';
}

List<MiniChartMarker> _strokePhaseMarkers(_LatestPuttSeries series) {
  return [
    MiniChartMarker(
      label: 'Setup',
      ms: series.setupOffsetMs.toDouble(),
      color: const Color(0xFF1976D2),
    ),
    MiniChartMarker(
      label: 'Backstroke',
      ms: series.motionStartOffsetMs.toDouble(),
      color: const Color(0xFF2E7D32),
    ),
    MiniChartMarker(
      label: 'Forward',
      ms: series.transitionOffsetMs.toDouble(),
      color: const Color(0xFF8E24AA),
    ),
    MiniChartMarker(
      label: 'Impact',
      ms: series.imuImpactOffsetMs.toDouble(),
      color: const Color(0xFFEF6C00),
    ),
  ];
}

List<MiniChartMarker> _gyroPhaseMarkers(_LatestPuttSeries series) {
  return [
    MiniChartMarker(
      label: 'Backstroke',
      ms: series.motionStartOffsetMs.toDouble(),
      color: const Color(0xFF2E7D32),
    ),
    MiniChartMarker(
      label: 'Forward',
      ms: series.transitionOffsetMs.toDouble(),
      color: const Color(0xFF8E24AA),
    ),
    MiniChartMarker(
      label: 'Impact',
      ms: series.imuImpactOffsetMs.toDouble(),
      color: const Color(0xFFEF6C00),
    ),
  ];
}

List<ChartPoint> _buildStrokeSpeedPoints({
  required List<double> rawImu,
  required int imuChannels,
  required int sampleCount,
  required int imuSampleRateHz,
  required int motionStartOffsetMs,
  required int transitionOffsetMs,
  required int impactOffsetMs,
  required int followThroughEndOffsetMs,
}) {
  if (imuSampleRateHz <= 0 || sampleCount <= 0) {
    return const <ChartPoint>[];
  }

  final dt = 1.0 / imuSampleRateHz;
  final motionStartIdx =
      ((motionStartOffsetMs * imuSampleRateHz) / 1000.0).round().clamp(
            0,
            sampleCount - 1,
          );
  final transitionIdx =
      ((transitionOffsetMs * imuSampleRateHz) / 1000.0).round().clamp(
            motionStartIdx,
            sampleCount - 1,
          );
  final impactIdx = ((impactOffsetMs * imuSampleRateHz) / 1000.0).round().clamp(
        transitionIdx,
        sampleCount - 1,
      );
  final followThroughEndIdx =
      ((followThroughEndOffsetMs * imuSampleRateHz) / 1000.0).round().clamp(
        impactIdx,
        sampleCount - 1,
      );

  var forwardVx = 0.0;
  var forwardVy = 0.0;
  var axisX = 0.0;
  var axisY = 0.0;
  var peakHorizontalSpeed = 0.0;
  final points = <ChartPoint>[];

  if (imuChannels >= 10) {
    for (var sampleIndex = transitionIdx;
        sampleIndex <= impactIdx;
        sampleIndex++) {
      final offset = sampleIndex * imuChannels;
      final accelX = rawImu[offset] * 9.80665;
      final accelY = rawImu[offset + 1] * 9.80665;
      final accelZ = rawImu[offset + 2] * 9.80665;
      final q = _normalizedQuaternionFromValues(
        rawImu[offset + 6],
        rawImu[offset + 7],
        rawImu[offset + 8],
        rawImu[offset + 9],
      );
      final worldAccel = _rotateVectorByQuaternion([accelX, accelY, accelZ], q);
      forwardVx += worldAccel[0] * dt;
      forwardVy += worldAccel[1] * dt;
      final horizontalSpeed =
          math.sqrt(forwardVx * forwardVx + forwardVy * forwardVy);
      if (horizontalSpeed > peakHorizontalSpeed) {
        peakHorizontalSpeed = horizontalSpeed;
        axisX = forwardVx / horizontalSpeed;
        axisY = forwardVy / horizontalSpeed;
      }
    }
  }

  var projectedBias = 0.0;
  if (imuChannels >= 10 && peakHorizontalSpeed > 1e-6 && motionStartIdx > 0) {
    for (var sampleIndex = 0; sampleIndex < motionStartIdx; sampleIndex++) {
      final offset = sampleIndex * imuChannels;
      final accelX = rawImu[offset] * 9.80665;
      final accelY = rawImu[offset + 1] * 9.80665;
      final accelZ = rawImu[offset + 2] * 9.80665;
      final q = _normalizedQuaternionFromValues(
        rawImu[offset + 6],
        rawImu[offset + 7],
        rawImu[offset + 8],
        rawImu[offset + 9],
      );
      final worldAccel = _rotateVectorByQuaternion([accelX, accelY, accelZ], q);
      projectedBias += (worldAccel[0] * axisX) + (worldAccel[1] * axisY);
    }
    projectedBias /= motionStartIdx;
  }

  var projectedVelocity = 0.0;
  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final sampleMs = sampleIndex * 1000.0 / imuSampleRateHz;
    var projectedSpeed = 0.0;

    if (sampleIndex >= motionStartIdx && sampleIndex <= followThroughEndIdx) {
      if (imuChannels >= 10 && peakHorizontalSpeed > 1e-6) {
        final offset = sampleIndex * imuChannels;
        final accelX = rawImu[offset] * 9.80665;
        final accelY = rawImu[offset + 1] * 9.80665;
        final accelZ = rawImu[offset + 2] * 9.80665;
        final q = _normalizedQuaternionFromValues(
          rawImu[offset + 6],
          rawImu[offset + 7],
          rawImu[offset + 8],
          rawImu[offset + 9],
        );
        final worldAccel = _rotateVectorByQuaternion([accelX, accelY, accelZ], q);
        final projectedAccel =
            ((worldAccel[0] * axisX) + (worldAccel[1] * axisY)) - projectedBias;
        projectedVelocity += projectedAccel * dt;
        projectedSpeed = sampleIndex < transitionIdx
            ? -projectedVelocity.abs()
            : projectedVelocity.abs();
      } else if (imuChannels > 1) {
        final offset = sampleIndex * imuChannels;
        projectedVelocity += rawImu[offset + 1] * 9.80665 * dt;
        projectedSpeed = sampleIndex < transitionIdx
            ? -projectedVelocity.abs()
            : projectedVelocity.abs();
      }
    }

    points.add(ChartPoint(ms: sampleMs, value: projectedSpeed));
  }

  return List<ChartPoint>.unmodifiable(points);
}

List<double> _normalizedQuaternionFromValues(
  double qi,
  double qj,
  double qk,
  double qr,
) {
  final norm = math.sqrt(qr * qr + qi * qi + qj * qj + qk * qk);
  if (norm < 1e-8) {
    return const [1.0, 0.0, 0.0, 0.0];
  }
  return [qr / norm, qi / norm, qj / norm, qk / norm];
}

List<double> _rotateVectorByQuaternion(List<double> vector, List<double> q) {
  final w = q[0];
  final x = q[1];
  final y = q[2];
  final z = q[3];

  final ww = w * w;
  final xx = x * x;
  final yy = y * y;
  final zz = z * z;
  final wx = w * x;
  final wy = w * y;
  final wz = w * z;
  final xy = x * y;
  final xz = x * z;
  final yz = y * z;

  final vx = vector[0];
  final vy = vector[1];
  final vz = vector[2];

  return [
    (ww + xx - yy - zz) * vx + 2.0 * ((xy - wz) * vy + (xz + wy) * vz),
    2.0 * ((xy + wz) * vx + (ww - xx + yy - zz) * vy + (yz - wx) * vz),
    2.0 * ((xz - wy) * vx + (yz + wx) * vy + (ww - xx - yy + zz) * vz),
  ];
}

int _resolvePiezoImpactOffsetMs(
  List<ChartPoint> piezo1Points,
  List<ChartPoint> piezo2Points, {
  required int expectedOffsetMs,
}) {
  final combinedCount = math.max(piezo1Points.length, piezo2Points.length);
  if (combinedCount <= 0) {
    return expectedOffsetMs;
  }

  final piezo1Baseline = piezo1Points.isEmpty
      ? 0.0
      : piezo1Points.map((point) => point.value).reduce((a, b) => a + b) /
          piezo1Points.length;
  final piezo2Baseline = piezo2Points.isEmpty
      ? 0.0
      : piezo2Points.map((point) => point.value).reduce((a, b) => a + b) /
          piezo2Points.length;
  final expectedIndex = expectedOffsetMs <= 0
      ? 0
      : (piezo1Points.isNotEmpty ? piezo1Points : piezo2Points)
          .indexWhere((point) => point.ms >= expectedOffsetMs);
  final clampedExpectedIndex =
      (expectedIndex < 0 ? combinedCount - 1 : expectedIndex)
          .clamp(0, combinedCount - 1);
  final searchRadius = 200;
  final searchStart = math.max(0, clampedExpectedIndex - searchRadius);
  final searchEnd = math.min(combinedCount - 1, clampedExpectedIndex + searchRadius);
  var bestIndex = clampedExpectedIndex;
  var bestStrength = double.negativeInfinity;
  var bestAbsolutePeak = double.negativeInfinity;

  for (var index = searchStart; index <= searchEnd; index++) {
    final piezo1Value =
        index < piezo1Points.length ? piezo1Points[index].value : 0.0;
    final piezo2Value =
        index < piezo2Points.length ? piezo2Points[index].value : 0.0;
    final absolutePeak = math.max(piezo1Value, piezo2Value);
    if (absolutePeak >= _piezoImpactAbsoluteThreshold &&
        absolutePeak > bestAbsolutePeak) {
      bestAbsolutePeak = absolutePeak;
      bestIndex = index;
      continue;
    }
    if (bestAbsolutePeak >= _piezoImpactAbsoluteThreshold) {
      continue;
    }
    final piezo1Delta = index < piezo1Points.length
        ? (piezo1Value - piezo1Baseline).abs()
        : 0.0;
    final piezo2Delta = index < piezo2Points.length
        ? (piezo2Value - piezo2Baseline).abs()
        : 0.0;
    final combinedStrength = math.max(piezo1Delta, piezo2Delta);
    if (combinedStrength > bestStrength) {
      bestStrength = combinedStrength;
      bestIndex = index;
    }
  }

  if (bestIndex < piezo1Points.length) {
    return piezo1Points[bestIndex].ms.round();
  }
  if (bestIndex < piezo2Points.length) {
    return piezo2Points[bestIndex].ms.round();
  }
  return expectedOffsetMs;
}

List<ChartPoint> _shiftChartPoints(
  List<ChartPoint> points,
  double deltaMs,
) {
  if (deltaMs == 0.0) {
    return List<ChartPoint>.unmodifiable(points);
  }
  return List<ChartPoint>.unmodifiable(
    points.map((point) => ChartPoint(ms: point.ms + deltaMs, value: point.value)),
  );
}

_LatestPuttSeries? _buildLatestPuttSeries(StoredStroke stroke) {
  final codec = const PacketCodec();
  final packet = codec.decodeRawStrokePacket(stroke.rawPacketBytes);
  final freshMetrics = processStrokePacket(packet, codec: codec);
  final rawImu = codec.decodeScaledImu(packet);
  if (packet.imuChannels <= 0 || rawImu.isEmpty) {
    return null;
  }

  final sampleCount = rawImu.length ~/ packet.imuChannels;
  if (sampleCount <= 0) {
    return null;
  }

  final faceAnglePoints = <ChartPoint>[];
  final gyroIntegratedFaceAnglePoints = <ChartPoint>[];
  final gyroIntegratedXPoints = <ChartPoint>[];
  final gyroXPoints = <ChartPoint>[];
  final gyroYPoints = <ChartPoint>[];
  final gyroZPoints = <ChartPoint>[];
  final yawPoints = <ChartPoint>[];
  final pitchPoints = <ChartPoint>[];
  final rollPoints = <ChartPoint>[];
  final accelXPoints = <ChartPoint>[];
  final accelYPoints = <ChartPoint>[];
  final accelZPoints = <ChartPoint>[];
  final piezoChannels = codec.splitPiezoChannels(packet);
  final piezo1Values =
      piezoChannels.isNotEmpty ? piezoChannels[0] : const <int>[];
  final piezo2Values =
      piezoChannels.length > 1 ? piezoChannels[1] : const <int>[];
  final piezo1Points = <ChartPoint>[];
  final piezo2Points = <ChartPoint>[];
  final calibrationIdx = packet.imuSampleCount > 0
      ? packet.reserved.clamp(0, packet.imuSampleCount - 1)
      : 0;
  final maxImuMs = packet.imuSampleRateHz > 0
      ? ((sampleCount - 1) * 1000.0 / packet.imuSampleRateHz).round()
      : 0;
  final maxPiezoMs = packet.piezoSampleRateHz > 0
      ? ((packet.piezoSampleCount - 1) * 1000.0 / packet.piezoSampleRateHz)
          .round()
      : 0;
  final imuImpactOffsetMs =
      freshMetrics.impactImuOffsetMs.clamp(0, maxImuMs).toInt();
  final expectedPiezoImpactOffsetMs =
      freshMetrics.impactPiezoOffsetMs.clamp(0, maxPiezoMs).toInt();
  final imuStartMs = freshMetrics.eventMarkers.impactMs - imuImpactOffsetMs;
  final motionStartOffsetMs =
      (freshMetrics.eventMarkers.motionStartMs - imuStartMs)
          .clamp(0, maxImuMs)
          .toInt();
  final transitionOffsetMs =
      (freshMetrics.eventMarkers.transitionMs - imuStartMs)
          .clamp(0, maxImuMs)
          .toInt();
  final followThroughEndOffsetMs =
      (freshMetrics.eventMarkers.followThroughEndMs - imuStartMs)
          .clamp(0, maxImuMs)
          .toInt();
  final calibrationOrientation = packet.imuChannels >= 10
      ? _orientationFromQuaternionValues(
          rawImu[calibrationIdx * packet.imuChannels + 6],
          rawImu[calibrationIdx * packet.imuChannels + 7],
          rawImu[calibrationIdx * packet.imuChannels + 8],
          rawImu[calibrationIdx * packet.imuChannels + 9],
        )
      : const _OrientationAngles(yawDeg: 0.0, pitchDeg: 0.0, rollDeg: 0.0);
  var integratedGyroZDeg = 0.0;
  var integratedGyroXDeg = 0.0;
  var calibrationIntegratedGyroZDeg = 0.0;
  var calibrationIntegratedGyroXDeg = 0.0;

  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final offset = sampleIndex * packet.imuChannels;
    final sampleMs = sampleIndex * 1000.0 / packet.imuSampleRateHz;
    final accelX = rawImu[offset] * _gravityMps2;
    final accelY = rawImu[offset + 1] * _gravityMps2;
    final accelZ = rawImu[offset + 2] * _gravityMps2;
    final gyroX = rawImu[offset + 3];
    final gyroY = rawImu[offset + 4];
    final gyroZ = rawImu[offset + 5];
    if (packet.imuSampleRateHz > 0 && sampleIndex > 0) {
      integratedGyroXDeg += gyroX / packet.imuSampleRateHz;
      integratedGyroZDeg += gyroZ / packet.imuSampleRateHz;
    }
    if (sampleIndex == calibrationIdx) {
      calibrationIntegratedGyroXDeg = integratedGyroXDeg;
      calibrationIntegratedGyroZDeg = integratedGyroZDeg;
    }
    final calibratedIntegratedGyroXDeg =
        integratedGyroXDeg - calibrationIntegratedGyroXDeg;
    final calibratedIntegratedGyroZDeg =
        integratedGyroZDeg - calibrationIntegratedGyroZDeg;
    accelXPoints.add(ChartPoint(ms: sampleMs, value: accelX));
    accelYPoints.add(ChartPoint(ms: sampleMs, value: accelY));
    accelZPoints.add(ChartPoint(ms: sampleMs, value: accelZ));
    gyroXPoints.add(ChartPoint(ms: sampleMs, value: gyroX));
    gyroYPoints.add(ChartPoint(ms: sampleMs, value: gyroY));
    gyroZPoints.add(ChartPoint(ms: sampleMs, value: gyroZ));
    gyroIntegratedFaceAnglePoints.add(
      ChartPoint(ms: sampleMs, value: calibratedIntegratedGyroZDeg),
    );
    gyroIntegratedXPoints.add(
      ChartPoint(ms: sampleMs, value: calibratedIntegratedGyroXDeg),
    );

    double faceAngle = 0.0;
    if (packet.imuChannels >= 10) {
      final orientation = _orientationFromQuaternionValues(
        rawImu[offset + 6],
        rawImu[offset + 7],
        rawImu[offset + 8],
        rawImu[offset + 9],
      );
      final calibratedYawDeg = _wrapDegrees180(
        orientation.yawDeg - calibrationOrientation.yawDeg,
      );
      final calibratedRollDeg = _wrapDegrees180(
        orientation.rollDeg - calibrationOrientation.rollDeg,
      );
      yawPoints.add(ChartPoint(ms: sampleMs, value: calibratedYawDeg));
      pitchPoints.add(ChartPoint(ms: sampleMs, value: orientation.pitchDeg));
      rollPoints.add(ChartPoint(ms: sampleMs, value: calibratedRollDeg));
      faceAngle = calibratedRollDeg;
    }
    faceAnglePoints.add(ChartPoint(ms: sampleMs, value: faceAngle));
  }

  final speedPoints = _buildStrokeSpeedPoints(
    rawImu: rawImu,
    imuChannels: packet.imuChannels,
    sampleCount: sampleCount,
    imuSampleRateHz: packet.imuSampleRateHz,
    motionStartOffsetMs: motionStartOffsetMs,
    transitionOffsetMs: transitionOffsetMs,
    impactOffsetMs: imuImpactOffsetMs,
    followThroughEndOffsetMs: followThroughEndOffsetMs,
  );

  for (var sampleIndex = 0; sampleIndex < packet.piezoSampleCount; sampleIndex++) {
    final sampleMs = sampleIndex * 1000.0 / packet.piezoSampleRateHz;
    if (sampleIndex < piezo1Values.length) {
      piezo1Points.add(
        ChartPoint(ms: sampleMs, value: piezo1Values[sampleIndex].toDouble()),
      );
    }
    if (sampleIndex < piezo2Values.length) {
      piezo2Points.add(
        ChartPoint(ms: sampleMs, value: piezo2Values[sampleIndex].toDouble()),
      );
    }
  }

  final detectedPiezoImpactOffsetMs = _resolvePiezoImpactOffsetMs(
    piezo1Points,
    piezo2Points,
    expectedOffsetMs: expectedPiezoImpactOffsetMs,
  ).clamp(0, maxPiezoMs).toInt();
  final piezoTimelineShiftMs =
      imuImpactOffsetMs.toDouble() - detectedPiezoImpactOffsetMs.toDouble();
  var alignedPiezo1Points = _shiftChartPoints(
    piezo1Points,
    piezoTimelineShiftMs,
  );
  var alignedPiezo2Points = _shiftChartPoints(
    piezo2Points,
    piezoTimelineShiftMs,
  );
  final piezoImpactOffsetMs = imuImpactOffsetMs;
  alignedPiezo1Points = List<ChartPoint>.unmodifiable([
    ChartPoint(ms: 0, value: alignedPiezo1Points.isEmpty ? 0 : alignedPiezo1Points.first.value),
    ...alignedPiezo1Points.where(
      (point) => point.ms >= 0 && point.ms <= maxImuMs,
    ),
    ChartPoint(
      ms: maxImuMs.toDouble(),
      value: alignedPiezo1Points.isEmpty ? 0 : alignedPiezo1Points.last.value,
    ),
  ]);
  alignedPiezo2Points = List<ChartPoint>.unmodifiable([
    ChartPoint(ms: 0, value: alignedPiezo2Points.isEmpty ? 0 : alignedPiezo2Points.first.value),
    ...alignedPiezo2Points.where(
      (point) => point.ms >= 0 && point.ms <= maxImuMs,
    ),
    ChartPoint(
      ms: maxImuMs.toDouble(),
      value: alignedPiezo2Points.isEmpty ? 0 : alignedPiezo2Points.last.value,
    ),
  ]);

  return _LatestPuttSeries(
    faceAnglePoints: List<ChartPoint>.unmodifiable(faceAnglePoints),
    speedPoints: speedPoints,
    gyroIntegratedFaceAnglePoints:
        List<ChartPoint>.unmodifiable(gyroIntegratedFaceAnglePoints),
    gyroIntegratedXPoints: List<ChartPoint>.unmodifiable(gyroIntegratedXPoints),
    gyroXPoints: List<ChartPoint>.unmodifiable(gyroXPoints),
    gyroYPoints: List<ChartPoint>.unmodifiable(gyroYPoints),
    gyroZPoints: List<ChartPoint>.unmodifiable(gyroZPoints),
    yawPoints: List<ChartPoint>.unmodifiable(yawPoints),
    pitchPoints: List<ChartPoint>.unmodifiable(pitchPoints),
    rollPoints: List<ChartPoint>.unmodifiable(rollPoints),
    accelXPoints: List<ChartPoint>.unmodifiable(accelXPoints),
    accelYPoints: List<ChartPoint>.unmodifiable(accelYPoints),
    accelZPoints: List<ChartPoint>.unmodifiable(accelZPoints),
    piezo1Points: alignedPiezo1Points,
    piezo2Points: alignedPiezo2Points,
    setupOffsetMs: 0,
    motionStartOffsetMs: motionStartOffsetMs,
    transitionOffsetMs: transitionOffsetMs,
    imuImpactOffsetMs: imuImpactOffsetMs,
    piezoImpactOffsetMs: piezoImpactOffsetMs,
    impactAbsoluteMs: freshMetrics.eventMarkers.impactMs,
  );
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

_OrientationAngles _orientationFromQuaternionValues(
  double qi,
  double qj,
  double qk,
  double qr,
) {
  final qi2 = qi * qi;
  final qj2 = qj * qj;
  final qk2 = qk * qk;
  final qr2 = qr * qr;
  final denom = qi2 + qj2 + qk2 + qr2;
  if (denom == 0.0) {
    return const _OrientationAngles(yawDeg: 0.0, pitchDeg: 0.0, rollDeg: 0.0);
  }

  final yawDeg = math.atan2(
        2.0 * (qi * qj + qk * qr),
        (qi2 - qj2 - qk2 + qr2),
      ) *
      180.0 /
      math.pi;
  final pitchDeg = math.asin(
        (-2.0 * (qi * qk - qj * qr) / denom).clamp(-1.0, 1.0),
      ) *
      180.0 /
      math.pi;
  final rollDeg = math.atan2(
        2.0 * (qj * qk + qi * qr),
        (-qi2 - qj2 + qk2 + qr2),
      ) *
      180.0 /
      math.pi;

  return _OrientationAngles(
    yawDeg: yawDeg,
    pitchDeg: pitchDeg,
    rollDeg: rollDeg,
  );
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
