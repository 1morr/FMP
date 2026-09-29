import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';

import '../../support/memory_database.dart';

InstalledPlugin plugin(String id, {String version = '1.0.0'}) =>
    InstalledPlugin(
      id: id,
      version: version,
      manifestJson: '{"id":"$id"}',
      script: 'export default {};',
      installedAt: DateTime.utc(2026, 9, 29, 12, 30, 15, 250),
    );

void main() {
  test('installs, reads by id and lists in id order', () async {
    final repository = PluginRepository(memoryDatabase());

    await repository.install(plugin('b'));
    await repository.install(plugin('a'));

    expect(await repository.byId('a'), plugin('a'));
    expect(await repository.byId('missing'), isNull);
    expect(await repository.list(), [plugin('a'), plugin('b')]);
  });

  test('installing the same id again updates it', () async {
    final repository = PluginRepository(memoryDatabase());

    await repository.install(plugin('a'));
    await repository.install(plugin('a', version: '2.0.0'));

    expect(await repository.list(), [plugin('a', version: '2.0.0')]);
  });

  group('stored format', () {
    test('installedAt is UTC epoch milliseconds', () async {
      final database = memoryDatabase();
      // plugin() 的 installedAt 是 2026-09-29T12:30:15.250Z。
      await PluginRepository(database).install(plugin('a'));

      final row = await database
          .customSelect('SELECT installed_at FROM installed_plugins')
          .getSingle();

      expect(row.read<int>('installed_at'), 1790685015250);
      expect(
        (await PluginRepository(database).byId('a'))!.installedAt.isUtc,
        isTrue,
      );
    });
  });

  group('plugin storage lifetime', () {
    test('removing a plugin removes its storage', () async {
      final database = memoryDatabase();
      final plugins = PluginRepository(database);
      final storage = PluginStorageRepository(database);
      await plugins.install(plugin('a'));
      await plugins.install(plugin('b'));
      await storage.write('a', 'buvid', 'x');
      await storage.write('b', 'buvid', 'y');

      await plugins.remove('a');

      expect(await plugins.byId('a'), isNull);
      expect(await storage.read('a', 'buvid'), isNull);
      expect(await storage.read('b', 'buvid'), 'y');
      // 直接查表，確認不是只有讀不到而是真的刪掉。
      final rows = await database
          .customSelect("SELECT * FROM plugin_storage WHERE plugin_id = 'a'")
          .get();
      expect(rows, isEmpty);
    });

    test('updating a plugin keeps its storage', () async {
      final database = memoryDatabase();
      final plugins = PluginRepository(database);
      final storage = PluginStorageRepository(database);
      await plugins.install(plugin('a'));
      await storage.write('a', 'buvid', 'x');

      await plugins.install(plugin('a', version: '2.0.0'));

      expect(await storage.read('a', 'buvid'), 'x');
    });
  });
}
