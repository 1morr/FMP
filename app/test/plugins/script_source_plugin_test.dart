import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../support/fake_http_adapter.dart';
import 'plugin_harness.dart';

final _formats = [StreamFormat(container: 'mp4', codec: 'aac')];

void main() {
  group('the test plugin', () {
    test('searches with synthetic results', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      final first = await plugin.search(SearchQuery(keyword: 'hi'));
      final second = await plugin.search(SearchQuery(keyword: 'hi', page: 2));

      expect(first.items.map((t) => t.sourceId), ['tone-220', 'tone-440']);
      expect(first.hasMore, isTrue);
      expect(second.items.map((t) => t.sourceId), ['tone-880']);
      expect(second.hasMore, isFalse);
      final track = first.items.first;
      expect(track.sourceTypeId, 'fmp-test');
      expect(track.cid, isNull);
      expect(track.title, 'Test tone 220 Hz (hi)');
      expect(track.uploader, 'FMP');
      expect(track.duration, const Duration(seconds: 2));
      expect(track.artwork, isEmpty);
    });

    test('reads its own storage while searching', () async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());
      await harness.storage.write('fmp-test', 'titlePrefix', 'Tone');

      final page = await plugin.search(SearchQuery(keyword: 'x'));

      expect(page.items.first.title, 'Tone 220 Hz (x)');
    });

    test('resolves a stream to the bundled tone', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      final result = await plugin.resolveStream(
        StreamRequest(sourceId: 'tone-440', formats: _formats),
      );

      expect(result.previewOnly, isFalse);
      final candidate = result.candidates.single;
      expect(
        candidate.url,
        Uri.parse('asset:///test/fixtures/plugins/test_plugin/tone.wav'),
      );
      expect(candidate.container, 'wav');
      expect(candidate.codec, 'pcm_s16le');
      expect(candidate.bitrate, 256000);
      expect(candidate.expiresAt, isNull);
      expect(candidate.headers, isEmpty);
    });

    test('an unknown track is NotFound', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.resolveStream(
          StreamRequest(sourceId: 'song-1', formats: _formats),
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('exports and capabilities', () {
    test('a declared capability must be exported', () async {
      await expectLater(
        PluginHarness().load(
          pluginSource(
            'export function search() {}',
            capabilities: ['search', 'resolveStream'],
          ),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('an exported capability must be declared', () async {
      await expectLater(
        PluginHarness().load(
          pluginSource(
            'export function search() {}\nexport function charts() {}',
          ),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('other exports are allowed', () async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search() {}\n'
          'export function helper() {}\n'
          'export const version = 2;',
        ),
      );

      expect(plugin.manifest.id, 'plugin-a');
    });

    test('calling an undeclared capability is Unsupported', () async {
      final plugin = await PluginHarness().load(
        pluginSource('export function search() {}'),
      );

      expect(
        () => plugin.resolveStream(
          StreamRequest(sourceId: 'a', formats: _formats),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('the manifest redaction list reaches the log', () async {
      final harness = PluginHarness();
      final source =
          pluginSource(
            "export function search() { fmp.log.info('ticket=FAKE_TICKET_42'); "
            'return { items: [], hasMore: false }; }',
          ).replaceFirst(
            '"allowedHosts"',
            '"redaction": {"keyNames": ["ticket"]},\n  "allowedHosts"',
          );
      final plugin = await harness.load(source);

      await plugin.search(SearchQuery(keyword: 'x'));

      expect(
        harness.records('plugin-a').single.message,
        isNot(contains('FAKE_TICKET_42')),
      );
    });
  });

  group('returned values', () {
    Future<Object> search(String result) async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search() { return $result; }',
          allowedHosts: ['example.test'],
        ),
      );
      return plugin
          .search(SearchQuery(keyword: 'x'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    Future<Object> resolve(String result) async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function resolveStream() { return $result; }',
          capabilities: ['resolveStream'],
          allowedHosts: ['example.test'],
        ),
      );
      return plugin
          .resolveStream(StreamRequest(sourceId: 'a', formats: _formats))
          .then<Object>((result) => result, onError: (Object error) => error);
    }

    test('the plugin cannot claim another source', () async {
      final page = await search(
        "{ items: [{ sourceId: 'a1', sourceTypeId: 'other', title: 'A' }], "
        'hasMore: false }',
      );

      // sourceTypeId 不是插件的欄位：表外的鍵，整個結果不收。
      expect(page, isA<ParseError>());
    });

    test('artwork on an allowed host is kept', () async {
      final page = await search(
        "{ items: [{ sourceId: 'a1', cid: 7, title: 'A', artwork: "
        "[{ url: 'https://img.example.test/a.jpg', width: 320 }] }], "
        'hasMore: true }',
      );

      page as SearchPage;
      final artwork = page.items.single.artwork.single;
      expect(artwork.url, Uri.parse('https://img.example.test/a.jpg'));
      expect(artwork.width, 320);
      expect(page.items.single.cid, 7);
    });

    for (final (description, result) in [
      ('a missing hasMore', '{ items: [] }'),
      ('an unknown field', '{ items: [], hasMore: false, total: 3 }'),
      (
        'a track without a title',
        "{ items: [{ sourceId: 'a1' }], hasMore: false }",
      ),
      (
        'a source id with a colon',
        "{ items: [{ sourceId: 'a:1', title: 'A' }], hasMore: false }",
      ),
      (
        'a fractional duration',
        "{ items: [{ sourceId: 'a1', title: 'A', durationMs: 1.5 }], "
            'hasMore: false }',
      ),
      (
        'artwork on another host',
        "{ items: [{ sourceId: 'a1', title: 'A', artwork: "
            "[{ url: 'https://evil.test/a.jpg' }] }], hasMore: false }",
      ),
      ('undefined', 'undefined'),
      ('a string', "'a track'"),
    ]) {
      test('search rejects $description as ParseError', () async {
        expect(await search(result), isA<ParseError>());
      });
    }

    test('a stream on an allowed host keeps its fields', () async {
      final candidates = await resolve(
        "{ candidates: [{ url: 'https://cdn.example.test/a.m4a', "
        "headers: { Referer: 'https://example.test/' }, container: 'mp4', "
        "codec: 'aac', bitrate: 192000, expiresAt: 1790000000000 }] }",
      );

      candidates as StreamResult;
      final candidate = candidates.candidates.single;
      expect(candidate.headers, {'Referer': 'https://example.test/'});
      expect(
        candidate.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true),
      );
      // previewOnly 是選填，沒給就不是試聽。
      expect(candidates.previewOnly, isFalse);
    });

    test('a preview-only result says so', () async {
      for (final (value, expected) in [
        ('true', true),
        ('false', false),
        ('null', false),
      ]) {
        final result = await resolve(
          "{ candidates: [{ url: 'https://cdn.example.test/a.m4a' }], "
          'previewOnly: $value }',
        );

        expect(
          result,
          isA<StreamResult>().having(
            (r) => r.previewOnly,
            'previewOnly',
            expected,
          ),
          reason: value,
        );
      }
    });

    for (final (description, result) in [
      ('no candidates', '{ candidates: [] }'),
      (
        'a previewOnly that is not a boolean',
        "{ candidates: [{ url: 'https://example.test/a' }], previewOnly: 1 }",
      ),
      ('an http stream', "{ candidates: [{ url: 'http://example.test/a' }] }"),
      (
        'a stream on another host',
        "{ candidates: [{ url: 'https://evil.test/a' }] }",
      ),
      ('a file stream', "{ candidates: [{ url: 'file:///etc/passwd' }] }"),
      (
        'an asset URL with a host',
        "{ candidates: [{ url: 'asset://evil.test/a.wav' }] }",
      ),
      (
        'an expiry DateTime cannot hold',
        "{ candidates: [{ url: 'https://example.test/a', "
            'expiresAt: 9000000000000000 }] }',
      ),
      (
        'headers that are not strings',
        "{ candidates: [{ url: 'https://example.test/a', headers: { a: 1 } }] }",
      ),
    ]) {
      test('resolveStream rejects $description as ParseError', () async {
        expect(await resolve(result), isA<ParseError>());
      });
    }
  });

  group('inputs', () {
    test('what the host sends is checked before the call', () {
      expect(() => SearchQuery(keyword: ' '), throwsArgumentError);
      expect(() => SearchQuery(keyword: 'a', page: 0), throwsRangeError);
      expect(
        () => StreamRequest(sourceId: 'a:1', formats: _formats),
        throwsArgumentError,
      );
      expect(
        () => StreamRequest(sourceId: 'a', formats: const []),
        throwsArgumentError,
      );
    });

    test('the plugin receives the documented JSON', () async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search(query) { return { items: [{ sourceId: '
          "'q', title: JSON.stringify(query) }], hasMore: false }; }\n"
          'export function resolveStream(request) { return { candidates: '
          "[{ url: 'https://example.test/' + encodeURIComponent("
          'JSON.stringify(request)) }] }; }',
          capabilities: ['search', 'resolveStream'],
        ),
      );

      final page = await plugin.search(SearchQuery(keyword: 'k', page: 3));
      final stream = await plugin.resolveStream(
        StreamRequest(sourceId: 'bv1', cid: 9, formats: _formats),
      );

      expect(page.items.single.title, '{"keyword":"k","page":3}');
      expect(
        Uri.decodeComponent(stream.candidates.single.url.pathSegments.single),
        '{"sourceId":"bv1","cid":9,"purpose":"playback",'
        '"formats":[{"container":"mp4","codec":"aac"}]}',
      );
    });
  });

  group('login exports', () {
    const qr = '{"methods": ["qr"]}';
    const qrExports =
        'export function loginQrStart() {}\n'
        'export function loginQrPoll() {}\n';
    const verify = 'export function loginVerify() {}\n';
    const search = 'export function search() {}\n';

    Future<void> refused(String body, {String? login = qr}) => expectLater(
      PluginHarness().load(
        pluginSource(
          body,
          capabilities: ['search', if (login != null) 'login'],
          login: login,
        ),
      ),
      throwsA(isA<Unsupported>()),
    );

    test(
      'the login capability needs loginVerify, not a login export',
      () async {
        final plugin = await PluginHarness().load(
          pluginSource(
            '$search$qrExports$verify',
            capabilities: ['search', 'login'],
            login: qr,
          ),
        );

        expect(plugin.manifest.login, isNotNull);
        await refused('$search$qrExports');
        await refused('$search${qrExports}export function login() {}\n');
      },
    );

    test('qr needs loginQrStart and loginQrPoll', () async {
      await refused('$search${verify}export function loginQrStart() {}\n');
      await refused('$search${verify}export function loginQrPoll() {}\n');
    });

    test('refresh needs loginRefresh', () async {
      const refreshing = '{"methods": ["cookie"], "refresh": "onStartup"}';
      final plugin = await PluginHarness().load(
        pluginSource(
          '$search${verify}export function loginRefresh() {}\n',
          capabilities: ['search', 'login'],
          login: refreshing,
        ),
      );

      expect(plugin.manifest.login!.refresh, isNotNull);
      await refused('$search$verify', login: refreshing);
    });

    test('a login export that is not declared is refused', () async {
      await refused('$search$verify', login: null);
      // methods 沒有 qr 卻匯出 QR 的函式；沒宣告 refresh 卻匯出 loginRefresh。
      await refused(
        '$search$verify$qrExports',
        login: '{"methods": ["cookie"]}',
      );
      await refused(
        '$search$qrExports${verify}export function loginRefresh() {}\n',
      );
    });
  });

  group('login', () {
    const qrSource = '''
export function search() { return { items: [], hasMore: false }; }
export function loginQrStart() { return { qrText: 'https://example.test/qr?k=1', token: 'T1' }; }
export function loginQrPoll(token) {
  return token === 'T1'
    ? { status: 'done', credentials: { cookies: { SESSDATA: 'FAKE_SESSDATA_123' } } }
    : { status: 'expired' };
}
export function loginVerify(credentials) {
  return {
    userId: '42',
    displayName: credentials.cookies.SESSDATA === 'FAKE_SESSDATA_123' ? 'Tester' : 'Other',
    avatar: [{ url: 'https://example.test/face.jpg', width: 96 }],
  };
}
''';

    Future<ScriptSourcePlugin> load(
      String body, {
      PluginHarness? harness,
      String login = '{"methods": ["qr"]}',
    }) => (harness ?? PluginHarness()).load(
      pluginSource(body, capabilities: ['search', 'login'], login: login),
    );

    test('runs the QR exports and decodes what they return', () async {
      final plugin = await load(qrSource);

      final code = await plugin.loginQrStart();
      final done = await plugin.loginQrPoll(code.token);
      final expired = await plugin.loginQrPoll('T2');
      final account = await plugin.loginVerify(done.credentials!);

      expect(code.qrText, 'https://example.test/qr?k=1');
      expect(done.status, LoginQrStatus.done);
      expect(done.credentials!.cookies, {'SESSDATA': 'FAKE_SESSDATA_123'});
      expect(expired.status, LoginQrStatus.expired);
      expect(expired.credentials, isNull);
      expect(account.userId, '42');
      expect(account.displayName, 'Tester');
      expect(
        account.avatar.single.url,
        Uri.parse('https://example.test/face.jpg'),
      );
    });

    test('a method that is not declared is Unsupported', () async {
      final plugin = await load(
        'export function search() {}\nexport function loginVerify() {}\n',
        login: '{"methods": ["cookie"]}',
      );

      expect(plugin.loginQrStart, throwsA(isA<Unsupported>()));
      expect(
        () => plugin.loginRefresh(const LoginCredentials(cookies: {})),
        throwsA(isA<Unsupported>()),
      );
    });

    for (final (description, poll) in [
      ('done without credentials', "{ status: 'done' }"),
      (
        'credentials before done',
        "{ status: 'waiting', credentials: { cookies: {} } }",
      ),
      ('an unknown status', "{ status: 'confirmed' }"),
    ]) {
      test('a poll with $description is a ParseError', () async {
        final plugin = await load(
          qrSource.replaceFirst(
            RegExp(r'export function loginQrPoll[\s\S]*?\n}\n'),
            'export function loginQrPoll() { return $poll; }\n',
          ),
        );

        await expectLater(plugin.loginQrPoll('T1'), throwsA(isA<ParseError>()));
      });
    }

    test('an avatar outside the allowed hosts is a ParseError', () async {
      final plugin = await load(
        qrSource.replaceFirst(
          'https://example.test/face.jpg',
          'https://evil.test/face.jpg',
        ),
      );

      await expectLater(
        plugin.loginVerify(const LoginCredentials(cookies: {})),
        throwsA(isA<ParseError>()),
      );
    });

    test('loginVerify registers the credentials first and keeps them when it '
        'fails', () async {
      final harness = PluginHarness();
      final plugin = await load(
        "export function search() {}\n"
        "export function loginQrStart() {}\nexport function loginQrPoll() {}\n"
        "export function loginVerify(c) {\n"
        "  fmp.log.info('verifying ' + c.cookies.SESSDATA);\n"
        "  throw { fmpError: 'CredentialInvalid', message: 'bad ' + c.cookies.SESSDATA };\n"
        "}\n",
        harness: harness,
      );

      await expectLater(
        plugin.loginVerify(
          const LoginCredentials(
            cookies: {'SESSDATA': 'FAKE_SESSDATA_123', 'short': '5'},
          ),
        ),
        throwsA(isA<CredentialInvalid>()),
      );

      // 插件自己的 log 已經遮掉；失敗之後仍登記著。短值不登記（也不讓呼叫失敗）。
      expect(
        harness.records('plugin-a').single.message,
        isNot(contains('FAKE_SESSDATA_123')),
      );
      expect(
        harness.redactor.redact('x FAKE_SESSDATA_123'),
        isNot(contains('FAKE_SESSDATA_123')),
      );
    });

    test('loginRefresh gives new credentials, registered, or null', () async {
      final harness = PluginHarness();
      final plugin = await load(
        'export function search() {}\nexport function loginVerify() {}\n'
        'export function loginRefresh(c) {\n'
        "  return c.cookies.SESSDATA === 'FAKE_OLD_SESSDATA'\n"
        "    ? { cookies: { SESSDATA: 'FAKE_NEW_SESSDATA' }, extra: { refresh_token: 'FAKE_NEW_REFRESH' } }\n"
        '    : null;\n'
        '}\n',
        harness: harness,
        login: '{"methods": ["cookie"], "refresh": "onStartup"}',
      );

      final refreshed = await plugin.loginRefresh(
        const LoginCredentials(cookies: {'SESSDATA': 'FAKE_OLD_SESSDATA'}),
      );
      final unchanged = await plugin.loginRefresh(
        const LoginCredentials(cookies: {'SESSDATA': 'FAKE_OTHER_SESSDATA'}),
      );

      expect(refreshed!.cookies, {'SESSDATA': 'FAKE_NEW_SESSDATA'});
      expect(refreshed.extra, {'refresh_token': 'FAKE_NEW_REFRESH'});
      expect(unchanged, isNull);
      for (final value in [
        'FAKE_OLD_SESSDATA',
        'FAKE_OTHER_SESSDATA',
        'FAKE_NEW_SESSDATA',
        'FAKE_NEW_REFRESH',
      ]) {
        expect(harness.redactor.redact(value), isNot(value), reason: value);
      }
    });

    test('responses during a login export do not go into the cookie jar, '
        'later ones do', () async {
      final harness = PluginHarness(
        handler: (options) => switch (options.uri.path) {
          '/login' => reply(
            200,
            headers: {'Set-Cookie': 'SESSDATA=FAKE_SESSDATA_123; Path=/'},
          ),
          '/anon' => reply(
            200,
            headers: {'Set-Cookie': 'buvid3=FAKE_BUVID_456; Path=/'},
          ),
          _ => reply(200, body: '{"items": [], "hasMore": false}'),
        },
      );
      final plugin = await load('''
export async function search({ keyword }) {
  const response = await fmp.http.request({ url: 'https://example.test/' + keyword });
  return JSON.parse(response.body.startsWith('{') ? response.body : '{"items": [], "hasMore": false}');
}
export async function loginQrStart() {
  await fmp.http.request({ url: 'https://example.test/login' });
  return { qrText: 'x', token: 't' };
}
export async function loginQrPoll() {
  const response = await fmp.http.request({ url: 'https://example.test/login' });
  const header = response.headers['set-cookie'][0];
  const value = header.substring('SESSDATA='.length, header.indexOf(';'));
  return { status: 'done', credentials: { cookies: { SESSDATA: value } } };
}
export async function loginVerify() {
  await fmp.http.request({ url: 'https://example.test/login' });
  return { userId: '1', displayName: 'Tester' };
}
''', harness: harness);
      String? cookie() =>
          harness.adapter.requests.last.headers['cookie'] as String?;

      await plugin.loginQrStart();
      final poll = await plugin.loginQrPoll('t');
      await plugin.loginVerify(poll.credentials!);
      await plugin.search(SearchQuery(keyword: 'check'));

      // 插件讀得到回應的 set-cookie，但 jar 裡沒有它。
      expect(poll.credentials!.cookies, {'SESSDATA': 'FAKE_SESSDATA_123'});
      expect(cookie(), isNull);

      await plugin.search(SearchQuery(keyword: 'anon'));
      await plugin.search(SearchQuery(keyword: 'check'));

      expect(cookie(), 'buvid3=FAKE_BUVID_456');
    });
  });
}
