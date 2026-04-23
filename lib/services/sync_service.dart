import 'dart:async';

import 'package:designcode/services/session_repository.dart';

abstract class SyncService {
  Stream<String> get statusStream;

  String get status;

  Future<void> syncPending(SessionRepository repository);

  Future<void> dispose();
}

class DisabledSyncService implements SyncService {
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  String get status => 'Cloud sync disabled';

  @override
  Future<void> syncPending(SessionRepository repository) async {
    _statusController.add(status);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}

class FirestoreSyncService implements SyncService {
  FirestoreSyncService();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  String _status = 'Idle';

  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  String get status => _status;

  @override
  Future<void> syncPending(SessionRepository repository) async {
    final pending = await repository.loadPendingSyncStrokes();
    if (pending.isEmpty) {
      _setStatus('Cloud sync unavailable in local demo build');
      return;
    }

    _setStatus('Cloud sync unavailable in local demo build');
  }

  void _setStatus(String next) {
    _status = next;
    _statusController.add(next);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}
