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

  group('enabled and index source', () {
    test('a new plugin is enabled and has no source or checks', () async {
      final repository = PluginRepository(memoryDatabase());

      await repository.install(plugin('a'));

      final stored = (await repository.byId('a'))!;
      expect(stored.enabled, isTrue);
      expect(stored.sourceIndexUrl, isNull);
      expect(stored.checksJson, isNull);
    });

    test('setEnabled switches a plugin and leaves the others', () async {
      final repository = PluginRepository(memoryDatabase());
      await repository.install(plugin('a'));
      await repository.install(plugin('b'));

      await repository.setEnabled('a', enabled: false);

      expect((await repository.byId('a'))!.enabled, isFalse);
      expect((await repository.byId('b'))!.enabled, isTrue);
      await repository.setEnabled('a', enabled: true);
      expect((await repository.byId('a'))!.enabled, isTrue);
      // 沒有這個插件：什麼都不發生。
      await repository.setEnabled('missing', enabled: false);
      expect(await repository.list(), hasLength(2));
    });

    test('updating a disabled plugin keeps it disabled', () async {
      final repository = PluginRepository(memoryDatabase());
      await repository.install(plugin('a'));
      await repository.setEnabled('a', enabled: false);

      await repository.install(plugin('a', version: '2.0.0'));

      final stored = (await repository.byId('a'))!;
      expect(stored.version, '2.0.0');
      expect(stored.enabled, isFalse);
    });

    test('the source index and the checks are replaced on update', () async {
      final repository = PluginRepository(memoryDatabase());
      await repository.install(
        InstalledPlugin(
          id: 'a',
          version: '1.0.0',
          manifestJson: '{}',
          script: 's',
          installedAt: DateTime.utc(2026),
          sourceIndexUrl: 'https://one.test/index.json',
          checksJson: '{"search":{}}',
        ),
      );
      expect((await repository.byId('a'))!.checksJson, '{"search":{}}');

      // 新版本沒有檢查案例（驗證不過）：舊版本的案例不留下。
      await repository.install(
        InstalledPlugin(
          id: 'a',
          version: '2.0.0',
          manifestJson: '{}',
          script: 's',
          installedAt: DateTime.utc(2026),
          sourceIndexUrl: 'https://one.test/index.json',
        ),
      );

      final stored = (await repository.byId('a'))!;
      expect(stored.sourceIndexUrl, 'https://one.test/index.json');
      expect(stored.checksJson, isNull);
    });
  });

  group('custom indexes', () {
    test('adds, lists oldest first and removes', () async {
      final repository = PluginIndexRepository(memoryDatabase());

      await repository.add('https://b.test/i.json', DateTime.utc(2026, 1, 2));
      await repository.add('https://a.test/i.json', DateTime.utc(2026, 1, 1));

      expect(await repository.list(), [
        PluginIndexRecord(
          url: 'https://a.test/i.json',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
        PluginIndexRecord(
          url: 'https://b.test/i.json',
          addedAt: DateTime.utc(2026, 1, 2),
        ),
      ]);
      await repository.remove('https://a.test/i.json');
      expect((await repository.list()).map((r) => r.url), [
        'https://b.test/i.json',
      ]);
    });

    test('adding a known url keeps the first time', () async {
      final repository = PluginIndexRepository(memoryDatabase());
      await repository.add('https://a.test/i.json', DateTime.utc(2026, 1, 1));

      await repository.add('https://a.test/i.json', DateTime.utc(2026, 5, 5));

      expect(
        (await repository.list()).single.addedAt,
        DateTime.utc(2026, 1, 1),
      );
    });

    test('addedAt is UTC epoch milliseconds', () async {
      final database = memoryDatabase();
      await PluginIndexRepository(database).add(
        'https://a.test/i.json',
        DateTime.utc(2026, 9, 29, 12, 30, 15, 250),
      );

      final row = await database
          .customSelect('SELECT added_at FROM plugin_indexes')
          .getSingle();

      expect(row.read<int>('added_at'), 1790685015250);
    });
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
