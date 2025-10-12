abstract class StorageBackend {
  Future<Map<String, dynamic>> loadJson(String name);
  Future<void> saveJson(String name, Map<String, dynamic> data);
}
