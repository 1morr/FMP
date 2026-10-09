import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:fmp/ui/accounts/accounts_state.dart';
import 'package:fmp/ui/accounts/qr_login_dialog.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../plugins/plugin_harness.dart';
import '../support/plugin_page_harness.dart';

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

/// 已登入 [pluginId]（[status]）。憑證的存取排在 CredentialStore 在假時間 zone 建好的鏈上：
/// 在這個 zone 呼叫、pump 讓它跑完（見 PluginPageHarness.create）。
Future<void> _signIn(
  WidgetTester tester,
  PluginPageHarness h,
  String pluginId, {
  AccountStatus status = AccountStatus.active,
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
      // 網頁登入還沒有平台實作、貼上 cookie 還沒有畫面（M3 PR 9）：沒有按鈕。
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
    expect(_inCard('Gamma', _button('Sign in with QR code')), findsOneWidget);
    expect(
      _inCard('Gamma', find.bySubtype<ButtonStyleButton>()),
      findsOneWidget,
    );
    expect(_inCard('Beta', find.bySubtype<ButtonStyleButton>()), findsNothing);
    expect(
      _inCard(
        'Beta',
        find.text("Signing in to Beta isn't available on this platform yet"),
      ),
      findsOneWidget,
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

  test('availableLoginMethods: QR only for now, nothing without secure '
      'storage', () {
    PlatformCapabilities platform({required bool secureStorage}) =>
        PlatformCapabilities(
          dataDirectory: true,
          singleInstance: false,
          fontFallback: FontFallback.none,
          playback: null,
          networkInterfaces: false,
          cache: null,
          secureStorage: secureStorage,
          files: false,
        );
    const all = PluginLogin(
      methods: {LoginMethod.cookie, LoginMethod.webView, LoginMethod.qr},
    );

    expect(availableLoginMethods(all, platform(secureStorage: true)), [
      LoginMethod.qr,
    ]);
    expect(availableLoginMethods(all, platform(secureStorage: false)), isEmpty);
    expect(
      availableLoginMethods(
        const PluginLogin(methods: {LoginMethod.cookie}),
        platform(secureStorage: true),
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

  for (final width in [400.0, 1000.0]) {
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
