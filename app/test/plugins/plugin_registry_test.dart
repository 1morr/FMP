import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

ProviderContainer _container(PluginHarness harness) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(harness.database),
      logProvider.overrideWithValue(harness.log),
      redactorProvider.overrideWithValue(harness.redactor),
      sourceHttpClientFactoryProvider.overrideWithValue(harness.httpClients),
      mediaHttpClientFactoryProvider.overrideWithValue(
        harness.mediaHttpClients,
      ),
      scriptPluginLoaderProvider.overrideWithValue(harness.loader),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// [id] 直接放進資料庫（不經安裝流程）；[script] 預設是一個合法的插件。
Future<void> _store(PluginHarness harness, String id, {String? script}) {
  final source =
      script ??
      pluginSource(
        'export function search() { return { items: [], hasMore: false }; }',
        id: id,
      );
  final file = PluginFile.parse(source);
  return harness.plugins.install(
    InstalledPlugin(
      id: id,
      version: '1.0.0',
      manifestJson: file.manifestJson,
      script: source,
      installedAt: DateTime.utc(2026),
    ),
  );
}

void main() {
  test('a disabled plugin is not loaded at start', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    await harness.plugins.setEnabled('plugin-a', enabled: false);
    await _store(harness, 'plugin-b');

    final container = _container(harness);
    final registered = await container.read(pluginRegistryProvider.future);

    expect(registered.keys, ['plugin-b']);
    final registry = container.read(pluginRegistryProvider.notifier);
    expect(registry.isDisabled('plugin-a'), isTrue);
    expect(registry.isDisabled('plugin-b'), isFalse);
    expect(registry.mediaClient('plugin-a'), isNull);
  });

  test('disabling unloads the plugin and enabling loads it again', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    final container = _container(harness);
    final plugin = (await container.read(
      pluginRegistryProvider.future,
    ))['plugin-a']!;
    final registry = container.read(pluginRegistryProvider.notifier);

    await registry.setEnabled('plugin-a', enabled: false);

    expect(container.read(pluginRegistryProvider).value, isEmpty);
    expect(registry.isDisabled('plugin-a'), isTrue);
    expect(registry.mediaClient('plugin-a'), isNull);
    expect((await harness.plugins.byId('plugin-a'))!.enabled, isFalse);
    await expectLater(
      plugin.search(SearchQuery(keyword: 'x')),
      throwsA(isA<AppError>()),
    );

    await registry.setEnabled('plugin-a', enabled: true);

    final registered = container.read(pluginRegistryProvider).value!;
    expect(registered.keys, ['plugin-a']);
    expect(registry.isDisabled('plugin-a'), isFalse);
    expect(registry.mediaClient('plugin-a'), isNotNull);
    expect((await harness.plugins.byId('plugin-a'))!.enabled, isTrue);
  });

  test('enabled survives a restart', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    final first = _container(harness);
    await first.read(pluginRegistryProvider.future);
    await first
        .read(pluginRegistryProvider.notifier)
        .setEnabled('plugin-a', enabled: false);
    first.dispose();

    final second = _container(harness);
    expect(await second.read(pluginRegistryProvider.future), isEmpty);
    await second
        .read(pluginRegistryProvider.notifier)
        .setEnabled('plugin-a', enabled: true);
    second.dispose();

    final third = _container(harness);
    expect((await third.read(pluginRegistryProvider.future)).keys, [
      'plugin-a',
    ]);
  });

  test('disabling keeps the storage of the plugin', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    await harness.storage.write('plugin-a', 'buvid', 'kept');
    final container = _container(harness);
    await container.read(pluginRegistryProvider.future);

    await container
        .read(pluginRegistryProvider.notifier)
        .setEnabled('plugin-a', enabled: false);

    expect(await harness.storage.read('plugin-a', 'buvid'), 'kept');
  });

  test('enabling a plugin that does not load keeps it disabled', () async {
    final harness = PluginHarness();
    final container = _container(harness);
    await container.read(pluginRegistryProvider.future);
    // 壞掉的腳本直接放進資料庫（安裝流程不會讓它進來）。
    await _store(
      harness,
      'plugin-a',
      script: pluginSource('export function search( {', id: 'plugin-a'),
    );
    await harness.plugins.setEnabled('plugin-a', enabled: false);
    final registry = container.read(pluginRegistryProvider.notifier);

    await expectLater(
      registry.setEnabled('plugin-a', enabled: true),
      throwsA(isA<AppError>()),
    );

    expect((await harness.plugins.byId('plugin-a'))!.enabled, isFalse);
    expect(container.read(pluginRegistryProvider).value, isEmpty);
  });

  test('unregister is repeatable and leaves the database alone', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    final container = _container(harness);
    await container.read(pluginRegistryProvider.future);
    final registry = container.read(pluginRegistryProvider.notifier);

    await registry.unregister('plugin-a');
    await registry.unregister('plugin-a');

    expect(container.read(pluginRegistryProvider).value, isEmpty);
    expect(await harness.plugins.byId('plugin-a'), isNotNull);
  });
}
