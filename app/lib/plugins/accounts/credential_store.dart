import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

const _tag = 'credentials';

/// App 唯一的 [CredentialStore]。第一次讀到就開始載入。
final credentialStoreProvider = Provider<CredentialStore>((ref) {
  final store = CredentialStore(
    storage: ref.watch(secureStorageProvider),
    accounts: ref.watch(accountRepositoryProvider),
    plugins: ref.watch(pluginRepositoryProvider),
    settings: ref.watch(sourceSettingsRepositoryProvider),
    redactor: ref.watch(redactorProvider),
    log: ref.watch(logProvider),
  );
  ref.onDispose(store.dispose);
  return store;
});

/// 讀取失敗後多久重讀一次（design §6.1）。
const credentialRetryDelay = Duration(seconds: 30);

/// 一個插件的憑證現在是什麼狀態。是否登入只看這裡（ADR 0012 §決定 3）。
enum CredentialState {
  /// 沒有憑證。
  none,

  /// 有憑證，可以帶。
  active,

  /// 有憑證但被音源拒絕：保留、停止帶它（ADR 0012 §決定 5）。
  invalidated,

  /// secure storage 讀不出來：不帶、不刪，稍後重讀。只存在記憶體。
  unreadable,
}

/// 唯一的憑證來源（ADR 0012 §決定 3、ADR 0029 §決定 5）：憑證存在平台的 secure
/// storage（鍵 `credentials.<插件 id>`，值是 [LoginCredentials] 的 JSON），帳號的
/// 顯示資訊存 `accounts`，記憶體只放讀進來的狀態，請求只讀記憶體。
///
/// 建立後立刻開始載入（[ready]）：所有查詢都等它完成，所以啟動時的請求不會在
/// 憑證讀進來之前以匿名送出。載入時每個宣告 `login` 的已安裝插件（加上有帳號列的）
/// 讀一次，帳號列與憑證不一致就刪掉多的那一邊（寫入中斷或移除不完整的殘留）。
///
/// 讀取失敗（含內容壞掉）不刪除：該插件為 [CredentialState.unreadable]，
/// [credentialRetryDelay] 後重讀一次。
///
/// 載入與寫入時把每個 cookie 值與 `extra` 值登記到遮蔽函式；短於
/// [Redactor.minimumSecretLength] 的值略過（它們不是秘密，而 `registerSecret`
/// 對它們會拋錯）。
final class CredentialStore implements CredentialSource {
  CredentialStore({
    required this._storage,
    required this._accounts,
    required this._plugins,
    required this._settings,
    required this._redactor,
    required this._log,
  }) {
    ready = _serial(_load);
  }

  final SecureStorage _storage;
  final AccountRepository _accounts;
  final PluginRepository _plugins;
  final SourceSettingsRepository _settings;
  final Redactor _redactor;
  final Log _log;

  /// 載入完成。不會以錯誤結束：載入失敗記一筆 error，之後當作沒有憑證。
  late final Future<void> ready;

  final _entries = <String, _Entry>{};

  /// 插件 manifest 宣告的「以登入身分瀏覽與播放」預設（[setBrowseAsLoggedInDefault]）。
  final _browseDefaults = <String, bool>{};
  final _changes = StreamController<void>.broadcast();

  /// 載入、重讀、[save]、[delete] 依序執行的鏈：重讀從 storage 拿到舊值時若
  /// 中間有登出或重新登入，舊值不能在之後蓋回記憶體（登出後又帶憑證、新憑證的
  /// 遮蔽登記被取消）。
  Future<void> _tail = Future.value();
  Timer? _retry;
  var _disposed = false;

  static String _key(String pluginId) => 'credentials.$pluginId';

  /// 排在 [_tail] 之後執行 [action]；它的錯誤只交給呼叫端，不擋後面的。
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _load() async {
    try {
      final accounts = {
        for (final account in await _accounts.list()) account.pluginId: account,
      };
      final ids = {
        for (final plugin in await _plugins.list())
          if (_declaresLogin(plugin.manifestJson)) plugin.id,
        ...accounts.keys,
      };
      for (final id in ids) {
        await _readSafely(id, accounts[id]);
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'Failed to load the credentials',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    _scheduleRetry();
    _changed();
  }

  /// manifest 宣告了 `login`。解析不了的插件也載入不了，當作沒有。
  static bool _declaresLogin(String manifestJson) {
    try {
      return PluginManifest.parse(manifestJson).login != null;
    } on AppError {
      return false;
    }
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// [_read]，但對齊時的寫入失敗只記錄，不擋住其他插件。
  Future<void> _readSafely(String pluginId, Account? account) async {
    try {
      await _read(pluginId, account);
    } on Object catch (error, stackTrace) {
      _log.error(
        'Failed to align the credentials with the account',
        tag: _tag,
        fields: {'pluginId': pluginId},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 從 secure storage 讀 [pluginId] 的憑證放進記憶體，並對齊帳號列 [account]。
  Future<void> _read(String pluginId, Account? account) async {
    final LoginCredentials? credentials;
    try {
      final raw = await _storage.read(_key(pluginId));
      credentials = raw == null
          ? null
          : LoginCredentials.fromJson(jsonDecode(raw));
    } on Object catch (error, stackTrace) {
      // 不刪：暫時讀不到不代表憑證沒了。內容不印進訊息，只記錯誤型別。
      _entries[pluginId] = const _Entry.unreadable();
      _log.warning(
        'Credentials are unreadable; keeping them and retrying',
        tag: _tag,
        fields: {'pluginId': pluginId, 'errorType': '${error.runtimeType}'},
        stackTrace: stackTrace,
      );
      return;
    }
    if (credentials == null) {
      _forget(pluginId);
      if (account != null) {
        _log.warning(
          'An account has no credentials; removing the account',
          tag: _tag,
          fields: {'pluginId': pluginId},
        );
        await _accounts.remove(pluginId);
      }
      return;
    }
    if (account == null) {
      _forget(pluginId);
      _log.warning(
        'Credentials have no account; removing the credentials',
        tag: _tag,
        fields: {'pluginId': pluginId},
      );
      await _storage.delete(_key(pluginId));
      return;
    }
    _set(pluginId, credentials, account.status);
  }

  void _scheduleRetry() {
    if (_disposed ||
        !_entries.values.any(
          (entry) => entry.state == CredentialState.unreadable,
        )) {
      return;
    }
    _retry?.cancel();
    _retry = Timer(credentialRetryDelay, () => _serial(_reread));
  }

  /// 重讀現在仍是 [CredentialState.unreadable] 的插件（排隊時被登出或重新登入的
  /// 已經不是了）。
  Future<void> _reread() async {
    final unreadable = [
      for (final MapEntry(:key, :value) in _entries.entries)
        if (value.state == CredentialState.unreadable) key,
    ];
    if (unreadable.isEmpty) return;
    try {
      final accounts = {
        for (final account in await _accounts.list()) account.pluginId: account,
      };
      for (final id in unreadable) {
        await _readSafely(id, accounts[id]);
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'Failed to re-read the credentials',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    _changed();
  }

  void _set(
    String pluginId,
    LoginCredentials credentials,
    AccountStatus status,
  ) {
    _forget(pluginId);
    credentials.registerWith(_redactor);
    _entries[pluginId] = _Entry(credentials, status);
  }

  /// 清掉 [pluginId] 在記憶體的狀態並取消遮蔽登記。
  void _forget(String pluginId) {
    _entries.remove(pluginId)?.credentials?.unregisterFrom(_redactor);
  }

  /// 憑證的狀態可能變了（載入、重讀、[save]、[delete] 之後）時發出；畫面以它重讀
  /// [state]。
  Stream<void> get changes => _changes.stream;

  /// [pluginId] 現在的狀態。
  Future<CredentialState> state(String pluginId) async {
    await ready;
    return _entries[pluginId]?.state ?? CredentialState.none;
  }

  /// [pluginId] 可以給插件和請求用的憑證：只有 [CredentialState.active]；沒有、
  /// 讀不到或已失效回 `null`。
  Future<LoginCredentials?> activeCredentials(String pluginId) async {
    await ready;
    final entry = _entries[pluginId];
    return entry?.state == CredentialState.active ? entry!.credentials : null;
  }

  /// 登入成功後寫入（驗證已在呼叫端做完）：先 secure storage、再帳號列。中途
  /// 失敗時記憶體不變（這次執行不帶新憑證）；第一次登入留下的是沒有帳號列的憑證，
  /// 下次載入時對齊刪掉；重新登入（已有帳號列）時舊列留著，下次載入時新憑證配舊列
  /// 的狀態與顯示資訊，再登入一次就蓋掉。丟出寫入的錯誤。
  Future<void> save(Account account, LoginCredentials credentials) =>
      _serial(() async {
        await _storage.write(
          _key(account.pluginId),
          jsonEncode(credentials.toJson()),
        );
        await _accounts.upsert(account);
        _set(account.pluginId, credentials, account.status);
        _changed();
      });

  /// 刷新拿到新憑證：寫入（先 secure storage、再帳號列的最後刷新紀錄 `refreshed`），
  /// 記憶體換成新的；狀態仍是 `active`。沒有帳號列（已登出）時什麼都不做，新憑證
  /// 不能復活登出的帳號。丟出寫入的錯誤，記憶體不變。
  Future<void> replace(String pluginId, LoginCredentials credentials) =>
      _serial(() async {
        final account = await _accounts.byId(pluginId);
        if (account == null) return;
        await _storage.write(_key(pluginId), jsonEncode(credentials.toJson()));
        final updated = account.withRefresh(
          status: AccountStatus.active,
          refreshedAt: clock.now().toUtc(),
          result: RefreshResult.refreshed,
        );
        await _accounts.upsert(updated);
        _set(pluginId, credentials, updated.status);
        _changed();
      });

  /// 記下一次沒有換憑證的刷新（`unchanged`、`failed`）：只寫帳號列。沒有帳號列時
  /// 什麼都不做。
  Future<void> recordRefresh(String pluginId, RefreshResult result) =>
      _serial(() async {
        final account = await _accounts.byId(pluginId);
        if (account == null) return;
        await _accounts.upsert(
          account.withRefresh(refreshedAt: clock.now().toUtc(), result: result),
        );
        _changed();
      });

  /// [pluginId] 的憑證被音源拒絕（ADR 0012 §決定 5）：帳號列標 `invalidated`，記憶體
  /// 的狀態跟著改，憑證保留、之後不帶。回傳這次是不是從 `active` 轉過來的——已經是
  /// 失效、沒有憑證或讀不到時是 `false`，呼叫端據此只提示一次。[result] 是同時記下的
  /// 最後刷新結果。
  Future<bool> invalidate(String pluginId, {RefreshResult? result}) =>
      _serial(() async {
        final entry = _entries[pluginId];
        if (entry == null || entry.state != CredentialState.active) {
          return false;
        }
        final account = await _accounts.byId(pluginId);
        if (account == null) return false;
        await _accounts.upsert(
          account.withRefresh(
            status: AccountStatus.invalidated,
            refreshedAt: result == null ? null : clock.now().toUtc(),
            result: result,
          ),
        );
        _set(pluginId, entry.credentials!, AccountStatus.invalidated);
        _changed();
        return true;
      });

  /// 刪除 [pluginId] 的憑證與遮蔽登記（登出、移除插件）。帳號列由呼叫端刪。沒有
  /// 憑證時什麼都不做；可重複呼叫。
  Future<void> delete(String pluginId) => _serial(() async {
    await _storage.delete(_key(pluginId));
    _forget(pluginId);
    _changed();
  });

  /// [pluginId] 的 manifest 宣告的「以登入身分瀏覽與播放」預設（`login.
  /// browseAsLoggedInDefault`，沒宣告是開）。插件載入時由 `ScriptPluginLoader` 設，
  /// 請求都來自載入了的插件，所以 [browseAsLoggedIn] 讀得到。
  void setBrowseAsLoggedInDefault(String pluginId, bool value) =>
      _browseDefaults[pluginId] = value;

  /// 停止重讀的計時器。
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _retry = null;
    unawaited(_changes.close());
  }

  @override
  Future<CredentialMaterial?> credentialMaterial(String pluginId) async {
    final credentials = await activeCredentials(pluginId);
    return credentials == null
        ? null
        : (cookies: credentials.cookies, headers: const <String, String>{});
  }

  @override
  Future<Set<String>> credentialCookieNames(String pluginId) async {
    await ready;
    return _entries[pluginId]?.credentials?.cookies.keys.toSet() ?? const {};
  }

  /// 沒設定過就是 manifest 宣告的預設（[setBrowseAsLoggedInDefault]，ADR 0012
  /// §決定 6），沒宣告是開。
  @override
  Future<bool> browseAsLoggedIn(String pluginId) async =>
      await _settings.browseAsLoggedIn(pluginId) ??
      _browseDefaults[pluginId] ??
      true;
}

final class _Entry {
  const _Entry(LoginCredentials this.credentials, AccountStatus status)
    : state = status == AccountStatus.active
          ? CredentialState.active
          : CredentialState.invalidated;

  const _Entry.unreadable()
    : credentials = null,
      state = CredentialState.unreadable;

  final LoginCredentials? credentials;
  final CredentialState state;
}
