import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/search/search_state.dart';

import '../../plugins/plugin_harness.dart';

// 搜尋頁的音源 chip 跟著插件清單（ADR 0030 §決定 7：停用的不出現在搜尋）。插件頁的
// 啟用開關只經 PluginRegistry.setEnabled，這裡守住 chip 那一端。

Future<void> _store(PluginHarness harness, String id, {String body = ''}) {
  final source = pluginSource(
    body.isEmpty
        ? 'export function search() { return { items: [], hasMore: false }; }'
        : body,
    id: id,
    capabilities: body.isEmpty ? const ['search'] : const ['resolveStream'],
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
  test('the search sources follow disabling and enabling a plugin', () async {
    final harness = PluginHarness();
    await _store(harness, 'plugin-a');
    await _store(harness, 'plugin-b');
    // 沒有 search 能力的不算音源。
    await _store(
      harness,
      'plugin-c',
      body: 'export function resolveStream() { return null; }',
    );
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
    final subscription = container.listen(searchSourcesProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(pluginRegistryProvider.future);
    List<String> ids() => [
      for (final plugin in container.read(searchSourcesProvider).value!)
        plugin.manifest.id,
    ];
    expect(ids(), ['plugin-a', 'plugin-b']);

    final registry = container.read(pluginRegistryProvider.notifier);
    await registry.setEnabled('plugin-a', enabled: false);
    expect(ids(), ['plugin-b']);

    await registry.setEnabled('plugin-a', enabled: true);
    expect(ids(), unorderedEquals(['plugin-a', 'plugin-b']));
  });
}
