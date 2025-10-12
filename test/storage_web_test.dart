@TestOn('browser')
library;

import 'package:humble_ai_agent/services/storage_service.dart';
import 'package:test/test.dart';

void main() {
  test('StorageService persists config on web', () async {
    final storage = StorageService();
    final marker = DateTime.now().microsecondsSinceEpoch.toString();
    await storage.saveConfig({'marker': marker});
    final result = await storage.loadConfig();
    expect(result['marker'], marker);
  });
}
