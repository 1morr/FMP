import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/source_plugin.dart';

const _tag = 'credentials';

final accountGuardProvider = Provider<AccountGuard>((ref) {
  final guard = AccountGuard(
    credentials: ref.watch(credentialStoreProvider),
    log: ref.watch(logProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});

/// 憑證被音源拒絕後轉成「已失效」的事件，每次從 `active` 轉過去發一次（外殼以它
/// 提示一次，ADR 0013 §決定 5）。
final accountInvalidationsProvider = StreamProvider<AccountInvalidated>(
  (ref) => ref.watch(accountGuardProvider).invalidations,
);

/// 一個插件的憑證轉成「已失效」。沒有定義 `==`：同一個插件失效、重新登入、再失效時，
/// 兩次事件在 provider 眼中不是同一個值，才都會通知。
final class AccountInvalidated {
  AccountInvalidated(this.pluginId);

  final String pluginId;
}

/// 一次刷新的結果（[AccountGuard.refresh]）。
enum RefreshOutcome {
  /// 拿到新憑證，已寫入。
  refreshed,

  /// 沒有新的憑證（`loginRefresh` 回 `null`），啟動刷新用。
  unchanged,

  /// 憑證被拒而且換不到新的：已標 `invalidated`。
  invalidated,
}

/// 插件呼叫層的失效處理（ADR 0029 §決定 7，design §6.5）：判定「憑證無效」在插件
/// 內，插件丟 [CredentialInvalid] 時由這裡刷新並重跑原呼叫一次。
///
/// - 同一插件同時只有一個刷新在跑（共用 `Future`）；呼叫開始時帶的憑證和現在的不同
///   ＝已經被別的呼叫刷新過，直接重跑。
/// - 插件宣告 `refresh`：`loginRefresh` 拿到新憑證就寫入並重跑一次（重跑的呼叫讀到
///   新憑證）；回 `null` 或丟 [CredentialInvalid] 就標 `invalidated`。沒宣告 `refresh`
///   直接標 `invalidated`。重跑又被拒也標 `invalidated`，不再重跑。
/// - 刷新時的網路錯誤、限流等不是憑證的問題：不標失效，丟出刷新的錯誤。
/// - 只有 [CredentialInvalid] 觸發這一切；呼叫當時沒有可用憑證時也不處理（沒帶憑證
///   的請求不可能是憑證失效）。
final class AccountGuard {
  AccountGuard({required this._credentials, required this._log});

  final CredentialStore _credentials;
  final Log _log;

  final _refreshing = <String, Future<RefreshOutcome>>{};
  final _invalidations = StreamController<AccountInvalidated>.broadcast(
    sync: true,
  );

  /// 每次轉成 `invalidated` 時發出。
  Stream<AccountInvalidated> get invalidations => _invalidations.stream;

  /// 執行 [call]（對 [plugin] 的一次能力呼叫）。宣告 `login` 以外的插件不經過任何
  /// 處理。
  Future<T> run<T>(SourcePlugin plugin, Future<T> Function() call) async {
    final pluginId = plugin.manifest.id;
    if (plugin.manifest.login == null) return call();
    final before = await _credentials.activeCredentials(pluginId);
    try {
      return await call();
    } on CredentialInvalid {
      final now = await _credentials.activeCredentials(pluginId);
      // 呼叫沒帶憑證，或帳號在等的期間登出、已被標失效：沒有東西可以刷新。
      if (before == null || now == null) rethrow;
      if (now == before) {
        final outcome = await refresh(plugin, rejected: true);
        if (outcome != RefreshOutcome.refreshed) {
          rethrow;
        }
      }
      try {
        return await call();
      } on CredentialInvalid {
        await _invalidate(pluginId, RefreshResult.failed);
        rethrow;
      }
    }
  }

  /// 刷新 [plugin] 的憑證（同一插件單飛）。[rejected] 為真是憑證剛被音源拒絕（`null`
  /// 也是失效）；為假是啟動刷新（`null` 是 `unchanged`）。
  ///
  /// 沒有可用憑證時回 [RefreshOutcome.unchanged]、什麼都不記。刷新丟出 [CredentialInvalid]
  /// 以外的錯誤時記 `failed`、不標失效，並丟出那個錯誤。
  Future<RefreshOutcome> refresh(
    SourcePlugin plugin, {
    required bool rejected,
  }) {
    final pluginId = plugin.manifest.id;
    final running = _refreshing[pluginId];
    if (running != null) return running;
    final started = _refresh(plugin, rejected: rejected);
    _refreshing[pluginId] = started;
    unawaited(
      started.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_refreshing[pluginId], started)) {
          _refreshing.remove(pluginId);
        }
      }),
    );
    return started;
  }

  Future<RefreshOutcome> _refresh(
    SourcePlugin plugin, {
    required bool rejected,
  }) async {
    final pluginId = plugin.manifest.id;
    final current = await _credentials.activeCredentials(pluginId);
    if (current == null) return RefreshOutcome.unchanged;
    if (plugin.manifest.login?.refresh == null) {
      // 不支援刷新：被拒就是失效；啟動刷新不會走到（只對宣告的插件跑）。
      if (rejected) {
        await _invalidate(pluginId, RefreshResult.failed);
        return RefreshOutcome.invalidated;
      }
      return RefreshOutcome.unchanged;
    }
    final LoginCredentials? refreshed;
    try {
      refreshed = await plugin.loginRefresh(current);
    } on CredentialInvalid {
      await _invalidate(pluginId, RefreshResult.failed);
      return RefreshOutcome.invalidated;
    } on AppError catch (error) {
      _log.report('Failed to refresh the credentials', error, tag: _tag);
      await _credentials.recordRefresh(pluginId, RefreshResult.failed);
      rethrow;
    }
    if (refreshed == null) {
      if (rejected) {
        await _invalidate(pluginId, RefreshResult.failed);
        return RefreshOutcome.invalidated;
      }
      await _credentials.recordRefresh(pluginId, RefreshResult.unchanged);
      return RefreshOutcome.unchanged;
    }
    await _credentials.replace(pluginId, refreshed);
    _log.info(
      'Credentials refreshed',
      tag: _tag,
      fields: {'pluginId': pluginId},
    );
    return RefreshOutcome.refreshed;
  }

  Future<void> _invalidate(String pluginId, RefreshResult result) async {
    if (!await _credentials.invalidate(pluginId, result: result)) return;
    _log.warning(
      'Credentials were rejected; marked invalidated',
      tag: _tag,
      fields: {'pluginId': pluginId},
    );
    if (!_invalidations.isClosed) {
      _invalidations.add(AccountInvalidated(pluginId));
    }
  }

  void dispose() => unawaited(_invalidations.close());
}
