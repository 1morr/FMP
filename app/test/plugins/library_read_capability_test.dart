import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `libraryRead` 能力（ADR 0032 §決定 3、6）：必要匯出 `libraryPlaylists`、選填匯出
// `libraryLiveRooms`（只有同時宣告 `live` 才准）、輸入的 JSON、回傳值的驗證（`playlistId`
// 與 `title` 不空、同一頁 `playlistId` 不重複、`trackCount` 非負、`cursor` 不是空字串、
// `writable` 必填）、`requiresLogin` 案例的形狀。fmp-test 的歌單由
// test_plugin_bundle_test.dart 守。

const _playlists = '''
export function libraryPlaylists(query) {
  return { playlists: [{ playlistId: 'a', title: JSON.stringify(query), writable: true }], cursor: null };
}
''';

const _liveExports = '''
export function liveSearch() {}
export function liveRoomFromUrl() {}
export function liveStatus() {}
export function resolveLive() {}
''';

const _liveRooms =
    'export function libraryLiveRooms() { return { rooms: [] }; }';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['libraryRead'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('a libraryRead plugin exports libraryPlaylists', () async {
      final plugin = await _load(_playlists);

      expect(plugin.manifest.requiredExports, {'libraryPlaylists'});
      expect(plugin.manifest.optionalExports, isEmpty);
      // 能力名稱本身不是匯出。
      expect(plugin.manifest.requiredExports, isNot(contains('libraryRead')));
    });

    test('declaring libraryRead without libraryPlaylists is Unsupported', () {
      expect(
        _load('export function libraryRead() {}'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('exporting libraryPlaylists without declaring it is Unsupported', () {
      expect(
        _load(
          'export function search() {}\n$_playlists',
          capabilities: ['search'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('libraryLiveRooms is optional with libraryRead and live', () async {
      final exported = await _load(
        '$_playlists\n$_liveExports\n$_liveRooms',
        capabilities: ['libraryRead', 'live'],
      );
      final omitted = await _load(
        '$_playlists\n$_liveExports',
        capabilities: ['libraryRead', 'live'],
      );

      expect(exported.manifest.optionalExports, {'libraryLiveRooms'});
      expect(omitted.manifest.optionalExports, {'libraryLiveRooms'});
      // 選填的不在必要匯出裡。
      expect(
        omitted.manifest.requiredExports,
        isNot(contains('libraryLiveRooms')),
      );
    });

    test('libraryLiveRooms without live is Unsupported', () {
      expect(_load('$_playlists\n$_liveRooms'), throwsA(isA<Unsupported>()));
    });

    test('libraryLiveRooms without libraryRead is Unsupported', () {
      expect(
        _load('$_liveExports\n$_liveRooms', capabilities: ['live']),
        throwsA(isA<Unsupported>()),
      );
    });

    test('calling the plugin without the capability is Unsupported', () async {
      final plugin = await _load(
        'export function search() {}',
        capabilities: ['search'],
      );

      expect(
        () => plugin.libraryPlaylists(LibraryPlaylistsQuery()),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('the cursor reaches the plugin as documented', () async {
      final plugin = await _load(_playlists);

      final first = await plugin.libraryPlaylists(LibraryPlaylistsQuery());
      final next = await plugin.libraryPlaylists(
        LibraryPlaylistsQuery(cursor: 'c2'),
      );

      expect(first.playlists.single.title, '{}');
      expect(next.playlists.single.title, '{"cursor":"c2"}');
    });

    test('an empty cursor is rejected before the call', () {
      expect(() => LibraryPlaylistsQuery(cursor: ''), throwsArgumentError);
    });
  });

  group('libraryPlaylists returned values', () {
    Future<Object> page(String result) async {
      final plugin = await _load(
        'export function libraryPlaylists() { return $result; }',
      );
      return plugin
          .libraryPlaylists(LibraryPlaylistsQuery())
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    test('an empty page is accepted', () async {
      final result = await page('{ playlists: [] }');

      expect(result, isA<LibraryPlaylistPage>());
      expect((result as LibraryPlaylistPage).playlists, isEmpty);
      expect(result.cursor, isNull);
    });

    test('every field is read, in the order of the plugin', () async {
      final result = await page(
        '{ playlists: ['
        "{ playlistId: 'b', title: 'B', writable: false },"
        "{ playlistId: 'a', title: 'A', trackCount: 0, writable: true,"
        " artwork: [{ url: 'https://example.test/a.jpg', width: 300 }] }"
        "], cursor: 'next' }",
      ) as LibraryPlaylistPage;

      expect([for (final p in result.playlists) p.playlistId], ['b', 'a']);
      expect(result.playlists.first.trackCount, isNull);
      expect(result.playlists.first.artwork, isEmpty);
      expect(result.playlists.first.writable, isFalse);
      expect(result.playlists.last.trackCount, 0);
      expect(result.playlists.last.writable, isTrue);
      expect(result.playlists.last.artwork.single.width, 300);
      expect(result.cursor, 'next');
    });

    for (final (description, result) in [
      (
        'a duplicate playlistId on a page',
        "{ playlists: [{ playlistId: 'a', title: 'A', writable: true }, "
            "{ playlistId: 'a', title: 'B', writable: true }] }",
      ),
      (
        'an empty playlistId',
        "{ playlists: [{ playlistId: '', title: 'A', writable: true }] }",
      ),
      (
        'an empty title',
        "{ playlists: [{ playlistId: 'a', title: '', writable: true }] }",
      ),
      (
        'a blank title',
        "{ playlists: [{ playlistId: 'a', title: '  ', writable: true }] }",
      ),
      (
        'a negative trackCount',
        "{ playlists: [{ playlistId: 'a', title: 'A', trackCount: -1, "
            'writable: true }] }',
      ),
      (
        'a fractional trackCount',
        "{ playlists: [{ playlistId: 'a', title: 'A', trackCount: 1.5, "
            'writable: true }] }',
      ),
      (
        'a missing writable',
        "{ playlists: [{ playlistId: 'a', title: 'A' }] }",
      ),
      (
        'a writable that is not a boolean',
        "{ playlists: [{ playlistId: 'a', title: 'A', writable: 1 }] }",
      ),
      (
        'an unknown field',
        "{ playlists: [{ playlistId: 'a', title: 'A', writable: true, x: 1 }] }",
      ),
      ('an empty cursor', "{ playlists: [], cursor: '' }"),
      ('a missing playlists field', '{}'),
      ('a string', "'a'"),
      ('undefined', 'undefined'),
      (
        'artwork on another host',
        "{ playlists: [{ playlistId: 'a', title: 'A', writable: true, "
            "artwork: [{ url: 'https://evil.test/a.jpg' }] }] }",
      ),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await page(result), isA<ParseError>());
      });
    }

    test('the same title on different playlists is fine', () async {
      final result = await page(
        "{ playlists: [{ playlistId: 'a', title: 'A', writable: true }, "
        "{ playlistId: 'b', title: 'A', writable: true }] }",
      );

      expect(result, isA<LibraryPlaylistPage>());
    });

    test('AuthRequired thrown by the plugin keeps its type', () async {
      final plugin = await _load('''
export function libraryPlaylists() { throw { fmpError: 'AuthRequired' }; }
''');

      await expectLater(
        plugin.libraryPlaylists(LibraryPlaylistsQuery()),
        throwsA(isA<AuthRequired>()),
      );
    });
  });

  group('the libraryRead check', () {
    PluginCheck check(String body) =>
        parseChecks('{"libraryRead": $body}').single;

    const valid =
        '{"input": {}, "expect": {"minItems": 1, "nonEmpty": ["title"]}, '
        '"requiresLogin": true}';

    test('requires a login, and the input is the query', () {
      final parsed = check(valid);

      expect(parsed.capability, PluginCapability.libraryRead);
      expect(parsed.requiresLogin, isTrue);
      expect(parsed.mutates, isFalse);
      expect((parsed.input as LibraryPlaylistsQuery).cursor, isNull);
      final withCursor = check(
        '{"input": {"cursor": "c"}, "expect": {}, "requiresLogin": true}',
      );
      expect((withCursor.input as LibraryPlaylistsQuery).cursor, 'c');
    });

    test('a case without requiresLogin: true is rejected', () {
      for (final body in [
        '{"input": {}, "expect": {}}',
        '{"input": {}, "expect": {}, "requiresLogin": false}',
      ]) {
        expect(() => check(body), throwsFormatException, reason: body);
      }
    });

    test('an empty cursor in the input is rejected', () {
      expect(
        () => check(
          '{"input": {"cursor": ""}, "expect": {}, "requiresLogin": true}',
        ),
        throwsFormatException,
      );
    });

    test('nonEmpty names must be LibraryPlaylist fields', () {
      expect(
        () => check(
          '{"input": {}, "expect": {"nonEmpty": ["nope"]}, '
          '"requiresLogin": true}',
        ),
        throwsFormatException,
      );
    });

    test('runs libraryPlaylists and checks its playlists', () async {
      final plugin = await _load(_playlists);
      final parsed = check(valid);

      final result = await parsed.run(plugin);

      expect(result, isA<LibraryPlaylistPage>());
      expect(
        parsed.expectation.evaluate(
          result: result,
          describe: (error) => '$error',
        ),
        isEmpty,
      );
      final tooMany = check(
        '{"input": {}, "expect": {"minItems": 2}, "requiresLogin": true}',
      );
      expect(
        tooMany.expectation.evaluate(
          result: result,
          describe: (error) => '$error',
        ),
        isNotEmpty,
      );
    });
  });
}
