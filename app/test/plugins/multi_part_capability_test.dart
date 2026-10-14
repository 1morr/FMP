import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `multiPart` 能力與搜尋結果的 `partCount`（ADR 0028 §決定 5）：匯出名稱和能力同名、
// 輸入的 JSON、回傳值的驗證、宣告與匯出的一致、由分 P 建出的曲目，以及 fmp-test 的三種狀況。

const _export = '''
export function multiPart(query) {
  return { parts: [{ cid: 7, title: JSON.stringify(query), index: 1 }] };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['multiPart'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('a multiPart plugin exports one function named multiPart', () async {
      final plugin = await _load(_export);

      expect(plugin.manifest.requiredExports, {'multiPart'});
    });

    test('declaring multiPart without exporting it is Unsupported', () {
      expect(_load('export function search() {}'), throwsA(isA<Unsupported>()));
    });

    test('exporting multiPart without declaring it is Unsupported', () {
      expect(
        _load(
          'export function search() {}\nexport function multiPart() {}',
          capabilities: ['search'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('calling multiPart without the capability is Unsupported', () async {
      final plugin = await _load(
        'export function search() {}',
        capabilities: ['search'],
      );

      expect(
        () => plugin.multiPart(MultiPartQuery(sourceId: 'a')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('the source id reaches the plugin as documented', () async {
      final plugin = await _load(_export);

      final result = await plugin.multiPart(MultiPartQuery(sourceId: 'BV1'));

      expect(result.parts.single.title, '{"sourceId":"BV1"}');
      expect(result.parts.single.cid, 7);
      expect(result.parts.single.index, 1);
      expect(result.parts.single.duration, isNull);
    });

    test('the input is checked before the call', () {
      expect(() => MultiPartQuery(sourceId: ' '), throwsArgumentError);
    });
  });

  group('returned values', () {
    Future<Object> parts(String result) async {
      final plugin = await _load(
        'export function multiPart() { return $result; }',
      );
      return plugin
          .multiPart(MultiPartQuery(sourceId: 'a'))
          .then<Object>((value) => value, onError: (Object error) => error);
    }

    for (final (description, result) in [
      ('no parts', '{ parts: [] }'),
      ('a missing parts list', '{}'),
      (
        'an unknown field',
        "{ parts: [{ cid: 1, title: 'T', index: 1 }], n: 1 }",
      ),
      ('a part without a cid', "{ parts: [{ title: 'T', index: 1 }] }"),
      ('a part without a title', '{ parts: [{ cid: 1, index: 1 }] }'),
      ('an empty title', "{ parts: [{ cid: 1, title: '', index: 1 }] }"),
      ('a part without an index', "{ parts: [{ cid: 1, title: 'T' }] }"),
      ('an index of 0', "{ parts: [{ cid: 1, title: 'T', index: 0 }] }"),
      (
        'a negative duration',
        "{ parts: [{ cid: 1, title: 'T', index: 1, durationMs: -1 }] }",
      ),
      (
        'an unknown part field',
        "{ parts: [{ cid: 1, title: 'T', index: 1, page: 1 }] }",
      ),
      ('undefined', 'undefined'),
    ]) {
      test('multiPart rejects $description as ParseError', () async {
        expect(await parts(result), isA<ParseError>());
      });
    }

    test('an error thrown by the plugin keeps its type', () async {
      final plugin = await _load('''
export function multiPart() { throw { fmpError: 'RateLimited' }; }
''');

      await expectLater(
        plugin.multiPart(MultiPartQuery(sourceId: 'a')),
        throwsA(isA<RateLimited>()),
      );
    });
  });

  group('partCount of a search result', () {
    Future<Object> search(String partCount) async {
      final plugin = await _load(
        '''
export function search() {
  return { items: [{ sourceId: 'a', title: 'T', $partCount }], hasMore: false };
}
''',
        capabilities: ['search'],
      );
      return plugin
          .search(SearchQuery(keyword: 'k', page: 1))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('is optional and read as an integer of at least 1', () async {
      final page = await search('partCount: 3') as SearchPage;
      final none = await search('') as SearchPage;
      final nothing = await search('partCount: null') as SearchPage;

      expect(page.items.single.partCount, 3);
      expect(none.items.single.partCount, isNull);
      expect(nothing.items.single.partCount, isNull);
    });

    for (final value in ['0', '-1', "'3'", '1.5']) {
      test('$value is rejected as ParseError', () async {
        expect(await search('partCount: $value'), isA<ParseError>());
      });
    }
  });

  group('the tracks of the parts', () {
    const video = TrackInfo(
      sourceTypeId: 'bilibili',
      sourceId: 'BV1',
      title: 'The video',
      uploader: 'Up',
      duration: Duration(minutes: 9),
    );

    test('use the part cid, title and duration under the video', () {
      const part = MultiPart(
        cid: 22,
        title: 'Second',
        duration: Duration(seconds: 30),
        index: 2,
      );

      final track = part.toTrackInfo(video);

      expect(track.sourceTypeId, 'bilibili');
      expect(track.sourceId, 'BV1');
      expect(track.cid, 22);
      expect(track.title, 'Second');
      expect(track.duration, const Duration(seconds: 30));
      expect(track.uploader, 'Up');
      expect(track.partIndex, 2);
      expect(track.parentTitle, 'The video');
      expect('${track.key}', 'bilibili:BV1:22');
      expect(track.displayTitle, 'The video · P2 Second');
    });

    test('a track that is not a part shows its own title', () {
      expect(video.displayTitle, 'The video');
    });
  });

  group('fmp-test', () {
    Future<ScriptSourcePlugin> load() =>
        PluginHarness().load(testPluginFile.readAsStringSync());

    test('the parts keyword gives three states of part counts', () async {
      final plugin = await load();

      final first = await plugin.search(SearchQuery(keyword: 'parts', page: 1));
      final second = await plugin.search(
        SearchQuery(keyword: 'parts', page: 2),
      );

      expect(
        [
          for (final item in [...first.items, ...second.items]) item.partCount,
        ],
        [3, null, null],
      );
    });

    test('other keywords give single videos', () async {
      final plugin = await load();

      final page = await plugin.search(SearchQuery(keyword: 'tone', page: 1));

      expect({for (final item in page.items) item.partCount}, {1});
    });

    test('each part has its own cid and plays the bundled tone', () async {
      final plugin = await load();

      final result = await plugin.multiPart(
        MultiPartQuery(sourceId: 'parts-220'),
      );
      final stream = await plugin.resolveStream(
        StreamRequest(
          sourceId: 'parts-220',
          cid: result.parts[1].cid,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );

      expect(result.parts.map((part) => part.index), [1, 2, 3]);
      expect({for (final part in result.parts) part.cid}, hasLength(3));
      expect(stream.candidates.first.url.scheme, 'asset');
    });

    test('the unknown-count videos have two parts and one part', () async {
      final plugin = await load();

      final two = await plugin.multiPart(MultiPartQuery(sourceId: 'parts-440'));
      final one = await plugin.multiPart(MultiPartQuery(sourceId: 'parts-880'));

      expect(two.parts, hasLength(2));
      expect(one.parts, hasLength(1));
    });

    test('a video it does not know is NotFound', () async {
      final plugin = await load();

      await expectLater(
        plugin.multiPart(MultiPartQuery(sourceId: 'tone-440')),
        throwsA(isA<NotFound>()),
      );
    });
  });
}
