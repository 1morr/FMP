import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/plugin_registry.dart';

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    credentials: ref.watch(credentialStoreProvider),
    accounts: ref.watch(accountRepositoryProvider),
    settings: ref.watch(sourceSettingsRepositoryProvider),
    clearCookies: ref.watch(sourceHttpClientFactoryProvider).clearCookies,
  ),
);

/// 帳號的寫入面（ADR 0029 §決定 11、design §6.6）。登入流程在 M3 的下一個 PR 加進來。
final class AccountService {
  AccountService({
    required this._credentials,
    required this._accounts,
    required this._settings,
    required this._clearCookies,
  });

  final CredentialStore _credentials;
  final AccountRepository _accounts;
  final SourceSettingsRepository _settings;
  final Future<void> Function(String pluginId) _clearCookies;

  /// 登出 [pluginId]：憑證（含遮蔽登記）→ 帳號列 → 該插件的記憶體 cookie jar。
  /// `source_settings` 保留。每一步都可重複；中途失敗就停在那一步並丟出錯誤，
  /// 憑證先刪所以之後的請求不會再帶它。
  Future<void> logout(String pluginId) async {
    await _credentials.delete(pluginId);
    await _accounts.remove(pluginId);
    await _clearCookies(pluginId);
  }

  /// 移除插件時的帳號面：[logout] 加上刪 `source_settings`（design §7.4）。
  Future<void> removePlugin(String pluginId) async {
    await logout(pluginId);
    await _settings.remove(pluginId);
  }
}
