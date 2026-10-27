import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `live` 能力（ADR 0028 §決定 3）：四個匯出的呼叫、回傳值的驗證、宣告與匯出的一致，
// 以及請求以 `userPreference` 帶憑證。fmp-test 的五個直播間在最後一組。

final _formats = [StreamFormat(container: 'mp4', codec: 'aac')];

const _liveExports = '''
export function liveSearch(query) {
  return { items: [{ roomId: 'r1', title: JSON.stringify(query), status: 'live' }], hasMore: false };
}
export function liveRoomFromUrl(query) {
  return query.url.endsWith('/r1') ? { roomId: 'r1' } : null;
}
export function liveStatus(query) {
  return { roomId: query.roomId, title: 'Room', status: 'offline' };
}
export function resolveLive(request) {
  return { candidates: [{ url: 'https://cdn.example.test/' + JSON.stringify(request) }] };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['live'],
  PluginHarness? harness,
}) => (harness ?? PluginHarness()).load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('a live plugin exports all four functions', () async {
      final plugin = await _load(_liveExports);

      expect(plugin.manifest.requiredExports, {
        'liveSearch',
        'liveRoomFromUrl',
        'liveStatus',
        'resolveLive',
      });
    });

    for (final missing in [
      'liveSearch',
      'liveRoomFromUrl',
      'liveStatus',
      'resolveLive',
    ]) {
      test('declaring live without $missing is Unsupported', () async {
        final others = [
          for (final name in [
            'liveSearch',
            'liveRoomFromUrl',
            'liveStatus',
            'resolveLive',
          ])
            if (name != missing) 'export function $name() {}',
        ].join('\n');

        await expectLater(_load(others), throwsA(isA<Unsupported>()));
      });
    }

    test('exporting a live function without declaring live is Unsupported', () {
      expect(
        _load(
          'export function search() {}\nexport function liveStatus() {}',
          capabilities: ['search'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('the capability is not exported under its own name', () {
      // `live` 沒有同名的匯出：只匯出 `live` 而沒有那四個，載入失敗。
      expect(_load('export function live() {}'), throwsA(isA<Unsupported>()));
    });

    test(
      'calling a live method without the capability is Unsupported',
      () async {
        final plugin = await _load(
          'export function search() {}',
          capabilities: ['search'],
        );

        expect(
          () => plugin.liveSearch(LiveSearchQuery(keyword: 'k')),
          throwsA(isA<Unsupported>()),
        );
        expect(
          () => plugin.liveRoomFromUrl(LiveUrlQuery(url: 'https://a.test/')),
          throwsA(isA<Unsupported>()),
        );
        expect(
          () => plugin.liveStatus(LiveRoomQuery(roomId: 'r')),
          throwsA(isA<Unsupported>()),
        );
        expect(
          () => plugin.resolveLive(
            LiveStreamRequest(roomId: 'r', formats: _formats),
          ),
          throwsA(isA<Unsupported>()),
        );
      },
    );
  });

  group('calls', () {
    test(
      'the plugin receives the documented JSON and the results decode',
      () async {
        final plugin = await _load(_liveExports);

        final page = await plugin.liveSearch(
          LiveSearchQuery(keyword: 'k', page: 2, status: LiveRoomStatus.live),
        );
        final unfiltered = await plugin.liveSearch(
          LiveSearchQuery(keyword: 'k'),
        );
        final known = await plugin.liveRoomFromUrl(
          LiveUrlQuery(url: 'https://example.test/r1'),
        );
        final unknown = await plugin.liveRoomFromUrl(
          LiveUrlQuery(url: 'https://example.test/other'),
        );
        final room = await plugin.liveStatus(LiveRoomQuery(roomId: 'r9'));
        final stream = await plugin.resolveLive(
          LiveStreamRequest(roomId: 'r9', formats: _formats),
        );

        expect(page.items.single.roomId, 'r1');
        expect(page.items.single.status, LiveRoomStatus.live);
        expect(
          page.items.single.title,
          '{"keyword":"k","page":2,"status":"live"}',
        );
        expect(page.hasMore, isFalse);
        // 沒給 status 就不送這個欄位。
        expect(unfiltered.items.single.title, '{"keyword":"k","page":1}');
        expect(known!.roomId, 'r1');
        expect(unknown, isNull);
        expect(room.roomId, 'r9');
        expect(room.status, LiveRoomStatus.offline);
        expect(room.hostName, isNull);
        expect(room.online, isNull);
        expect(room.artwork, isEmpty);
        expect(
          Uri.decodeComponent(stream.candidates.single.url.pathSegments.single),
          '{"roomId":"r9","formats":[{"container":"mp4","codec":"aac"}]}',
        );
        // 直播流可以沒有期限。
        expect(stream.candidates.single.expiresAt, isNull);
      },
    );

    test('a room keeps its optional fields', () async {
      final plugin = await _load('''
export function liveSearch() { return { items: [], hasMore: false }; }
export function liveRoomFromUrl() { return null; }
export function liveStatus(query) {
  return {
    roomId: query.roomId, title: 'T', hostName: 'Host', status: 'live', online: 1234,
    artwork: [{ url: 'https://img.example.test/a.jpg', width: 320 }],
  };
}
export function resolveLive() { return { candidates: [{ url: 'https://example.test/a' }] }; }
''');

      final room = await plugin.liveStatus(LiveRoomQuery(roomId: 'r1'));

      expect(room.hostName, 'Host');
      expect(room.online, 1234);
      expect(
        room.artwork.single.url,
        Uri.parse('https://img.example.test/a.jpg'),
      );
      expect(room.artwork.single.width, 320);
    });

    test('area is trimmed and an empty one counts as missing', () async {
      Future<LiveRoom> room(String area) async {
        final plugin = await _load('''
export function liveSearch() { return { items: [], hasMore: false }; }
export function liveRoomFromUrl() { return null; }
export function liveStatus(query) {
  return { roomId: query.roomId, title: 'T', status: 'live', area: $area };
}
export function resolveLive() { return { candidates: [{ url: 'https://example.test/a' }] }; }
''');
        return plugin.liveStatus(LiveRoomQuery(roomId: 'r1'));
      }

      expect((await room("'  Games '")).area, 'Games');
      expect((await room("'   '")).area, isNull);
      expect((await room("''")).area, isNull);
      expect((await room('null')).area, isNull);
      expect((await room('undefined')).area, isNull);
    });

    test('inputs are checked before the call', () {
      expect(() => LiveSearchQuery(keyword: ' '), throwsArgumentError);
      expect(() => LiveSearchQuery(keyword: 'k', page: 0), throwsRangeError);
      expect(() => LiveRoomQuery(roomId: ''), throwsArgumentError);
      expect(() => LiveUrlQuery(url: ' '), throwsArgumentError);
      expect(
        () => LiveStreamRequest(roomId: '', formats: _formats),
        throwsArgumentError,
      );
      expect(
        () => LiveStreamRequest(roomId: 'r', formats: const []),
        throwsArgumentError,
      );
    });
  });

  group('liveStatus never turns a failure into offline (D10)', () {
    for (final (name, thrown, matcher) in <(String, String, Matcher)>[
      (
        'a network error',
        "{ fmpError: 'NetworkError', message: 'down' }",
        isA<NetworkError>(),
      ),
      ('a rate limit', "{ fmpError: 'RateLimited' }", isA<RateLimited>()),
      ('an unknown room', "{ fmpError: 'NotFound' }", isA<NotFound>()),
    ]) {
      test('$name stays an error', () async {
        final plugin = await _load('''
export function liveSearch() {}
export function liveRoomFromUrl() {}
export function liveStatus() { throw $thrown; }
export function resolveLive() {}
''');

        await expectLater(
          plugin.liveStatus(LiveRoomQuery(roomId: 'r')),
          throwsA(matcher),
        );
      });
    }

    test('a result that is not a room is a ParseError, not offline', () async {
      final plugin = await _load('''
export function liveSearch() {}
export function liveRoomFromUrl() {}
export function liveStatus() { return null; }
export function resolveLive() {}
''');

      await expectLater(
        plugin.liveStatus(LiveRoomQuery(roomId: 'r')),
        throwsA(isA<ParseError>()),
      );
    });
  });

  group('returned values', () {
    Future<Object> status(String result) async {
      final plugin = await _load('''
export function liveSearch() {}
export function liveRoomFromUrl() {}
export function liveStatus() { return $result; }
export function resolveLive() {}
''');
      return plugin
          .liveStatus(LiveRoomQuery(roomId: 'r'))
          .then<Object>((room) => room, onError: (Object error) => error);
    }

    Future<Object> search(String result) async {
      final plugin = await _load('''
export function liveSearch() { return $result; }
export function liveRoomFromUrl() {}
export function liveStatus() {}
export function resolveLive() {}
''');
      return plugin
          .liveSearch(LiveSearchQuery(keyword: 'k'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    Future<Object> resolve(String result) async {
      final plugin = await _load('''
export function liveSearch() {}
export function liveRoomFromUrl() {}
export function liveStatus() {}
export function resolveLive() { return $result; }
''');
      return plugin
          .resolveLive(LiveStreamRequest(roomId: 'r', formats: _formats))
          .then<Object>((stream) => stream, onError: (Object error) => error);
    }

    Future<Object> fromUrl(String result) async {
      final plugin = await _load('''
export function liveSearch() {}
export function liveRoomFromUrl() { return $result; }
export function liveStatus() {}
export function resolveLive() {}
''');
      return plugin
          .liveRoomFromUrl(LiveUrlQuery(url: 'https://example.test/x'))
          .then<Object>(
            (ref) => ref ?? 'null',
            onError: (Object error) => error,
          );
    }

    for (final (description, result) in [
      ('a missing title', "{ roomId: 'r', status: 'live' }"),
      ('an empty room id', "{ roomId: '', title: 'T', status: 'live' }"),
      ('a missing status', "{ roomId: 'r', title: 'T' }"),
      ('an unknown status', "{ roomId: 'r', title: 'T', status: 'paused' }"),
      (
        'a status in the wrong case',
        "{ roomId: 'r', title: 'T', status: 'Live' }",
      ),
      (
        'an unknown field',
        "{ roomId: 'r', title: 'T', status: 'live', viewers: 3 }",
      ),
      (
        'a negative audience',
        "{ roomId: 'r', title: 'T', status: 'live', online: -1 }",
      ),
      (
        'a fractional audience',
        "{ roomId: 'r', title: 'T', status: 'live', online: 1.5 }",
      ),
      (
        'artwork on another host',
        "{ roomId: 'r', title: 'T', status: 'live', "
            "artwork: [{ url: 'https://evil.test/a.jpg' }] }",
      ),
      (
        'a numeric area',
        "{ roomId: 'r', title: 'T', status: 'live', area: 3 }",
      ),
      ('a string', "'live'"),
      ('undefined', 'undefined'),
    ]) {
      test('liveStatus rejects $description as ParseError', () async {
        expect(await status(result), isA<ParseError>());
      });
    }

    for (final (description, result) in [
      ('a missing hasMore', '{ items: [] }'),
      ('an unknown field', '{ items: [], hasMore: false, total: 1 }'),
      (
        'a room without a status',
        "{ items: [{ roomId: 'r', title: 'T' }], hasMore: false }",
      ),
      ('undefined', 'undefined'),
    ]) {
      test('liveSearch rejects $description as ParseError', () async {
        expect(await search(result), isA<ParseError>());
      });
    }

    for (final (description, result) in [
      ('a missing roomId', '{}'),
      ('an empty roomId', "{ roomId: '' }"),
      ('an unknown field', "{ roomId: 'r', url: 'https://example.test/' }"),
      ('a string', "'r'"),
    ]) {
      test('liveRoomFromUrl rejects $description as ParseError', () async {
        expect(await fromUrl(result), isA<ParseError>());
      });
    }

    test('liveRoomFromUrl reads null and undefined as not mine', () async {
      expect(await fromUrl('null'), 'null');
      expect(await fromUrl('undefined'), 'null');
    });

    for (final (description, result) in [
      ('no candidates', '{ candidates: [] }'),
      (
        'a stream on another host',
        "{ candidates: [{ url: 'https://evil.test/a' }] }",
      ),
      ('an http stream', "{ candidates: [{ url: 'http://example.test/a' }] }"),
    ]) {
      test('resolveLive rejects $description as ParseError', () async {
        expect(await resolve(result), isA<ParseError>());
      });
    }

    test('resolveLive keeps an expiry when the plugin knows one', () async {
      final stream = await resolve(
        "{ candidates: [{ url: 'https://example.test/a', "
        'expiresAt: 1790000000000 }] }',
      );

      expect(
        (stream as StreamResult).candidates.single.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true),
      );
    });
  });

  group('credentials follow the user preference', () {
    const source = '''
export async function liveSearch() {
  await fmp.http.request({ url: 'https://example.test/search', auth: 'userPreference' });
  return { items: [], hasMore: false };
}
export async function liveRoomFromUrl() {
  await fmp.http.request({ url: 'https://example.test/short', auth: 'userPreference' });
  return null;
}
export async function liveStatus(query) {
  await fmp.http.request({ url: 'https://example.test/status', auth: 'userPreference' });
  return { roomId: query.roomId, title: 'T', status: 'live' };
}
export async function resolveLive() {
  await fmp.http.request({ url: 'https://example.test/stream', auth: 'userPreference' });
  return { candidates: [{ url: 'https://example.test/a' }] };
}
export function loginVerify() { return { userId: '42', displayName: 'Tester' }; }
''';

    Future<(PluginHarness, ScriptSourcePlugin)> loggedIn() async {
      final harness = PluginHarness();
      final plugin = await harness.load(
        pluginSource(
          source,
          capabilities: ['live', 'login'],
          login: '{"methods": ["cookie"]}',
        ),
      );
      await harness.credentials.save(
        Account(
          pluginId: 'plugin-a',
          userId: '42',
          displayName: 'Tester',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 14),
        ),
        const LoginCredentials(cookies: {'SESSDATA': 'FAKE_LIVE_SESSION'}),
      );
      return (harness, plugin);
    }

    test(
      'all four live calls carry the cookie while the switch is on',
      () async {
        final (harness, plugin) = await loggedIn();
        String? cookie() =>
            harness.adapter.requests.last.headers['cookie'] as String?;

        await plugin.liveSearch(LiveSearchQuery(keyword: 'k'));
        expect(cookie(), 'SESSDATA=FAKE_LIVE_SESSION', reason: 'liveSearch');
        await plugin.liveRoomFromUrl(LiveUrlQuery(url: 'https://b23.tv/x'));
        expect(
          cookie(),
          'SESSDATA=FAKE_LIVE_SESSION',
          reason: 'liveRoomFromUrl',
        );
        await plugin.liveStatus(LiveRoomQuery(roomId: 'r'));
        expect(cookie(), 'SESSDATA=FAKE_LIVE_SESSION', reason: 'liveStatus');
        await plugin.resolveLive(
          LiveStreamRequest(roomId: 'r', formats: _formats),
        );
        expect(cookie(), 'SESSDATA=FAKE_LIVE_SESSION', reason: 'resolveLive');
      },
    );

    test('they send no cookie once the switch is off', () async {
      final (harness, plugin) = await loggedIn();
      await SourceSettingsRepository(harness.database)
          .setBrowseAsLoggedIn('plugin-a', value: false);
      // 先確認最後一個請求就是這次呼叫發的，不然「沒有 cookie」可能是看到上一個。
      String? cookie(String path) {
        final request = harness.adapter.requests.last;
        expect(request.uri.path, path);
        return request.headers['cookie'] as String?;
      }

      await plugin.liveSearch(LiveSearchQuery(keyword: 'k'));
      expect(cookie('/search'), isNull, reason: 'liveSearch');
      await plugin.liveRoomFromUrl(LiveUrlQuery(url: 'https://b23.tv/x'));
      expect(cookie('/short'), isNull, reason: 'liveRoomFromUrl');
      await plugin.liveStatus(LiveRoomQuery(roomId: 'r'));
      expect(cookie('/status'), isNull, reason: 'liveStatus');
      await plugin.resolveLive(
        LiveStreamRequest(roomId: 'r', formats: _formats),
      );
      expect(cookie('/stream'), isNull, reason: 'resolveLive');
    });
  });
}
