import 'package:flutter/material.dart';
import 'app/batipro_app.dart';
import 'data/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.initialize();
  runApp(const BatiProApp());
}
