import 'dart:async';

import 'package:flutter/material.dart';
import 'app/batipro_app.dart';
import 'app/app_language.dart';
import 'data/app_storage.dart';
import 'data/backup_service.dart';
import 'data/api_client.dart';
import 'data/cloud_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.initialize();
  final languagePrefs = await AppStorage.getInstance();
  AppLanguage.set(languagePrefs.getString('batipro_language') ?? 'ar');
  try {
    await BackupService.createAutomaticDailyBackup();
  } catch (_) {
    // A backup failure must never prevent the application from starting.
  }
  await ApiClient.instance.initialize();
  runApp(const BatiProApp());
  if (ApiClient.instance.isAuthenticated) {
    unawaited(() async {
      try {
        await CloudSyncService.synchronize();
      } catch (_) {
        // Keep offline startup available; the settings screen reports sync errors.
      }
    }());
  }
}
