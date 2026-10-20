import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'cache_harness.dart';
import '../../support/memory_database.dart';

void main() {
  group('opening', () {
    test(
      'creates cache.db and files/ under fmp_cache and starts empty',
      () async {
        final harness = CacheHarness();

        final store = await harness.open();

        expect(harness.databaseFile.existsSync(), isTrue);
        expect(harness.files.existsSync(), isTrue);
        expect(await store.watchUsage().first, {
          CacheCategory.image: 0,
          CacheCategory.chart: 0,
        });
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
      expect(await store.watchUsage().first, {
        CacheCategory.image: 10,
        CacheCategory.chart: 0,
      });
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
      'reopening right after an unawaited close keeps the entries',
      () async {
        final harness = CacheHarness();
        final first = await harness.open();
        await first.put(CacheCategory.chart, 'a', 'k', Uint8List.fromList([1]));

        // 不 await：Riverpod 的 onDispose 就是這樣關的。
        unawaited(first.close());
        final second = await harness.open();

        expect(
          harness.records(cacheLogTag).map((record) => record.message),
          isNot(contains('Failed to open the cache, starting it over')),
        );
        expect(await second.get(CacheCategory.chart, 'a', 'k'), [1]);
      },
    );

    test('opening waits for a close of the same directory that is still '
        'running', () async {
      final harness = CacheHarness();
      final first = await harness.open();
      await first.close();
      // 對帳一開始就清空 staging/：這個檔案還在，就表示第二次開啟還沒開工。
      harness.staging.createSync(recursive: true);
      final marker = File(p.join(harness.staging.path, 'marker'))
        ..writeAsBytesSync([1]);
      final closing = Completer<void>();
      final key = cacheCloseKey(harness.root);
      pendingCacheCloses[key] = closing.future;
      addTearDown(() => pendingCacheCloses.remove(key));

      var opened = false;
      final opening = harness.open().whenComplete(() => opened = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(opened, isFalse);
      expect(marker.existsSync(), isTrue);
      closing.complete();
      final store = await opening;
      expect(marker.existsSync(), isFalse);
      expect(
        harness.records(cacheLogTag).map((record) => record.message),
        isNot(contains('Failed to open the cache, starting it over')),
      );
      expect(await store.watchUsage().first, isNotEmpty);
    });

    test('a database that is locked by another connection is not corruption: '
        'it throws and leaves the files alone', () async {
      final harness = CacheHarness();
      final first = await harness.open();
      await first.put(CacheCategory.chart, 'a', 'k', Uint8List.fromList([1]));
      await first.close();
      final blocker = sqlite3.open(harness.databaseFile.path)
        ..execute('BEGIN EXCLUSIVE');
      var released = false;
      void release() {
        if (released) return;
        released = true;
        blocker.execute('ROLLBACK');
        blocker.close();
      }

      addTearDown(release);

      await expectLater(
        openCacheStore(
          harness.directory,
          limitBytes: 1 << 20,
          log: harness.log,
        ),
        throwsA(isA<Object>()),
      );

      expect(
        harness.records(cacheLogTag).map((record) => record.message),
        isNot(contains('Failed to open the cache, starting it over')),
      );
      expect(harness.databaseFile.existsSync(), isTrue);
      expect(harness.fileNames(), hasLength(1));
      release();
      final reopened = await harness.open();
      expect(await reopened.get(CacheCategory.chart, 'a', 'k'), [1]);
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

        expect(await store.watchUsage().first, {
          CacheCategory.image: 0,
          CacheCategory.chart: 0,
        });
        expect(
          harness.fileNames(),
          isEmpty,
          reason: 'its files are strays now',
        );
        await put(harness.manager(store), 'https://example.test/a.jpg', 10);
        expect(await store.watchUsage().first, {
          CacheCategory.image: 10,
          CacheCategory.chart: 0,
        });
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

      expect(await store.watchUsage().first, {
        CacheCategory.image: 10,
        CacheCategory.chart: 0,
      });
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
      expect(await store.watchUsage().first, {
        CacheCategory.image: 300,
        CacheCategory.chart: 0,
      });

      await at(4, () => put(b, 'https://example.test/4.jpg', 100));

      expect(await store.watchUsage().first, {
        CacheCategory.image: 300,
        CacheCategory.chart: 0,
      });
      expect(await a.getFileFromCache('https://example.test/1.jpg'), isNull);
      expect(harness.fileNames(), hasLength(3));

      // 讀過的那一筆變成最近用過：下一次淘汰的是沒讀過的 3。
      expect(await read(b, 'https://example.test/2.jpg', minute: 5), isNotNull);
      await at(6, () => put(a, 'https://example.test/5.jpg', 100));

      expect(await a.getFileFromCache('https://example.test/3.jpg'), isNull);
      expect(await b.getFileFromCache('https://example.test/2.jpg'), isNotNull);
      expect(await store.watchUsage().first, {
        CacheCategory.image: 300,
        CacheCategory.chart: 0,
      });
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

      expect(await store.watchUsage().first, {
        CacheCategory.image: 100,
        CacheCategory.chart: 0,
      });
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

      expect(await store.watchUsage().first, {
        CacheCategory.image: 200,
        CacheCategory.chart: 0,
      });
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

      expect(await store.watchUsage().first, {
        CacheCategory.image: 0,
        CacheCategory.chart: 0,
      });
      expect(harness.fileNames(), isEmpty);
      expect(
        await harness
            .manager(store)
            .getFileFromCache('https://example.test/1.jpg'),
        isNull,
      );
    });

    test(
      'the usage is sent again after a write, an eviction and a clear',
      () async {
        final harness = CacheHarness();
        final store = await harness.open(limitBytes: 100);
        final manager = harness.manager(store);
        final usage = StreamIterator(store.watchUsage());
        addTearDown(usage.cancel);
        // 一次動作可能改索引好幾次（寫入、更新最後存取）：等到出現想要的值。
        Future<void> until(int bytes) async {
          while (await usage.moveNext()) {
            if (usage.current[CacheCategory.image] == bytes) return;
          }
          fail('the usage stream ended before $bytes');
        }

        await until(0);
        await at(1, () => put(manager, 'https://example.test/1.jpg', 60));
        await until(60);
        // 超過上限：淘汰較舊的那張。
        await at(2, () => put(manager, 'https://example.test/2.jpg', 70));
        await until(70);
        await store.clear();
        await until(0);
      },
    );

    test('clearing works after the system removed files/', () async {
      // Android 可能在 App 執行中清掉整個 getCacheDir()。
      final harness = CacheHarness();
      final store = await harness.open();
      await put(harness.manager(store), 'https://example.test/1.jpg', 10);
      harness.files.deleteSync(recursive: true);

      await store.clear();

      expect(await store.watchUsage().first, {
        CacheCategory.image: 0,
        CacheCategory.chart: 0,
      });
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

      expect(await store.watchUsage().first, {
        CacheCategory.image: 60,
        CacheCategory.chart: 0,
      });
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

  // 不經圖片 cache manager 的類別（排行，M4 design §9.1）：`put`／`get`／`remove`。
  group('entries of the chart category', () {
    Uint8List bytes(int size, [int value = 1]) =>
        Uint8List.fromList(List.filled(size, value));

    test('what was put is read back, and the usage counts it', () async {
      final harness = CacheHarness();
      final store = await harness.open();

      await store.put(CacheCategory.chart, 'a', 'chart:a:hot', bytes(5, 7));

      expect(
        await store.get(CacheCategory.chart, 'a', 'chart:a:hot'),
        bytes(5, 7),
      );
      expect(await store.watchUsage().first, {
        CacheCategory.image: 0,
        CacheCategory.chart: 5,
      });
      expect(harness.fileNames(), hasLength(1));
    });

    test('nothing, another plugin or another category is a miss', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await store.put(CacheCategory.chart, 'a', 'k', bytes(5));

      expect(await store.get(CacheCategory.chart, 'a', 'other'), isNull);
      expect(await store.get(CacheCategory.chart, 'b', 'k'), isNull);
      expect(await store.get(CacheCategory.image, 'a', 'k'), isNull);
    });

    test(
      'putting the same key replaces the content and the old file',
      () async {
        final harness = CacheHarness();
        final store = await harness.open();
        await store.put(CacheCategory.chart, 'a', 'k', bytes(5, 1));

        await store.put(CacheCategory.chart, 'a', 'k', bytes(8, 2));

        expect(await store.get(CacheCategory.chart, 'a', 'k'), bytes(8, 2));
        expect(harness.fileNames(), hasLength(1));
        expect((await store.watchUsage().first)[CacheCategory.chart], 8);
      },
    );

    test('the same key under two plugins is two entries', () async {
      final harness = CacheHarness();
      final store = await harness.open();

      await store.put(CacheCategory.chart, 'a', 'k', bytes(3, 1));
      await store.put(CacheCategory.chart, 'b', 'k', bytes(3, 2));

      expect(await store.get(CacheCategory.chart, 'a', 'k'), bytes(3, 1));
      expect(await store.get(CacheCategory.chart, 'b', 'k'), bytes(3, 2));
    });

    test('remove with a key deletes that entry and its file only', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await store.put(CacheCategory.chart, 'a', 'one', bytes(3));
      await store.put(CacheCategory.chart, 'a', 'two', bytes(4));

      await store.remove(CacheCategory.chart, 'a', key: 'one');

      expect(await store.get(CacheCategory.chart, 'a', 'one'), isNull);
      expect(await store.get(CacheCategory.chart, 'a', 'two'), isNotNull);
      expect(harness.fileNames(), hasLength(1));
    });

    test('remove without a key deletes the plugin\'s entries of the category '
        'and leaves images and other plugins alone', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await put(harness.manager(store), 'https://example.test/a.jpg', 10);
      await store.put(CacheCategory.chart, 'a', 'one', bytes(3));
      await store.put(CacheCategory.chart, 'a', 'two', bytes(4));
      await store.put(CacheCategory.chart, 'b', 'one', bytes(5));

      await store.remove(CacheCategory.chart, 'a');

      expect(await store.get(CacheCategory.chart, 'a', 'one'), isNull);
      expect(await store.get(CacheCategory.chart, 'a', 'two'), isNull);
      expect(await store.get(CacheCategory.chart, 'b', 'one'), isNotNull);
      expect(await store.watchUsage().first, {
        CacheCategory.image: 10,
        CacheCategory.chart: 5,
      });
      expect(harness.fileNames(), hasLength(2));
    });

    test('removing a plugin deletes its chart entries too', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await store.put(CacheCategory.chart, 'a', 'k', bytes(3));
      await store.put(CacheCategory.chart, 'b', 'k', bytes(3));

      await store.removePlugin('a');

      expect(await store.get(CacheCategory.chart, 'a', 'k'), isNull);
      expect(await store.get(CacheCategory.chart, 'b', 'k'), isNotNull);
      expect(harness.fileNames(), hasLength(1));
    });

    test('an evicted entry is a miss, the oldest going first', () async {
      final harness = CacheHarness();
      final store = await harness.open(limitBytes: 10);
      await at(1, () => store.put(CacheCategory.chart, 'a', 'old', bytes(6)));

      await at(2, () => store.put(CacheCategory.chart, 'a', 'new', bytes(6)));

      expect(await store.get(CacheCategory.chart, 'a', 'old'), isNull);
      expect(await store.get(CacheCategory.chart, 'a', 'new'), isNotNull);
    });

    test('a file the system removed is a miss, not an error', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await store.put(CacheCategory.chart, 'a', 'k', bytes(3));
      harness.files.deleteSync(recursive: true);

      expect(await store.get(CacheCategory.chart, 'a', 'k'), isNull);
    });

    test('stored format: the category string is chart', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await store.put(CacheCategory.chart, 'a', 'chart:a:hot', bytes(3));

      final database = sqlite3.open(
        harness.databaseFile.path,
        mode: OpenMode.readOnly,
      );
      addTearDown(database.close);
      final row = database
          .select(
            'SELECT key, category, plugin_id, size_bytes FROM cache_entries',
          )
          .single;
      expect(row['key'], 'chart:a:hot');
      expect(row['category'], 'chart');
      expect(row['plugin_id'], 'a');
      expect(row['size_bytes'], 3);
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
      CacheDirectory directory, {
      AppDatabase? database,
    }) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appDatabaseProvider.overrideWithValue(database ?? memoryDatabase()),
          logProvider.overrideWithValue(harness.log),
          cacheDirectoryProvider.overrideWithValue(directory),
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(
              dataDirectory: true,
              singleInstance: false,
              secureStorage: false,
              fontFallback: FontFallback.none,
              playback: null,
              networkInterfaces: false,
              files: false,
              loginWebView: false,
              urlOpener: false,
              restartsItself: false,
              shareFiles: false,
              pluginDevTools: false,
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
      // 不 listen：沒有人聽這個 provider 時，設定的改動也要套用。
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
      expect(await store.watchUsage().first, {
        CacheCategory.image: 600 * 1024,
        CacheCategory.chart: 0,
      });
    });

    test('a limit the user set replaces the platform default', () async {
      final harness = CacheHarness();
      final database = memoryDatabase();
      await NetworkSettingsRepository(database).write(cacheLimitMebibytes: 2);
      final store = await container(
        harness,
        harness.directory,
        database: database,
      ).read(cacheStoreProvider.future);
      addTearDown(store.close);
      final manager = harness.manager(store);

      await at(1, () => put(manager, 'https://example.test/1.jpg', 900 * 1024));
      await at(2, () => put(manager, 'https://example.test/2.jpg', 900 * 1024));

      // 上限 2 MiB（預設是 1）：兩張都留著。
      expect(await store.watchUsage().first, {
        CacheCategory.image: 1800 * 1024,
        CacheCategory.chart: 0,
      });
    });

    test('changing the limit evicts down to it right away', () async {
      final harness = CacheHarness();
      final database = memoryDatabase();
      final repository = NetworkSettingsRepository(database);
      await repository.write(cacheLimitMebibytes: 2);
      final container0 = container(
        harness,
        harness.directory,
        database: database,
      );
      final store = await container0.read(cacheStoreProvider.future);
      addTearDown(store.close);
      final manager = harness.manager(store);
      await at(1, () => put(manager, 'https://example.test/1.jpg', 900 * 1024));
      await at(2, () => put(manager, 'https://example.test/2.jpg', 900 * 1024));

      await repository.write(cacheLimitMebibytes: 1);
      await eventually(
        () async =>
            (await store.watchUsage().first)[CacheCategory.image] == 900 * 1024,
        reason: 'the cache was not evicted after the limit was lowered',
      );

      // 留下較新的那張。
      expect(
        await read(manager, 'https://example.test/1.jpg', minute: 3),
        isNull,
      );
      expect(
        await read(manager, 'https://example.test/2.jpg', minute: 4),
        isNotNull,
      );
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
