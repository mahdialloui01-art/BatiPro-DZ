import 'package:flutter/material.dart';
import 'app/batipro_app.dart';
import 'data/app_storage.dart';
import 'data/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.initialize();
  try {
    await BackupService.createAutomaticDailyBackup();
  } catch (_) {
    // A backup failure must never prevent the application from starting.
  }
  runApp(const BatiProApp());
}
