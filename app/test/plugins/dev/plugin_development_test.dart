import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/plugins/dev/dev_folder.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:path/path.dart' as p;

import '../../support/pump_until.dart';
import '../plugin_harness.dart';
import 'dev_support.dart';

// 開發資料夾的載入與標記列的生命週期（M3 PR 16b，design §3.3、§3.4）。不連網：以
// `fmp-test` 的複本當資料夾，插件不發請求。

Future<void> _until(bool Function() condition) =>
    pumpUntil(condition, maxRounds: 1000);

/// 開發資料夾的動作都做完（序列的屏障：不在開發中的 id 的重新載入什麼都不做）。
Future<void> _idle(ProviderContainer container) async {
  await container.read(pluginDevFolderProvider.future);
  await settle();
  await container.read(pluginDevelopmentProvider.notifier).reload('~barrier~');
}

String _installedSource({String version = '0.9.0'}) =>
    scriptOf(fixturePlugin('test_plugin'))
        .readAsStringSync()
        .replaceFirst('"version": "1.0.0"', '"version": "$version"');

void main() {
  late PluginHarness harness;
  late Directory root;

  setUp(() {
    harness = PluginHarness();
    root = tempFolder();
  });

  ProviderContainer start({bool pluginDevTools = true}) {
    final container = devContainer(harness, pluginDevTools: pluginDevTools);
    container.listen(pluginDevelopmentProvider, (_, _) {});
    return container;
  }

  String versionOf(ProviderContainer container, String id) =>
      container.read(pluginRegistryProvider).value![id]!.manifest.version;

  bool applied(ProviderContainer container) =>
      container.read(pluginDevelopmentProvider)?.busy == false;

  test('without an installed row it adds a marked row and loads the dev '
      'version; unloading removes the row and its storage', () async {
    copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    final container = start();

    await _until(() => applied(container));

    final state = container.read(pluginDevelopmentProvider)!;
    expect(state.plugins.map((plugin) => plugin.id), ['fmp-test']);
    expect(state.plugins.single.load, DevLoad.loaded);
    expect(state.plugins.single.replacedVersion, isNull);
    expect(state.plugins.single.cases, hasLength(3));
    expect(versionOf(container, 'fmp-test'), '1.0.0');
    expect((await harness.plugins.byId('fmp-test'))!.fromDevFolder, isTrue);
    // 外鍵：有列，storage 寫得進去。
    await harness.storage.write('fmp-test', 'k', 'v');
    expect(await harness.storage.read('fmp-test', 'k'), 'v');

    await selectFolder(harness, null);
    await _until(() => container.read(pluginDevelopmentProvider) == null);
    await _idle(container);

    expect(container.read(pluginRegistryProvider).value, isEmpty);
    expect(await harness.plugins.byId('fmp-test'), isNull);
    expect(await harness.storage.read('fmp-test', 'k'), isNull);
  });

  test('over an installed row the dev version replaces it; unloading '
      'restores the installed version and keeps row and storage', () async {
    await storeInstalled(harness, _installedSource());
    final before = (await harness.plugins.byId('fmp-test'))!;
    await harness.storage.write('fmp-test', 'k', 'v');
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    setVersion(dev, '2.0.0');
    await selectFolder(harness, root);
    final container = start();
    await container.read(pluginRegistryProvider.future);

    await _until(() => applied(container));

    expect(versionOf(container, 'fmp-test'), '2.0.0');
    expect(
      container.read(pluginDevelopmentProvider)!.plugins.single.replacedVersion,
      '0.9.0',
    );
    // 列的 version／manifest／script／enabled 都不動，storage 共用。
    expect(await harness.plugins.byId('fmp-test'), before);
    expect(await harness.storage.read('fmp-test', 'k'), 'v');

    await selectFolder(harness, null);
    await _until(() => container.read(pluginDevelopmentProvider) == null);
    await _idle(container);

    expect(versionOf(container, 'fmp-test'), '0.9.0');
    expect(await harness.plugins.byId('fmp-test'), before);
    expect(await harness.storage.read('fmp-test', 'k'), 'v');
  });

  test('over a disabled installed row the dev version loads; unloading puts '
      'the installed one back as disabled', () async {
    await storeInstalled(harness, _installedSource(), enabled: false);
    final before = (await harness.plugins.byId('fmp-test'))!;
    copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    final container = start();
    final registry = container.read(pluginRegistryProvider.notifier);
    await container.read(pluginRegistryProvider.future);
    expect(registry.isDisabled('fmp-test'), isTrue);

    await _until(() => applied(container));

    expect(versionOf(container, 'fmp-test'), '1.0.0');
    expect(registry.isDisabled('fmp-test'), isFalse);

    await selectFolder(harness, null);
    await _until(() => container.read(pluginDevelopmentProvider) == null);
    await _idle(container);

    expect(container.read(pluginRegistryProvider).value, isEmpty);
    expect(registry.isDisabled('fmp-test'), isTrue);
    expect(await harness.plugins.byId('fmp-test'), before);
  });

  test('a leftover marked row is deleted with its storage and never loaded; '
      'installed rows stay', () async {
    await storeMarked(
      harness,
      scriptOf(fixturePlugin('test_plugin')).readAsStringSync(),
    );
    await harness.storage.write('fmp-test', 'k', 'v');
    await storeInstalled(
      harness,
      scriptOf(fixturePlugin('http_test_plugin')).readAsStringSync(),
    );
    await harness.storage.write('fmp-test-http', 'k', 'i');
    final container = start();

    // registry 的 build 略過標記列。
    expect((await container.read(pluginRegistryProvider.future)).keys, [
      'fmp-test-http',
    ]);
    await _idle(container);

    expect(await harness.plugins.byId('fmp-test'), isNull);
    expect(await harness.storage.read('fmp-test', 'k'), isNull);
    expect(await harness.plugins.byId('fmp-test-http'), isNotNull);
    expect(await harness.storage.read('fmp-test-http', 'k'), 'i');
    expect(container.read(pluginRegistryProvider).value!.keys, [
      'fmp-test-http',
    ]);
  });

  test('turning developer mode off unloads the folder and restores the '
      'installed version', () async {
    await storeInstalled(harness, _installedSource());
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    setVersion(dev, '2.0.0');
    await selectFolder(harness, root);
    final container = start();
    await container.read(pluginRegistryProvider.future);
    await _until(() => applied(container));
    expect(versionOf(container, 'fmp-test'), '2.0.0');
    await container.read(developerProvider.future);

    await container.read(developerProvider.notifier).setDeveloperMode(false);
    await _until(() => container.read(pluginDevelopmentProvider) == null);
    await _idle(container);

    expect(versionOf(container, 'fmp-test'), '0.9.0');
  });

  test('a platform without pluginDevTools never loads the folder but still '
      'deletes leftover marked rows, never installed ones', () async {
    copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    await storeMarked(
      harness,
      scriptOf(fixturePlugin('http_test_plugin')).readAsStringSync(),
    );
    await storeInstalled(harness, _installedSource());
    final installed = (await harness.plugins.byId('fmp-test'))!;
    await harness.storage.write('fmp-test', 'k', 'v');
    final container = start(pluginDevTools: false);

    await _idle(container);

    expect(container.read(pluginDevelopmentProvider), isNull);
    expect(await harness.plugins.byId('fmp-test-http'), isNull);
    expect(await harness.plugins.byId('fmp-test'), installed);
    expect(await harness.storage.read('fmp-test', 'k'), 'v');
    expect(versionOf(container, 'fmp-test'), '0.9.0');
  });

  test('reload picks up the new version and closes the old runtime', () async {
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    final container = start();
    await _until(() => applied(container));
    final old = container.read(pluginRegistryProvider).value!['fmp-test']!;
    expect(old.manifest.version, '1.0.0');

    setVersion(dev, '1.0.1');
    await container.read(pluginDevelopmentProvider.notifier).reload('fmp-test');

    expect(versionOf(container, 'fmp-test'), '1.0.1');
    expect(
      container
          .read(pluginDevelopmentProvider)!
          .plugins
          .single
          .manifest!
          .version,
      '1.0.1',
    );
    expect((await harness.plugins.byId('fmp-test'))!.version, '1.0.1');
    await expectLater(
      old.search(SearchQuery(keyword: 'x')),
      throwsA(isA<AppError>()),
    );
  });

  test('a broken script is not loaded, does not fall back to the installed '
      'version and is reported', () async {
    await storeInstalled(harness, _installedSource());
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    final script = scriptOf(dev);
    script.writeAsStringSync(
      '${script.readAsStringSync()}\nexport function broken( {',
    );
    await selectFolder(harness, root);
    final container = start();
    await container.read(pluginRegistryProvider.future);

    await _until(() => applied(container));

    final plugin = container.read(pluginDevelopmentProvider)!.plugins.single;
    expect(plugin.load, DevLoad.failed);
    expect(plugin.problem, isNotEmpty);
    expect(container.read(pluginRegistryProvider).value, isEmpty);
    expect(
      container
          .read(pluginDevelopmentProvider.notifier)
          .isInDevelopment('fmp-test'),
      isTrue,
    );
    final records = harness.log.history.where(
      (record) => record.tag == 'plugins' && record.level == LogLevel.error,
    );
    expect(records, isNotEmpty);
  });

  test('an unreadable directory named like an installed plugin keeps it out '
      'of the list until unloaded', () async {
    await storeInstalled(harness, _installedSource());
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    scriptOf(dev).writeAsStringSync('export function search() {}');
    await selectFolder(harness, root);
    final container = start();
    await container.read(pluginRegistryProvider.future);

    await _until(() => applied(container));

    final plugin = container.read(pluginDevelopmentProvider)!.plugins.single;
    expect(plugin.id, 'fmp-test');
    expect(plugin.load, DevLoad.failed);
    expect(container.read(pluginRegistryProvider).value, isEmpty);

    await selectFolder(harness, null);
    await _until(() => container.read(pluginDevelopmentProvider) == null);
    await _idle(container);

    expect(versionOf(container, 'fmp-test'), '0.9.0');
  });

  test('two directories with the same id: the first loads, the second is a '
      'folder problem', () async {
    copyPlugin(fixturePlugin('test_plugin'), root, 'a-first');
    copyPlugin(fixturePlugin('test_plugin'), root, 'b-second');
    await selectFolder(harness, root);
    final container = start();

    await _until(() => applied(container));

    final state = container.read(pluginDevelopmentProvider)!;
    expect(state.plugins, hasLength(1));
    expect(p.basename(state.plugins.single.directory.path), 'a-first');
    expect(state.problems, [
      const DevFolderDuplicateId(
        id: 'fmp-test',
        first: 'a-first',
        second: 'b-second',
      ),
    ]);
  });

  test('rescan loads a directory added after the first apply', () async {
    copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    final container = start();
    await _until(() => applied(container));
    expect(container.read(pluginRegistryProvider).value!.keys, ['fmp-test']);

    copyPlugin(fixturePlugin('http_test_plugin'), root, 'fmp-test-http');
    await container.read(pluginDevelopmentProvider.notifier).rescan();

    expect(container.read(pluginRegistryProvider).value!.keys.toSet(), {
      'fmp-test',
      'fmp-test-http',
    });
    expect(
      container.read(pluginDevelopmentProvider)!.plugins.map((p) => p.id),
      ['fmp-test', 'fmp-test-http'],
    );
  });

  test('a missing folder is a folder problem', () async {
    await selectFolder(harness, Directory(p.join(root.path, 'missing')));
    final container = start();

    await _until(() => applied(container));

    final state = container.read(pluginDevelopmentProvider)!;
    expect(state.plugins, isEmpty);
    expect(state.problems, [const DevFolderMissing()]);
  });

  test('a folder without plugin directories is a folder problem', () async {
    Directory(p.join(root.path, 'notes')).createSync();
    await selectFolder(harness, root);
    final container = start();

    await _until(() => applied(container));

    final state = container.read(pluginDevelopmentProvider)!;
    expect(state.plugins, isEmpty);
    expect(state.problems, [const DevFolderEmpty()]);
  });

  test('a script that becomes unreadable on reload keeps its id and does not '
      'fall back to the installed version', () async {
    await storeInstalled(harness, _installedSource());
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'dev-dir');
    await selectFolder(harness, root);
    final container = start();
    await container.read(pluginRegistryProvider.future);
    await _until(() => applied(container));
    expect(versionOf(container, 'fmp-test'), '1.0.0');

    // 標頭壞掉：讀不出 manifest，掃描只知道目錄名。
    scriptOf(dev).writeAsStringSync('export function search() {}');
    await container.read(pluginDevelopmentProvider.notifier).reload('fmp-test');

    final plugin = container.read(pluginDevelopmentProvider)!.plugins.single;
    expect(plugin.id, 'fmp-test');
    expect(plugin.load, DevLoad.failed);
    expect(plugin.problem, isNotEmpty);
    expect(
      container
          .read(pluginDevelopmentProvider.notifier)
          .isInDevelopment('fmp-test'),
      isTrue,
    );
    expect(container.read(pluginRegistryProvider).value, isEmpty);
  });

  test('a manifest id that changes on reload is a failure', () async {
    final dev = copyPlugin(fixturePlugin('test_plugin'), root, 'fmp-test');
    await selectFolder(harness, root);
    final container = start();
    await _until(() => applied(container));

    final script = scriptOf(dev);
    script.writeAsStringSync(
      script.readAsStringSync().replaceFirst(
        '"id": "fmp-test"',
        '"id": "other"',
      ),
    );
    await container.read(pluginDevelopmentProvider.notifier).reload('fmp-test');

    final plugin = container.read(pluginDevelopmentProvider)!.plugins.single;
    expect(plugin.load, DevLoad.failed);
    expect(plugin.changedId, 'other');
    expect(plugin.manifest, isNull);
    expect(container.read(pluginRegistryProvider).value, isEmpty);
  });
}
