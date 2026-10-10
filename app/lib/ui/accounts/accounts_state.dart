import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/plugins/plugins_state.dart';

// 帳號頁讀的資料（ADR 0029 §決定 6、8，design §6.7）。插件清單讀資料庫，不讀插件清單
// （`pluginRegistryProvider`）：沒有宣告 `login` 的插件時不必建 `CredentialStore`。

/// 帳號頁的一列：一個宣告 `login` 的已啟用插件。
typedef LoginPlugin = ({String id, PluginManifest manifest, PluginLogin login});

/// 已啟用、宣告 `login` 的插件，依 id 排序（同插件頁）；`installed_plugins` 變動就重算。
final loginPluginsProvider =
    Provider.autoDispose<AsyncValue<List<LoginPlugin>>>(
      (ref) => ref
          .watch(installedPluginsProvider)
          .whenData(
            (installed) => [
              for (final plugin in installed)
                if (plugin.enabled)
                  if (manifestOf(plugin) case final manifest?)
                    if (manifest.login case final login?)
                      (id: plugin.id, manifest: manifest, login: login),
            ],
          ),
    );

/// 一列的帳號狀態。
@immutable
final class AccountView {
  const AccountView({
    required this.state,
    required this.account,
    required this.browseAsLoggedIn,
  });

  /// 是否登入只看它（ADR 0012 §決定 3）。
  final CredentialState state;

  /// 帳號的顯示資訊；[state] 是 `none` 時不看它。
  final Account? account;

  /// 「以登入身分瀏覽與播放」存的值；`null` 是沒設定過（用 manifest 的預設）。
  final bool? browseAsLoggedIn;
}

/// [pluginId] 的帳號狀態；憑證或 `source_settings` 變動就重讀。
final accountViewProvider = StreamProvider.autoDispose
    .family<AccountView, String>((ref, pluginId) async* {
      final credentials = ref.watch(credentialStoreProvider);
      final accounts = ref.watch(accountRepositoryProvider);
      final settings = ref.watch(sourceSettingsRepositoryProvider);
      final changes = StreamController<void>();
      final subscriptions = [
        credentials.changes.listen(changes.add),
        settings.changes().listen(changes.add),
      ];
      ref.onDispose(() {
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
        unawaited(changes.close());
      });
      Future<AccountView> read() async {
        final state = await credentials.state(pluginId);
        Account? account;
        for (final candidate in await accounts.list()) {
          if (candidate.pluginId == pluginId) account = candidate;
        }
        return AccountView(
          state: state,
          account: account,
          browseAsLoggedIn: await settings.browseAsLoggedIn(pluginId),
        );
      }

      yield await read();
      await for (final _ in changes.stream) {
        yield await read();
      }
    });

/// [login] 的方式裡，這個 App 在這個平台做得到的（ADR 0029 §決定 8：「methods ∩
/// 平台有能力」），依 [LoginMethod] 的順序。
///
/// - 沒有 secure storage 就一個都沒有：憑證沒地方放（ADR 0012 §決定 3）。
/// - `qr`、`cookie` 不需要平台能力。
/// - `webView` 要平台層的登入 WebView（`PlatformCapabilities.loginWebView`）。
List<LoginMethod> availableLoginMethods(
  PluginLogin login,
  PlatformCapabilities capabilities,
) => [
  if (capabilities.secureStorage)
    for (final method in LoginMethod.values)
      if (login.methods.contains(method))
        if (switch (method) {
          LoginMethod.qr || LoginMethod.cookie => true,
          LoginMethod.webView => capabilities.loginWebView,
        })
          method,
];

/// 帳號列存的頭像（`Artwork[]` 的 JSON）。沒有或讀不懂就是空的：頭像只是裝飾。
List<TrackArtwork> avatarOf(Account account) {
  final json = account.avatarJson;
  if (json == null) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (decoded is! List<Object?>) return const [];
  return [
    for (final item in decoded)
      if (item case {'url': final String url})
        if (Uri.tryParse(url) case final uri?)
          TrackArtwork(
            url: uri,
            width: switch (item['width']) {
              final int width => width,
              _ => null,
            },
          ),
  ];
}

/// 登入失敗（QR、網頁登入）給使用者看的訊息，[name] 是插件的顯示名稱。登入時的
/// [CredentialInvalid] 是插件不接受這次拿到的憑證（`loginVerify` 拒絕），不是類別表的
/// 「登入已失效，請重新登入」（那是已存的憑證被拒，ADR 0013 §決定 5）；其餘照
/// [errorMessage]。貼上 cookie 的對話框另有指向輸入的說法（`accounts.cookieRejected`）。
String loginErrorMessage(
  Translations t,
  AppError error, {
  required String name,
}) => error is CredentialInvalid
    ? t.accounts.loginRejected(name: name)
    : errorMessage(t, error, sourceName: name);
