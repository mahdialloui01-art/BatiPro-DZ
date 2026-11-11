import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart' as legacy_prefs;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite-backed local persistence. Existing SharedPreferences values are
/// copied once and retained there until the user has a verified backup.
class AppStorage {
  AppStorage._();

  static Database? _database;
  static final Map<String, String> _cache = <String, String>{};
  static const String _migrationKey = '__legacy_shared_preferences_migrated_v1';
  static const String _centimeMigrationKey = '__batipro_currency_centime_v1';

  static Future<void> initialize({bool inMemory = false}) async {
    if (_database != null) return;

    final useFfi = inMemory || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (useFfi) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    late final String databasePath;
    if (inMemory) {
      databasePath = inMemoryDatabasePath;
    } else {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(p.join(support.path, 'BatiProDZ'));
      await directory.create(recursive: true);
      databasePath = p.join(directory.path, 'batipro_dz.sqlite');
    }

    final db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE app_data (
              data_key TEXT PRIMARY KEY NOT NULL,
              data_value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    _database = db;

    final rows = await db.query('app_data');
    _cache
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(
        row['data_key'] as String,
        row['data_value'] as String,
      )));

    if (!inMemory) {
      await _migrateLegacyPreferences(db);
      await _migrateCurrencyValuesToCentimes(db);
    }
  }

  static Future<void> _migrateLegacyPreferences(Database db) async {
    final marker = await db.query(
      'app_data',
      columns: const ['data_key'],
      where: 'data_key = ?',
      whereArgs: const [_migrationKey],
      limit: 1,
    );
    if (marker.isNotEmpty) return;

    final legacy = await legacy_prefs.SharedPreferences.getInstance();
    final legacyKeys = legacy.getKeys()
        .where((key) => key.startsWith('batipro_'))
        .toList(growable: false);

    await db.transaction((txn) async {
      for (final key in legacyKeys) {
        final value = legacy.getString(key);
        if (value == null) continue;
        await txn.insert(
          'app_data',
          {
            'data_key': key,
            'data_value': value,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.insert(
        'app_data',
        {
          'data_key': _migrationKey,
          'data_value': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    final migrated = await db.query('app_data');
    _cache
      ..clear()
      ..addEntries(migrated.map((row) => MapEntry(
        row['data_key'] as String,
        row['data_value'] as String,
      )));
  }


  /// One-time conversion of legacy DZD amounts to integer Algerian centimes.
  /// Only explicitly named monetary fields are converted; quantities and weights stay unchanged.
  static Future<void> _migrateCurrencyValuesToCentimes(Database db) async {
    final marker = await db.query(
      'app_data',
      columns: const ['data_key'],
      where: 'data_key = ?',
      whereArgs: const [_centimeMigrationKey],
      limit: 1,
    );
    if (marker.isNotEmpty) return;

    const moneyFields = <String>{
      'purchasePrice', 'salePrice', 'stockUnitPrice', 'unitPrice', 'price',
      'total', 'subtotal', 'discount', 'paid', 'amount', 'balance',
      'openingBalance', 'paidSales', 'purchases', 'expenses', 'sales',
      'customerDebt', 'supplierDebt', 'cost',
      'purchase_price', 'sale_price', 'unit_price', 'line_total',
      'opening_balance', 'paid_sales', 'customer_debt', 'supplier_debt',
    };

    dynamic convert(dynamic value) {
      if (value is Map) {
        final result = <String, dynamic>{};
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final child = entry.value;
          if (moneyFields.contains(key) && child is num) {
            result[key] = (child * 100).round();
          } else {
            result[key] = convert(child);
          }
        }
        return result;
      }
      if (value is List) return value.map((item) => convert(item)).toList();
      return value;
    }

    await db.transaction((txn) async {
      final rows = await txn.query(
        'app_data',
        columns: const ['data_key', 'data_value'],
        where: "data_key LIKE 'batipro_%'",
      );
      final now = DateTime.now().toIso8601String();
      for (final row in rows) {
        final key = row['data_key'] as String;
        final raw = row['data_value'] as String;
        try {
          final decoded = jsonDecode(raw);
          final converted = jsonEncode(convert(decoded));
          if (converted != raw) {
            await txn.update(
              'app_data',
              {'data_value': converted, 'updated_at': now},
              where: 'data_key = ?',
              whereArgs: [key],
            );
          }
        } on FormatException {
          // Plain-text settings (such as the currency label) are not amounts.
        }
      }
      await txn.insert('app_data', {
        'data_key': _centimeMigrationKey,
        'data_value': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    final migrated = await db.query('app_data');
    _cache
      ..clear()
      ..addEntries(migrated.map((row) => MapEntry(
        row['data_key'] as String,
        row['data_value'] as String,
      )));
  }

  /// Exports every persisted key/value row without copying a live SQLite/WAL file.
  static Future<String> exportBackupJson() async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    final rows = await db.query('app_data', orderBy: 'data_key ASC');
    return jsonEncode({
      'format': 'BatiProDZ-backup',
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'data': rows.map((row) => {
        'key': row['data_key'],
        'value': row['data_value'],
        'updated_at': row['updated_at'],
      }).toList(),
    });
  }

  /// Validates a complete backup before replacing local data in one transaction.
  static Future<int> restoreBackupJson(String source) async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['format'] != 'BatiProDZ-backup' ||
        decoded['version'] != 1 || decoded['data'] is! List) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح أو غير مدعوم.');
    }
    final entries = <Map<String, String>>[];
    final seen = <String>{};
    for (final raw in decoded['data'] as List) {
      if (raw is! Map || raw['key'] is! String || raw['value'] is! String) {
        throw const FormatException('بيانات النسخة الاحتياطية غير مكتملة.');
      }
      final key = (raw['key'] as String).trim();
      if (key.isEmpty || !seen.add(key)) {
        throw const FormatException('توجد مفاتيح فارغة أو مكررة في النسخة الاحتياطية.');
      }
      entries.add({
        'data_key': key,
        'data_value': raw['value'] as String,
        'updated_at': raw['updated_at'] is String
            ? raw['updated_at'] as String
            : DateTime.now().toIso8601String(),
      });
    }
    if (entries.isEmpty) {
      throw const FormatException('النسخة الاحتياطية فارغة.');
    }
    await db.transaction((txn) async {
      await txn.delete('app_data');
      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert('app_data', entry);
      }
      await batch.commit(noResult: true);
    });
    _cache
      ..clear()
      ..addEntries(entries.map((entry) => MapEntry(entry['data_key']!, entry['data_value']!)));
    await _migrateCurrencyValuesToCentimes(db);
    return entries.length;
  }

  /// Closes the in-memory database between widget tests.
  static Future<void> resetForTests() async {
    final db = _database;
    _database = null;
    _cache.clear();
    if (db != null) await db.close();
  }

  static Future<AppStorage> getInstance() async {
    if (_database == null) {
      throw StateError('AppStorage.initialize() must complete before use.');
    }
    return AppStorage._();
  }

  String? getString(String key) => _cache[key];

  Set<String> getKeys() => _cache.keys.toSet();

  Future<bool> setString(String key, String value) async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    await db.insert(
      'app_data',
      {
        'data_key': key,
        'data_value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cache[key] = value;
    return true;
  }

  /// Persists related collections in one SQLite transaction.
  static Future<void> setStrings(Map<String, String> values) async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'app_data',
          {
            'data_key': entry.key,
            'data_value': entry.value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _cache.addAll(values);
  }

  static Future<void> clearAll() async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    await db.delete('app_data');
    _cache.clear();
  }

  Future<bool> remove(String key) async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    await db.delete('app_data', where: 'data_key = ?', whereArgs: [key]);
    _cache.remove(key);
    return true;
  }
}
