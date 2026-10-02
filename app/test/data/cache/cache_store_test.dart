import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'cache_harness.dart';

void main() {
  group('opening', () {
    test(
      'creates cache.db and files/ under fmp_cache and starts empty',
      () async {
        final harness = CacheHarness();

        final store = await harness.open();

        expect(harness.databaseFile.existsSync(), isTrue);
        expect(harness.files.existsSync(), isTrue);
        expect(await store.usage(), {CacheCategory.image: 0});
      },
    );

    test('a cache.db that is not a database is thrown away and rebuilt, '
        'without an error page', () async {
      final harness = CacheHarness();
      harness.files.createSync(recursive: true);
      harness.databaseFile.writeAsStringSync('not a database ' * 100);
      File(p.join(harness.files.path, 'old.jpg')).writeAsBytesSync([1, 2, 3]);
      // 平台快取目錄裡 fmp_cache/ 以外的東西（舊版的歌詞快取、別的套件）不屬於
      // 快取庫：重建只清 fmp_cache/ 裡面。
      final neighbour = File(p.join(harness.platformCache.path, 'other.txt'))
        ..writeAsStringSync('keep');
      final lyrics = Directory(p.join(harness.platformCache.path, 'lyrics'))
        ..createSync();
      File(p.join(lyrics.path, 'a.lrc')).writeAsStringSync('keep');

      final store = await harness.open();

      expect(neighbour.readAsStringSync(), 'keep');
      expect(lyrics.listSync(), hasLength(1));
      expect(harness.fileNames(), isEmpty);
      await put(harness.manager(store), 'https://example.test/a.jpg', 10);
      expect(await store.usage(), {CacheCategory.image: 10});
      expect(
        harness.records(cacheLogTag).map((record) => record.message),
        contains('Failed to open the cache, starting it over'),
      );
      expect(
        harness.log.history.where((r) => r.level == LogLevel.error),
        isEmpty,
      );
    });

    test(
      'a cache.db of another schema version starts empty and writable',
      () async {
        // 升級或 revert 後的降級：drift 兩種都走 onUpgrade，快取不寫逐步
        // migration，整個清掉照目前的 schema 重建。
        final harness = CacheHarness();
        harness.files.createSync(recursive: true);
        final old = sqlite3.open(harness.databaseFile.path);
        old
          ..execute('CREATE TABLE cache_entries (key TEXT, path TEXT)')
          ..execute("INSERT INTO cache_entries VALUES ('k', 'old.jpg')")
          ..execute('CREATE TABLE something_else (x INTEGER)')
          ..execute('PRAGMA user_version = 7');
        old.close();
        File(p.join(harness.files.path, 'old.jpg')).writeAsBytesSync([1, 2, 3]);

        final store = await harness.open();

        expect(await store.usage(), {CacheCategory.image: 0});
        expect(
          harness.fileNames(),
          isEmpty,
          reason: 'its files are strays now',
        );
        await put(harness.manager(store), 'https://example.test/a.jpg', 10);
        expect(await store.usage(), {CacheCategory.image: 10});
        final reopened = sqlite3.open(
          harness.databaseFile.path,
          mode: OpenMode.readOnly,
        );
        addTearDown(reopened.close);
        expect(reopened.userVersion, 1);
        expect(
          reopened
              .select("SELECT name FROM sqlite_master WHERE type = 'table'")
              .map((row) => row['name']),
          isNot(contains('something_else')),
        );
      },
    );

    test('reconciles the index with files/ and empties staging/', () async {
      final harness = CacheHarness();
      final first = await harness.open();
      final manager = harness.manager(first);
      await put(manager, 'https://example.test/kept.jpg', 10);
      await put(manager, 'https://example.test/lost.jpg', 20);
      final lost = (await manager.getFileFromCache(
        'https://example.test/lost.jpg',
      ))!.file;
      await first.close();
      // 系統清掉一個檔、App 寫到一半被關掉留下一個不在索引的檔與暫存檔。
      lost.deleteSync();
      File(p.join(harness.files.path, 'stray.jpg')).writeAsBytesSync([1]);
      harness.staging.createSync();
      File(p.join(harness.staging.path, '0.part')).writeAsBytesSync([1]);

      final store = await harness.open();

      expect(await store.usage(), {CacheCategory.image: 10});
      expect(harness.fileNames(), hasLength(1));
      expect(harness.stagingEntries(), isEmpty);
      expect(
        await read(
          harness.manager(store),
          'https://example.test/kept.jpg',
          minute: 1,
        ),
        isNotNull,
      );
    });
  });

  group('eviction', () {
    test('a write over the limit removes the least recently used entries, '
        'whatever their plugin, until the cache fits', () async {
      final harness = CacheHarness();
      final store = await harness.open(limitBytes: 300);
      final a = harness.manager(store, pluginId: 'a');
      final b = harness.manager(store, pluginId: 'b');
      await at(1, () => put(a, 'https://example.test/1.jpg', 100));
      await at(2, () => put(b, 'https://example.test/2.jpg', 100));
      await at(3, () => put(a, 'https://example.test/3.jpg', 100));
      expect(await store.usage(), {CacheCategory.image: 300});

      await at(4, () => put(b, 'https://example.test/4.jpg', 100));

      expect(await store.usage(), {CacheCategory.image: 300});
      expect(await a.getFileFromCache('https://example.test/1.jpg'), isNull);
      expect(harness.fileNames(), hasLength(3));

      // 讀過的那一筆變成最近用過：下一次淘汰的是沒讀過的 3。
      expect(await read(b, 'https://example.test/2.jpg', minute: 5), isNotNull);
      await at(6, () => put(a, 'https://example.test/5.jpg', 100));

      expect(await a.getFileFromCache('https://example.test/3.jpg'), isNull);
      expect(await b.getFileFromCache('https://example.test/2.jpg'), isNotNull);
      expect(await store.usage(), {CacheCategory.image: 300});
      expect(
        harness.records(cacheLogTag).where((r) => r.message == 'Cache evicted'),
        hasLength(2),
      );
    });

    test('lowering the limit evicts at once', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      final manager = harness.manager(store);
      await at(1, () => put(manager, 'https://example.test/1.jpg', 100));
      await at(2, () => put(manager, 'https://example.test/2.jpg', 100));

      await store.setLimit(150);

      expect(await store.usage(), {CacheCategory.image: 100});
      expect(
        await manager.getFileFromCache('https://example.test/2.jpg'),
        isNotNull,
      );
      expect(
        await manager.getFileFromCache('https://example.test/1.jpg'),
        isNull,
      );
    });

    test('a write under the limit evicts nothing', () async {
      final harness = CacheHarness();
      final store = await harness.open(limitBytes: 200);
      final manager = harness.manager(store);

      await put(manager, 'https://example.test/1.jpg', 100);
      await put(manager, 'https://example.test/2.jpg', 100);

      expect(await store.usage(), {CacheCategory.image: 200});
      expect(harness.records(cacheLogTag), isEmpty);
    });
  });

  group('clear and remove', () {
    test('clearing removes every entry and file, and usage is 0', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await put(harness.manager(store), 'https://example.test/1.jpg', 10);
      await put(
        harness.manager(store, pluginId: 'b'),
        'https://example.test/2.jpg',
        10,
      );
      // 不在索引裡的檔也清掉。
      File(p.join(harness.files.path, 'stray.jpg')).writeAsBytesSync([1]);

      await store.clear();

      expect(await store.usage(), {CacheCategory.image: 0});
      expect(harness.fileNames(), isEmpty);
      expect(
        await harness
            .manager(store)
            .getFileFromCache('https://example.test/1.jpg'),
        isNull,
      );
    });

    test('clearing works after the system removed files/', () async {
      // Android 可能在 App 執行中清掉整個 getCacheDir()。
      final harness = CacheHarness();
      final store = await harness.open();
      await put(harness.manager(store), 'https://example.test/1.jpg', 10);
      harness.files.deleteSync(recursive: true);

      await store.clear();

      expect(await store.usage(), {CacheCategory.image: 0});
    });

    test("removing a plugin deletes only that plugin's entries", () async {
      final harness = CacheHarness();
      final store = await harness.open();
      final a = harness.manager(store, pluginId: 'a');
      final b = harness.manager(store, pluginId: 'b');
      await put(a, 'https://example.test/a.jpg', 10);
      await put(b, 'https://example.test/b.jpg', 20);
      // 兩個插件給同一個網址時各存一份：移除 a 不動 b 的那份。
      await put(a, 'https://example.test/same.jpg', 30);
      await put(b, 'https://example.test/same.jpg', 40);

      await store.removePlugin('a');

      expect(await store.usage(), {CacheCategory.image: 60});
      expect(await a.config.repo.getAllObjects(), isEmpty);
      expect(
        (await b.config.repo.getAllObjects()).map((object) => object.key),
        unorderedEquals([
          'https://example.test/b.jpg',
          'https://example.test/same.jpg',
        ]),
      );
      expect(harness.fileNames(), hasLength(2));
    });
  });

  test('stored format', () async {
    // 快取可以丟，但類別字串仍是寫死的（不是 enum 的 name），時間是 UTC epoch
    // 毫秒。
    final harness = CacheHarness();
    final store = await harness.open();
    await at(
      7,
      () => put(harness.manager(store), 'https://example.test/a.jpg', 10),
    );

    final database = sqlite3.open(
      harness.databaseFile.path,
      mode: OpenMode.readOnly,
    );
    addTearDown(database.close);
    final row = database
        .select(
          'SELECT key, category, plugin_id, size_bytes, last_access '
          'FROM cache_entries',
        )
        .single;
    expect(row['key'], 'https://example.test/a.jpg');
    expect(row['category'], 'image');
    expect(row['plugin_id'], 'a');
    expect(row['size_bytes'], 10);
    expect(
      row['last_access'],
      DateTime.utc(2026, 10, 2, 12, 7).millisecondsSinceEpoch,
    );
  });

  group('cacheStoreProvider', () {
    ProviderContainer container(
      CacheHarness harness,
      CacheDirectory directory,
    ) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          logProvider.overrideWithValue(harness.log),
          cacheDirectoryProvider.overrideWithValue(directory),
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(
              dataDirectory: true,
              singleInstance: false,
              fontFallback: FontFallback.none,
              playback: null,
              networkInterfaces: false,
              cache: CacheSizes(
                defaultLimitMebibytes: 1,
                memoryImages: 1,
                memoryImageMebibytes: 1,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('opens the store with the platform default limit', () async {
      final harness = CacheHarness();
      final store = await container(
        harness,
        harness.directory,
      ).read(cacheStoreProvider.future);
      // dispose 不等關庫；暫存目錄刪掉之前要關好（Windows 上開著的檔刪不掉）。
      addTearDown(store.close);
      final manager = harness.manager(store);

      await at(1, () => put(manager, 'https://example.test/1.jpg', 600 * 1024));
      await at(2, () => put(manager, 'https://example.test/2.jpg', 600 * 1024));

      // 上限 1 MiB：第二張寫入後淘汰第一張。
      expect(await store.usage(), {CacheCategory.image: 600 * 1024});
    });

    test('a cache that cannot be opened is an error that is logged, '
        'and nothing else stops', () async {
      final harness = CacheHarness();
      final broken = CacheDirectory(
        applicationCachePath: () async =>
            throw const FileSystemException('no cache directory'),
      );

      await expectLater(
        container(harness, broken).read(cacheStoreProvider.future),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        harness.log.history
            .where((r) => r.level == LogLevel.error)
            .map((r) => r.message),
        ['Failed to open the cache'],
      );
    });
  });
}
