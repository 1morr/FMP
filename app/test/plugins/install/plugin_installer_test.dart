import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:path/path.dart' as p;

import '../../support/pump_until.dart';
import '../plugin_harness.dart';

/// 與 App 同一套 provider；資料庫、log、HTTP、載入器（含逾時）用 [harness] 的。重試照 App 關閉
/// （`appProviderScope`，ADR 0013 §決定 4）。
ProviderContainer _container(PluginHarness harness, {String? devPluginPath}) {
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
      devPluginPathProvider.overrideWithValue(devPluginPath),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _version(String version, {String body = ''}) => pluginSource(
  'export function search() { return { items: [], hasMore: false }; }'
  '\n$body',
).replaceFirst('"version": "1.0.0"', '"version": "$version"');

void main() {
  test('installs, stores and registers a plugin', () async {
    final harness = PluginHarness();
    final container = _container(harness);

    final plugin = await container
        .read(pluginInstallerProvider)
        .installBytes(testPluginFile.readAsBytesSync());

    final stored = (await harness.plugins.byId('fmp-test'))!;
    expect(stored.version, '1.0.0');
    expect(stored.script, testPluginFile.readAsStringSync());
    expect(jsonDecode(stored.manifestJson), containsPair('id', 'fmp-test'));
    final registered = await container.read(pluginRegistryProvider.future);
    expect(registered.keys, ['fmp-test']);
    expect(identical(registered['fmp-test'], plugin), isTrue);
    final page = await plugin.search(SearchQuery(keyword: 'x'));
    expect(page.items, isNotEmpty);
  });

  test('the registry loads installed plugins at start', () async {
    final harness = PluginHarness();
    await _container(harness)
        .read(pluginInstallerProvider)
        .installSource(_version('1.0.0'));

    final container = _container(harness);
    final registered = await container.read(pluginRegistryProvider.future);

    expect(registered.keys, ['plugin-a']);
    expect(
      container.read(pluginRegistryProvider.notifier).mediaClient('plugin-a'),
      isNotNull,
    );
  });

  test('pluginNameProvider gives the manifest name of a registered plugin, '
      'null for one that is not', () async {
    final harness = PluginHarness();
    final container = _container(harness);
    expect(container.read(pluginNameProvider('fmp-test')), isNull);

    await container
        .read(pluginInstallerProvider)
        .installBytes(testPluginFile.readAsBytesSync());
    await container.read(pluginRegistryProvider.future);

    expect(container.read(pluginNameProvider('fmp-test')), 'FMP Test Plugin');
    expect(container.read(pluginNameProvider('not-installed')), isNull);
  });

  group('media clients', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fmp_registry_media');
      addTearDown(() => temp.delete(recursive: true));
    });

    Future<void> download(MediaHttpClient client, String url) =>
        client.download(
          Uri.parse(url),
          destination: File(p.join(temp.path, 'cover.jpg')),
          maxBytes: 1024,
        );

    String withHosts(String version, List<String> hosts) => pluginSource(
      'export function search() { return { items: [], hasMore: false }; }',
      allowedHosts: hosts,
    ).replaceFirst('"version": "1.0.0"', '"version": "$version"');

    test('each plugin gets one for the hosts in its manifest', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      await container
          .read(pluginInstallerProvider)
          .installSource(withHosts('1.0.0', ['example.test']));
      final registry = container.read(pluginRegistryProvider.notifier);

      final media = registry.mediaClient('plugin-a')!;
      expect(media.pluginId, 'plugin-a');
      await download(media, 'https://cdn.example.test/a.jpg');
      expect(harness.adapter.requests.single.uri.host, 'cdn.example.test');
      await expectLater(
        download(media, 'https://cdn.example/a.jpg'),
        throwsA(isA<Unsupported>()),
      );
      expect(harness.adapter.requests, hasLength(1));
      expect(registry.mediaClient('plugin-b'), isNull);
    });

    test(
      'an update replaces it with the new hosts and closes the old one',
      () async {
        final harness = PluginHarness();
        final container = _container(harness);
        final installer = container.read(pluginInstallerProvider);
        await installer.installSource(withHosts('1.0.0', ['example.test']));
        final registry = container.read(pluginRegistryProvider.notifier);
        final old = registry.mediaClient('plugin-a')!;

        await installer.installSource(withHosts('2.0.0', ['cdn.example']));

        final updated = registry.mediaClient('plugin-a')!;
        expect(identical(updated, old), isFalse);
        await download(updated, 'https://cdn.example/a.jpg');
        await expectLater(
          download(updated, 'https://example.test/a.jpg'),
          throwsA(isA<Unsupported>()),
        );
        // 舊的已關閉：請求到不了 adapter，也不當成連不上。
        await expectLater(
          download(old, 'https://example.test/a.jpg'),
          throwsA(isA<UnexpectedError>()),
        );
        expect(harness.adapter.requests, hasLength(1));
      },
    );
  });

  test(
    'a stored plugin that no longer loads is reported and skipped',
    () async {
      final harness = PluginHarness();
      await _container(harness)
          .read(pluginInstallerProvider)
          .installSource(_version('1.0.0'));
      await harness.plugins.install(
        InstalledPlugin(
          id: 'broken',
          version: '1',
          manifestJson: '{}',
          script: 'not a plugin file',
          installedAt: DateTime.utc(2026, 9, 30),
        ),
      );

      final registered = await _container(harness)
          .read(pluginRegistryProvider.future);

      expect(registered.keys, ['plugin-a']);
      expect(
        harness.records('plugins').single.message,
        'Failed to load an installed plugin',
      );
    },
  );

  test('installing the same id updates it and keeps its storage', () async {
    final harness = PluginHarness();
    final container = _container(harness);
    final installer = container.read(pluginInstallerProvider);
    final old = await installer.installSource(_version('1.0.0'));
    await harness.storage.write('plugin-a', 'k', 'kept');

    final updated = await installer.installSource(_version('2.0.0'));

    expect((await harness.plugins.byId('plugin-a'))!.version, '2.0.0');
    expect(await harness.storage.read('plugin-a', 'k'), 'kept');
    final registered = await container.read(pluginRegistryProvider.future);
    expect(identical(registered['plugin-a'], updated), isTrue);
    // 被取代的 runtime 已關閉。
    await expectLater(
      old.search(SearchQuery(keyword: 'x')),
      throwsA(isA<UnexpectedError>()),
    );
  });

  test('a plugin that fails to load leaves nothing behind', () async {
    final harness = PluginHarness();
    final container = _container(harness);

    await expectLater(
      container
          .read(pluginInstallerProvider)
          .installSource(
            pluginSource('export function other() {}'), // search 沒匯出
          ),
      throwsA(isA<Unsupported>()),
    );

    expect(await harness.plugins.list(), isEmpty);
    expect(await container.read(pluginRegistryProvider.future), isEmpty);
  });

  test('plugins registered at the same time are all listed', () async {
    final harness = PluginHarness();
    final container = _container(harness);
    const body =
        'export function search() { return { items: [], hasMore: false }; }';
    final a = await harness.load(pluginSource(body), installed: false);
    final b = await harness.load(
      pluginSource(body, id: 'plugin-b'),
      installed: false,
    );
    final registry = container.read(pluginRegistryProvider.notifier);

    await Future.wait([registry.register(a), registry.register(b)]);

    final registered = await container.read(pluginRegistryProvider.future);
    expect(registered.keys, unorderedEquals(['plugin-a', 'plugin-b']));
  });

  test('a plugin that stops responding stays listed as unresponsive', () async {
    final harness = PluginHarness(
      callTimeout: const Duration(milliseconds: 500),
      livenessGrace: const Duration(milliseconds: 300),
    );
    final container = _container(harness);
    final plugin = await container
        .read(pluginInstallerProvider)
        .installSource(
          pluginSource('export function search() { while (true) {} }'),
        );
    var emitted = 0;
    container.listen(pluginRegistryProvider, (_, _) => emitted++);

    await expectLater(
      plugin.search(SearchQuery(keyword: 'x')),
      throwsA(isA<UnexpectedError>()),
    );
    await plugin.whenUnresponsive;
    await pumpUntil(() => emitted > 0);

    final registered = await container.read(pluginRegistryProvider.future);
    expect(registered['plugin-a']!.health, PluginHealth.unresponsive);
  });

  group('development entry', () {
    test('reads the path from the argument, then the environment', () {
      expect(
        devPluginPath(
          AppFlavor.dev,
          ['--verbose', '--fmp-dev-plugin=C:/p/a.js'],
          {'FMP_DEV_PLUGIN': '/b.js'},
        ),
        'C:/p/a.js',
      );
      expect(
        devPluginPath(AppFlavor.dev, const [], {'FMP_DEV_PLUGIN': '/b.js'}),
        '/b.js',
      );
      expect(
        devPluginPath(AppFlavor.dev, const ['--fmp-dev-plugin='], const {}),
        isNull,
      );
      expect(
        devPluginPath(AppFlavor.dev, const [], const {'FMP_DEV_PLUGIN': ''}),
        isNull,
      );
    });

    test('prod reads neither the argument nor the environment', () {
      expect(
        devPluginPath(
          AppFlavor.prod,
          ['--fmp-dev-plugin=C:/p/a.js'],
          {'FMP_DEV_PLUGIN': '/b.js'},
        ),
        isNull,
      );
    });

    test('installs the file at the path', () async {
      final harness = PluginHarness();
      final container = _container(harness, devPluginPath: testPluginFile.path);

      final plugin = await container.read(devPluginInstallProvider.future);

      expect(plugin!.manifest.id, 'fmp-test');
      expect((await container.read(pluginRegistryProvider.future)).keys, [
        'fmp-test',
      ]);
    });

    test('does nothing without a path', () async {
      final container = _container(PluginHarness());

      expect(await container.read(devPluginInstallProvider.future), isNull);
    });

    test('reports a file that cannot be read', () async {
      final harness = PluginHarness();
      final missing = '${Directory.systemTemp.path}/fmp-missing-plugin.js';
      final container = _container(harness, devPluginPath: missing);

      await expectLater(
        container.read(devPluginInstallProvider.future),
        throwsA(isA<UnexpectedError>()),
      );
      expect(
        harness.records('plugins').single.message,
        'Failed to install the development plugin',
      );
    });
  });

  test('bytes that are not UTF-8 are a ParseError', () async {
    final container = _container(PluginHarness());

    await expectLater(
      container
          .read(pluginInstallerProvider)
          .installBytes(Uint8List.fromList([0xFF])),
      throwsA(isA<ParseError>()),
    );
  });
}
