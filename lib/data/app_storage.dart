import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart' as legacy_prefs;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite-backed local persistence. Existing SharedPreferences values are
/// copied once and retained there until the user has a verified backup.
class AppStorage {
  AppStorage._();

  static Database? _database;
  static final Map<String, String> _cache = <String, String>{};
  static const String _migrationKey = '__legacy_shared_preferences_migrated_v1';

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

  Future<bool> remove(String key) async {
    final db = _database;
    if (db == null) throw StateError('SQLite database is not initialized.');
    await db.delete('app_data', where: 'data_key = ?', whereArgs: [key]);
    _cache.remove(key);
    return true;
  }
}
