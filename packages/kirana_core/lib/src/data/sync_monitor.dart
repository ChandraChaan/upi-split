import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum SyncState { synced, syncing, offline }

class WriteFailure {
  const WriteFailure(this.label, this.error);
  final String label;
  final Object error;
}

/// Tracks whether local writes have reached the server.
///
/// Firestore's commit future stays pending while offline, so writes are never
/// awaited by the UI. They go through [track], which keeps this count honest
/// and reports server rejections, which would otherwise be silent.
class SyncMonitor extends ChangeNotifier {
  SyncMonitor(this._db, {Connectivity? connectivity, bool watchNetwork = true}) {
    if (watchNetwork) {
      final c = connectivity ?? Connectivity();
      c.checkConnectivity().then(_onConnectivity, onError: (_) {});
      _connectivity = c.onConnectivityChanged.listen(_onConnectivity);
    }
    // Writes queued by an earlier run of the app are still being uploaded.
    _awaitQueue();
  }

  final FirebaseFirestore _db;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  final _failures = StreamController<WriteFailure>.broadcast();

  bool _online = true;
  bool _queueDraining = false;
  int _inFlight = 0;
  bool _disposed = false;

  Stream<WriteFailure> get failures => _failures.stream;
  int get pendingWrites => _inFlight;
  bool get isOnline => _online;

  SyncState get state {
    final dirty = _inFlight > 0 || _queueDraining;
    if (!_online) return SyncState.offline;
    return dirty ? SyncState.syncing : SyncState.synced;
  }

  /// Runs [commit] without blocking the caller.
  void track(String label, Future<void> Function() commit) {
    _inFlight++;
    _notify();
    commit().then((_) {}, onError: (Object error) {
      if (!_failures.isClosed) _failures.add(WriteFailure(label, error));
    }).whenComplete(() {
      _inFlight--;
      _notify();
    });
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _online) return;
    _online = online;
    _notify();
  }

  void _awaitQueue() {
    _queueDraining = true;
    _db.waitForPendingWrites().catchError((Object _) {}).whenComplete(() {
      _queueDraining = false;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivity?.cancel();
    _failures.close();
    super.dispose();
  }
}
