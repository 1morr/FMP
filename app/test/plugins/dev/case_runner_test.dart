import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/dev/case_runner.dart';
import 'package:fmp/plugins/dev/plugin_folder.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import '../plugin_harness.dart' show pluginSource;
import 'dev_support.dart';

// 隔離環境與錄製（M4 PR 12，design §12）：帶憑證錄製與 `mutates`。這個插件沒有
// libraryRead，所以這裡以程式把 search 案例標成 `requiresLogin`。重播的假憑證
// （PR 13）也在這裡。憑證與帳號都是假值。

const _cookie = 'FAKE_LIBRARY_SESSION_0001';
const _credentials = LoginCredentials(cookies: {'LIB_SESSION': _cookie});

const _searchChecks =
    '{"search": {"input": {"keyword": "road", "page": 1}, "expect": '
    '{"minItems": 1, "nonEmpty": ["sourceId", "title"]}}}';

/// `search` 帶登入身分請求（`userPreference`）；`loginRefresh` 會打 /refresh。
const _script = '''
export async function search({ keyword }) {
  const response = await fmp.http.request({
    url: 'https://example.test/library?q=' + encodeURIComponent(keyword),
    auth: 'userPreference',
  });
  if (response.status === 401) throw { fmpError: 'CredentialInvalid' };
  const json = JSON.parse(response.body);
  return {
    items: json.list.map((item) => ({
      sourceId: item.id,
      title: item.title,
      uploader: json.owner,
    })),
    hasMore: false,
  };
}
export async function loginVerify(credentials) {
  return { userId: '1', displayName: 'verified' };
}
export async function loginRefresh(credentials) {
  await fmp.http.request({ url: 'https://example.test/refresh', auth: 'never' });
  return { cookies: { LIB_SESSION: 'FAKE_ROTATED_SESSION_0002' } };
}
''';

PluginCheck _flag(
  PluginCheck check, {
  bool requiresLogin = true,
  bool mutates = false,
}) => PluginCheck(
  check.capability,
  check.input,
  check.expectation,
  requiresLogin: requiresLogin,
  mutates: mutates,
);

Directory _pluginDirectory() {
  final directory = tempFolder();
  File(p.join(directory.path, 'library.js')).writeAsStringSync(
    pluginSource(
      _script,
      id: 'library-test',
      capabilities: ['search', 'login'],
      login: '{"methods": ["cookie"], "refresh": "onStartup"}',
    ),
  );
  File(p.join(directory.path, 'checks.json')).writeAsStringSync(_searchChecks);
  return directory;
}

/// 上游的回應：自己的顯示名稱在 `owner`，歌單標題是 [title]。
ResponseBody _library(RequestOptions options, {String title = 'Road trip'}) =>
    reply(
      200,
      body: jsonEncode({
        'owner': 'FAKE_Reader',
        'list': [
          {'id': 'p1', 'title': title},
        ],
      }),
      headers: {'Content-Type': 'application/json'},
    );

const _account = LoginAccount(userId: '98765432', displayName: 'FAKE_Reader');

void main() {
  late Directory directory;
  late PluginFolder folder;
  late FakeHttpAdapter upstream;
  late Redactor redactor;
  late Log log;
  late ResponseBody Function(RequestOptions) handler;

  setUp(() {
    directory = _pluginDirectory();
    folder = PluginFolder.read(directory);
    expect(folder.problems, isEmpty);
    handler = _library;
    upstream = FakeHttpAdapter((options) => handler(options));
    redactor = Redactor();
    log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
  });

  PluginCheck check({bool requiresLogin = true, bool mutates = false}) => _flag(
    folder.checks.single,
    requiresLogin: requiresLogin,
    mutates: mutates,
  );

  CaseTransports transports() =>
      CaseTransports(network: () => upstream, now: () => DateTime.utc(2026));

  Future<CaseRun> run(
    PluginCheck check,
    CaseTransport transport, {
    LoginCredentials? credentials = _credentials,
  }) => runIsolatedCase(
    file: folder.file!,
    check: check,
    transport: transport,
    log: log,
    redactor: redactor,
    reportTag: 'test',
    credentials: credentials,
  );

  /// 網路紀錄的 `credentials` 欄位，依請求順序。
  List<Object?> credentialsLogged() => [
    for (final record in log.history)
      if (record.tag == 'network') record.fields['credentials'],
  ];

  String? cookieOf(RequestOptions options) =>
      options.headers['cookie'] as String?;

  group('the isolated environment', () {
    for (final mode in ['real', 'record']) {
      test('carries the stored credentials in $mode mode for a requiresLogin '
          'case', () async {
        final transport = mode == 'real'
            ? transports().real()
            : transports().record(redactor);

        final result = await run(check(), transport);

        expect(result.matched, isTrue, reason: '${result.problems}');
        expect(cookieOf(upstream.requests.single), contains(_cookie));
        expect(credentialsLogged(), [true]);
        // 憑證不進 log、結果與問題。
        final shown = [
          for (final record in log.history) record.toJsonLine(),
          ...result.problems,
        ].join(' | ');
        expect(shown, isNot(contains(_cookie)));
      });

      // 變異：不標 requiresLogin 的案例，同樣的憑證不放進去（閘門是 requiresLogin）。
      test('does not carry them in $mode mode when the case does not require '
          'a login', () async {
        final transport = mode == 'real'
            ? transports().real()
            : transports().record(redactor);

        await run(check(requiresLogin: false), transport);

        expect(cookieOf(upstream.requests.single), isNull);
        expect(credentialsLogged(), [false]);
      });
    }

    test('never carries them in replay mode', () async {
      final transport = transports().replay(
        const [],
        redactor,
        AllowedHosts(folder.manifest.allowedHosts),
      );

      final result = await run(check(), transport);

      // fixture 是空的：請求比對不到（案例失敗）；重點是請求沒帶憑證。
      expect(result.matched, isFalse);
      expect(credentialsLogged(), everyElement(isFalse));
      expect(upstream.requests, isEmpty);
      expect(
        [for (final record in log.history) record.toJsonLine()].join(),
        isNot(contains(_cookie)),
      );
    });

    test(
      'does not inject for a login case (it takes them as the input)',
      () async {
        final login = PluginCheck(
          PluginCapability.login,
          _credentials,
          folder.checks.single.expectation,
          requiresLogin: true,
        );

        await run(login, transports().real());

        // loginVerify 不發請求；憑證存放是空的，沒有東西被放進去。
        expect(upstream.requests, isEmpty);
      },
    );

    test(
      'a rejected credential fails the case; nothing is refreshed',
      () async {
        handler = (options) => reply(401);

        final result = await run(check(), transports().real());

        expect(result.error?.typeName, 'CredentialInvalid');
        // 刷新會換掉音源端的 token，新 token 只活在這個案例的記憶體。
        expect(
          upstream.requests.where((r) => r.uri.path == '/refresh'),
          isEmpty,
        );
        expect(upstream.requests, hasLength(1));
      },
    );

    test('a mutates case is never run against the network', () async {
      for (final transport in [
        transports().real(),
        transports().record(redactor),
      ]) {
        await expectLater(
          run(check(mutates: true), transport),
          throwsStateError,
        );
      }
      expect(upstream.requests, isEmpty);
    });

    test('a mutates case replays', () async {
      final transport = transports().replay(
        const [],
        redactor,
        AllowedHosts(folder.manifest.allowedHosts),
      );

      final result = await run(check(mutates: true), transport);

      // 插件載入了、也被呼叫（請求比對不到 fixture，所以案例沒過）。
      expect(result.loaded, isTrue);
      expect(result.problems, isNotEmpty);
    });
  });

  // 重播的假憑證（design 的 PR 12 → PR 13 後續）：`requiresLogin` 的非 login 案例在重播時，
  // 隔離環境放 checks.json 的 login 案例的假憑證（fixtureCredentials）；真實的 credentials
  // 永遠不進重播。閘門：下面各條，加上 contract_runner_test.dart 的 libraryRead 案例。
  group('replay credentials', () {
    const fixtureCookie = 'FAKE_FIXTURE_SESSION_0001';
    const fixtureCredentials = LoginCredentials(
      cookies: {'LIB_SESSION': fixtureCookie},
    );

    List<NamedFixture> fixtures() => [
      (
        name: '001.json',
        fixture: HttpFixture(
          request: const FixtureRequest(
            method: 'GET',
            url: 'https://example.test/library?q=road',
          ),
          response: const FixtureResponse(
            status: 200,
            jsonBody: {
              'owner': 'FAKE_Reader',
              'list': [
                {'id': 'p1', 'title': 'Road trip'},
              ],
            },
            headers: {
              'content-type': ['application/json'],
            },
          ),
        ),
      ),
    ];

    CaseTransport replay() => transports().replay(
      fixtures(),
      redactor,
      AllowedHosts(folder.manifest.allowedHosts),
    );

    Future<CaseRun> replayRun(
      PluginCheck check, {
      LoginCredentials? credentials,
      LoginCredentials? fixtureCredentials,
    }) => runIsolatedCase(
      file: folder.file!,
      check: check,
      transport: replay(),
      log: log,
      redactor: redactor,
      reportTag: 'test',
      credentials: credentials,
      fixtureCredentials: fixtureCredentials,
    );

    test('a requiresLogin case replays with the fake credentials', () async {
      final result = await replayRun(
        check(),
        fixtureCredentials: fixtureCredentials,
      );

      expect(result.matched, isTrue, reason: '${result.problems}');
      expect(credentialsLogged(), [true]);
      // 重播不連網；假憑證也不進 log。
      expect(upstream.requests, isEmpty);
      expect(
        [for (final record in log.history) record.toJsonLine()].join(),
        isNot(contains(fixtureCookie)),
      );
    });

    // 變異：沒有假憑證（checks.json 沒有 login 案例）就什麼也不放。
    test('without fake credentials the request is anonymous', () async {
      final result = await replayRun(check());

      expect(result.matched, isTrue, reason: '${result.problems}');
      expect(credentialsLogged(), [false]);
    });

    test('the real stored credentials never reach a replay', () async {
      final result = await replayRun(check(), credentials: _credentials);

      expect(credentialsLogged(), [false]);
      expect(result.matched, isTrue, reason: '${result.problems}');
      expect(
        [for (final record in log.history) record.toJsonLine()].join(),
        isNot(contains(_cookie)),
      );
    });

    // 閘門是 requiresLogin：不標的案例，同樣的假憑證不放進去。
    test('a case that does not require a login gets none', () async {
      await replayRun(
        check(requiresLogin: false),
        fixtureCredentials: fixtureCredentials,
      );

      expect(credentialsLogged(), [false]);
    });

    test('the fake credentials are ignored on a network transport', () async {
      await runIsolatedCase(
        file: folder.file!,
        check: check(),
        transport: transports().real(),
        log: log,
        redactor: redactor,
        reportTag: 'test',
        fixtureCredentials: fixtureCredentials,
      );

      expect(cookieOf(upstream.requests.single), isNull);
      expect(credentialsLogged(), [false]);
    });

    test('fixtureCredentialsOf takes the input of the login case', () {
      final search = folder.checks.single;
      final login = PluginCheck(
        PluginCapability.login,
        fixtureCredentials,
        search.expectation,
        requiresLogin: true,
      );

      expect(fixtureCredentialsOf([search, login]), same(fixtureCredentials));
      expect(fixtureCredentialsOf([login, search]), same(fixtureCredentials));
      // 沒有 login 案例就沒有（其他案例的輸入不是憑證）。
      expect(fixtureCredentialsOf([search]), isNull);
      expect(fixtureCredentialsOf(const []), isNull);
    });
  });

  group('recordCase', () {
    Future<RecordResult> record(
      PluginCheck check, {
      LoginAccount? account = _account,
      LoginCredentials? credentials = _credentials,
    }) => recordCase(
      folder,
      check,
      transport: transports().record(redactor),
      log: log,
      redactor: redactor,
      reportTag: 'test',
      credentials: credentials,
      account: account,
      wait: noWait,
    );

    File? written() {
      final fixtures = Directory(p.join(directory.path, 'fixtures'));
      return fixtures.existsSync()
          ? fixtures.listSync(recursive: true).whereType<File>().firstOrNull
          : null;
    }

    test('skips a mutates case without calling the plugin', () async {
      final result = await record(check(mutates: true));

      expect(result.skipped, 'search: mutates the remote');
      expect(result.run, isNull);
      expect(upstream.requests, isEmpty);
      expect(written(), isNull);
    });

    // 控制組：同一個案例沒有 mutates 就會送出請求並寫檔。
    test('the same case without mutates records', () async {
      final result = await record(check());

      expect(result.skipped, isNull);
      expect(upstream.requests, hasLength(1));
      expect(result.written, 1);
    });

    test('scrubs the account from the traffic before writing', () async {
      final result = await record(check());

      expect(result.problems, isEmpty);
      final text = written()!.readAsStringSync();
      // 自己的顯示名稱換掉；歌單標題與憑證照 Redactor 的規則留著／遮掉。
      expect(text, isNot(contains('FAKE_Reader')));
      expect(text, contains('Road trip'));
      expect(text, isNot(contains(_cookie)));
      final body =
          ((jsonDecode(text) as Map)['response'] as Map)['jsonBody'] as Map;
      expect(body['owner'], '***');
    });

    // 變異：沒有 requiresLogin 的案例不換值（換值是帶憑證錄製的一部分）。
    test('does not scrub a case that does not require a login', () async {
      await record(check(requiresLogin: false), credentials: null);

      expect(written()!.readAsStringSync(), contains('FAKE_Reader'));
    });

    test('an unrelated field does not block the write', () async {
      handler = (options) => _library(options, title: 'Night drive');

      final result = await record(check());

      expect(result.written, 1);
      expect(written()!.readAsStringSync(), contains('Night drive'));
    });

    test(
      'writes nothing when the account is still visible after scrubbing',
      () async {
        // 回應的狀態碼不換值（scrubAccount 不動 status），accountLeaks 仍認得：
        // userId `200` 就是這樣一個換不掉的殘留。
        final result = await record(
          check(),
          account: const LoginAccount(
            userId: '200',
            displayName: 'FAKE_Reader',
          ),
        );

        expect(result.written, isNull);
        expect(
          result.problems,
          contains(
            contains(
              "fixtures not written: the recorded traffic still contains the "
              "account's userId after scrubbing",
            ),
          ),
        );
        expect(written(), isNull);
      },
    );

    test('writes nothing without a stored account to scrub with', () async {
      final result = await record(check(), account: null);

      expect(result.written, isNull);
      expect(result.problems, contains(contains('no stored account')));
      expect(upstream.requests, isEmpty);
      expect(written(), isNull);
    });

    test('is skipped when not logged in, sending nothing', () async {
      final result = await record(check(), credentials: null);

      expect(result.skipped, 'search: requires a login');
      expect(upstream.requests, isEmpty);
    });
  });
}
