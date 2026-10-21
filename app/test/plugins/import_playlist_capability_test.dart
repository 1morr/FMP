import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `importPlaylist` 能力（ADR 0032 §決定 1、2、6）：兩個匯出（`playlistFromUrl`、
// `importPlaylist`，能力名稱本身不是匯出）、輸入的 JSON、回傳值的驗證、`mixSeed` 與
// `mix` 的關係、分 P 兩欄。fmp-test 的歌單由 test_plugin_bundle_test.dart 守。

const _exports = '''
export function playlistFromUrl(query) {
  return query.url === 'none' ? null : { playlistId: query.url };
}
export function importPlaylist(query) {
  return {
    playlist: { title: JSON.stringify(query) },
    items: [{ track: { sourceId: 'a', title: 'T' } }],
    cursor: 'next',
  };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['importPlaylist'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('an importPlaylist plugin exports the two functions', () async {
      final plugin = await _load(_exports);

      expect(plugin.manifest.requiredExports, ImportPlaylistExports.all);
      expect(ImportPlaylistExports.all, {'playlistFromUrl', 'importPlaylist'});
    });

    test('declaring importPlaylist without playlistFromUrl is Unsupported', () {
      expect(
        _load('export function importPlaylist() {}'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('declaring importPlaylist without importPlaylist is Unsupported', () {
      expect(
        _load('export function playlistFromUrl() {}'),
        throwsA(isA<Unsupported>()),
      );
    });

    for (final name in ['playlistFromUrl', 'importPlaylist']) {
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

      expect(
        () => plugin.playlistFromUrl(PlaylistUrlQuery(url: 'https://a.test/')),
        throwsA(isA<Unsupported>()),
      );
      expect(
        () => plugin.importPlaylist(PlaylistPageQuery(playlistId: 'a')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('the url and the page reach the plugin as documented', () async {
      final plugin = await _load(_exports);

      final first = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'pl'),
      );
      final next = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'pl', cursor: 'c1'),
      );

      // 第一頁不送 cursor。
      expect(first.playlist.title, '{"playlistId":"pl"}');
      expect(next.playlist.title, '{"playlistId":"pl","cursor":"c1"}');
    });

    test('a recognised url gives the playlist id', () async {
      final plugin = await _load(_exports);

      final ref = await plugin.playlistFromUrl(
        PlaylistUrlQuery(url: 'https://a.test/x'),
      );

      expect(ref, isA<PlaylistIdRef>());
      expect((ref! as PlaylistIdRef).playlistId, 'https://a.test/x');
    });

    test('an unknown url is null', () async {
      final plugin = await _load(_exports);

      expect(await plugin.playlistFromUrl(PlaylistUrlQuery(url: 'none')), null);
    });

    test('the page decodes, and the host fills the source id', () async {
      final plugin = await _load(_exports);

      final page = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'pl'),
      );

      expect(page.cursor, 'next');
      expect(page.total, isNull);
      expect(page.items.single.track.sourceTypeId, 'plugin-a');
      expect(page.items.single.unavailable, isFalse);
      expect(page.items.single.remoteItemId, isNull);
      expect(page.playlist.writable, isNull);
    });

    test('inputs are checked before the call', () {
      expect(() => PlaylistUrlQuery(url: ' '), throwsArgumentError);
      expect(() => PlaylistPageQuery(playlistId: ''), throwsArgumentError);
      expect(
        () => PlaylistPageQuery(playlistId: 'a', cursor: ''),
        throwsArgumentError,
      );
    });
  });

  group('playlistFromUrl returned values', () {
    Future<Object?> from(
      String result, {
      List<String> capabilities = const ['importPlaylist'],
    }) async {
      final plugin = await _load(
        'export function playlistFromUrl() { return $result; }\n'
        'export function importPlaylist() {}\n'
        '${capabilities.contains('mix') ? 'export function mix() {}' : ''}',
        capabilities: capabilities,
      );
      return plugin
          .playlistFromUrl(PlaylistUrlQuery(url: 'https://a.test/'))
          .then<Object?>((ref) => ref, onError: (Object error) => error);
    }

    for (final (description, result) in [
      ('an empty playlist id', "{ playlistId: '' }"),
      ('a missing playlist id', '{}'),
      ('an unknown field', "{ playlistId: 'a', title: 'T' }"),
      ('a playlist id and a mixSeed', "{ playlistId: 'a', mixSeed: {} }"),
      ('a string', "'a'"),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await from(result), isA<ParseError>());
      });
    }

    test('null means "not mine"', () async {
      expect(await from('null'), isNull);
    });

    test('a mixSeed from a plugin that declares mix is accepted', () async {
      final ref = await from(
        "{ mixSeed: { sourceId: 'v1', cid: 3 } }",
        capabilities: ['importPlaylist', 'mix'],
      );

      expect(ref, isA<PlaylistMixSeedRef>());
      final seed = (ref! as PlaylistMixSeedRef).seed;
      expect(seed.sourceId, 'v1');
      expect(seed.cid, 3);
    });

    test('a mixSeed from a plugin without mix is ParseError', () async {
      expect(await from("{ mixSeed: { sourceId: 'v1' } }"), isA<ParseError>());
    });

    for (final (description, result) in [
      ('without a source id', '{ mixSeed: {} }'),
      ('with an empty source id', "{ mixSeed: { sourceId: '' } }"),
      ('with an unknown field', "{ mixSeed: { sourceId: 'a', x: 1 } }"),
      (
        'next to a playlist id',
        "{ mixSeed: { sourceId: 'a' }, playlistId: 'p' }",
      ),
    ]) {
      test('rejects a mixSeed $description', () async {
        expect(
          await from(result, capabilities: ['importPlaylist', 'mix']),
          isA<ParseError>(),
        );
      });
    }
  });

  group('importPlaylist returned values', () {
    Future<Object> page(String result) async {
      final plugin = await _load(
        'export function playlistFromUrl() { return null; }\n'
        'export function importPlaylist() { return $result; }',
      );
      return plugin
          .importPlaylist(PlaylistPageQuery(playlistId: 'a'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    const playlist = "playlist: { title: 'T' }";
    const track = "{ sourceId: 'a', title: 'T' }";

    test('an empty playlist is a page without items', () async {
      final result = await page('{ $playlist, items: [], cursor: null }');

      expect(result, isA<PlaylistPage>());
      expect((result as PlaylistPage).items, isEmpty);
      expect(result.cursor, isNull);
    });

    test('the optional fields are read', () async {
      final result = await page('''{
  playlist: { title: 'T', description: 'D', ownerName: 'O', writable: true,
    artwork: [{ url: 'https://example.test/a.jpg', width: 64 }] },
  items: [
    { track: $track, remoteItemId: 'r1', unavailable: true },
    { track: $track, unavailable: false },
  ],
  cursor: 'c',
  total: 0,
}''') as PlaylistPage;

      expect(result.playlist.description, 'D');
      expect(result.playlist.ownerName, 'O');
      expect(result.playlist.writable, isTrue);
      expect(result.playlist.artwork.single.width, 64);
      expect(result.items.map((item) => item.remoteItemId), ['r1', null]);
      expect(result.items.map((item) => item.unavailable), [true, false]);
      expect(result.total, 0);
    });

    test('truncated is read and defaults to false', () async {
      final on = await page(
        '{ $playlist, items: [], truncated: true }',
      ) as PlaylistPage;
      final off = await page('{ $playlist, items: [] }') as PlaylistPage;
      final explicit = await page(
        '{ $playlist, items: [], truncated: false }',
      ) as PlaylistPage;

      expect(on.truncated, isTrue);
      expect(off.truncated, isFalse);
      expect(explicit.truncated, isFalse);
    });

    test('writable false is not the same as not knowing', () async {
      final result = await page(
        "{ playlist: { title: 'T', writable: false }, items: [], "
        'cursor: null }',
      ) as PlaylistPage;

      expect(result.playlist.writable, isFalse);
    });

    for (final (description, result) in [
      ('a missing playlist', '{ items: [], cursor: null }'),
      ('a playlist without a title', '{ playlist: {}, items: [] }'),
      (
        'a playlist with an empty title',
        "{ playlist: { title: '' }, items: [] }",
      ),
      (
        'a playlist with an unknown field',
        "{ playlist: { title: 'T', x: 1 }, items: [] }",
      ),
      (
        'a writable that is not a boolean',
        "{ playlist: { title: 'T', writable: 'yes' }, items: [] }",
      ),
      ('missing items', '{ $playlist }'),
      ('an empty cursor', "{ $playlist, items: [], cursor: '' }"),
      ('a cursor that is not a string', '{ $playlist, items: [], cursor: 3 }'),
      (
        'truncated with a cursor',
        "{ $playlist, items: [], cursor: 'c', truncated: true }",
      ),
      (
        'a truncated that is not a boolean',
        "{ $playlist, items: [], truncated: 'yes' }",
      ),
      ('a negative total', '{ $playlist, items: [], total: -1 }'),
      ('a total that is not a number', "{ $playlist, items: [], total: '5' }"),
      ('an unknown field', '{ $playlist, items: [], hasMore: false }'),
      ('an item without a track', '{ $playlist, items: [{}] }'),
      (
        'an item with an unknown field',
        '{ $playlist, items: [{ track: $track, position: 1 }] }',
      ),
      (
        'an empty remoteItemId',
        "{ $playlist, items: [{ track: $track, remoteItemId: '' }] }",
      ),
      (
        'an unavailable that is not a boolean',
        "{ $playlist, items: [{ track: $track, unavailable: 'yes' }] }",
      ),
      (
        'a track without a title',
        "{ $playlist, items: [{ track: { sourceId: 'a' } }] }",
      ),
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
          "{ playlist: { title: 'T', artwork: "
          "[{ url: 'https://evil.test/a.jpg' }] }, items: [] }",
        ),
        isA<ParseError>(),
      );
      expect(
        await page(
          '{ $playlist, items: [{ track: { sourceId: "a", title: "T", '
          'artwork: [{ url: "https://evil.test/a.jpg" }] } }] }',
        ),
        isA<ParseError>(),
      );
    });

    test('an error thrown by the plugin keeps its type', () async {
      for (final (name, matcher) in [
        ('NotFound', isA<NotFound>()),
        ('AuthRequired', isA<AuthRequired>()),
      ]) {
        final plugin = await _load('''
export function playlistFromUrl() { return null; }
export function importPlaylist() { throw { fmpError: '$name' }; }
''');

        await expectLater(
          plugin.importPlaylist(PlaylistPageQuery(playlistId: 'a')),
          throwsA(matcher),
        );
      }
    });
  });

  group('the part fields of a track', () {
    Future<Object> pageWith(String trackFields) async {
      final plugin = await _load('''
export function playlistFromUrl() { return null; }
export function importPlaylist() {
  return {
    playlist: { title: 'T' },
    items: [{ track: { sourceId: 'v', title: 'P1', $trackFields } }],
    cursor: null,
  };
}
''');
      return plugin
          .importPlaylist(PlaylistPageQuery(playlistId: 'a'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('both given are read and reach the track info', () async {
      final result = await pageWith(
        "partIndex: 2, parentTitle: 'Video', cid: 7",
      ) as PlaylistPage;

      final track = result.items.single.track;
      expect(track.partIndex, 2);
      expect(track.parentTitle, 'Video');
      final info = track.toTrackInfo();
      expect(info.partIndex, 2);
      expect(info.parentTitle, 'Video');
      expect(info.cid, 7);
      expect(info.displayTitle, 'Video · P2 P1');
    });

    test('neither given leaves a track that is not a part', () async {
      final result = await pageWith('cid: 7') as PlaylistPage;

      final info = result.items.single.track.toTrackInfo();
      expect(info.partIndex, isNull);
      expect(info.parentTitle, isNull);
    });

    for (final (description, fields) in [
      ('only partIndex', 'partIndex: 2'),
      ('only parentTitle', "parentTitle: 'Video'"),
      (
        'a null parentTitle with a partIndex',
        'partIndex: 2, parentTitle: null',
      ),
      ('a partIndex of 0', "partIndex: 0, parentTitle: 'Video'"),
      ('a fractional partIndex', "partIndex: 1.5, parentTitle: 'Video'"),
      ('a blank parentTitle', "partIndex: 1, parentTitle: ' '"),
      ('a partIndex that is a string', "partIndex: '1', parentTitle: 'V'"),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await pageWith(fields), isA<ParseError>());
      });
    }

    test('search results take the part fields too', () async {
      final plugin = await _load(
        '''
export function search() {
  return { items: [{ sourceId: 'v', title: 'P1', partIndex: 1, parentTitle: 'Video' }], hasMore: false };
}
''',
        capabilities: ['search'],
      );

      final page = await plugin.search(SearchQuery(keyword: 'k'));

      expect(page.items.single.partIndex, 1);
      expect(page.items.single.parentTitle, 'Video');
    });

    test('a search result with only one of the two is ParseError', () async {
      final plugin = await _load(
        '''
export function search() {
  return { items: [{ sourceId: 'v', title: 'P1', partIndex: 1 }], hasMore: false };
}
''',
        capabilities: ['search'],
      );

      await expectLater(
        plugin.search(SearchQuery(keyword: 'k')),
        throwsA(isA<ParseError>()),
      );
    });

    test('the check fields carry the part fields', () {
      const track = TrackSummary(
        sourceTypeId: 'p',
        sourceId: 'v',
        title: 'P1',
        partIndex: 3,
        parentTitle: 'Video',
      );

      expect(trackFields(track)['partIndex'], 3);
      expect(trackFields(track)['parentTitle'], 'Video');
    });
  });

  group('the importPlaylist check on a plugin', () {
    PluginCheck check() => parseChecks('''
{"importPlaylist": {"input": {"url": "https://a.test/x"}, "expect": {"minItems": 1}}}
''').single;

    Future<Object> run(String playlistFromUrl) async {
      final plugin = await _load(
        'export function playlistFromUrl() { return $playlistFromUrl; }\n'
        'export function importPlaylist(query) {\n'
        '  return { playlist: { title: query.playlistId }, items: [{ track: { sourceId: "a", title: "T" } }], cursor: null };\n'
        '}\n'
        'export function mix() {}',
        capabilities: ['importPlaylist', 'mix'],
      );
      return check()
          .run(plugin)
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('runs the first page of the recognised playlist', () async {
      final result = await run("{ playlistId: 'pl-1' }") as PlaylistPage;

      expect(result.playlist.title, 'pl-1');
    });

    test('an unrecognised url fails the case', () async {
      expect(await run('null'), isA<ParseError>());
    });

    test('a mixSeed is not a playlist: the case fails', () async {
      expect(await run("{ mixSeed: { sourceId: 'v' } }"), isA<ParseError>());
    });
  });
}
