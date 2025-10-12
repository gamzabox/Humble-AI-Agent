import 'storage/storage_backend.dart';

class StorageService {
  StorageService({String? baseDir, StorageBackend? backend})
    : _backend = backend ?? createStorageBackend(baseDir: baseDir);

  final StorageBackend _backend;

  Future<Map<String, dynamic>> loadJson(String name) => _backend.loadJson(name);

  Future<void> saveJson(String name, Map<String, dynamic> data) =>
      _backend.saveJson(name, data);

  Future<Map<String, dynamic>> loadConfig() => loadJson('config.json');

  Future<void> saveConfig(Map<String, dynamic> data) =>
      saveJson('config.json', data);

  Future<Map<String, dynamic>> loadSessions() => loadJson('sessions.json');

  Future<void> saveSessions(Map<String, dynamic> data) =>
      saveJson('sessions.json', data);
}
