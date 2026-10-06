import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:yaml/yaml.dart';

import 'plugin_harness.dart';

// 內附測試插件（`fmp-test`）是 dev 實機驗證的離線音源：以 `--fmp-dev-plugin`
// 安裝後可以搜尋、播放，不連網（ADR 0027 §決定 1）。它的串流指向 dev flavor
// 打包的音檔，prod 不打包（app/AGENTS.md § 插件）。

void main() {
  test('every search result plays a bundled asset', () async {
    final plugin = await PluginHarness().load(
      testPluginFile.readAsStringSync(),
    );
    final ids = <String>[];
    for (var page = 1; ; page++) {
      final result = await plugin.search(SearchQuery(keyword: 'x', page: page));
      ids.addAll([for (final item in result.items) item.sourceId]);
      if (!result.hasMore) break;
    }
    expect(ids, hasLength(greaterThanOrEqualTo(2)));

    for (final id in ids) {
      final result = await plugin.resolveStream(
        StreamRequest(
          sourceId: id,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
      final candidates = result.candidates;
      expect(candidates.first.url.scheme, 'asset');
      expect(
        candidates.first.url.path,
        startsWith('/test/fixtures/plugins/test_plugin/'),
      );
    }
  });

  test(
    'searching "fail" fails as rate limited, for an offline toast',
    () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.search(SearchQuery(keyword: 'fail')),
        throwsA(isA<RateLimited>()),
      );
      // 只有剛好是它才失敗。
      expect(
        (await plugin.search(SearchQuery(keyword: 'failure'))).items,
        isNotEmpty,
      );
    },
  );

  test('searching "missing" makes the second song stream an asset that does '
      'not exist, for an unopenable look-ahead', () async {
    final plugin = await PluginHarness().load(
      testPluginFile.readAsStringSync(),
    );
    Future<Uri> streamOf(String sourceId) async => (await plugin.resolveStream(
      StreamRequest(
        sourceId: sourceId,
        formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
      ),
    )).candidates.first.url;

    final items = (await plugin.search(SearchQuery(keyword: 'missing'))).items;
    expect(items, hasLength(2));
    final first = await streamOf(items[0].sourceId);
    final second = await streamOf(items[1].sourceId);
    // asset 鍵就是 app/ 底下的相對路徑：第一首的在，第二首的不在。
    expect(File(first.path.substring(1)).existsSync(), isTrue);
    expect(second.scheme, 'asset');
    expect(File(second.path.substring(1)).existsSync(), isFalse);
    // 只有剛好是它才改第二首；第二頁不受影響。
    final other = (await plugin.search(SearchQuery(keyword: 'missing2'))).items;
    expect(await streamOf(other[1].sourceId), first);
    final page2 = await plugin.search(SearchQuery(keyword: 'missing', page: 2));
    expect(await streamOf(page2.items.single.sourceId), first);
  });

  // 播放恢復的實機驗證（ADR 0018 §決定 7），不連網。
  group('recovery keywords', () {
    late Future<StreamResult> Function(String sourceId) resolve;
    late Future<List<String>> Function(String keyword) search;

    setUp(() async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );
      resolve = (sourceId) => plugin.resolveStream(
        StreamRequest(
          sourceId: sourceId,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
      search = (keyword) async => [
        for (final item in (await plugin.search(
          SearchQuery(keyword: keyword),
        )).items)
          item.sourceId,
      ];
    });

    test('"preview" songs are preview clips of the bundled tone', () async {
      final ids = await search('preview');
      expect(ids, hasLength(2));
      for (final id in ids) {
        final result = await resolve(id);
        expect(result.previewOnly, isTrue);
        expect(result.candidates.single.url.scheme, 'asset');
      }
      // 其他關鍵字的歌不是試聽。
      expect(
        (await resolve((await search('previews')).first)).previewOnly,
        isFalse,
      );
    });

    test('"flaky" songs fail with NetworkError every other time, starting '
        'with the first', () async {
      final [first, second] = await search('flaky');
      await expectLater(resolve(first), throwsA(isA<NetworkError>()));
      expect((await resolve(first)).candidates, hasLength(1));
      await expectLater(resolve(first), throwsA(isA<NetworkError>()));
      // 每一首各自算。
      await expectLater(resolve(second), throwsA(isA<NetworkError>()));
    });

    test(
      '"unavailable" makes only the first song unavailable for copyright',
      () async {
        final [first, second] = await search('unavailable');
        await expectLater(
          resolve(first),
          throwsA(
            isA<Unavailable>().having(
              (e) => e.reason,
              'reason',
              UnavailableReason.copyright,
            ),
          ),
        );
        expect((await resolve(second)).candidates, hasLength(1));
      },
    );
  });

  test('the test plugin is bundled only in the dev flavor', () {
    final assets =
        (loadYaml(File('pubspec.yaml').readAsStringSync())
                as YamlMap)['flutter']['assets']
            as YamlList;
    expect(
      assets,
      contains(
        allOf(
          containsPair('path', 'test/fixtures/plugins/test_plugin/'),
          containsPair('flavors', ['dev']),
        ),
      ),
    );
  });
}
