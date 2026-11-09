import 'dart:convert';
import 'dart:math';

import 'api_client.dart';
import 'app_storage.dart';

/// Manual Windows sync with per-document optimistic concurrency.
/// Conflicts are surfaced and local values are never silently overwritten.
class CloudSyncService {
  CloudSyncService._();

  static const _metadataKey = '__batipro_sync_meta_v1';
  static bool _isRunning = false;
  static bool get isRunning => _isRunning;
  static String _newId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _deviceId() => ApiClient.instance.getOrCreateDeviceId();

  static Map<String, dynamic> _readMetadata(AppStorage storage) {
    final raw = storage.getString(_metadataKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{'cursor': 0, 'documents': <String, dynamic>{}};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('بيانات متابعة المزامنة المحلية غير صالحة.');
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, dynamic>> synchronize() async {
    if (_isRunning) throw StateError('المزامنة جارية بالفعل.');
    _isRunning = true;
    try {
    final api = ApiClient.instance;
    if (!api.isAuthenticated) throw StateError('سجّل الدخول إلى خادم PostgreSQL أولاً.');
    final storage = await AppStorage.getInstance();
    final deviceId = await _deviceId();
    final metadata = _readMetadata(storage);
    final documents = Map<String, dynamic>.from(metadata['documents'] as Map? ?? {});
    var cursor = (metadata['cursor'] as num?)?.toInt() ?? 0;

    var pulled = 0;

    // A new installation starts from a consistent server snapshot, not old
    // event history, so pre-existing local values are never blindly replaced.
    if (documents.isEmpty && cursor == 0) {
      final snapshot = await api.syncSnapshot();
      final remoteDocuments = (snapshot['documents'] as List? ?? const []);
      for (final raw in remoteDocuments) {
        final remote = Map<String, dynamic>.from(raw as Map);
        final key = remote['key'] as String;
        final deleted = remote['deleted'] == true;
        final value = remote['value'] as String?;
        final localValue = storage.getString(key);
        final compatible = localValue == null || (!deleted && localValue == value);
        if (!compatible) {
          await storage.setString(_metadataKey,
              jsonEncode({'cursor': cursor, 'documents': documents}));
          throw StateError('هذا الجهاز يحتوي بيانات محلية مختلفة عن الخادم في "$key". لم ندمجها تلقائياً حتى لا تضيع أي نسخة.');
        }
        if (deleted) {
          await storage.remove(key);
        } else if (value != null) {
          await storage.setString(key, value);
        }
        documents[key] = {
          'revision': (remote['revision'] as num).toInt(),
          'value': value,
          'deleted': deleted,
        };
        pulled++;
      }
      cursor = (snapshot['cursor'] as num?)?.toInt() ?? 0;
      await storage.setString(_metadataKey,
          jsonEncode({'cursor': cursor, 'documents': documents}));
    }

    bool eligible(String key) => key.startsWith('batipro_') &&
        !key.startsWith('batipro_sync_') && key != 'batipro_auto_backup_day';

    final localKeys = storage.getKeys().where(eligible).toSet();
    final knownKeys = documents.keys.toSet();
    final mutations = <Map<String, dynamic>>[];
    final mutationValues = <String, Map<String, dynamic>>{};

    for (final key in localKeys) {
      final value = storage.getString(key);
      final known = documents[key] is Map
          ? Map<String, dynamic>.from(documents[key] as Map)
          : <String, dynamic>{'revision': 0, 'value': null, 'deleted': true};
      if (value == null || (known['deleted'] != true && known['value'] == value)) continue;
      final mutationId = _newId();
      mutations.add({
        'mutation_id': mutationId, 'key': key, 'value': value,
        'deleted': false, 'base_revision': (known['revision'] as num?)?.toInt() ?? 0,
      });
      mutationValues[mutationId] = {'key': key, 'value': value, 'deleted': false};
    }

    for (final key in knownKeys.difference(localKeys)) {
      final known = Map<String, dynamic>.from(documents[key] as Map);
      if (known['deleted'] == true) continue;
      final mutationId = _newId();
      mutations.add({
        'mutation_id': mutationId, 'key': key, 'value': null,
        'deleted': true, 'base_revision': (known['revision'] as num?)?.toInt() ?? 0,
      });
      mutationValues[mutationId] = {'key': key, 'value': null, 'deleted': true};
    }

    var pushed = 0;
    for (var offset = 0; offset < mutations.length; offset += 10) {
      final batch = mutations.skip(offset).take(10).toList(growable: false);
      final response = await api.pushSyncChanges(deviceId: deviceId, mutations: batch);
      final accepted = (response['accepted'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map));
      for (final item in accepted) {
        final mutation = mutationValues[item['mutation_id']];
        if (mutation == null) continue;
        documents[mutation['key'] as String] = {
          'revision': (item['revision'] as num).toInt(),
          'value': mutation['value'], 'deleted': mutation['deleted'],
        };
        pushed++;
      }
      await storage.setString(_metadataKey, jsonEncode({'cursor': cursor, 'documents': documents}));
      final conflicts = (response['conflicts'] as List? ?? const []);
      if (conflicts.isNotEmpty) {
        final first = Map<String, dynamic>.from(conflicts.first as Map);
        throw StateError('تعارض في البيانات "${first['key']}". احتفظنا بنسختك المحلية ولم نستبدلها.');
      }
    }

    var pages = 0;
    while (true) {
      final page = await api.pullSyncChanges(deviceId: deviceId, after: cursor, limit: 200);
      final changes = (page['changes'] as List? ?? const []);
      if (changes.isEmpty) break;
      var processedCursor = cursor;
      for (final raw in changes) {
        final change = Map<String, dynamic>.from(raw as Map);
        final key = change['key'] as String;
        final revision = (change['revision'] as num).toInt();
        final deleted = change['deleted'] == true;
        final value = change['value'] as String?;
        final known = documents[key] is Map
            ? Map<String, dynamic>.from(documents[key] as Map)
            : <String, dynamic>{'revision': 0, 'value': null, 'deleted': true};
        final localValue = storage.getString(key);
        final localMatchesBase = known['deleted'] == true
            ? localValue == null : localValue == known['value'];
        if (change['device_id'] != deviceId && !localMatchesBase) {
          await storage.setString(_metadataKey, jsonEncode({'cursor': processedCursor, 'documents': documents}));
          throw StateError('تعارض أثناء استقبال "$key". احتفظنا بنسختك المحلية ولم نتجاوز هذا التغيير.');
        }
        if (deleted) {
          await storage.remove(key);
        } else if (value != null) {
          await storage.setString(key, value);
        }
        documents[key] = {'revision': revision, 'value': value, 'deleted': deleted};
        processedCursor = (change['event_id'] as num).toInt();
        pulled++;
      }
      cursor = processedCursor;
      await storage.setString(_metadataKey, jsonEncode({'cursor': cursor, 'documents': documents}));
      pages++;
      if (page['has_more'] != true || pages > 1000) break;
    }

    await storage.setString(_metadataKey, jsonEncode({'cursor': cursor, 'documents': documents}));
    return {'pushed': pushed, 'pulled': pulled, 'cursor': cursor, 'device_id': deviceId};
    } finally {
      _isRunning = false;
    }
  }
}
