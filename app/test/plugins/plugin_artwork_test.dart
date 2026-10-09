import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/plugins/plugin_registry.dart';

import '../data/cache/cache_harness.dart';
import '../support/fake_http_adapter.dart';
import 'plugin_harness.dart';

/// App 的 provider，插件與快取庫用測試的：[plugins] 的資料庫、log、假 adapter，
/// [cache] 是開好的快取庫（`null` 是開不起來）。
ProviderContainer _container(PluginHarness plugins, CacheStore? cache) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(plugins.database),
      logProvider.overrideWithValue(plugins.log),
      redactorProvider.overrideWithValue(plugins.redactor),
      credentialStoreProvider.overrideWithValue(plugins.credentials),
      sourceHttpClientFactoryProvider.overrideWithValue(plugins.httpClients),
      mediaHttpClientFactoryProvider.overrideWithValue(
        plugins.mediaHttpClients,
      ),
      scriptPluginLoaderProvider.overrideWithValue(plugins.loader),
      devPluginPathProvider.overrideWithValue(null),
      loginWebViewProvider.overrideWithValue(null),
      cacheStoreProvider.overrideWithValue(
        cache == null
            ? AsyncError<CacheStore>(StateError('no cache'), StackTrace.empty)
            : AsyncData(cache),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _plugin(String version, List<String> hosts, {String id = 'plugin-a'}) =>
    pluginSource(
      'export function search() { return { items: [], hasMore: false }; }',
      id: id,
      allowedHosts: hosts,
    ).replaceFirst('"version": "1.0.0"', '"version": "$version"');

void main() {
  late PluginHarness plugins;
  late CacheStore cache;

  setUp(() async {
    plugins = PluginHarness(handler: (_) => reply(200, body: 'png'));
    cache = await CacheHarness().open();
  });

  test(
    "a plugin's covers are downloaded with its media client and hosts",
    () async {
      final container = _container(plugins, cache);
      await container
          .read(pluginInstallerProvider)
          .installSource(_plugin('1.0.0', ['example.test']));

      final manager = container.read(artworkCacheManagerProvider('plugin-a'))!;
      await manager.getSingleFile('https://i0.example.test/a.png');

      expect(plugins.adapter.requests.single.uri.host, 'i0.example.test');
      await expectLater(
        manager.getSingleFile('https://cdn.example/a.png'),
        throwsA(isA<Unsupported>()),
      );
      expect(plugins.adapter.requests, hasLength(1));
      expect(await cache.watchUsage().first, {CacheCategory.image: 3});
    },
  );

  test(
    'there is none for a plugin that is not installed, or without a cache',
    () async {
      final container = _container(plugins, cache);
      await container.read(pluginRegistryProvider.future);
      expect(container.read(artworkCacheManagerProvider('plugin-a')), isNull);

      final broken = _container(plugins, null);
      await broken
          .read(pluginInstallerProvider)
          .installSource(_plugin('1.0.0', ['example.test']));
      expect(broken.read(artworkCacheManagerProvider('plugin-a')), isNull);
    },
  );

  test("an update rebuilds it with the new hosts; another plugin's change does not", () async {
    final container = _container(plugins, cache);
    final installer = container.read(pluginInstallerProvider);
    await installer.installSource(_plugin('1.0.0', ['example.test']));
    final first = container.read(artworkCacheManagerProvider('plugin-a'));

    await installer.installSource(
      _plugin('1.0.0', ['example.test'], id: 'plugin-b'),
    );
    expect(
      identical(container.read(artworkCacheManagerProvider('plugin-a')), first),
      isTrue,
    );

    await installer.installSource(_plugin('2.0.0', ['cdn.example']));
    final updated = container.read(artworkCacheManagerProvider('plugin-a'))!;

    expect(identical(updated, first), isFalse);
    await updated.getSingleFile('https://cdn.example/a.png');
    await expectLater(
      updated.getSingleFile('https://example.test/b.png'),
      throwsA(isA<Unsupported>()),
    );
    expect(plugins.adapter.requests.single.uri.host, 'cdn.example');
  });
}
