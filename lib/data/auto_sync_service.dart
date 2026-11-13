import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'cloud_sync_service.dart';

/// Automatically retries durable local changes while the application is open.
class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();
  static const Duration _interval = Duration(seconds: 20);

  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _attemptRunning = false;

  DateTime? lastSuccessAt;
  String? lastError;
  Map<String, dynamic>? lastResult;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) {
      if (_foreground) unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(syncNow());
  }

  Future<void> syncNow() async {
    if (!_foreground || _attemptRunning || !ApiClient.instance.isAuthenticated) {
      return;
    }
    _attemptRunning = true;
    try {
      lastResult = await CloudSyncService.synchronize();
      lastSuccessAt = DateTime.now();
      lastError = null;
    } catch (error) {
      // Never block local SQLite operations when the server is unreachable.
      lastError = error.toString();
      debugPrint('BatiPro automatic sync deferred: $error');
    } finally {
      _attemptRunning = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
