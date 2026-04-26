import 'dart:async';

import 'package:designcode/camera/camera_lab_page.dart';
import 'package:designcode/data/local_database.dart' as db;
import 'package:designcode/main.dart' as base;
import 'package:designcode/services/app_controller.dart';
import 'package:designcode/services/ble_service.dart';
import 'package:designcode/services/session_repository.dart';
import 'package:designcode/services/sync_service.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PutterKyleStyleApp());
}

class PutterKyleStyleApp extends StatefulWidget {
  const PutterKyleStyleApp({super.key});

  @override
  State<PutterKyleStyleApp> createState() => _PutterKyleStyleAppState();
}

class _PutterKyleStyleAppState extends State<PutterKyleStyleApp> {
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
      title: 'PutterIQ Kyle Style',
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
          return KyleStyleScaffold(controller: _controller);
        },
      ),
    );
  }
}

class KyleStyleScaffold extends StatefulWidget {
  const KyleStyleScaffold({super.key, required this.controller});

  final AppController controller;

  @override
  State<KyleStyleScaffold> createState() => _KyleStyleScaffoldState();
}

class _KyleStyleScaffoldState extends State<KyleStyleScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
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
