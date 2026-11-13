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




  static Future<void> _saveMetadata(
    AppStorage storage,
    int cursor,
    Map<String, dynamic> documents, {
    Map<String, dynamic>? keepLocalUntil,
    List<Map<String, dynamic>>? conflicts,
    List<Map<String, dynamic>>? pendingMutations,
  }) async {
    final data = <String, dynamic>{
      'cursor': cursor,
      'documents': documents,
      'keep_local_until': keepLocalUntil ?? <String, dynamic>{},
      if (conflicts != null && conflicts.isNotEmpty) 'conflicts': conflicts,
      if (pendingMutations != null && pendingMutations.isNotEmpty)
        'pending_mutations': pendingMutations,
    };
    await storage.setString(_metadataKey, jsonEncode(data));
  }

  static String? _mergeRecordArrays(String? baseJson, String? localJson, String? serverJson) {
    if (localJson == null || serverJson == null) return null;
    try {
      final localRaw = jsonDecode(localJson);
      final serverRaw = jsonDecode(serverJson);
      final baseRaw = baseJson == null ? <dynamic>[] : jsonDecode(baseJson);
      if (localRaw is! List || serverRaw is! List || baseRaw is! List) return null;

      Map<String, Map<String, dynamic>> index(List<dynamic> values) {
        final result = <String, Map<String, dynamic>>{};
        for (final raw in values) {
          if (raw is! Map || raw['id'] == null) throw const FormatException('Missing record id');
          final id = raw['id'].toString().trim();
          if (id.isEmpty || result.containsKey(id)) throw const FormatException('Invalid record id');
          result[id] = Map<String, dynamic>.from(raw);
        }
        return result;
      }

      final base = index(baseRaw);
      final local = index(localRaw);
      final server = index(serverRaw);
      bool equal(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
          a == null || b == null ? a == null && b == null : jsonEncode(a) == jsonEncode(b);
      final ids = <String>{...base.keys, ...local.keys, ...server.keys};
      final merged = <Map<String, dynamic>>[];
      for (final id in ids) {
        final hasBase = base.containsKey(id);
        final hasLocal = local.containsKey(id);
        final hasServer = server.containsKey(id);
        final b = base[id], l = local[id], r = server[id];
        if (!hasBase) {
          if (hasLocal && hasServer && !equal(l, r)) return null;
          if (hasLocal) merged.add(l!);
          else if (hasServer) merged.add(r!);
          continue;
        }
        final localChanged = hasLocal != hasBase || (hasLocal && !equal(l, b));
        final serverChanged = hasServer != hasBase || (hasServer && !equal(r, b));
        if (localChanged && serverChanged) {
          if (hasLocal != hasServer || (hasLocal && !equal(l, r))) return null;
          if (hasLocal) merged.add(l!);
        } else if (localChanged) {
          if (hasLocal) merged.add(l!);
        } else if (hasServer) {
          merged.add(r!);
        }
      }
      return jsonEncode(merged);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> pendingConflicts() async {
    final storage = await AppStorage.getInstance();
    final metadata = _readMetadata(storage);
    return (metadata['conflicts'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<void> resolveConflict(String key, {required bool keepLocal}) async {
    final storage = await AppStorage.getInstance();
    final metadata = _readMetadata(storage);
    final documents = Map<String, dynamic>.from(metadata['documents'] as Map? ?? {});
    final keepLocalUntil = Map<String, dynamic>.from(metadata['keep_local_until'] as Map? ?? {});
    final pendingMutations = (metadata['pending_mutations'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
    final conflicts = (metadata['conflicts'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
    final index = conflicts.indexWhere((item) => item['key'] == key);
    if (index < 0) throw StateError('لم يتم العثور على التعارض المطلوب.');
    final conflict = conflicts.removeAt(index);
    final serverValue = conflict['server_value'] as String?;
    final serverDeleted = conflict['server_deleted'] == true;
    final serverRevision = (conflict['server_revision'] as num).toInt();
    documents[key] = {
      'revision': serverRevision,
      'value': serverValue,
      'deleted': serverDeleted,
    };
    if (keepLocal) {
      keepLocalUntil[key] = serverRevision;
    } else {
      keepLocalUntil.remove(key);
    }
    if (!keepLocal) {
      if (serverDeleted) {
        await storage.remove(key);
      } else if (serverValue != null) {
        await storage.setString(key, serverValue);
      }
    }
    await _saveMetadata(
      storage,
      (metadata['cursor'] as num?)?.toInt() ?? 0,
      documents,
      keepLocalUntil: keepLocalUntil,
      conflicts: conflicts,
      pendingMutations: (metadata['pending_mutations'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)).toList(),
    );
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
    final keepLocalUntil = Map<String, dynamic>.from(metadata['keep_local_until'] as Map? ?? {});
    if ((metadata['conflicts'] as List? ?? const []).isNotEmpty) {
      throw StateError('يوجد تعارض محفوظ. اختر النسخة التي تريد الاحتفاظ بها أولاً.');
    }
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
          metadata['conflicts'] = [{
            'key': key, 'server_revision': remote['revision'],
            'server_value': value, 'server_deleted': deleted,
            'local_value': localValue, 'local_deleted': false,
          }];
          await storage.setString(_metadataKey, jsonEncode({
            'cursor': cursor, 'documents': documents, 'conflicts': metadata['conflicts'],
          }));
          throw StateError('تعارض في بيانات "$key". اختر النسخة المحلية أو نسخة الخادم.');
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
      await _saveMetadata(storage, cursor, documents,
          keepLocalUntil: keepLocalUntil, pendingMutations: pendingMutations);
    }

    bool eligible(String key) => key.startsWith('batipro_') &&
        !key.startsWith('batipro_sync_') && key != 'batipro_auto_backup_day';

    final localKeys = storage.getKeys().where(eligible).toSet();
    final knownKeys = documents.keys.toSet();
    final pendingKeys = pendingMutations.map((item) => item['key'] as String).toSet();

    // Persist each mutation ID before sending it. If the response is lost after
    // PostgreSQL commits, the next attempt reuses the same ID and is idempotent.
    for (final key in localKeys) {
      if (pendingKeys.contains(key)) continue;
      final value = storage.getString(key);
      final known = documents[key] is Map
          ? Map<String, dynamic>.from(documents[key] as Map)
          : <String, dynamic>{'revision': 0, 'value': null, 'deleted': true};
      if (value == null || (known['deleted'] != true && known['value'] == value)) continue;
      pendingMutations.add({
        'mutation_id': _newId(), 'key': key, 'value': value,
        'deleted': false, 'base_revision': (known['revision'] as num?)?.toInt() ?? 0,
      });
      pendingKeys.add(key);
    }

    for (final key in knownKeys.difference(localKeys)) {
      if (pendingKeys.contains(key)) continue;
      final known = Map<String, dynamic>.from(documents[key] as Map);
      if (known['deleted'] == true) continue;
      pendingMutations.add({
        'mutation_id': _newId(), 'key': key, 'value': null,
        'deleted': true, 'base_revision': (known['revision'] as num?)?.toInt() ?? 0,
      });
      pendingKeys.add(key);
    }

    await _saveMetadata(storage, cursor, documents,
        keepLocalUntil: keepLocalUntil, pendingMutations: pendingMutations);
    final mutations = List<Map<String, dynamic>>.from(pendingMutations);
    final mutationValues = <String, Map<String, dynamic>>{
      for (final mutation in mutations)
        mutation['mutation_id'] as String: {
          'key': mutation['key'], 'value': mutation['value'],
          'deleted': mutation['deleted'],
        },
    };

    var pushed = 0;
    for (var offset = 0; offset < mutations.length; offset += 10) {
      final batch = mutations.skip(offset).take(10).toList(growable: false);
      final response = await api.pushSyncChanges(deviceId: deviceId, mutations: batch);
      final accepted = (response['accepted'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map));
      final acceptedIds = <String>{};
      for (final item in accepted) {
        final mutationId = item['mutation_id'] as String;
        final mutation = mutationValues[mutationId];
        if (mutation == null) continue;
        acceptedIds.add(mutationId);
        documents[mutation['key'] as String] = {
          'revision': (item['revision'] as num).toInt(),
          'value': mutation['value'], 'deleted': mutation['deleted'],
        };
        pushed++;
      }
      pendingMutations.removeWhere((item) => acceptedIds.contains(item['mutation_id']));
      await _saveMetadata(storage, cursor, documents,
          keepLocalUntil: keepLocalUntil, pendingMutations: pendingMutations);
      final conflicts = (response['conflicts'] as List? ?? const []);
      if (conflicts.isNotEmpty) {
        final conflictIds = conflicts.map((raw) =>
            (raw as Map)['mutation_id'] as String).toSet();
        pendingMutations.removeWhere((item) => conflictIds.contains(item['mutation_id']));
        final pending = <Map<String, dynamic>>[];
        var mergedAny = false;
        for (final raw in conflicts) {
          final conflict = Map<String, dynamic>.from(raw as Map);
          final key = conflict['key'] as String;
          final known = documents[key] is Map
              ? Map<String, dynamic>.from(documents[key] as Map)
              : <String, dynamic>{};
          final serverDeleted = conflict['server_deleted'] == true;
          final serverValue = conflict['server_value'] as String?;
          final merged = _mergeRecordArrays(
            known['value'] as String?,
            storage.getString(key),
            serverDeleted ? '[]' : serverValue,
          );
          if (merged != null && !serverDeleted) {
            await storage.setString(key, merged);
            final serverRevision = (conflict['server_revision'] as num).toInt();
            documents[key] = {
              'revision': serverRevision,
              'value': serverValue,
              'deleted': false,
            };
            keepLocalUntil[key] = serverRevision;
            mergedAny = true;
          } else {
            final localValue = storage.getString(key);
            pending.add({
              'key': key,
              'server_revision': conflict['server_revision'],
              'server_value': serverValue,
              'server_deleted': serverDeleted,
              'local_value': localValue,
              'local_deleted': localValue == null,
            });
          }
        }
        if (pending.isNotEmpty) metadata['conflicts'] = pending;
        await _saveMetadata(storage, cursor, documents, keepLocalUntil: keepLocalUntil,
            conflicts: pending, pendingMutations: pendingMutations);
        if (mergedAny && pending.isEmpty) {
          throw StateError('دمجنا السجلات الجديدة غير المتعارضة. أعد المزامنة لإرسال الدمج إلى الخادم.');
        }
        throw StateError('توجد تعديلات متعارضة على نفس السجل. اختر النسخة التي تريد الاحتفاظ بها.');
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
        final keepUntil = (keepLocalUntil[key] as num?)?.toInt();
        if (keepUntil != null && revision <= keepUntil) {
          processedCursor = (change['event_id'] as num).toInt();
          if (revision >= keepUntil) keepLocalUntil.remove(key);
          pulled++;
          continue;
        }
        final localMatchesBase = known['deleted'] == true
            ? localValue == null : localValue == known['value'];

        // A newer local edit may have happened after this device queued and
        // uploaded an older snapshot. Advance the server revision without
        // replacing that newer SQLite value; the next pass uploads it.
        final localDiffersFromOwnEvent = deleted
            ? localValue != null
            : localValue != value;
        if (change['device_id'] == deviceId && !localMatchesBase &&
            localDiffersFromOwnEvent) {
          documents[key] = {'revision': revision, 'value': value, 'deleted': deleted};
          processedCursor = (change['event_id'] as num).toInt();
          pulled++;
          continue;
        }

        if (change['device_id'] != deviceId && !localMatchesBase) {
          final merged = _mergeRecordArrays(
            known['value'] as String?,
            localValue,
            deleted ? '[]' : value,
          );
          if (merged != null && !deleted) {
            await storage.setString(key, merged);
            documents[key] = {'revision': revision, 'value': value, 'deleted': false};
            processedCursor = (change['event_id'] as num).toInt();
            pulled++;
            continue;
          }
          final pending = (metadata['conflicts'] as List? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map)).toList();
          if (!pending.any((item) => item['key'] == key)) {
            pending.add({
              'key': key, 'server_revision': revision,
              'server_value': value, 'server_deleted': deleted,
              'local_value': localValue, 'local_deleted': localValue == null,
            });
          }
          metadata['conflicts'] = pending;
          await _saveMetadata(storage, processedCursor, documents,
              keepLocalUntil: keepLocalUntil, conflicts: pending,
              pendingMutations: pendingMutations);
          throw StateError('تعارض أثناء استقبال "$key". اختر النسخة التي تريد الاحتفاظ بها.');
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
      await _saveMetadata(storage, cursor, documents,
          keepLocalUntil: keepLocalUntil, pendingMutations: pendingMutations);
      pages++;
      if (page['has_more'] != true || pages > 1000) break;
    }

    await _saveMetadata(storage, cursor, documents,
        keepLocalUntil: keepLocalUntil, pendingMutations: pendingMutations);
    return {'pushed': pushed, 'pulled': pulled, 'cursor': cursor, 'device_id': deviceId};
    } finally {
      _isRunning = false;
    }
  }
}
