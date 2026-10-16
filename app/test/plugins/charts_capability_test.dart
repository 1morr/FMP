import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `charts` 能力（ADR 0032 §決定 5、6）：兩個匯出（`chartList`、`chart`，能力名稱本身
// 不是匯出）、輸入的 JSON、回傳值的驗證（`chartId` 不重複、`title` 不空、`tracks` 可以是空
// 的）。fmp-test 的榜單由 test_plugin_bundle_test.dart 守。

const _exports = '''
export function chartList() {
  return { charts: [{ chartId: 'hot', title: 'Hot' }, { chartId: 'new', title: 'New' }] };
}
export function chart(query) {
  return { tracks: [{ sourceId: 'a', title: JSON.stringify(query) }] };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['charts'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('a charts plugin exports the two functions', () async {
      final plugin = await _load(_exports);

      expect(plugin.manifest.requiredExports, ChartsExports.all);
      expect(ChartsExports.all, {'chartList', 'chart'});
      // 能力名稱本身不是匯出。
      expect(plugin.manifest.requiredExports, isNot(contains('charts')));
    });

    test('declaring charts without chartList is Unsupported', () {
      expect(_load('export function chart() {}'), throwsA(isA<Unsupported>()));
    });

    test('declaring charts without chart is Unsupported', () {
      expect(
        _load('export function chartList() {}'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('exporting a function named after the capability is not enough', () {
      expect(_load('export function charts() {}'), throwsA(isA<Unsupported>()));
    });

    for (final name in ['chartList', 'chart']) {
      test('exporting $name without declaring it is Unsupported', () {
        expect(
          _load(
            'export function search() {}\nexport function $name() {}',
            capabilities: ['search'],
          ),
          throwsA(isA<Unsupported>()),
        );
      });
    }

    test('calling the plugin without the capability is Unsupported', () async {
      final plugin = await _load(
        'export function search() {}',
        capabilities: ['search'],
      );

      expect(plugin.chartList, throwsA(isA<Unsupported>()));
      expect(
        () => plugin.chart(ChartQuery(chartId: 'hot')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('the list and the chart reach the plugin as documented', () async {
      final plugin = await _load(_exports);

      final list = await plugin.chartList();
      final page = await plugin.chart(ChartQuery(chartId: 'hot'));

      expect([for (final chart in list.charts) chart.chartId], ['hot', 'new']);
      expect([for (final chart in list.charts) chart.title], ['Hot', 'New']);
      expect(page.tracks.single.title, '{"chartId":"hot"}');
      // 宿主填音源 id。
      expect(page.tracks.single.sourceTypeId, 'plugin-a');
    });

    test('the chart id is checked before the call', () {
      expect(() => ChartQuery(chartId: ' '), throwsArgumentError);
      expect(() => ChartQuery(chartId: ''), throwsArgumentError);
    });
  });

  group('chartList returned values', () {
    Future<Object> list(String result) async {
      final plugin = await _load(
        'export function chartList() { return $result; }\n'
        'export function chart() { return { tracks: [] }; }',
      );
      return plugin.chartList().then<Object>(
        (list) => list,
        onError: (Object error) => error,
      );
    }

    test('no charts is a valid list', () async {
      final result = await list('{ charts: [] }');

      expect(result, isA<ChartList>());
      expect((result as ChartList).charts, isEmpty);
    });

    for (final (description, result) in [
      (
        'a duplicate chartId',
        "{ charts: [{ chartId: 'a', title: 'A' }, { chartId: 'a', title: 'B' }] }",
      ),
      ('an empty title', "{ charts: [{ chartId: 'a', title: '' }] }"),
      ('a blank title', "{ charts: [{ chartId: 'a', title: '   ' }] }"),
      ('an empty chartId', "{ charts: [{ chartId: '', title: 'A' }] }"),
      ('a missing title', "{ charts: [{ chartId: 'a' }] }"),
      ('a missing chartId', "{ charts: [{ title: 'A' }] }"),
      ('no charts field', '{}'),
      ('an unknown field', "{ charts: [{ chartId: 'a', title: 'A', x: 1 }] }"),
      ('a string', "'a'"),
      ('undefined', 'undefined'),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await list(result), isA<ParseError>());
      });
    }

    test('two different ids with the same title are fine', () async {
      final result = await list(
        "{ charts: [{ chartId: 'a', title: 'T' }, { chartId: 'b', title: 'T' }] }",
      );

      expect(result, isA<ChartList>());
    });
  });

  group('chart returned values', () {
    Future<Object> page(String result) async {
      final plugin = await _load(
        "export function chartList() { return { charts: [] }; }\n"
        'export function chart() { return $result; }',
      );
      return plugin
          .chart(ChartQuery(chartId: 'a'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('an empty chart is accepted', () async {
      final result = await page('{ tracks: [] }');

      expect(result, isA<ChartPage>());
      expect((result as ChartPage).tracks, isEmpty);
    });

    test(
      'the tracks keep the order of the plugin, with their part fields',
      () async {
        final result = await page(
          "{ tracks: [{ sourceId: 'b', title: 'B' }, "
          "{ sourceId: 'a', cid: 7, title: 'A', partIndex: 2, "
          "parentTitle: 'Video' }] }",
        ) as ChartPage;

        expect([for (final track in result.tracks) track.sourceId], ['b', 'a']);
        expect(result.tracks.last.cid, 7);
        expect(result.tracks.last.partIndex, 2);
        expect(result.tracks.last.parentTitle, 'Video');
      },
    );

    for (final (description, result) in [
      ('a missing tracks field', '{}'),
      ('a track without a title', "{ tracks: [{ sourceId: 'a' }] }"),
      ('an unknown field', '{ tracks: [], total: 1 }'),
      ('a string', "'a'"),
      ('undefined', 'undefined'),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await page(result), isA<ParseError>());
      });
    }

    test('artwork on another host is rejected', () async {
      expect(
        await page(
          '{ tracks: [{ sourceId: "a", title: "T", '
          'artwork: [{ url: "https://evil.test/a.jpg" }] }] }',
        ),
        isA<ParseError>(),
      );
    });

    test('an error thrown by the plugin keeps its type', () async {
      final plugin = await _load('''
export function chartList() { return { charts: [] }; }
export function chart() { throw { fmpError: 'NetworkError' }; }
''');

      await expectLater(
        plugin.chart(ChartQuery(chartId: 'a')),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('the charts check on a plugin', () {
    PluginCheck check(String expect) => parseChecks('''
{"charts": {"input": {"chartId": "hot"}, "expect": $expect}}
''').single;

    Future<Object> run(String chartBody, String expect) async {
      final plugin = await _load(
        "export function chartList() { return { charts: [] }; }\n"
        'export function chart(query) { $chartBody }',
      );
      return check(expect)
          .run(plugin)
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('runs chart with the input and checks its tracks', () async {
      final result = await run(
        'return { tracks: [{ sourceId: "a", title: query.chartId }] };',
        '{"minItems": 1}',
      ) as ChartPage;

      expect(result.tracks.single.title, 'hot');
      expect(
        check('{"minItems": 1, "nonEmpty": ["title"]}').expectation
            .evaluate(result: result, describe: (error) => '$error'),
        isEmpty,
      );
    });

    test('does not need a login', () {
      expect(check('{"minItems": 0}').requiresLogin, isFalse);
      expect(check('{"minItems": 0}').mutates, isFalse);
    });

    test('too few tracks is a problem; an empty chart passes minItems 0', () {
      final empty = const ChartPage(tracks: []);

      expect(
        check('{"minItems": 1}').expectation
            .evaluate(result: empty, describe: (error) => '$error'),
        isNotEmpty,
      );
      expect(
        check('{"minItems": 0}').expectation
            .evaluate(result: empty, describe: (error) => '$error'),
        isEmpty,
      );
    });

    test('a chart that fails with the expected error', () async {
      final plugin = await _load(
        "export function chartList() { return { charts: [] }; }\n"
        "export function chart() { throw { fmpError: 'NetworkError' }; }",
      );
      final failing = parseChecks('''
{"charts": {"input": {"chartId": "broken"}, "expect": {"error": "NetworkError"}}}
''').single;

      final error = await failing
          .run(plugin)
          .then<Object>((page) => page, onError: (Object error) => error);

      expect(error, isA<NetworkError>());
      expect(
        failing.expectation.evaluate(
          error: error as AppError,
          describe: (error) => error.typeName,
        ),
        isEmpty,
      );
    });

    test('an input without a chartId is rejected', () {
      expect(
        () => parseChecks('{"charts": {"input": {}, "expect": {}}}'),
        throwsFormatException,
      );
    });
  });
}
