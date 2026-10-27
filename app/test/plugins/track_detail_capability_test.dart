import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `trackDetail` 能力（ADR 0028 §決定 6）：匯出名稱和能力同名、輸入的 JSON、回傳值的驗證
// （封閉的 stats.kind、非負的 count、頭像網域）、宣告與匯出的一致。

const _export = '''
export function trackDetail(query) {
  return { description: JSON.stringify(query) };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['trackDetail'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test(
      'a trackDetail plugin exports one function named trackDetail',
      () async {
        final plugin = await _load(_export);

        expect(plugin.manifest.requiredExports, {'trackDetail'});
      },
    );

    test('declaring trackDetail without exporting it is Unsupported', () {
      expect(_load('export function search() {}'), throwsA(isA<Unsupported>()));
    });

    test('exporting trackDetail without declaring it is Unsupported', () {
      expect(
        _load(
          'export function search() {}\nexport function trackDetail() {}',
          capabilities: ['search'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('calling trackDetail without the capability is Unsupported', () async {
      final plugin = await _load(
        'export function search() {}',
        capabilities: ['search'],
      );

      expect(
        () => plugin.trackDetail(TrackDetailQuery(sourceId: 'a')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('the source id and cid reach the plugin as documented', () async {
      final plugin = await _load(_export);

      final withCid = await plugin.trackDetail(
        TrackDetailQuery(sourceId: 'BV1', cid: 9),
      );
      final without = await plugin.trackDetail(
        TrackDetailQuery(sourceId: 'BV1'),
      );

      expect(withCid.description, '{"sourceId":"BV1","cid":9}');
      expect(without.description, '{"sourceId":"BV1"}');
    });

    test('the input is checked before the call', () {
      expect(() => TrackDetailQuery(sourceId: ' '), throwsArgumentError);
    });
  });

  group('returned values', () {
    Future<Object> detail(String result) async {
      final plugin = await _load(
        'export function trackDetail() { return $result; }',
      );
      return plugin
          .trackDetail(TrackDetailQuery(sourceId: 'a'))
          .then<Object>((value) => value, onError: (Object error) => error);
    }

    test('every field is optional and null counts as missing', () async {
      final empty = await detail('{}') as TrackDetail;
      final nulls = await detail(
        '{ description: null, publishedAt: null, uploaderAvatar: null, '
        'album: null, stats: null }',
      ) as TrackDetail;

      for (final value in [empty, nulls]) {
        expect(value.isEmpty, isTrue);
        expect(value.stats, isEmpty);
        expect(value.uploaderAvatar, isEmpty);
      }
    });

    test(
      'webUrl on an allowed host is kept, missing or null is null',
      () async {
        final given = await detail(
          "{ webUrl: 'https://www.example.test/v/1' }",
        ) as TrackDetail;
        final nothing = await detail('{}') as TrackDetail;
        final nulled = await detail('{ webUrl: null }') as TrackDetail;

        expect(given.webUrl, Uri.parse('https://www.example.test/v/1'));
        // 只有網址也算有內容（面板才不會當成空的詳細）。
        expect(given.isEmpty, isFalse);
        expect(nothing.webUrl, isNull);
        expect(nulled.webUrl, isNull);
      },
    );

    test('a full detail is decoded', () async {
      final value = await detail('''{
  description: 'About',
  publishedAt: 1715934600000,
  uploaderAvatar: [{ url: 'https://example.test/a.png', width: 48 }],
  album: 'Album',
  stats: [{ kind: 'view', count: 12 }, { kind: 'coin', count: 0 }],
}''') as TrackDetail;

      expect(value.description, 'About');
      expect(value.publishedAt, DateTime.utc(2024, 5, 17, 8, 30));
      expect(value.uploaderAvatar.single.url.host, 'example.test');
      expect(value.uploaderAvatar.single.width, 48);
      expect(value.album, 'Album');
      expect(
        [for (final s in value.stats) (s.kind, s.count)],
        [(TrackStatKind.view, 12), (TrackStatKind.coin, 0)],
      );
    });

    for (final (description, result) in [
      ('an unknown kind', "{ stats: [{ kind: 'plays', count: 1 }] }"),
      ('a stat without a kind', '{ stats: [{ count: 1 }] }'),
      ('a stat without a count', "{ stats: [{ kind: 'view' }] }"),
      ('a negative count', "{ stats: [{ kind: 'view', count: -1 }] }"),
      ('a fractional count', "{ stats: [{ kind: 'view', count: 1.5 }] }"),
      (
        'an unknown stat field',
        "{ stats: [{ kind: 'view', count: 1, label: 'x' }] }",
      ),
      ('a stats value that is not a list', '{ stats: 1 }'),
      ('an unknown field', '{ views: 1 }'),
      ('a text publishedAt', "{ publishedAt: '2024-05-17' }"),
      ('a negative publishedAt', '{ publishedAt: -1 }'),
      ('a publishedAt past the date limit', '{ publishedAt: 9e15 }'),
      (
        'an avatar on another host',
        "{ uploaderAvatar: [{ url: 'https://other.test/a.png' }] }",
      ),
      (
        'an avatar that is not https',
        "{ uploaderAvatar: [{ url: 'http://example.test/a.png' }] }",
      ),
      ('a numeric description', '{ description: 1 }'),
      ('a webUrl on another host', "{ webUrl: 'https://evil.test/v/1' }"),
      ('a webUrl that is not https', "{ webUrl: 'http://example.test/v/1' }"),
      (
        'a webUrl on a look-alike host',
        "{ webUrl: 'https://evil-example.test/v/1' }",
      ),
      ('a numeric webUrl', '{ webUrl: 1 }'),
      ('undefined', 'undefined'),
    ]) {
      test('trackDetail rejects $description as ParseError', () async {
        expect(await detail(result), isA<ParseError>());
      });
    }

    test('an error thrown by the plugin keeps its type', () async {
      final plugin = await _load('''
export function trackDetail() { throw { fmpError: 'NetworkError' }; }
''');

      await expectLater(
        plugin.trackDetail(TrackDetailQuery(sourceId: 'a')),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
