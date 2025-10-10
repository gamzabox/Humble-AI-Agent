import 'dart:convert';
import 'dart:io';

class StorageService {
  final String? baseDir;
  StorageService({this.baseDir});

  Directory get _configDir {
    if (baseDir != null) return Directory(baseDir!);
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return Directory("$home/.config/humble-ai-agent");
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

  Future<Map<String, dynamic>> loadJson(String name) async {
    final file = await _ensureFile(name);
    final text = await file.readAsString();
    try {
      final data = jsonDecode(text);
      return (data is Map<String, dynamic>) ? data : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> saveJson(String name, Map<String, dynamic> data) async {
    final file = await _ensureFile(name);
    await file.writeAsString(jsonEncode(data));
  }

  Future<Map<String, dynamic>> loadConfig() => loadJson('config.json');
  Future<void> saveConfig(Map<String, dynamic> data) => saveJson('config.json', data);

  Future<Map<String, dynamic>> loadSessions() => loadJson('sessions.json');
  Future<void> saveSessions(Map<String, dynamic> data) => saveJson('sessions.json', data);
}

