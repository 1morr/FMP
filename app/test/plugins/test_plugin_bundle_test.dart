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
      final candidates = await plugin.resolveStream(
        StreamRequest(
          sourceId: id,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
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
