import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';

class BackupService {
  BackupService._();

  static Future<File> createAutomaticDailyBackup() async {
    final storage = await AppStorage.getInstance();
    final today = _dateKey(DateTime.now());
    if (storage.getString('batipro_auto_backup_day') == today) {
      final support = await getApplicationSupportDirectory();
      final folder = Directory(p.join(support.path, 'BatiProDZ', 'backups'));
      final existing = await folder.exists()
          ? await folder.list().where((entity) =>
              entity is File && p.basename(entity.path).startsWith('BatiProDZ-auto-')).cast<File>().toList()
          : <File>[];
      if (existing.isNotEmpty) {
        existing.sort((a, b) => b.path.compareTo(a.path));
        return existing.first;
      }
    }

    final support = await getApplicationSupportDirectory();
    final folder = Directory(p.join(support.path, 'BatiProDZ', 'backups'));
    await folder.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(folder.path, 'BatiProDZ-auto-$stamp.json'));
    await file.writeAsString(await AppStorage.exportBackupJson(), flush: true);
    await storage.setString('batipro_auto_backup_day', today);

    final backups = await folder
        .list()
        .where((entity) => entity is File &&
            p.basename(entity.path).startsWith('BatiProDZ-auto-') &&
            entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.path.compareTo(a.path));
    for (final old in backups.skip(7)) {
      await old.delete();
    }
    return file;
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
