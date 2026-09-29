import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';

import '../../support/memory_database.dart';

void main() {
  late PluginStorageRepository storage;

  setUp(() async {
    final database = memoryDatabase();
    storage = PluginStorageRepository(database);
    for (final id in ['a', 'b']) {
      await PluginRepository(database).install(
        InstalledPlugin(
          id: id,
          version: '1.0.0',
          manifestJson: '{}',
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
    }
  });

  test('reads null for a key that was never written', () async {
    expect(await storage.read('a', 'buvid'), isNull);
  });

  test('writes, overwrites and deletes a key', () async {
    await storage.write('a', 'buvid', 'first');
    expect(await storage.read('a', 'buvid'), 'first');

    await storage.write('a', 'buvid', 'second');
    expect(await storage.read('a', 'buvid'), 'second');

    await storage.delete('a', 'buvid');
    expect(await storage.read('a', 'buvid'), isNull);

    // 刪除不存在的 key 不算錯。
    await storage.delete('a', 'buvid');
  });

  test('keys are separate per plugin', () async {
    await storage.write('a', 'buvid', 'x');
    await storage.write('b', 'buvid', 'y');
    await storage.delete('a', 'buvid');

    expect(await storage.read('a', 'buvid'), isNull);
    expect(await storage.read('b', 'buvid'), 'y');
  });

  test('writing for a plugin that is not installed fails', () async {
    await expectLater(
      storage.write('missing', 'buvid', 'x'),
      throwsA(anything),
    );
    expect(await storage.read('missing', 'buvid'), isNull);
  });
}
