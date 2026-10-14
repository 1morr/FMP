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

  test('changes fires after an install, a toggle and a removal', () async {
    final repository = PluginRepository(memoryDatabase());
    var events = 0;
    final subscription = repository.changes().listen((_) => events++);
    addTearDown(subscription.cancel);

    await repository.install(plugin('a'));
    await Future<void>.delayed(Duration.zero);
    final afterInstall = events;
    await repository.setEnabled('a', enabled: false);
    await Future<void>.delayed(Duration.zero);
    final afterToggle = events;
    await repository.remove('a');
    await Future<void>.delayed(Duration.zero);

    expect(afterInstall, greaterThan(0));
    expect(afterToggle, greaterThan(afterInstall));
    expect(events, greaterThan(afterToggle));
  });

  group('custom indexes', () {
    test('changes fires after an add and a removal, not for plugins', () async {
      final database = memoryDatabase();
      final repository = PluginIndexRepository(database);
      var events = 0;
      final subscription = repository.changes().listen((_) => events++);
      addTearDown(subscription.cancel);

      await PluginRepository(database).install(plugin('a'));
      await Future<void>.delayed(Duration.zero);
      expect(events, 0);
      await repository.add('https://a.test/i.json', DateTime.utc(2026, 1, 1));
      await Future<void>.delayed(Duration.zero);
      final afterAdd = events;
      await repository.remove('https://a.test/i.json');
      await Future<void>.delayed(Duration.zero);

      expect(afterAdd, greaterThan(0));
      expect(events, greaterThan(afterAdd));
    });

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

  group('development folder rows', () {
    InstalledPlugin marked(String id, {String version = '1.0.0'}) =>
        InstalledPlugin(
          id: id,
          version: version,
          manifestJson: '{"id":"$id"}',
          script: 'export default {};',
          installedAt: DateTime.utc(2026, 9, 29, 12, 30, 15, 250),
          fromDevFolder: true,
        );

    test('inserts a marked row when there is none', () async {
      final repository = PluginRepository(memoryDatabase());

      expect(await repository.putDevFolderRow(plugin('a')), isTrue);

      expect(await repository.byId('a'), marked('a'));
    });

    test('updates the content of a marked row', () async {
      final repository = PluginRepository(memoryDatabase());
      await repository.putDevFolderRow(plugin('a'));

      final updated = InstalledPlugin(
        id: 'a',
        version: '2.0.0',
        manifestJson: '{"id":"a","v":2}',
        script: 'export const x = 2;',
        installedAt: DateTime.utc(2030),
      );
      expect(await repository.putDevFolderRow(updated), isTrue);

      final row = (await repository.byId('a'))!;
      expect(row.version, '2.0.0');
      expect(row.manifestJson, '{"id":"a","v":2}');
      expect(row.script, 'export const x = 2;');
      expect(row.fromDevFolder, isTrue);
    });

    test('leaves an installed row untouched', () async {
      final repository = PluginRepository(memoryDatabase());
      final installed = InstalledPlugin(
        id: 'a',
        version: '1.0.0',
        manifestJson: '{"id":"a"}',
        script: 'installed',
        installedAt: DateTime.utc(2026),
        enabled: true,
        sourceIndexUrl: 'https://example.invalid/index.json',
        checksJson: '{}',
      );
      await repository.install(installed);
      await repository.setEnabled('a', enabled: false);
      final before = (await repository.byId('a'))!;

      expect(
        await repository.putDevFolderRow(plugin('a', version: '9.9.9')),
        isFalse,
      );

      // 每個欄位都不動（含 manifest、來源 index、安裝時間）。
      expect(await repository.byId('a'), before);
      expect(before.fromDevFolder, isFalse);
      expect(before.enabled, isFalse);
    });

    test(
      'removes marked rows with their storage, never installed ones',
      () async {
        final database = memoryDatabase();
        final plugins = PluginRepository(database);
        final storage = PluginStorageRepository(database);
        await plugins.install(plugin('installed'));
        await plugins.putDevFolderRow(plugin('marked'));
        await plugins.putDevFolderRow(plugin('kept'));
        await storage.write('installed', 'k', 'i');
        await storage.write('marked', 'k', 'm');
        await storage.write('kept', 'k', 'p');

        final removed = await plugins.removeDevFolderRows(keep: {'kept'});

        expect(removed, ['marked']);
        expect(await plugins.byId('marked'), isNull);
        expect(await storage.read('marked', 'k'), isNull);
        expect(await plugins.byId('installed'), isNotNull);
        expect(await storage.read('installed', 'k'), 'i');
        expect(await plugins.byId('kept'), isNotNull);
        expect(await storage.read('kept', 'k'), 'p');
        expect(await plugins.removeDevFolderRows(), ['kept']);
        expect(await plugins.byId('installed'), isNotNull);
      },
    );

    test('installing converts a marked row and keeps its storage', () async {
      final database = memoryDatabase();
      final plugins = PluginRepository(database);
      final storage = PluginStorageRepository(database);
      await plugins.putDevFolderRow(plugin('a'));
      await storage.write('a', 'k', 'v');

      await plugins.install(plugin('a', version: '2.0.0'));

      expect((await plugins.byId('a'))!.fromDevFolder, isFalse);
      expect(await plugins.removeDevFolderRows(), isEmpty);
      expect(await storage.read('a', 'k'), 'v');
    });
  });
}
