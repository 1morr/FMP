import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/data/cache/cache_store.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import 'cache_harness.dart';

const _url = 'https://cdn.example/cover.png';

void main() {
  group('downloading', () {
    test(
      'goes through the media client and indexes the file under the plugin',
      () async {
        final harness = CacheHarness(
          handler: (_) => image(
            6,
            headers: {'ETag': '"v1"', 'Cache-Control': 'public, max-age=60'},
          ),
        );
        final store = await harness.open();
        final manager = harness.manager(store, pluginId: 'a');

        final file = await at(1, () => manager.getSingleFile(_url));

        expect(file.lengthSync(), 6);
        expect(harness.adapter.requests.single.uri.toString(), _url);
        final records = harness.records(networkLogTag);
        expect(records.single.fields['client'], 'media');
        expect(records.single.fields['pluginId'], 'a');
        final object = (await manager.config.repo.get(_url))!;
        expect(object.length, 6);
        expect(object.eTag, '"v1"');
        expect(object.touched, DateTime.utc(2026, 10, 2, 12, 1));
        expect(object.validTill, DateTime.utc(2026, 10, 2, 12, 2));
        expect(object.relativePath, endsWith('.png'));
        expect(harness.fileNames(), {object.relativePath});
        expect(await store.usage(), {CacheCategory.image: 6});
        // 下載好的檔案交出去之後，staging/ 不留東西。
        expect(harness.stagingEntries(), isEmpty);
      },
    );

    test('a later run is served from the cache without a request', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      await harness.manager(store).getSingleFile(_url);

      // 新的 cache manager（像重開 App）：記憶體裡什麼都沒有，只有索引。
      final file = await read(harness.manager(store), _url, minute: 9);

      expect(file, isNotNull);
      expect(harness.adapter.requests, hasLength(1));
    });

    test(
      'freshness follows Cache-Control like flutter_cache_manager',
      () async {
        final harness = CacheHarness(
          handler: (options) => image(
            1,
            headers: switch (options.uri.path) {
              '/no-cache.png' => {'Cache-Control': 'no-cache'},
              '/zero.png' => {'Cache-Control': 'max-age=0'},
              _ => {},
            },
          ),
        );
        final store = await harness.open();
        final manager = harness.manager(store);
        final start = DateTime.utc(2026, 10, 2, 12);

        Future<DateTime> validTill(String path) async {
          final url = 'https://cdn.example$path';
          await at(0, () => manager.getSingleFile(url));
          return (await manager.config.repo.get(url))!.validTill;
        }

        expect(
          await validTill('/plain.png'),
          start.add(const Duration(days: 7)),
        );
        expect(await validTill('/no-cache.png'), start);
        // max-age=0 不算（flutter_cache_manager 只認大於 0 的值）。
        expect(
          await validTill('/zero.png'),
          start.add(const Duration(days: 7)),
        );
      },
    );

    test('file names come only from known image types', () async {
      final harness = CacheHarness(
        handler: (options) => image(
          1,
          contentType: switch (options.uri.path) {
            '/a' => 'image/jpeg; charset=binary',
            '/b' => 'image/webp',
            _ => 'text/html; name=../../evil.sh',
          },
        ),
      );
      final store = await harness.open();
      final manager = harness.manager(store);

      for (final path in ['/a', '/b', '/c']) {
        await manager.getSingleFile('https://cdn.example$path');
      }

      final names = harness.fileNames();
      expect(names.where((name) => name.endsWith('.jpg')), hasLength(1));
      expect(names.where((name) => name.endsWith('.webp')), hasLength(1));
      expect(names.where((name) => !name.contains('.')), hasLength(1));
    });

    test('the header WebHelper adds for revalidation is not sent', () async {
      // If-None-Match 不在 mediaRequestHeaders：過期就整個重新下載。
      final harness = CacheHarness(
        handler: (_) =>
            image(1, headers: {'ETag': '"v1"', 'Cache-Control': 'no-cache'}),
      );
      final store = await harness.open();
      final manager = harness.manager(store);
      await manager.getSingleFile(_url);

      await manager.getSingleFile(_url);

      expect(harness.adapter.requests, hasLength(2));
      expect(
        harness.adapter.requests.last.headers.keys.map(
          (name) => name.toLowerCase(),
        ),
        isNot(contains('if-none-match')),
      );
      expect(await store.usage(), {CacheCategory.image: 1});
      expect(harness.fileNames(), hasLength(1));
    });
  });

  group('failures', () {
    Future<void> expectNothingLeft(
      CacheHarness harness,
      CacheStore store,
    ) async {
      expect(harness.fileNames(), isEmpty);
      expect(harness.stagingEntries(), isEmpty);
      expect(await store.usage(), {CacheCategory.image: 0});
    }

    test(
      'a failed download leaves no file and no entry, and is reported',
      () async {
        final harness = CacheHarness(handler: (_) => reply(404));
        final store = await harness.open();

        await expectLater(
          harness.manager(store).getSingleFile(_url),
          throwsA(isA<NotFound>()),
        );

        await expectNothingLeft(harness, store);
        final report = harness
            .records(cacheLogTag)
            .singleWhere((r) => r.message == 'Failed to download an image');
        expect(report.fields['type'], 'NotFound');
        expect(report.level, LogLevel.warning);
      },
    );

    test('an image over 10 MiB is refused', () async {
      final harness = CacheHarness(
        handler: (_) =>
            reply(200, headers: {'Content-Length': '${artworkMaxBytes + 1}'}),
      );
      final store = await harness.open();

      await expectLater(
        harness.manager(store).getSingleFile(_url),
        throwsA(isA<Unsupported>()),
      );

      await expectNothingLeft(harness, store);
    });

    test(
      "a host outside the plugin's allowed hosts is never requested",
      () async {
        final harness = CacheHarness();
        final store = await harness.open();

        await expectLater(
          harness.manager(store).getSingleFile('https://elsewhere.test/a.png'),
          throwsA(isA<Unsupported>()),
        );

        expect(harness.adapter.requests, isEmpty);
        await expectNothingLeft(harness, store);
      },
    );

    test('a connection that breaks mid-body leaves nothing behind', () async {
      // PR 3 的已知問題：WebHelper 的串流中途出錯時不刪寫一半的檔。這裡的
      // 內容先完整下載到 staging/，中斷發生在媒體 client 裡，WebHelper 根本沒
      // 開始寫。
      final body = StreamController<List<int>>();
      final harness = CacheHarness(
        handler: (_) => ResponseBody(
          body.stream.map((chunk) => Uint8List.fromList(chunk)),
          200,
          headers: {
            'content-type': ['image/png'],
          },
        ),
      );
      final store = await harness.open();
      final download = harness.manager(store).getSingleFile(_url);
      await pumpUntil(() => harness.adapter.requests.isNotEmpty);
      body.add(List.filled(8, 1));
      await pumpUntil(() => harness.stagingEntries().isNotEmpty);

      body.addError(const SocketException('connection reset'));
      await body.close();

      await expectLater(download, throwsA(isA<NetworkError>()));
      await expectNothingLeft(harness, store);
    });
  });

  group('sharing', () {
    test('requests for the same image at once share one download', () async {
      final response = Completer<ResponseBody>();
      final harness = CacheHarness(handler: (_) => response.future);
      final store = await harness.open();
      final manager = harness.manager(store);

      final first = manager.getSingleFile(_url);
      final second = manager.getSingleFile(_url);
      await pumpUntil(() => harness.adapter.requests.isNotEmpty);
      response.complete(image(3));

      expect((await first).path, (await second).path);
      expect(harness.adapter.requests, hasLength(1));
    });

    test('two plugins downloading the same URL at once keep separate staging '
        'files and separate entries', () async {
      // PR 3 的已知問題：同一個 destination 同時下載兩次會共用 `.part`。每次
      // 下載的暫存檔名都不同，兩個插件同時抓同一個網址也不會撞在一起。
      final responses = <Completer<ResponseBody>>[];
      final harness = CacheHarness(
        handler: (_) {
          final response = Completer<ResponseBody>();
          responses.add(response);
          return response.future;
        },
      );
      final store = await harness.open();
      final a = harness.manager(store, pluginId: 'a');
      final b = harness.manager(store, pluginId: 'b');

      final fromA = a.getSingleFile(_url);
      final fromB = b.getSingleFile(_url);
      await pumpUntil(() => responses.length == 2);
      // 兩個請求誰先到 adapter 不一定（各自先查索引、建暫存檔）。
      responses[0].complete(image(3));
      responses[1].complete(image(5));

      final fileA = await fromA;
      final fileB = await fromB;
      expect([fileA.lengthSync(), fileB.lengthSync()], unorderedEquals([3, 5]));
      expect((await a.config.repo.get(_url))!.length, fileA.lengthSync());
      expect((await b.config.repo.get(_url))!.length, fileB.lengthSync());
      expect(harness.fileNames(), hasLength(2));
      expect(await store.usage(), {CacheCategory.image: 8});
      expect(harness.stagingEntries(), isEmpty);
    });
  });

  group('the unified store is the only one evicting', () {
    test(
      'a file deleted behind its back is a miss and is downloaded again',
      () async {
        final harness = CacheHarness();
        final store = await harness.open();
        final manager = harness.manager(store);
        final file = await manager.getSingleFile(_url);

        // 系統清掉快取目錄裡的檔案。
        file.deleteSync();

        expect(await manager.getFileFromCache(_url), isNull);
        expect(await manager.config.repo.get(_url), isNull);
        await manager.getSingleFile(_url);
        expect(harness.adapter.requests, hasLength(2));
      },
    );

    test(
      'an image the store evicted is downloaded again by the same manager',
      () async {
        // design §13 的風險：flutter_cache_manager 記憶體裡還有這一筆，但它取檔
        // 前先看檔案在不在，所以不會交出被淘汰的檔。
        final harness = CacheHarness(handler: (_) => image(100));
        final store = await harness.open(limitBytes: 150);
        final manager = harness.manager(store);
        await at(1, () => manager.getSingleFile(_url));

        await at(
          2,
          () => manager.getSingleFile('https://cdn.example/other.png'),
        );
        expect(await store.usage(), {CacheCategory.image: 100});

        await at(3, () => manager.getSingleFile(_url));
        expect(harness.adapter.requests.map((request) => request.uri.path), [
          '/cover.png',
          '/other.png',
          '/cover.png',
        ]);
        expect(await store.usage(), {CacheCategory.image: 100});
        expect(harness.fileNames(), hasLength(1));
      },
    );

    test('its own capacity and age clean-up gets nothing to delete', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      final manager = harness.manager(store);
      await manager.getSingleFile(_url);
      final repo = manager.config.repo;

      expect(await repo.getObjectsOverCapacity(0), isEmpty);
      expect(await repo.getOldObjects(Duration.zero), isEmpty);
      expect(await repo.deleteAll(const []), 0);
      expect(await repo.getAllObjects(), hasLength(1));
    });
  });

  group('last access', () {
    test('put, get and touched map to last_access', () async {
      final harness = CacheHarness();
      final store = await harness.open();
      final manager = harness.manager(store);

      // put：寫入時是當下。
      await at(1, () => manager.getSingleFile(_url));
      final repo = manager.config.repo;
      expect((await repo.get(_url))!.touched, DateTime.utc(2026, 10, 2, 12, 1));

      // get：從索引讀到就更新成當下。
      await read(harness.manager(store), _url, minute: 4);
      expect((await repo.get(_url))!.touched, DateTime.utc(2026, 10, 2, 12, 4));

      // 不更新最後存取的寫入（flutter_cache_manager 搬移索引時）沿用物件帶的時間。
      final object = (await repo.get(_url))!;
      await at(8, () => repo.update(object, setTouchedToNow: false));
      expect((await repo.get(_url))!.touched, DateTime.utc(2026, 10, 2, 12, 4));
    });

    test(
      'an update that carries the id of an evicted entry is written again',
      () async {
        // flutter_cache_manager 記憶體裡的物件可能帶著已被刪掉的那一列的 id：照
        // id 更新會什麼都沒寫到。
        final harness = CacheHarness();
        final store = await harness.open();
        final manager = harness.manager(store);
        await manager.getSingleFile(_url);
        final repo = manager.config.repo;
        final stale = (await repo.get(_url))!;
        await repo.delete(stale.id!);

        await repo.update(stale);

        final again = await repo.get(_url);
        expect(again, isNotNull);
        expect(again!.relativePath, stale.relativePath);
        expect(await store.usage(), {CacheCategory.image: stale.length});
      },
    );

    test('a last-access update that lands after the file was removed does not '
        'bring the entry back', () async {
      // flutter_cache_manager 讀到一列、看過檔案還在之後，才排一次不等的
      // updateOrInsert（3.4.5 cache_store.dart 的 _getCacheDataFromDatabase）。
      // 清除或淘汰插在兩者之間時，那次寫入不能把已刪的檔案寫回索引。
      final harness = CacheHarness();
      final store = await harness.open();
      final manager = harness.manager(store);
      await manager.getSingleFile(_url);
      final repo = manager.config.repo;
      final seen = (await repo.get(_url))!;

      await store.clear();
      await repo.updateOrInsert(seen);

      expect(await repo.get(_url), isNull);
      expect(await store.usage(), {CacheCategory.image: 0});
    });
  });

  test('the size in the index is the size on disk', () async {
    // putFile 對已有的鍵沿用舊的 CacheObject（連 length），只換檔案內容。
    final harness = CacheHarness();
    final store = await harness.open();
    await put(harness.manager(store), _url, 10);

    await put(harness.manager(store), _url, 50);

    expect(await store.usage(), {CacheCategory.image: 50});
    expect(harness.fileNames(), hasLength(1));
  });

  test('downloads write a network record for each hop and nothing else '
      'reaches the network', () async {
    // 轉址的每一跳都經媒體 client（每跳檢查網域），各一筆網路紀錄。
    final harness = CacheHarness(
      handler: (options) => switch (options.uri.path) {
        '/start.png' => redirect('https://cdn.example/cover.png'),
        _ => image(2),
      },
    );
    final store = await harness.open();

    await harness
        .manager(store)
        .getSingleFile('https://example.test/start.png');

    expect(harness.records(networkLogTag).map((r) => r.fields['host']), [
      'example.test',
      'cdn.example',
    ]);
    expect(
      harness.adapter.requests.map((request) => request.headers['cookie']),
      everyElement(isNull),
    );
  });
}
