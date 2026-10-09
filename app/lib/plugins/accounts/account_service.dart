import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    credentials: ref.watch(credentialStoreProvider),
    accounts: ref.watch(accountRepositoryProvider),
    settings: ref.watch(sourceSettingsRepositoryProvider),
    clearCookies: ref.watch(sourceHttpClientFactoryProvider).clearCookies,
    plugins: ref.watch(pluginRepositoryProvider),
    loginWebView: ref.watch(loginWebViewProvider),
  ),
);

/// 登出時要清的 WebView 網址：`cookieHosts` 與登入頁 `url`（ADR 0029 §決定 11）。登入頁的
/// 網域（Google 帳號）也有登入狀態，不清的話下次開登入頁就直接登入。
List<Uri> loginWebViewHosts(PluginLoginWebView webView) => [
  ...webView.cookieHosts,
  webView.url,
];

/// 帳號的寫入面（ADR 0029 §決定 6、11，design §6.4、§6.6）：登入、登出、「以登入身分
/// 瀏覽與播放」。
final class AccountService {
  AccountService({
    required this._credentials,
    required this._accounts,
    required this._settings,
    required this._clearCookies,
    required this._plugins,
    required this._loginWebView,
  });

  final CredentialStore _credentials;
  final AccountRepository _accounts;
  final SourceSettingsRepository _settings;
  final Future<void> Function(String pluginId) _clearCookies;

  /// 讀已安裝插件的 manifest（登出時要知道它的 `login.webView`）。
  final PluginRepository _plugins;

  /// 平台的登入 WebView；平台沒有這個能力時為 `null`。
  final LoginWebView? _loginWebView;

  /// 三種登入方式共用的最後一步（ADR 0012 §決定 4）：[plugin] 的 `loginVerify` 通過
  /// 才寫入——先 secure storage、再帳號列（`active`、登入時間）、再登記遮蔽
  /// （`CredentialStore.save`）。驗證丟錯就什麼都不寫、原樣丟出。
  ///
  /// 寫入失敗包成 `AppError` 丟出，當作登入失敗；secure storage 寫好而帳號列沒寫的
  /// 殘留怎麼收尾見 `CredentialStore.save`。
  Future<Account> login(
    SourcePlugin plugin,
    LoginCredentials credentials,
  ) async {
    final pluginId = plugin.manifest.id;
    final verified = await plugin.loginVerify(credentials);
    final account = Account(
      pluginId: pluginId,
      userId: verified.userId,
      displayName: verified.displayName,
      avatarJson: verified.avatar.isEmpty
          ? null
          : jsonEncode([
              for (final image in verified.avatar)
                {'url': image.url.toString(), 'width': ?image.width},
            ]),
      status: AccountStatus.active,
      loggedInAt: clock.now().toUtc(),
    );
    try {
      await _credentials.save(account, credentials);
    } on Object catch (error, stackTrace) {
      throw AppError.wrap(error, stackTrace, pluginId: pluginId);
    }
    return account;
  }

  /// 登出 [pluginId]：憑證（含遮蔽登記）→ WebView 的 cookie → 帳號列 → 該插件的記憶體
  /// cookie jar。`source_settings` 保留。每一步都可重複；中途失敗就停在那一步並丟出錯誤，
  /// 憑證先刪所以之後的請求不會再帶它。
  ///
  /// WebView 那一步只在平台有登入 WebView、而且插件（還在 `installed_plugins`）的 manifest
  /// 宣告 `login.webView` 時做：清 [loginWebViewHosts]。移除插件時也走這裡，順序照
  /// design §7.4（憑證 → WebView → 帳號列）。
  Future<void> logout(String pluginId) async {
    await _credentials.delete(pluginId);
    await _clearWebView(pluginId);
    await _accounts.remove(pluginId);
    await _clearCookies(pluginId);
  }

  Future<void> _clearWebView(String pluginId) async {
    final loginWebView = _loginWebView;
    if (loginWebView == null) return;
    final installed = await _plugins.byId(pluginId);
    if (installed == null) return;
    final webView = PluginManifest.parse(installed.manifestJson).login?.webView;
    if (webView == null) return;
    await loginWebView.clear(loginWebViewHosts(webView));
  }

  /// 移除插件時的帳號面：[logout] 加上刪 `source_settings`（design §7.4）。
  Future<void> removePlugin(String pluginId) async {
    await logout(pluginId);
    await _settings.remove(pluginId);
  }

  /// 「以登入身分瀏覽與播放」（每音源設定，ADR 0012 §決定 6）。之後的請求就照新值，
  /// 認證攔截器每次送出都重讀。
  Future<void> setBrowseAsLoggedIn(String pluginId, {required bool value}) =>
      _settings.setBrowseAsLoggedIn(pluginId, value: value);
}
