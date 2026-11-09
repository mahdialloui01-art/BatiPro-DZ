import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/data/app_storage.dart';

void main() {
  setUp(() async {
    await AppStorage.resetForTests();
    await AppStorage.initialize(inMemory: true);
  });

  tearDown(() async {
    await AppStorage.resetForTests();
  });

  test('backup restores all persisted keys and values', () async {
    final storage = await AppStorage.getInstance();
    await storage.setString('batipro_inventory_v1', '[{"name":"T12","quantity":25}]');
    await storage.setString('batipro_shop_name', 'محل التجربة');

    final backup = await AppStorage.exportBackupJson();
    await storage.setString('batipro_shop_name', 'قيمة جديدة');
    await storage.setString('batipro_temporary', 'will be removed');

    final count = await AppStorage.restoreBackupJson(backup);
    expect(count, 2);
    expect(storage.getString('batipro_shop_name'), 'محل التجربة');
    expect(storage.getString('batipro_inventory_v1'), '[{"name":"T12","quantity":25}]');
    expect(storage.getString('batipro_temporary'), isNull);
  });

  test('invalid backup is rejected without changing existing data', () async {
    final storage = await AppStorage.getInstance();
    await storage.setString('batipro_shop_name', 'safe');

    final invalid = jsonEncode({
      'format': 'BatiProDZ-backup',
      'version': 1,
      'data': [
        {'key': 'batipro_shop_name', 'value': 'unsafe'},
        {'key': 'batipro_shop_name', 'value': 'duplicate'},
      ],
    });

    expect(() => AppStorage.restoreBackupJson(invalid), throwsFormatException);
    expect(storage.getString('batipro_shop_name'), 'safe');
  });
}
