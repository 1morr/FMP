import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/accounts/qr_login.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../../support/credentials.dart';
import '../../support/fake_login_webview.dart';
import '../../support/fake_http_adapter.dart';
import '../../support/memory_database.dart';
import '../plugin_harness.dart';

const _sessdata = 'FAKE_SESSDATA_123';
const _credentials = LoginCredentials(cookies: {'SESSDATA': _sessdata});

/// 腳本化的登入插件：每次 `loginQrPoll` 依序回 [polls] 的下一個（用完就一直是最後
/// 一個）；`loginVerify` 回 [verify] 或丟 [verifyError]。記下每次呼叫。
final class _LoginPlugin implements SourcePlugin {
  _LoginPlugin({
    this.polls = const [LoginQrPoll(LoginQrStatus.waiting)],
    this.verify = const LoginAccount(userId: '42', displayName: 'Tester'),
    this.verifyError,
    this.pollError,
  });

  final List<LoginQrPoll> polls;
  final LoginAccount verify;
  final AppError? verifyError;
  final AppError? pollError;

  final calls = <String>[];
  var _codes = 0;

  @override
  final manifest = const PluginManifest(
    id: 'plugin-a',
    name: 'Plugin A',
    version: '1.0.0',
    author: 'FMP tests',
    capabilities: {PluginCapability.search, PluginCapability.login},
    allowedHosts: ['example.test'],
    login: PluginLogin(methods: {LoginMethod.qr}),
  );

  @override
  PluginHealth get health => PluginHealth.ready;

  @override
  Future<void> get whenUnresponsive => Completer<void>().future;

  @override
  Future<LoginQrCode> loginQrStart() async {
    _codes++;
    calls.add('start');
    return LoginQrCode(qrText: 'qr-$_codes', token: 'token-$_codes');
  }

  @override
  Future<LoginQrPoll> loginQrPoll(String token) async {
    calls.add('poll $token');
    if (pollError case final error?) throw error;
    final polled = calls.where((call) => call.startsWith('poll')).length;
    return polls[(polled - 1).clamp(0, polls.length - 1)];
  }

  @override
  Future<LoginAccount> loginVerify(LoginCredentials credentials) async {
    calls.add('verify');
    if (verifyError case final error?) throw error;
    return verify;
  }

  @override
  Future<LoginCredentials?> loginRefresh(LoginCredentials credentials) =>
      throw UnimplementedError('refresh');

  @override
  Future<SearchPage> search(SearchQuery query) =>
      throw UnimplementedError('search');

  @override
  Future<StreamResult> resolveStream(StreamRequest request) =>
      throw UnimplementedError('resolveStream');

  @override
  void close() {}
}

/// 記下寫入時帳號表有沒有那一列：驗證「先憑證、後帳號列」。
final class _OrderedStorage implements SecureStorage {
  _OrderedStorage(this._accounts);

  final AccountRepository _accounts;
  final _inner = InMemorySecureStorage();
  final accountRowsAtWrite = <int>[];

  Map<String, String> get values => _inner.values;

  set writeError(Object? error) => _inner.writeError = error;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    accountRowsAtWrite.add((await _accounts.list()).length);
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

/// 一個 [AccountService] 與它用到的東西（記憶體資料庫）。
final class _Setup {
  _Setup({this.loginWebView}) {
    database = memoryDatabase();
    accounts = AccountRepository(database);
    plugins = PluginRepository(database);
    settings = SourceSettingsRepository(database);
    storage = _OrderedStorage(accounts);
    log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
    credentials = credentialStoreFor(
      database,
      redactor: redactor,
      log: log,
      storage: storage,
    );
    addTearDown(credentials.dispose);
    service = AccountService(
      credentials: credentials,
      accounts: accounts,
      settings: settings,
      clearCookies: (_) async {},
      plugins: plugins,
      loginWebView: loginWebView,
      guard: AccountGuard(credentials: credentials, log: log),
    );
  }

  final FakeLoginWebView? loginWebView;
  final redactor = Redactor();
  late final AppDatabase database;
  late final PluginRepository plugins;
  late final Log log;
  late final AccountRepository accounts;
  late final SourceSettingsRepository settings;
  late final _OrderedStorage storage;
  late final CredentialStore credentials;
  late final AccountService service;

  QrLogin qr(_LoginPlugin plugin) =>
      QrLogin(plugin: plugin, accounts: service, log: log);

  List<LogRecord> reports() => [
    for (final record in log.history)
      if (record.tag == 'accounts') record,
  ];
}

void main() {
  group('login', () {
    test('writes the credentials, then the account row, then registers the '
        'values', () async {
      final setup = _Setup();
      final plugin = _LoginPlugin(
        verify: LoginAccount(
          userId: '42',
          displayName: 'Tester',
          avatar: [Artwork(url: Uri.parse('https://example.test/a.jpg'))],
        ),
      );

      final account = await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 9, 12)),
        () => setup.service.login(plugin, _credentials),
      );

      expect(plugin.calls, ['verify']);
      expect(setup.storage.accountRowsAtWrite, [0]);
      expect(setup.storage.values.keys, ['credentials.plugin-a']);
      expect(await setup.accounts.list(), [account]);
      expect(account.pluginId, 'plugin-a');
      expect(account.userId, '42');
      expect(account.displayName, 'Tester');
      expect(account.status, AccountStatus.active);
      expect(account.loggedInAt, DateTime.utc(2026, 10, 9, 12));
      expect(jsonDecode(account.avatarJson!), [
        {'url': 'https://example.test/a.jpg'},
      ]);
      expect(
        await setup.credentials.activeCredentials('plugin-a'),
        _credentials,
      );
      expect(setup.redactor.redact(_sessdata), isNot(_sessdata));
    });

    test('writes nothing when loginVerify fails', () async {
      final setup = _Setup();
      final plugin = _LoginPlugin(verifyError: CredentialInvalid());

      await expectLater(
        setup.service.login(plugin, _credentials),
        throwsA(isA<CredentialInvalid>()),
      );

      expect(setup.storage.values, isEmpty);
      expect(await setup.accounts.list(), isEmpty);
      expect(await setup.credentials.state('plugin-a'), CredentialState.none);
    });

    test('a write that fails is a failed login, as an AppError', () async {
      final setup = _Setup();
      setup.storage.writeError = StateError('keystore');

      await expectLater(
        setup.service.login(_LoginPlugin(), _credentials),
        throwsA(
          isA<UnexpectedError>().having(
            (e) => e.pluginId,
            'pluginId',
            'plugin-a',
          ),
        ),
      );

      expect(await setup.accounts.list(), isEmpty);
      expect(await setup.credentials.state('plugin-a'), CredentialState.none);
    });
  });

  group('browse as logged in', () {
    test('the switch is stored; unset follows the manifest default', () async {
      final setup = _Setup();

      expect(await setup.credentials.browseAsLoggedIn('plugin-a'), isTrue);
      setup.credentials.setBrowseAsLoggedInDefault('plugin-a', false);
      expect(await setup.credentials.browseAsLoggedIn('plugin-a'), isFalse);

      await setup.service.setBrowseAsLoggedIn('plugin-a', value: true);

      expect(await setup.settings.browseAsLoggedIn('plugin-a'), isTrue);
      expect(await setup.credentials.browseAsLoggedIn('plugin-a'), isTrue);
    });

    test('loading a plugin sets its manifest default', () async {
      final harness = PluginHarness();
      await harness.load(
        pluginSource(
          'export function search() {}\nexport function loginVerify() {}\n',
          capabilities: ['search', 'login'],
          login: '{"methods": ["cookie"], "browseAsLoggedInDefault": false}',
        ),
      );
      await harness.load(
        pluginSource('export function search() {}', id: 'plugin-b'),
      );

      expect(await harness.credentials.browseAsLoggedIn('plugin-a'), isFalse);
      expect(await harness.credentials.browseAsLoggedIn('plugin-b'), isTrue);
    });
  });

  group('QR login', () {
    test('shows the code, follows scanned, and logs in on done', () {
      fakeAsync((async) {
        final setup = _Setup();
        final plugin = _LoginPlugin(
          polls: const [
            LoginQrPoll(LoginQrStatus.waiting),
            LoginQrPoll(LoginQrStatus.scanned),
            LoginQrPoll(LoginQrStatus.done, credentials: _credentials),
          ],
        );
        final login = setup.qr(plugin);

        unawaited(login.start());
        async.flushMicrotasks();
        expect(
          login.value,
          isA<QrLoginShowing>()
              .having((s) => s.qrText, 'qrText', 'qr-1')
              .having((s) => s.scanned, 'scanned', isFalse),
        );

        async.elapse(qrPollInterval);
        expect(login.value, isA<QrLoginShowing>());
        async.elapse(qrPollInterval);
        expect(
          login.value,
          isA<QrLoginShowing>().having((s) => s.scanned, 'scanned', isTrue),
        );
        async.elapse(qrPollInterval);

        expect(login.value, isA<QrLoginDone>());
        expect(plugin.calls, [
          'start',
          'poll token-1',
          'poll token-1',
          'poll token-1',
          'verify',
        ]);
        expect(async.pendingTimers, isEmpty);
        login.dispose();
      });
    });

    test('polls once per interval, one after another', () {
      fakeAsync((async) {
        final plugin = _LoginPlugin();
        final login = _Setup().qr(plugin);

        unawaited(login.start());
        async.elapse(qrPollInterval * 3 + const Duration(milliseconds: 500));

        expect(
          plugin.calls.where((call) => call.startsWith('poll')),
          hasLength(3),
        );
        // 下一次輪詢由一個一次性 Timer 排著，不是週期計時器。
        expect(async.pendingTimers, hasLength(1));
        expect(async.pendingTimers.single.isPeriodic, isFalse);
        login.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('stops at expired and starts over with a new code', () {
      fakeAsync((async) {
        final plugin = _LoginPlugin(
          polls: const [LoginQrPoll(LoginQrStatus.expired)],
        );
        final login = _Setup().qr(plugin);

        unawaited(login.start());
        async.elapse(qrPollInterval * 3);

        expect(
          login.value,
          isA<QrLoginExpired>().having((s) => s.qrText, 'qrText', 'qr-1'),
        );
        expect(plugin.calls, ['start', 'poll token-1']);
        expect(async.pendingTimers, isEmpty);

        unawaited(login.start());
        async.flushMicrotasks();

        expect(
          login.value,
          isA<QrLoginShowing>().having((s) => s.qrText, 'qrText', 'qr-2'),
        );
        async.elapse(qrPollInterval);
        expect(plugin.calls.last, 'poll token-2');
        login.dispose();
      });
    });

    test('leaving the screen stops polling', () {
      fakeAsync((async) {
        final plugin = _LoginPlugin();
        final login = _Setup().qr(plugin);
        unawaited(login.start());
        async.elapse(qrPollInterval);

        login.dispose();
        async.elapse(qrPollInterval * 5);

        expect(plugin.calls, ['start', 'poll token-1']);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a poll that comes back after leaving schedules nothing', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final plugin = _GatedPlugin(gate);
        final login = _Setup().qr(plugin);
        unawaited(login.start());
        async.elapse(qrPollInterval);
        expect(plugin.calls, ['start', 'poll token-1']);

        login.dispose();
        gate.complete();
        async.elapse(qrPollInterval * 3);

        expect(plugin.calls, ['start', 'poll token-1']);
        expect(async.pendingTimers, isEmpty);
      });
    });

    // 使用者在手機上確認之前就關了畫面：還在路上的那一次輪詢即使回 done 也不登入
    // （design §6.4「離開畫面停止輪詢」；已經進到驗證的才照樣寫入）。
    test('a poll that comes back done after leaving logs nothing in', () {
      fakeAsync((async) {
        final setup = _Setup();
        final gate = Completer<void>();
        final plugin = _GatedPlugin(
          gate,
          result: const LoginQrPoll(
            LoginQrStatus.done,
            credentials: _credentials,
          ),
        );
        final login = setup.qr(plugin);
        unawaited(login.start());
        async.elapse(qrPollInterval);

        login.dispose();
        gate.complete();
        async.elapse(qrPollInterval * 3);

        expect(plugin.calls, ['start', 'poll token-1']);
        expect(setup.storage.values, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a failed poll stops and is reported once', () {
      fakeAsync((async) {
        final setup = _Setup();
        final plugin = _LoginPlugin(
          pollError: NetworkError(pluginId: 'plugin-a'),
        );
        final login = setup.qr(plugin);

        unawaited(login.start());
        async.elapse(qrPollInterval * 3);

        expect(
          login.value,
          isA<QrLoginFailed>().having(
            (s) => s.error,
            'error',
            isA<NetworkError>(),
          ),
        );
        expect(plugin.calls, ['start', 'poll token-1']);
        expect(setup.reports(), hasLength(1));
        expect(async.pendingTimers, isEmpty);
        login.dispose();
      });
    });

    test('a verification that fails writes nothing', () {
      fakeAsync((async) {
        final setup = _Setup();
        final plugin = _LoginPlugin(
          polls: const [
            LoginQrPoll(LoginQrStatus.done, credentials: _credentials),
          ],
          verifyError: CredentialInvalid(pluginId: 'plugin-a'),
        );
        final login = setup.qr(plugin);

        unawaited(login.start());
        async.elapse(qrPollInterval);

        expect(login.value, isA<QrLoginFailed>());
        expect(setup.storage.values, isEmpty);
        expect(async.pendingTimers, isEmpty);
        login.dispose();
      });
    });
  });

  // 以真的 login* 流程（QuickJS、宿主的 HTTP client）登入，再確認之後的請求：
  // QR 輪詢回應設的 cookie 沒有落進 jar，`auth: 'never'` 與開關關閉時都不帶憑證
  // （ADR 0012 §決定 2、ADR 0029 §決定 2、4）。測試插件 fmp-test 不發請求，這裡用一個
  // 會發請求的插件。
  test('after a real QR login, never and a switched-off preference carry no '
      'credential cookie', () async {
    var polls = 0;
    final harness = PluginHarness(
      handler: (options) {
        switch (options.uri.path) {
          case '/poll':
            polls++;
            return polls < 2
                ? reply(200, body: '{"status":"waiting"}')
                : reply(
                    200,
                    body: '{"status":"done"}',
                    headers: {'Set-Cookie': 'SESSDATA=$_sessdata; Path=/'},
                  );
          case '/nav':
            final cookie = options.headers['cookie'] as String?;
            return reply(
              200,
              body: cookie == 'SESSDATA=$_sessdata'
                  ? '{"mid":"42","name":"Tester"}'
                  : '{"mid":null}',
            );
          default:
            return reply(200);
        }
      },
    );
    final plugin = await harness.load(
      pluginSource(
        '''
export async function search({ keyword }) {
  await fmp.http.request({
    url: 'https://example.test/search',
    auth: keyword === 'never' ? 'never' : 'userPreference',
  });
  return { items: [], hasMore: false };
}
export function loginQrStart() { return { qrText: 'https://example.test/qr', token: 't' }; }
export async function loginQrPoll() {
  const response = await fmp.http.request({ url: 'https://example.test/poll' });
  const status = JSON.parse(response.body).status;
  if (status !== 'done') return { status };
  const header = response.headers['set-cookie'][0];
  const value = header.substring('SESSDATA='.length, header.indexOf(';'));
  return { status, credentials: { cookies: { SESSDATA: value } } };
}
export async function loginVerify(credentials) {
  const response = await fmp.http.request({
    url: 'https://example.test/nav',
    headers: { Cookie: 'SESSDATA=' + credentials.cookies.SESSDATA },
  });
  const user = JSON.parse(response.body);
  if (!user.mid) throw { fmpError: 'CredentialInvalid' };
  return { userId: user.mid, displayName: user.name };
}
''',
        capabilities: ['search', 'login'],
        login: '{"methods": ["qr"]}',
      ),
    );
    final service = AccountService(
      credentials: harness.credentials,
      accounts: AccountRepository(harness.database),
      settings: SourceSettingsRepository(harness.database),
      clearCookies: harness.httpClients.clearCookies,
      plugins: harness.plugins,
      loginWebView: null,
      guard: harness.guard,
    );
    final login = QrLogin(
      plugin: plugin,
      accounts: service,
      log: harness.log,
      interval: const Duration(milliseconds: 1),
    );
    addTearDown(login.dispose);
    final done = Completer<QrLoginState>();
    login.addListener(() {
      if (login.value case QrLoginDone() || QrLoginFailed()) {
        if (!done.isCompleted) done.complete(login.value);
      }
    });

    unawaited(login.start());

    expect(await done.future, isA<QrLoginDone>());
    expect(await harness.credentials.state('plugin-a'), CredentialState.active);
    String? cookie() =>
        harness.adapter.requests.last.headers['cookie'] as String?;

    await plugin.search(SearchQuery(keyword: 'never'));
    expect(cookie(), isNull, reason: "auth: 'never'");

    await service.setBrowseAsLoggedIn('plugin-a', value: false);
    await plugin.search(SearchQuery(keyword: 'preference'));
    expect(cookie(), isNull, reason: 'the switch is off');

    // 對照：開關開著時才帶。
    await service.setBrowseAsLoggedIn('plugin-a', value: true);
    await plugin.search(SearchQuery(keyword: 'preference'));
    expect(cookie(), 'SESSDATA=$_sessdata');

    for (final record in harness.log.history) {
      expect('${record.message} ${record.fields}', isNot(contains(_sessdata)));
    }
  });

  group('logging out clears the login web view', () {
    final page = Uri.parse('https://accounts.example.test/login');
    final site = Uri.parse('https://www.example.test');
    final other = Uri.parse('https://other.example.test');

    /// 在 `installed_plugins` 放 `plugin-a`；[webView] 時 manifest 宣告網頁登入。
    Future<void> install(_Setup setup, {required bool webView}) =>
        setup.plugins.install(
          InstalledPlugin(
            id: 'plugin-a',
            version: '1.0.0',
            manifestJson: jsonEncode({
              'id': 'plugin-a',
              'name': 'Plugin A',
              'version': '1.0.0',
              'author': 'FMP tests',
              'apiVersion': 1,
              'capabilities': ['search', 'login'],
              'allowedHosts': ['example.test'],
              'login': {
                'methods': [if (webView) 'webView', 'cookie'],
                if (webView)
                  'webView': {
                    'url': '$page',
                    'cookieHosts': ['$site'],
                    'doneCookies': ['SID'],
                  },
              },
            }),
            script: '',
            installedAt: DateTime.utc(2026, 10, 9),
          ),
        );

    FakeLoginWebView signedInWebView() => FakeLoginWebView()
      ..setCookies(site, {'SID': 'FAKE_SITE_SID_123'})
      ..setCookies(page, {'SID': 'FAKE_PAGE_SID_123'})
      ..setCookies(other, {'SID': 'FAKE_OTHER_SID_123'});

    test('the cookie hosts and the sign-in page, after the credentials and '
        'before the account row', () async {
      final webView = signedInWebView()..clearError = StateError('webview');
      final setup = _Setup(loginWebView: webView);
      await install(setup, webView: true);
      await setup.service.login(_LoginPlugin(), _credentials);

      // 停在 WebView 那一步：憑證已經刪了，帳號列還在。
      await expectLater(
        setup.service.logout('plugin-a'),
        throwsA(isA<StateError>()),
      );
      expect(setup.storage.values, isEmpty);
      expect(await setup.accounts.list(), hasLength(1));
      expect(webView.cleared, isEmpty);

      webView.clearError = null;
      await setup.service.logout('plugin-a');
      await setup.service.logout('plugin-a');

      expect(await setup.accounts.list(), isEmpty);
      expect(webView.cleared, [
        [site, page],
        [site, page],
      ]);
      expect(await webView.cookies([site, page]), isEmpty);
      // 別的網址的 cookie 不動。
      expect(await webView.cookies([other]), {'SID': 'FAKE_OTHER_SID_123'});
    });

    test('removing the plugin clears it too', () async {
      final webView = signedInWebView();
      final setup = _Setup(loginWebView: webView);
      await install(setup, webView: true);

      await setup.service.removePlugin('plugin-a');

      expect(webView.cleared, [
        [site, page],
      ]);
    });

    test('nothing to clear without a webView login or without the '
        'platform web view', () async {
      final webView = signedInWebView();
      final withoutLogin = _Setup(loginWebView: webView);
      await install(withoutLogin, webView: false);
      await withoutLogin.service.logout('plugin-a');
      // 已經移除（沒有那一列）也不清。
      await _Setup(loginWebView: webView).service.logout('plugin-a');
      expect(webView.cleared, isEmpty);

      final withoutPlatform = _Setup();
      await install(withoutPlatform, webView: true);
      await withoutPlatform.service.logout('plugin-a');
    });
  });
}

/// `loginQrPoll` 等 [gate] 完成才回 [result]：模擬離開畫面時還在路上的輪詢。
final class _GatedPlugin extends _LoginPlugin {
  _GatedPlugin(
    this.gate, {
    this.result = const LoginQrPoll(LoginQrStatus.waiting),
  });

  final Completer<void> gate;
  final LoginQrPoll result;

  @override
  Future<LoginQrPoll> loginQrPoll(String token) async {
    calls.add('poll $token');
    await gate.future;
    return result;
  }
}
