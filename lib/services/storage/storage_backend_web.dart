import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
// ignore: avoid_web_libraries_in_flutter
import 'dart:indexed_db' as idb;

import 'storage_backend_interface.dart';

class IndexedDbStorageBackend implements StorageBackend {
  IndexedDbStorageBackend({
    this.dbName = 'humble_ai_agent',
    this.storeName = 'files',
    idb.IdbFactory? factory,
  }) : _factory =
           factory ??
           window.indexedDB ??
           (throw UnsupportedError('IndexedDB not supported'));

  final idb.IdbFactory _factory;
  final String dbName;
  final String storeName;
  idb.Database? _database;

  Future<idb.Database> _openDb() async {
    if (_database != null) return _database!;
    final db = await _factory.open(
      dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final request = event.target as idb.Request;
        final database = request.result as idb.Database;
        if (!database.objectStoreNames!.contains(storeName)) {
          database.createObjectStore(storeName);
        }
      },
    );
    _database = db;
    return db;
  }

  Map<String, dynamic> _decode(Object? value) {
    if (value == null) return <String, dynamic>{};
    if (value is Map) {
      return Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded as Map<dynamic, dynamic>);
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> loadJson(String name) async {
    final db = await _openDb();
    final txn = db.transaction(storeName, 'readonly');
    final store = txn.objectStore(storeName);
    final value = await store.getObject(name);
    await txn.completed;
    return _decode(value);
  }

  @override
  Future<void> saveJson(String name, Map<String, dynamic> data) async {
    final db = await _openDb();
    final txn = db.transaction(storeName, 'readwrite');
    final store = txn.objectStore(storeName);
    await store.put(jsonEncode(data), name);
    await txn.completed;
  }
}

StorageBackend createStorageBackend({String? baseDir}) {
  if (baseDir != null) {
    throw UnsupportedError('baseDir override is not supported on web');
  }
  return IndexedDbStorageBackend();
}
