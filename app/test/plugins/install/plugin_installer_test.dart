import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:path/path.dart' as p;

import '../../data/cache/cache_harness.dart';
import '../../support/pump_until.dart';
import '../plugin_harness.dart';

/// 與 App 同一套 provider；資料庫、log、HTTP、載入器（含逾時）用 [harness] 的。重試照 App 關閉
/// （`appProviderScope`，ADR 0013 §決定 4）。
ProviderContainer _container(
  PluginHarness harness, {
  String? devPluginPath,
  List<Override> extra = const [],
}) {
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
      ...extra,
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

  group('plugin repository', () {
    final indexUrl = Uri.parse('https://index.test/index.json');

    String source({
      String version = '1.0.0',
      List<String> capabilities = const ['search'],
      List<String> hosts = const ['example.test'],
    }) {
      final resolve = capabilities.contains('resolveStream')
          ? 'export function resolveStream() { return { candidates: [] }; }'
          : '';
      return pluginSource(
        'export function search() { return { items: [], hasMore: false }; }\n'
        '$resolve',
        capabilities: capabilities,
        allowedHosts: hosts,
      ).replaceFirst('"version": "1.0.0"', '"version": "$version"');
    }

    String hash(List<int> bytes) => sha256.convert(bytes).toString();

    /// [text] 在 index 裡的那一筆；其餘參數改掉其中的欄位，讓它與檔案不一致。
    PluginIndexEntry entry(
      String text, {
      String? sha256Override,
      int? apiVersion,
      Set<PluginCapability>? capabilities,
      List<String>? hosts,
      String? version,
      Uri? checksUrl,
      String? checksSha,
    }) {
      final manifest = PluginFile.parse(text).manifest;
      return PluginIndexEntry(
        id: manifest.id,
        name: manifest.name,
        author: manifest.author,
        description: '',
        version: version ?? manifest.version,
        apiVersion: apiVersion ?? hostApiVersion,
        capabilities: capabilities ?? manifest.capabilities,
        allowedHosts: hosts ?? manifest.allowedHosts,
        url: Uri.parse('https://index.test/${manifest.id}.js'),
        sha256: sha256Override ?? hash(utf8.encode(text)),
        checksUrl: checksUrl,
        checksSha256: checksSha,
      );
    }

    /// 網址 → 內容的假下載；沒列出的網址丟 NetworkError，並記下被要過的網址。
    PluginDownloader downloader(
      PluginHarness harness,
      Map<String, String> files, [
      List<String>? asked,
    ]) => PluginDownloader(
      fetch: (url, {required maxBytes}) async {
        asked?.add(url.toString());
        final body = files[url.toString()];
        if (body == null) throw NetworkError();
        return Uint8List.fromList(utf8.encode(body));
      },
      log: harness.log,
    );

    Future<PreparedPlugin> prepare(
      PluginHarness harness,
      String text,
      PluginIndexEntry theEntry, {
      Map<String, String> more = const {},
      InstalledPlugin? current,
    }) => downloader(harness, {
      theEntry.url.toString(): text,
      ...more,
    }).prepare(theEntry, indexUrl: indexUrl, current: current);

    Future<int> installedCount(PluginHarness harness) async =>
        (await harness.plugins.list()).length;

    Matcher rejected(PluginRejection reason) => throwsA(
      isA<PluginRejected>().having((e) => e.reason, 'reason', reason),
    );

    test('a file that does not match the SHA-256 is refused and nothing is '
        'written', () async {
      final harness = PluginHarness();
      final text = source();

      await expectLater(
        prepare(harness, text, entry(text, sha256Override: 'a' * 64)),
        rejected(PluginRejection.hashMismatch),
      );

      expect(await installedCount(harness), 0);
    });

    test('an index entry that differs from the file is refused', () async {
      final text = source();
      final differences = <String, PluginIndexEntry>{
        'version': entry(text, version: '1.0.1'),
        'capabilities': entry(
          text,
          capabilities: {PluginCapability.search, PluginCapability.login},
        ),
        'hosts': entry(text, hosts: ['example.test', 'evil.test']),
      };
      for (final MapEntry(:key, :value) in differences.entries) {
        final harness = PluginHarness();

        await expectLater(
          prepare(harness, text, value),
          rejected(PluginRejection.manifestMismatch),
          reason: key,
        );

        expect(await installedCount(harness), 0, reason: key);
      }
    });

    test('an apiVersion the host does not support is refused before the '
        'download', () async {
      final harness = PluginHarness();
      final text = source();
      final asked = <String>[];

      await expectLater(
        downloader(
          harness,
          {},
          asked,
        ).prepare(entry(text, apiVersion: 2), indexUrl: indexUrl),
        rejected(PluginRejection.appUpdateRequired),
      );
      expect(asked, isEmpty);
    });

    test('update status only goes up, only from the source index and only '
        'for a supported apiVersion', () {
      InstalledPlugin installed(String version, {String? from}) =>
          InstalledPlugin(
            id: 'plugin-a',
            version: version,
            manifestJson: '{}',
            script: '',
            installedAt: DateTime.utc(2026),
            sourceIndexUrl: from ?? indexUrl.toString(),
          );
      final text = source();
      PluginUpdateStatus status(
        InstalledPlugin plugin,
        String version, {
        int apiVersion = 1,
      }) => updateStatus(
        plugin,
        indexUrl.toString(),
        entry(text, version: version, apiVersion: apiVersion),
      );

      expect(status(installed('1.0.0'), '1.0.1'), PluginUpdateStatus.available);
      expect(
        status(installed('1.9.0'), '1.10.0'),
        PluginUpdateStatus.available,
      );
      expect(status(installed('1.0.0'), '1.0.0'), PluginUpdateStatus.none);
      expect(status(installed('2.0.0'), '1.9.9'), PluginUpdateStatus.none);
      expect(
        status(installed('1.0.0'), '2.0.0', apiVersion: 2),
        PluginUpdateStatus.needsAppUpdate,
      );
      // 同版本的不相容 index 不是更新。
      expect(
        status(installed('1.0.0'), '1.0.0', apiVersion: 2),
        PluginUpdateStatus.none,
      );
      expect(
        status(installed('1.0.0', from: 'https://other.test/i.json'), '2.0.0'),
        PluginUpdateStatus.none,
      );
      // 從檔案或網址安裝的（沒有來源 index）不從任何 index 更新。
      expect(
        updateStatus(
          InstalledPlugin(
            id: 'plugin-a',
            version: '1.0.0',
            manifestJson: '{}',
            script: '',
            installedAt: DateTime.utc(2026),
          ),
          indexUrl.toString(),
          entry(text, version: '2.0.0'),
        ),
        PluginUpdateStatus.none,
      );
    });

    test('installing from an index stores the source and the verified '
        'checks', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      final text = source();
      final checksUrl = Uri.parse('https://index.test/checks.json');
      const checks = '{"search":{"input":{}}}';
      final prepared = await prepare(
        harness,
        text,
        entry(text, checksUrl: checksUrl, checksSha: hash(utf8.encode(checks))),
        more: {checksUrl.toString(): checks},
      );

      expect(prepared.needsConfirmation, isTrue);
      await container
          .read(pluginInstallerProvider)
          .installPrepared(prepared, confirmed: true);

      final stored = (await harness.plugins.byId('plugin-a'))!;
      expect(stored.sourceIndexUrl, indexUrl.toString());
      expect(stored.checksJson, checks);
      expect(stored.script, text);
    });

    test('checks that fail verification or download leave the plugin '
        'installed without them', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      final text = source();
      final checksUrl = Uri.parse('https://index.test/checks.json');

      final wrongHash = await prepare(
        harness,
        text,
        entry(text, checksUrl: checksUrl, checksSha: 'b' * 64),
        more: {checksUrl.toString(): '{}'},
      );
      final missing = await prepare(
        harness,
        text,
        entry(text, checksUrl: checksUrl, checksSha: 'b' * 64),
      );

      expect(wrongHash.checksJson, isNull);
      expect(missing.checksJson, isNull);
      await container
          .read(pluginInstallerProvider)
          .installPrepared(wrongHash, confirmed: true);
      expect((await harness.plugins.byId('plugin-a'))!.checksJson, isNull);
    });

    test('an update that adds a capability or a host needs confirmation and '
        'is not installed without it', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      final installer = container.read(pluginInstallerProvider);
      await installer.installSource(source());
      final current = (await harness.plugins.byId('plugin-a'))!;
      final withCapability = source(
        version: '1.1.0',
        capabilities: ['search', 'resolveStream'],
      );
      final withHost = source(
        version: '1.1.0',
        hosts: ['example.test', 'new.test'],
      );
      final unchanged = source(version: '1.1.0');

      final moreCapabilities = await prepare(
        harness,
        withCapability,
        entry(withCapability),
        current: current,
      );
      final moreHosts = await prepare(
        harness,
        withHost,
        entry(withHost),
        current: current,
      );
      final same = await prepare(
        harness,
        unchanged,
        entry(unchanged),
        current: current,
      );

      expect(moreCapabilities.needsConfirmation, isTrue);
      expect(moreCapabilities.addedCapabilities, {
        PluginCapability.resolveStream,
      });
      expect(moreHosts.needsConfirmation, isTrue);
      expect(moreHosts.addedHosts, {'new.test'});
      expect(same.needsConfirmation, isFalse);
      expect(
        () => installer.installPrepared(moreHosts, confirmed: false),
        throwsStateError,
      );
      expect((await harness.plugins.byId('plugin-a'))!.version, '1.0.0');
      await installer.installPrepared(moreHosts, confirmed: true);
      expect((await harness.plugins.byId('plugin-a'))!.version, '1.1.0');
    });

    test('an update without added access keeps the storage', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      final installer = container.read(pluginInstallerProvider);
      await installer.installSource(source());
      await harness.storage.write('plugin-a', 'buvid', 'kept');
      final text = source(version: '1.1.0');

      final prepared = await prepare(
        harness,
        text,
        entry(text),
        current: await harness.plugins.byId('plugin-a'),
      );
      expect(prepared.needsConfirmation, isFalse);
      await installer.installPrepared(prepared, confirmed: false);

      expect(await harness.storage.read('plugin-a', 'buvid'), 'kept');
      final registered = await container.read(pluginRegistryProvider.future);
      expect(registered['plugin-a']!.manifest.version, '1.1.0');
    });

    test('updating a disabled plugin writes it but keeps it out of the '
        'registry', () async {
      final harness = PluginHarness();
      final container = _container(harness);
      final installer = container.read(pluginInstallerProvider);
      await installer.installSource(source());
      final registry = container.read(pluginRegistryProvider.notifier);
      await registry.setEnabled('plugin-a', enabled: false);

      await installer.installSource(source(version: '1.1.0'));

      final stored = (await harness.plugins.byId('plugin-a'))!;
      expect(stored.version, '1.1.0');
      expect(stored.enabled, isFalse);
      expect(await container.read(pluginRegistryProvider.future), isEmpty);
    });

    group('removing', () {
      test('leaves no storage, cache entry, row or runtime of the plugin '
          'behind', () async {
        final harness = PluginHarness();
        final cacheHarness = CacheHarness();
        final store = await cacheHarness.open();
        final container = _container(
          harness,
          extra: [cacheStoreProvider.overrideWith((ref) => store)],
        );
        final installer = container.read(pluginInstallerProvider);
        await installer.installSource(source());
        await installer.installSource(
          source().replaceAll('plugin-a', 'plugin-b'),
        );
        await harness.storage.write('plugin-a', 'buvid', 'x');
        const url = 'https://example.test/a.jpg';
        final manager = cacheHarness.manager(store, pluginId: 'plugin-a');
        await put(manager, url, 4);
        final other = cacheHarness.manager(store, pluginId: 'plugin-b');
        await put(other, url, 4);
        final registry = container.read(pluginRegistryProvider.notifier);
        final plugin = (await container.read(
          pluginRegistryProvider.future,
        ))['plugin-a']!;

        await installer.remove('plugin-a');

        expect(await harness.plugins.byId('plugin-a'), isNull);
        expect(await harness.storage.read('plugin-a', 'buvid'), isNull);
        expect(await manager.getFileFromCache(url), isNull);
        expect(await other.getFileFromCache(url), isNotNull);
        expect(registry.mediaClient('plugin-a'), isNull);
        final registered = await container.read(pluginRegistryProvider.future);
        expect(registered.keys, ['plugin-b']);
        await expectLater(
          plugin.search(SearchQuery(keyword: 'x')),
          throwsA(isA<AppError>()),
        );
      });

      test('can be run again after a step failed', () async {
        final harness = PluginHarness();
        final container = _container(harness);
        await container.read(pluginInstallerProvider).installSource(source());
        final registry = container.read(pluginRegistryProvider.notifier);
        var failures = 1;
        final installer = PluginInstaller(
          loader: harness.loader,
          repository: harness.plugins,
          register: registry.register,
          unregister: registry.unregister,
          removeCache: (_) async {
            if (failures-- > 0) throw StateError('disk is gone');
          },
        );

        await expectLater(
          installer.remove('plugin-a'),
          throwsA(isA<AppError>()),
        );
        // 停在快取那一步：資料庫的列還在，可以再按一次。
        expect(await harness.plugins.byId('plugin-a'), isNotNull);

        await installer.remove('plugin-a');

        expect(await harness.plugins.byId('plugin-a'), isNull);
        await installer.remove('plugin-a');
      });
    });
  });
}
