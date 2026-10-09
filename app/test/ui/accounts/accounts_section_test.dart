import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/accounts/web_login.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:fmp/ui/accounts/accounts_state.dart';
import 'package:fmp/ui/accounts/cookie_login_dialog.dart';
import 'package:fmp/ui/accounts/qr_login_dialog.dart';
import 'package:fmp/ui/accounts/web_login_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../plugins/plugin_harness.dart';
import '../../support/fake_login_webview.dart';
import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

Finder _button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.bySubtype<ButtonStyleButton>(),
);

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

/// [name] 那張卡裡的 [finder]。
Finder _inCard(String name, Finder finder) =>
    find.descendant(of: _card(name), matching: finder);

/// 會發一個失敗請求的 QR 登入：`loginQrStart` 以 `NetworkError` 失敗。
final _offlineQr = pluginSource(
  '''
export function search() {}
export function loginQrStart() { throw { fmpError: 'NetworkError' }; }
export function loginQrPoll() {}
export function loginVerify() {}
''',
  id: 'plugin-o',
  capabilities: ['search', 'login'],
  login: '{"methods": ["qr"]}',
);

const _pageText = 'https://accounts.example.test/login';
final _page = Uri.parse(_pageText);
final _site = Uri.parse('https://www.example.test');

/// 網頁登入與貼上 cookie 的插件：登入頁在 accounts 那一台，完成看 www 那一台的 `SID`；
/// `loginVerify` 認任何帶 `SID` 的 cookie。
final _webPlugin = pluginSource(
  '''
export function search() {}
export function loginVerify(credentials) {
  if (!credentials.cookies.SID) throw { fmpError: 'CredentialInvalid' };
  return { userId: 'web-user', displayName: 'Web User' };
}
''',
  id: 'plugin-w',
  capabilities: ['search', 'login'],
  login:
      '{"methods": ["webView", "cookie"], "webView": {"url": "$_pageText", '
      '"cookieHosts": ["https://www.example.test"], "doneCookies": ["SID"]}}',
);

/// `loginVerify` 一律以 `CredentialInvalid` 拒絕的插件：三種登入方式都有（QR 第一次輪詢就
/// `done`），看登入時被拒的訊息（不是「登入已失效」）。
final _rejectingPlugin = pluginSource(
  '''
export function search() {}
export function loginQrStart() { return { qrText: 'fmp-test://reject', token: 't' }; }
export function loginQrPoll() {
  return { status: 'done', credentials: { cookies: { SID: 'FAKE_QR_SID_123' } } };
}
export function loginVerify() { throw { fmpError: 'CredentialInvalid' }; }
''',
  id: 'plugin-r',
  capabilities: ['search', 'login'],
  login:
      '{"methods": ["qr", "webView", "cookie"], "webView": {"url": "$_pageText", '
      '"cookieHosts": ["https://www.example.test"], "doneCookies": ["SID"]}}',
);

/// 已登入 [pluginId]（[status]）。憑證的存取排在 CredentialStore 在假時間 zone 建好的鏈上：
/// 在這個 zone 呼叫、pump 讓它跑完（見 PluginPageHarness.create）。
Future<void> _signIn(
  WidgetTester tester,
  PluginPageHarness h,
  String pluginId, {
  AccountStatus status = AccountStatus.active,
  DateTime? lastRefreshAt,
  RefreshResult? lastRefreshResult,
}) async {
  var saved = false;
  unawaited(
    h.plugins.credentials
        .save(
          Account(
            pluginId: pluginId,
            userId: 'u',
            displayName: 'Someone',
            status: status,
            loggedInAt: DateTime.utc(2026, 10, 9),
            lastRefreshAt: lastRefreshAt,
            lastRefreshResult: lastRefreshResult,
          ),
          const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_123'}),
        )
        .then((_) => saved = true),
  );
  await tester.pump();
  expect(saved, isTrue);
}

/// 以 [size] 的視窗開外殼、到設定頁的「帳號」（寬版是第一組，窄版點進去）。
Future<void> _openAccounts(
  WidgetTester tester,
  PluginPageHarness h, {
  Size size = const Size(1000, 800),
}) async {
  await h.shell.pumpShell(tester, size: size, collapsePanel: true);
  await tester.tap(find.text('Settings').first);
  await h.settle(tester);
  if (size.width < 600) {
    await tester.tap(find.widgetWithText(ListTile, 'Accounts'));
    await h.settle(tester);
  }
  expect(find.byType(AccountsSection), findsOneWidget);
}

void main() {
  testWidgets('without a plugin that declares login: an empty state that '
      'leads to the plugin page', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(
      () => h.install(pluginScript('plugin-a', name: 'Alpha')),
    );
    await _openAccounts(tester, h);

    expect(find.text('No sources to sign in to'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(_button('Go to plugins'));
    await h.settle(tester);

    expect(find.byType(PluginsPage), findsOneWidget);
    expect(find.byType(AccountsSection), findsNothing);
  });

  testWidgets('one card per enabled plugin that declares login, with the '
      'methods this platform can do', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() async {
      await h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
          },
        ),
      );
      // 這個平台沒有登入 WebView：只有貼上 cookie。
      await h.install(
        pluginScript(
          'plugin-b',
          name: 'Beta',
          login: {
            'methods': ['webView', 'cookie'],
            'webView': {
              'url': 'https://example.test/login',
              'cookieHosts': ['https://example.test'],
              'doneCookies': ['SID'],
            },
          },
        ),
      );
      await h.install(
        pluginScript(
          'plugin-c',
          name: 'Gamma',
          login: {
            'methods': ['cookie', 'qr'],
          },
        ),
      );
      await h.install(
        pluginScript(
          'plugin-d',
          name: 'Delta',
          login: {
            'methods': ['qr'],
          },
        ),
        enabled: false,
      );
      await h.install(pluginScript('plugin-e', name: 'Epsilon'));
    });
    await _openAccounts(tester, h);

    expect(find.byType(Card), findsNWidgets(3));
    expect(_inCard('Alpha', _button('Sign in with QR code')), findsOneWidget);
    expect(
      _inCard('Alpha', find.bySubtype<ButtonStyleButton>()),
      findsOneWidget,
    );
    // 依 LoginMethod 的順序：QR、網頁、cookie。
    expect(
      _inCard('Gamma', find.bySubtype<ButtonStyleButton>()),
      findsNWidgets(2),
    );
    final qr = tester.getTopLeft(
      _inCard('Gamma', _button('Sign in with QR code')),
    );
    final paste = tester.getTopLeft(_inCard('Gamma', _button('Paste cookies')));
    expect(
      qr.dy < paste.dy || (qr.dy == paste.dy && qr.dx < paste.dx),
      isTrue,
      reason: 'QR $qr comes before paste $paste',
    );
    expect(_inCard('Beta', _button('Paste cookies')), findsOneWidget);
    expect(_inCard('Beta', _button('Sign in on the web')), findsNothing);
    expect(
      find.textContaining("isn't available on this platform"),
      findsNothing,
    );
    for (final name in ['Alpha', 'Beta', 'Gamma']) {
      expect(_inCard(name, find.text('Not signed in')), findsOneWidget);
    }
    expect(find.text('Delta'), findsNothing, reason: 'disabled');
    expect(find.text('Epsilon'), findsNothing, reason: 'no login');
  });

  testWidgets('without secure storage nothing can be signed in to', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester, secureStorage: false);
    await tester.runAsync(
      () => h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
          },
        ),
      ),
    );
    await _openAccounts(tester, h);

    expect(_button('Sign in with QR code'), findsNothing);
    expect(
      find.text("Signing in to Alpha isn't available on this platform yet"),
      findsOneWidget,
    );
  });

  test('availableLoginMethods: the web view needs the platform, nothing '
      'without secure storage', () {
    PlatformCapabilities platform({
      bool secureStorage = true,
      bool loginWebView = true,
    }) => PlatformCapabilities(
      dataDirectory: true,
      singleInstance: false,
      fontFallback: FontFallback.none,
      playback: null,
      networkInterfaces: false,
      cache: null,
      secureStorage: secureStorage,
      files: false,
      loginWebView: loginWebView,
    );
    const all = PluginLogin(
      methods: {LoginMethod.cookie, LoginMethod.webView, LoginMethod.qr},
    );

    expect(availableLoginMethods(all, platform()), [
      LoginMethod.qr,
      LoginMethod.webView,
      LoginMethod.cookie,
    ]);
    expect(availableLoginMethods(all, platform(loginWebView: false)), [
      LoginMethod.qr,
      LoginMethod.cookie,
    ]);
    expect(availableLoginMethods(all, platform(secureStorage: false)), isEmpty);
    expect(
      availableLoginMethods(
        const PluginLogin(methods: {LoginMethod.webView}),
        platform(loginWebView: false),
      ),
      isEmpty,
    );
  });

  testWidgets('a QR login with the test plugin, the switch and signing out', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() => h.install(testPluginFile.readAsStringSync()));
    await _openAccounts(tester, h);
    const name = 'FMP Test Plugin';
    expect(_inCard(name, find.text('Not signed in')), findsOneWidget);

    await tester.tap(_inCard(name, _button('Sign in with QR code')));
    await h.settle(tester);

    expect(find.byType(QrLoginDialog), findsOneWidget);
    expect(find.text('Sign in to $name with a QR code'), findsOneWidget);
    expect(
      find.text('Scan the QR code with the app on your phone'),
      findsOneWidget,
    );
    // QR 碼是一個有名稱的圖片節點。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.image == true &&
            widget.properties.label == 'Sign-in QR code',
      ),
      findsOneWidget,
    );

    // 測試插件第一次輪詢是 waiting，第二次 done（2 秒一次）。
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 2));
      await h.settle(tester);
    }
    await h.settle(tester);
    // 對話框關閉的動畫。
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(QrLoginDialog), findsNothing);
    expect(find.text('Signed in to $name'), findsOneWidget);
    expect(_inCard(name, find.text('FMP Test User')), findsOneWidget);
    expect(_inCard(name, find.text('Active')), findsOneWidget);
    expect(h.plugins.secureStorage.values.keys, ['credentials.fmp-test']);
    final browse = _inCard(name, find.byType(SwitchListTile));
    expect(tester.widget<SwitchListTile>(browse).value, isTrue);
    expect(
      find.text(
        'Many requests while signed in may be treated as automated '
        '(unconfirmed)',
      ),
      findsNothing,
    );

    await tester.tap(browse);
    await h.settle(tester);

    expect(tester.widget<SwitchListTile>(browse).value, isFalse);
    expect(
      await tester.runAsync(
        () =>
            SourceSettingsRepository(h.plugins.database)
                .browseAsLoggedIn('fmp-test'),
      ),
      isFalse,
    );

    // 登出先確認；取消什麼都不動。
    await tester.tap(_inCard(name, _button('Sign out')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of $name?'), findsOneWidget);
    await tester.tap(_button('Cancel'));
    await h.settle(tester);
    expect(h.plugins.secureStorage.values, isNotEmpty);

    await tester.tap(_inCard(name, _button('Sign out')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: _button('Sign out'),
      ),
    );
    await h.settle(tester);

    expect(h.plugins.secureStorage.values, isEmpty);
    expect(_inCard(name, find.text('Not signed in')), findsOneWidget);
    expect(_inCard(name, _button('Sign in with QR code')), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    // 開關的設定保留（ADR 0029 §決定 11）。
    expect(
      await tester.runAsync(
        () =>
            SourceSettingsRepository(h.plugins.database)
                .browseAsLoggedIn('fmp-test'),
      ),
      isFalse,
    );
  });

  testWidgets('closing the QR dialog stops the login', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() => h.install(testPluginFile.readAsStringSync()));
    await _openAccounts(tester, h);

    await tester.tap(_button('Sign in with QR code'));
    await h.settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QrLoginDialog), findsNothing);

    // 之後的輪詢不會發生：第二次輪詢本來會登入。
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 2));
      await h.settle(tester);
    }

    expect(h.plugins.secureStorage.values, isEmpty);
    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('an invalidated account offers to sign in again', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(
      () => h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
            'automationRisk': true,
            'browseAsLoggedInDefault': false,
          },
        ),
      ),
    );
    await _signIn(tester, h, 'plugin-a', status: AccountStatus.invalidated);
    await _openAccounts(tester, h);

    expect(_inCard('Alpha', find.text('Someone')), findsOneWidget);
    expect(_inCard('Alpha', find.text('Expired')), findsOneWidget);
    expect(_inCard('Alpha', _button('Sign in again')), findsOneWidget);
    expect(_inCard('Alpha', _button('Sign out')), findsOneWidget);
    expect(_button('Sign in with QR code'), findsNothing);
    // manifest 的預設（關）與 automationRisk 的說明。
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(
      find.text(
        'Many requests while signed in may be treated as automated '
        '(unconfirmed)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the last refresh only for plugins that refresh', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() async {
      await h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
            'refresh': 'onStartup',
          },
        ),
      );
      await h.install(
        pluginScript(
          'plugin-b',
          name: 'Beta',
          login: {
            'methods': ['qr'],
          },
        ),
      );
    });
    for (final (id, result) in [
      ('plugin-a', RefreshResult.unchanged),
      ('plugin-b', RefreshResult.refreshed),
    ]) {
      await _signIn(
        tester,
        h,
        id,
        lastRefreshAt: DateTime.utc(2026, 10, 9, 8, 30),
        lastRefreshResult: result,
      );
    }
    await _openAccounts(tester, h);

    expect(
      _inCard('Alpha', find.textContaining('Last refreshed: ')),
      findsOneWidget,
    );
    expect(
      _inCard('Alpha', find.textContaining('no change needed')),
      findsOneWidget,
    );
    // 沒宣告 refresh 的插件，就算帳號列有紀錄也不顯示。
    expect(
      _inCard('Beta', find.textContaining('Last refreshed')),
      findsNothing,
    );
  });

  testWidgets('a failed refresh is shown as failed', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(
      () => h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
            'refresh': 'onStartup',
          },
        ),
      ),
    );
    await _signIn(
      tester,
      h,
      'plugin-a',
      lastRefreshAt: DateTime.utc(2026, 10, 9, 8, 30),
      lastRefreshResult: RefreshResult.failed,
    );
    await _openAccounts(tester, h);

    expect(find.textContaining(', failed'), findsOneWidget);
  });

  group('a rejected credential during a user action', () {
    // ADR 0013 §決定 5：憑證無效「刷新失敗才提示一次需重新登入」。守衛的提示（附「登入」）
    // 先發，接著同一個失敗從搜尋或播放以錯誤提示送來：畫面上只能有一則，而且是附「登入」
    // 的那則（錯誤提示會把它換掉，使用者就沒有路去帳號頁）。
    const prompt = 'The sign-in to Test Source is no longer valid';

    /// 外殼的假插件 `fmp-test`，加上 `login`（不能刷新）：守衛只讀 manifest。
    final loginPlugin = _FakePlugin(
      PluginFile.parse(
        pluginScript(
          'fmp-test',
          name: 'Test Source',
          login: {
            'methods': ['qr'],
          },
        ),
      ).manifest,
    );

    Never reject() => throw CredentialInvalid(pluginId: 'fmp-test');

    void expectOnlyThePrompt() {
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(prompt), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Sign in'),
        ),
        findsOneWidget,
      );
    }

    testWidgets('a search shows only the prompt, and still fails inline', (
      tester,
    ) async {
      late final PluginPageHarness h;
      h = await PluginPageHarness.create(
        tester,
        onSearch: (_) => h.plugins.guard.run(loginPlugin, reject),
      );
      await _signIn(tester, h, 'fmp-test');
      await h.shell.pumpShell(tester, collapsePanel: true);

      await tester.enterText(find.byType(TextField), 'x');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expectOnlyThePrompt();
      expect(find.text('Search failed'), findsOneWidget);
    });

    testWidgets('a track that cannot be resolved shows only the prompt', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await _signIn(tester, h, 'fmp-test');
      h.shell.plugin.respond = (_) => h.plugins.guard.run(loginPlugin, reject);
      await h.shell.pumpShell(tester, collapsePanel: true);

      await h.shell.play(tester, [summary('a')]);
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expectOnlyThePrompt();
    });
  });

  testWidgets('a rejected credential prompts with a way to the account '
      'section', (tester) async {
    // 外殼的測試環境只認得它自己的測試音源的名稱。
    final h = await PluginPageHarness.create(
      tester,
      overrides: [pluginNameProvider('plugin-a').overrideWithValue('Alpha')],
    );
    final source = pluginScript(
      'plugin-a',
      name: 'Alpha',
      login: {
        'methods': ['qr'],
      },
    );
    await tester.runAsync(() => h.install(source));
    await _signIn(tester, h, 'plugin-a');
    await h.shell.pumpShell(tester, collapsePanel: true);
    expect(find.byType(AccountsSection), findsNothing);

    // 插件的能力呼叫丟 CredentialInvalid，又不能刷新。
    unawaited(
      h.plugins.guard
          .run<void>(
            _FakePlugin(PluginFile.parse(source).manifest),
            () => throw CredentialInvalid(pluginId: 'plugin-a'),
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
    await h.settle(tester);

    expect(
      find.text('The sign-in to Alpha is no longer valid'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Sign in'));
    await h.settle(tester);
    expect(find.byType(AccountsSection), findsOneWidget);
    expect(_inCard('Alpha', find.text('Expired')), findsOneWidget);
  });

  testWidgets('unreadable credentials say so and can still be signed out', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(
      tester,
      overrides: [
        accountViewProvider('plugin-a').overrideWith(
          (ref) => Stream.value(
            AccountView(
              state: CredentialState.unreadable,
              account: Account(
                pluginId: 'plugin-a',
                userId: 'u',
                displayName: 'Someone',
                status: AccountStatus.active,
                loggedInAt: DateTime.utc(2026, 10, 9),
              ),
              browseAsLoggedIn: null,
            ),
          ),
        ),
      ],
    );
    await tester.runAsync(
      () => h.install(
        pluginScript(
          'plugin-a',
          name: 'Alpha',
          login: {
            'methods': ['qr'],
          },
        ),
      ),
    );
    await _openAccounts(tester, h);

    expect(
      _inCard('Alpha', find.text('Temporarily unreadable, retrying soon')),
      findsOneWidget,
    );
    expect(_inCard('Alpha', _button('Sign out')), findsOneWidget);
    expect(_button('Sign in with QR code'), findsNothing);
    expect(_button('Sign in again'), findsNothing);
  });

  testWidgets('offline: the section works, a login is still sent and a '
      'failure shows the offline state', (tester) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() async {
      await h.install(testPluginFile.readAsStringSync());
      await h.install(_offlineQr);
    });
    await _signIn(tester, h, 'fmp-test');
    await _openAccounts(tester, h);
    await h.shell.setNetwork(tester, NetworkStatus.noInterface);

    // 本機資料照常：已登入的那一列、開關與登出都在。
    expect(_inCard('FMP Test Plugin', find.text('Someone')), findsOneWidget);
    final signIn = _inCard('Plugin plugin-o', _button('Sign in with QR code'));
    expect(tester.widget<ButtonStyleButton>(signIn).onPressed, isNotNull);

    await tester.tap(signIn);
    await h.settle(tester);

    expect(find.byType(QrLoginDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QrLoginDialog),
        matching: find.text('No network connection'),
      ),
      findsOneWidget,
    );
    expect(_button('Retry'), findsOneWidget);
  });

  group('web login', () {
    const name = 'Plugin plugin-w';

    Future<(PluginPageHarness, FakeLoginWebView)> openWebLogin(
      WidgetTester tester,
    ) async {
      final webView = FakeLoginWebView();
      final h = await PluginPageHarness.create(tester, loginWebView: webView);
      await tester.runAsync(() => h.install(_webPlugin));
      await _openAccounts(tester, h);
      expect(_inCard(name, _button('Sign in on the web')), findsOneWidget);
      expect(_inCard(name, _button('Paste cookies')), findsOneWidget);

      await tester.tap(_inCard(name, _button('Sign in on the web')));
      // 先等插件清單；載入中的進度條一直在動，不用 pumpAndSettle。
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WebLoginPage), findsOneWidget);
      expect(find.text('Sign in to $name'), findsOneWidget);
      expect(find.byKey(FakeLoginWebView.key), findsOneWidget);
      expect(webView.built.last.url, _page);
      return (h, webView);
    }

    testWidgets('closes when the site has the done cookies, signs in, and '
        'signing out clears the web view', (tester) async {
      final (h, webView) = await openWebLogin(tester);

      // 登入頁那一台先有同名的 cookie：不算完成。
      webView.setCookies(_page, {'SID': 'FAKE_PAGE_SID_123'});
      webView.loadPage();
      await tester.pump();
      expect(find.byType(WebLoginPage), findsOneWidget);

      webView.setCookies(_site, {'SID': 'FAKE_SITE_SID_123'});
      webView.loadPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(WebLoginPage), findsNothing);
      expect(find.text('Signed in to $name'), findsOneWidget);
      expect(_inCard(name, find.text('Web User')), findsOneWidget);
      expect(h.plugins.secureStorage.values.keys, ['credentials.plugin-w']);

      await tester.tap(_inCard(name, _button('Sign out')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Sign out'),
        ),
      );
      await h.settle(tester);

      expect(h.plugins.secureStorage.values, isEmpty);
      expect(webView.cleared, [
        [_site, _page],
      ]);
    });

    testWidgets('a stuck redirect offers a retry, then a restart', (
      tester,
    ) async {
      final (h, webView) = await openWebLogin(tester);
      webView.setCookies(_page, {'SID': 'FAKE_PAGE_SID_123'});
      webView.loadPage();
      await tester.pump();
      await tester.pump(webLoginStuckAfter);

      expect(find.text("The sign-in didn't finish"), findsOneWidget);
      expect(
        find.textContaining('The page stopped while redirecting'),
        findsOneWidget,
      );
      // WebView 照樣留著。
      expect(find.byKey(FakeLoginWebView.key), findsOneWidget);

      await tester.tap(_button('Retry'));
      await tester.pump();
      expect(find.byKey(FakeLoginWebView.key), findsNothing);
      await tester.pump();
      await tester.pump();
      expect(webView.resets, 1);
      expect(find.byKey(FakeLoginWebView.key), findsOneWidget);
      expect(find.text("The sign-in didn't finish"), findsNothing);

      webView.loadPage();
      await tester.pump();
      await tester.pump(webLoginStuckAfter);
      expect(find.textContaining('Close FMP, open it again'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WebLoginPage), findsNothing);
      expect(h.plugins.secureStorage.values, isEmpty);
      expect(_inCard(name, find.text('Not signed in')), findsOneWidget);
    });
  });

  group('a sign-in the plugin rejects says so, not that it expired', () {
    const name = 'Plugin plugin-r';
    const rejected = "$name didn't accept the sign-in. Try again.";

    Future<(PluginPageHarness, FakeLoginWebView)> open(
      WidgetTester tester,
    ) async {
      final webView = FakeLoginWebView();
      final h = await PluginPageHarness.create(tester, loginWebView: webView);
      await tester.runAsync(() => h.install(_rejectingPlugin));
      await _openAccounts(tester, h);
      return (h, webView);
    }

    testWidgets('QR', (tester) async {
      final (h, _) = await open(tester);
      await tester.tap(_inCard(name, _button('Sign in with QR code')));
      await h.settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await h.settle(tester);
      await h.settle(tester);

      expect(
        find.descendant(
          of: find.byType(QrLoginDialog),
          matching: find.text(rejected),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('expired'), findsNothing);
      expect(h.plugins.secureStorage.values, isEmpty);
    });

    testWidgets('web', (tester) async {
      final (h, webView) = await open(tester);
      await tester.tap(_inCard(name, _button('Sign in on the web')));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      webView.setCookies(_site, {'SID': 'FAKE_SITE_SID_123'});
      webView.loadPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(WebLoginPage), findsNothing);
      expect(find.text(rejected), findsOneWidget);
      expect(find.textContaining('expired'), findsNothing);
      expect(h.plugins.secureStorage.values, isEmpty);
    });
  });

  testWidgets('pasting cookies: unreadable text and a rejected cookie stay in '
      'the dialog, a cookies.txt signs in, nothing reaches the log', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester);
    await tester.runAsync(() => h.install(testPluginFile.readAsStringSync()));
    await _openAccounts(tester, h);
    const name = 'FMP Test Plugin';
    // 這個平台沒有登入 WebView：測試插件也沒有宣告。
    expect(_button('Sign in on the web'), findsNothing);

    await tester.tap(_inCard(name, _button('Paste cookies')));
    await h.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(CookieLoginDialog), findsOneWidget);
    expect(find.text('Paste cookies for $name'), findsOneWidget);
    expect(find.text('How to get them'), findsOneWidget);

    String? errorText() =>
        tester.widget<TextField>(find.byType(TextField)).decoration?.errorText;

    await tester.enterText(find.byType(TextField), 'not a cookie');
    await tester.tap(_button('Sign in'));
    await tester.pump();
    expect(
      errorText(),
      'No cookies found. Paste name=value pairs or the contents of a '
      'cookies.txt file.',
    );

    const wrong = 'other_cookie=FAKE_WRONG_VALUE_123';
    await tester.enterText(find.byType(TextField), wrong);
    await tester.pump();
    expect(errorText(), isNull, reason: 'editing clears the error');
    await tester.tap(_button('Sign in'));
    await h.settle(tester);
    expect(find.byType(CookieLoginDialog), findsOneWidget);
    // 被拒是貼的 cookie 不對，不是「登入已失效」。
    expect(
      errorText(),
      "$name didn't accept these cookies. Copy them again from a page where "
      "you're signed in.",
    );
    expect(find.text(wrong), findsOneWidget, reason: 'the input stays');
    expect(h.plugins.secureStorage.values, isEmpty);

    await tester.enterText(
      find.byType(TextField),
      '# Netscape HTTP Cookie File\n'
      '#HttpOnly_.fmp.test\tTRUE\t/\tTRUE\t0\tfmp_test_session\t'
      'FAKE_PASTED_SESSION_123\n',
    );
    await tester.tap(_button('Sign in'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CookieLoginDialog), findsNothing);
    expect(find.text('Signed in to $name'), findsOneWidget);
    expect(_inCard(name, find.text('FMP Test User')), findsOneWidget);
    expect(h.plugins.secureStorage.values.keys, ['credentials.fmp-test']);
    expect(
      h.plugins.secureStorage.values.values.single,
      contains('FAKE_PASTED_SESSION_123'),
    );

    // 假 cookie 掃描：失敗的那一次有記下來，但兩個值都不在任何一筆裡。外殼的 log 用自己的
    // 遮蔽函式（沒登記這些值），所以有寫進去就會原樣出現。
    final records = [...h.shell.log.history, ...h.plugins.log.history];
    expect(
      records.where((r) => r.message == 'Cookie login failed'),
      hasLength(1),
    );
    for (final record in records) {
      final text =
          '${record.message} ${record.fields} ${record.error} '
          '${record.stackTrace}';
      for (final value in ['FAKE_WRONG_VALUE_123', 'FAKE_PASTED_SESSION_123']) {
        expect(text, isNot(contains(value)), reason: record.message);
      }
    }
  });

  for (final width in [400.0, 1000.0]) {
    testWidgets('$width wide: the last refresh fits', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(
        () => h.install(
          pluginScript(
            'plugin-a',
            name: 'Alpha',
            login: {
              'methods': ['qr'],
              'refresh': 'onStartup',
            },
          ),
        ),
      );
      await _signIn(
        tester,
        h,
        'plugin-a',
        lastRefreshAt: DateTime.utc(2026, 10, 9, 8, 30),
        lastRefreshResult: RefreshResult.refreshed,
      );
      await _openAccounts(tester, h, size: Size(width, 800));

      expect(find.textContaining('Last refreshed: '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$width wide: the section and the QR dialog fit', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(testPluginFile.readAsStringSync()));
      await _openAccounts(tester, h, size: Size(width, 800));

      expect(find.text('FMP Test Plugin'), findsOneWidget);
      await tester.tap(_button('Sign in with QR code'));
      await h.settle(tester);
      expect(find.byType(QrLoginDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

/// 守衛只讀 manifest 的插件。
final class _FakePlugin implements SourcePlugin {
  _FakePlugin(this.manifest);

  @override
  final PluginManifest manifest;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
