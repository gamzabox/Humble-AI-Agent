import 'dart:convert';
import 'dart:io';

import 'storage_backend_interface.dart';

class IoStorageBackend implements StorageBackend {
  IoStorageBackend({this.baseDir});

  final String? baseDir;

  Directory get _configDir {
    if (baseDir != null) return Directory(baseDir!);
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return Directory('$home/.config/humble-ai-agent');
  }

  Future<File> _ensureFile(String name) async {
    final dir = _configDir;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$name');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('{}');
    }
    return file;
  }

  @override
  Future<Map<String, dynamic>> loadJson(String name) async {
    final file = await _ensureFile(name);
    final text = await file.readAsString();
    try {
      final data = jsonDecode(text);
      if (data is Map) {
        return Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
      }
    } catch (_) {
      // fall through to empty map
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> saveJson(String name, Map<String, dynamic> data) async {
    final file = await _ensureFile(name);
    await file.writeAsString(jsonEncode(data));
  }
}

StorageBackend createStorageBackend({String? baseDir}) =>
    IoStorageBackend(baseDir: baseDir);
