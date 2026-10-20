import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/radio/account_live_import.dart';
import 'package:fmp/ui/accounts/account_playlists_page.dart';
import 'package:fmp/ui/accounts/accounts_state.dart';
import 'package:fmp/ui/accounts/cookie_login_dialog.dart';
import 'package:fmp/ui/accounts/qr_login_dialog.dart';
import 'package:fmp/ui/accounts/web_login_page.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_widgets.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

const _tag = 'accounts';

/// 設定頁的「帳號」區塊（design §6.7，ADR 0029 §決定 8）：每個宣告 `login` 的已啟用
/// 插件一張卡（插件頁的卡片樣式；舊版帳號頁也是一個音源一張卡）。
///
/// - 未登入：插件宣告的登入方式裡、這個 App 在這個平台做得到的（[availableLoginMethods]）
///   各一顆按鈕；一個都沒有時寫明「這個平台還不能登入」。
/// - 已登入：頭像、名稱、狀態（正常／已失效／暫時無法讀取）、「以登入身分瀏覽與播放」
///   開關（`automationRisk` 時附說明）、登出（先確認）。已失效時多「重新登入」；狀態正常且插件
///   宣告 `libraryRead` 時多「歌單」，開帳號的歌單頁（[openAccountPlaylists]）。
/// - 卡片右上的「⋯」選單：登入正常、插件宣告 `live` 且實際匯出 `libraryLiveRooms` 時有「從帳號
///   匯入電台」（ADR 0033：條件不成立的項目不出現）；選單沒有項目就不畫「⋯」。
///
/// 都是本機資料，離線照常可用；登入照樣送出，失敗才在登入畫面顯示離線狀態
/// （ADR 0016 §決定 7 的更正）。動作在等資料庫時頂端有進度條、其他動作停用（同插件頁）。
class AccountsSection extends ConsumerStatefulWidget {
  const AccountsSection({super.key, required this.onOpenPlugins});

  /// 沒有可登入的音源時的「前往插件頁」。
  final VoidCallback onOpenPlugins;

  @override
  ConsumerState<AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends ConsumerState<AccountsSection> {
  int _working = 0;

  bool get _busy => _working > 0;

  Future<T> _work<T>(Future<T> Function() body) async {
    setState(() => _working++);
    try {
      return await body();
    } finally {
      if (mounted) setState(() => _working--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(translationsProvider).accounts;
    final spacing = AppTokens.of(context).spacing;
    final capabilities = ref.watch(platformCapabilitiesProvider);
    return switch (ref.watch(loginPluginsProvider)) {
      AsyncData(:final value) when value.isEmpty => EmptyState(
        icon: Icons.account_circle_outlined,
        title: a.none,
        body: a.noneHint,
        action: FilledButton.tonal(
          onPressed: widget.onOpenPlugins,
          child: Text(a.goToPlugins),
        ),
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 不忙時是透明的空條：出現與消失不改變下方的位置（同插件頁）。
          Opacity(
            opacity: _busy ? 1 : 0,
            child: LinearProgressIndicator(
              value: _busy ? null : 0,
              semanticsLabel: a.working,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.all(spacing.x4),
              itemCount: value.length,
              separatorBuilder: (_, _) => SizedBox(height: spacing.x3),
              itemBuilder: (context, i) {
                final plugin = value[i];
                return _AccountCard(
                  key: ValueKey(plugin.id),
                  plugin: plugin,
                  methods: availableLoginMethods(plugin.login, capabilities),
                  busy: _busy,
                  onLogin: (method) => unawaited(_login(plugin, method)),
                  onLogout: () => unawaited(_logout(plugin)),
                  onBrowse: (value) => unawaited(_setBrowse(plugin, value)),
                  onImportLive: () => unawaited(_importLive(plugin)),
                );
              },
            ),
          ),
        ],
      ),
      // 讀本機資料庫失敗：不是網路問題，照一般的失敗顯示。
      AsyncError() => EmptyState(
        icon: Icons.error_outline,
        title: a.loadFailed,
      ),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
    };
  }

  // 下面的動作：要用的東西在第一個 await 之前讀好。對話框開著時視窗跨過斷點，設定頁
  // 會換位置重建這一頁（State 被丟掉），之後就不能再用 `ref`（同插件頁）。

  Translations get _t => ref.read(translationsProvider);

  void _failed(
    AppError error,
    String operation,
    String Function(String reason) sentence,
  ) => ref
      .read(toasterProvider)
      .error(error, operation: operation, tag: _tag, sentence: sentence);

  Future<void> _login(LoginPlugin plugin, LoginMethod method) async {
    final t = _t;
    final toaster = ref.read(toasterProvider);
    final accounts = ref.read(accountServiceProvider);
    final loginWebView = ref.read(loginWebViewProvider);
    final name = plugin.manifest.name;
    final registry = ref.read(pluginRegistryProvider.future);
    String failed(String reason) =>
        t.accounts.loginFailed(name: name, reason: reason);
    // 驗證時被拒（CredentialInvalid）不是「登入已失效」：換成登入的說法
    // （loginErrorMessage）。
    void fail(AppError error) => toaster.error(
      error,
      operation: 'Failed to sign in',
      tag: _tag,
      sentence: error is CredentialInvalid
          ? (_) => t.accounts.loginRejected(name: name)
          : failed,
    );
    final SourcePlugin? source;
    try {
      source = (await registry)[plugin.id];
    } on Object catch (error, stackTrace) {
      if (mounted) fail(AppError.wrap(error, stackTrace, pluginId: plugin.id));
      return;
    }
    if (!mounted) return;
    if (source == null) {
      // 已啟用卻沒載入（載入失敗）：插件頁看得到原因。
      fail(
        UnexpectedError(
          pluginId: plugin.id,
          cause: StateError('The plugin is enabled but not loaded'),
          stackTrace: StackTrace.current,
        ),
      );
      return;
    }
    final Account? account;
    switch (method) {
      case LoginMethod.qr:
        account = await showQrLogin(context, plugin: source, name: name);
      case LoginMethod.cookie:
        account = await showCookieLogin(context, plugin: source, name: name);
      case LoginMethod.webView:
        // availableLoginMethods 只在平台有登入 WebView、manifest 有 webView 時給這一種。
        final credentials = await showWebLogin(
          context,
          webView: loginWebView!,
          spec: plugin.login.webView!,
          name: name,
        );
        if (credentials == null) return;
        // 頁面關了才驗證（design §6.4）。這一頁可能已經換位置重建（State 不在）：照樣
        // 驗證寫入，使用者已經登入了，只是沒有進度條。
        final verified = source;
        Future<Account> verify() => accounts.login(verified, credentials);
        try {
          account = await (mounted ? _work(verify) : verify());
        } on Object catch (error, stackTrace) {
          fail(AppError.wrap(error, stackTrace, pluginId: plugin.id));
          return;
        }
    }
    if (account != null) toaster.success(t.accounts.loggedIn(name: name));
  }

  Future<void> _logout(LoginPlugin plugin) async {
    final t = _t;
    final accounts = ref.read(accountServiceProvider);
    final toaster = ref.read(toasterProvider);
    final name = plugin.manifest.name;
    if (!await _confirmLogout(context, t, name) || !mounted) return;
    try {
      await _work(() => accounts.logout(plugin.id));
      toaster.success(t.accounts.loggedOut(name: name));
    } on Object catch (error, stackTrace) {
      // 每一步都可重複：再按一次登出從頭跑完。
      if (mounted) {
        _failed(
          AppError.wrap(error, stackTrace, pluginId: plugin.id),
          'Failed to sign out',
          (reason) => t.accounts.logoutFailed(name: name, reason: reason),
        );
      }
    }
  }

  Future<void> _importLive(LoginPlugin plugin) async {
    final t = _t;
    final importer = ref.read(accountLiveImporterProvider);
    final toaster = ref.read(toasterProvider);
    try {
      final result = await _work(() => importer.importFromAccount(plugin.id));
      final a = t.accounts;
      toaster.success(switch (result) {
        AccountLiveImport(:final added, :final existing)
            when added > 0 && existing > 0 =>
          a.liveImportBoth(added: added, existing: existing),
        AccountLiveImport(:final added) when added > 0 => a.liveImportAdded(
          added: added,
        ),
        AccountLiveImport(:final existing) when existing > 0 =>
          a.liveImportAllExisting(existing: existing),
        _ => a.liveImportEmpty,
      });
    } on Object catch (error, stackTrace) {
      // 離開這一頁後不再碰 ref；已經寫入的房間留著，再匯入一次算「已在清單」。
      if (mounted) {
        // 離線時原因是離線的說法（ADR 0013，同帳號的歌單頁）。
        final offline = switch (ref.read(networkStatusProvider)) {
          NetworkStatus.noInterface => t.offline.noInterface,
          NetworkStatus.unreachable => t.offline.unreachable,
          NetworkStatus.online => null,
        };
        _failed(
          AppError.wrap(error, stackTrace, pluginId: plugin.id),
          'Failed to import live rooms from the account',
          (reason) => t.accounts.liveImportFailed(reason: offline ?? reason),
        );
      }
    }
  }

  Future<void> _setBrowse(LoginPlugin plugin, bool value) async {
    final t = _t;
    final accounts = ref.read(accountServiceProvider);
    try {
      await _work(() => accounts.setBrowseAsLoggedIn(plugin.id, value: value));
    } on Object catch (error, stackTrace) {
      if (mounted) {
        _failed(
          AppError.wrap(error, stackTrace, pluginId: plugin.id),
          'Failed to save browse as logged in',
          (reason) => t.accounts.settingFailed(reason: reason),
        );
      }
    }
  }
}

/// 登出 [name] 的確認；使用者按了登出才是 `true`。
Future<bool> _confirmLogout(
  BuildContext context,
  Translations t,
  String name,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.accounts.logoutTitle(name: name)),
        content: Text(t.accounts.logoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.accounts.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.accounts.confirmLogout),
          ),
        ],
      ),
    ) ??
    false;

/// 卡片「⋯」選單的項目。
enum _CardAction { importLive }

/// 一個宣告 `login` 的插件。
class _AccountCard extends ConsumerWidget {
  const _AccountCard({
    super.key,
    required this.plugin,
    required this.methods,
    required this.busy,
    required this.onLogin,
    required this.onLogout,
    required this.onBrowse,
    required this.onImportLive,
  });

  final LoginPlugin plugin;

  /// 這個 App 在這個平台做得到的登入方式。
  final List<LoginMethod> methods;
  final bool busy;
  final ValueChanged<LoginMethod> onLogin;
  final VoidCallback onLogout;
  final ValueChanged<bool> onBrowse;
  final VoidCallback onImportLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(translationsProvider).accounts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final name = plugin.manifest.name;
    final view = ref.watch(accountViewProvider(plugin.id));
    final value = view.value;
    final state = value?.state;
    final account = value?.account;
    final loggedIn = state != null && state != CredentialState.none;
    final subtitle = switch (value) {
      null => view.hasError ? a.loadFailed : '',
      _ when !loggedIn => a.notLoggedIn,
      _ => account?.displayName ?? '',
    };
    final tag = switch (state) {
      CredentialState.active => PluginTag(
        text: a.statusActive,
        tone: PluginTagTone.primary,
      ),
      CredentialState.invalidated => PluginTag(
        text: a.statusInvalidated,
        tone: PluginTagTone.error,
      ),
      CredentialState.unreadable => PluginTag(text: a.statusUnreadable),
      CredentialState.none || null => null,
    };
    Widget methodButton(LoginMethod method) => FilledButton.tonalIcon(
      onPressed: busy ? null : () => onLogin(method),
      icon: Icon(switch (method) {
        LoginMethod.qr => Icons.qr_code_2,
        LoginMethod.webView => Icons.language,
        LoginMethod.cookie => Icons.cookie_outlined,
      }),
      label: Text(switch (method) {
        LoginMethod.qr => a.loginQr,
        LoginMethod.webView => a.loginWebView,
        LoginMethod.cookie => a.loginCookie,
      }),
    );
    // 從帳號匯入電台（design §7.4）：登入正常、manifest 允許匯出 `libraryLiveRooms`（同時宣告
    // `libraryRead` 與 `live`，見 `optionalExports`）、插件實際匯出了它。先看前兩個條件，才讀登記簿。
    final canImportLive =
        state == CredentialState.active &&
        plugin.manifest.optionalExports.contains(
          LibraryReadExports.liveRooms,
        ) &&
        (ref
                .watch(pluginRegistryProvider)
                .value?[plugin.id]
                ?.exportsLibraryLiveRooms ??
            false);
    final actions = <Widget>[
      if (state == CredentialState.none) ...methods.map(methodButton),
      // 已失效：只有一種方式時是「重新登入」，幾種時照列每一種。
      if (state == CredentialState.invalidated)
        if (methods.length == 1)
          FilledButton(
            onPressed: busy ? null : () => onLogin(methods.single),
            child: Text(a.relogin),
          )
        else
          ...methods.map(methodButton),
      // 帳號的歌單（design §7.3）：登入正常（不是已失效、暫時讀不到）而且插件宣告 `libraryRead`。
      if (state == CredentialState.active &&
          plugin.manifest.capabilities.contains(PluginCapability.libraryRead))
        FilledButton.tonalIcon(
          onPressed: busy
              ? null
              : () => unawaited(openAccountPlaylists(context, plugin.id)),
          icon: const Icon(Icons.queue_music),
          label: Text(a.playlists),
        ),
      if (loggedIn)
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: busy ? null : onLogout,
          child: Text(a.logout),
        ),
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.x4,
          spacing.x3,
          spacing.x2,
          spacing.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(
                  pluginId: plugin.id,
                  account: loggedIn ? account : null,
                ),
                SizedBox(width: spacing.x3),
                Expanded(
                  child: PluginHeading(
                    name: name,
                    byline: subtitle,
                    description: '',
                    tags: [?tag],
                  ),
                ),
                if (canImportLive)
                  PopupMenuButton<_CardAction>(
                    tooltip: a.more,
                    enabled: !busy,
                    onSelected: (action) => switch (action) {
                      _CardAction.importLive => onImportLive(),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _CardAction.importLive,
                        child: Text(a.liveImport),
                      ),
                    ],
                  ),
              ],
            ),
            if (loggedIn &&
                plugin.login.refresh != null &&
                account?.lastRefreshAt != null)
              Padding(
                padding: EdgeInsets.only(top: spacing.x2, right: spacing.x2),
                child: Text(
                  _lastRefreshText(
                    context,
                    ref.watch(translationsProvider),
                    account!,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (loggedIn)
              Padding(
                padding: EdgeInsets.only(top: spacing.x2, right: spacing.x2),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.browseAsLoggedIn),
                  subtitle: plugin.login.automationRisk
                      ? Text(a.automationRisk)
                      : null,
                  value:
                      value!.browseAsLoggedIn ??
                      plugin.login.browseAsLoggedInDefault,
                  onChanged: busy ? null : onBrowse,
                ),
              ),
            if (state == CredentialState.none && methods.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing.x2, right: spacing.x2),
                child: Text(
                  a.noMethod(name: name),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (actions.isNotEmpty) ...[
              SizedBox(height: spacing.x2),
              Wrap(
                spacing: spacing.x2,
                runSpacing: spacing.x1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「最後刷新：日期 時間，結果」。時間是裝置本地時間，格式跟著介面語言（同歷史頁）。
String _lastRefreshText(BuildContext context, Translations t, Account account) {
  final a = t.accounts;
  final at = account.lastRefreshAt!.toLocal();
  final dates = MaterialLocalizations.of(context);
  final time =
      '${dates.formatMediumDate(at)} '
      '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true)}';
  final result = switch (account.lastRefreshResult) {
    RefreshResult.refreshed => a.refreshRefreshed,
    RefreshResult.unchanged => a.refreshUnchanged,
    RefreshResult.failed || null => a.refreshFailed,
  };
  return a.lastRefresh(time: time, result: result);
}

/// 帳號的頭像；沒登入、沒有頭像或讀不到時是人像圖示。頭像只是裝飾，名稱在旁邊。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.pluginId, required this.account});

  final String pluginId;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    const fallback = CircleAvatar(
      radius: AppLayout.accountAvatar / 2,
      child: Icon(Icons.person_outline),
    );
    final account = this.account;
    if (account == null) return fallback;
    return ClipOval(
      child: ArtworkImage(
        pluginId: pluginId,
        artwork: avatarOf(account),
        size: AppLayout.accountAvatar,
        rounded: false,
        fallback: fallback,
      ),
    );
  }
}
