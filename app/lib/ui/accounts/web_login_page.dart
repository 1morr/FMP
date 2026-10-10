import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/accounts/web_login.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// App 內網頁登入（design §6.4，ADR 0029 §決定 9）：全螢幕頁，上面是標題列（關閉、標題），
/// 下面整塊是登入頁的 WebView。`cookieHosts` 的 `doneCookies` 齊了就自己關閉，回傳讀到的
/// cookie；驗證與寫入由呼叫端做（`AccountService.login`，design §6.4「關頁 → 驗證」）。
/// 使用者關閉是 `null`。
///
/// 用全螢幕頁而不是對話框：登入頁是一般網頁，要整個視窗的寬高（Android 的版面就是手機
/// 網頁）。慣例照 Material 的 full-screen dialog：左上角關閉、沒有確認鈕（完成由頁面判斷）。
Future<LoginCredentials?> showWebLogin(
  BuildContext context, {
  required LoginWebView webView,
  required PluginLoginWebView spec,
  required String name,
}) => Navigator.of(context).push(
  MaterialPageRoute<LoginCredentials>(
    fullscreenDialog: true,
    builder: (_) => WebLoginPage(webView: webView, spec: spec, name: name),
  ),
);

class WebLoginPage extends ConsumerStatefulWidget {
  const WebLoginPage({
    super.key,
    required this.webView,
    required this.spec,
    required this.name,
  });

  final LoginWebView webView;

  /// manifest 的 `login.webView`。
  final PluginLoginWebView spec;

  /// 插件的顯示名稱（manifest 的 `name`）。
  final String name;

  @override
  ConsumerState<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends ConsumerState<WebLoginPage> {
  late final WebLogin _login;

  @override
  void initState() {
    super.initState();
    _login = WebLogin(
      webView: widget.webView,
      spec: widget.spec,
      log: ref.read(logProvider),
    )..addListener(_onChanged);
  }

  void _onChanged() {
    if (_login.value case WebLoginDone(:final credentials) when mounted) {
      Navigator.of(context).pop(credentials);
    }
  }

  @override
  void dispose() {
    _login
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  /// 重試：先讓 WebView 離開畫面（[WebLoginRestarting]），等那一幀畫完、舊的 WebView 拆掉，
  /// 才丟掉它的環境。
  Future<void> _retry() =>
      _login.retry(webViewRemoved: () => WidgetsBinding.instance.endOfFrame);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: a.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(a.webTitle(name: widget.name)),
      ),
      body: ValueListenableBuilder<WebLoginState>(
        valueListenable: _login,
        builder: (context, state, _) {
          final loading = switch (state) {
            WebLoginShowing(loaded: false) || WebLoginRestarting() => true,
            _ => false,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 不在載入時是透明的空條：出現與消失不推動下面的 WebView（同帳號頁）。
              Opacity(
                opacity: loading ? 1 : 0,
                child: LinearProgressIndicator(
                  value: loading ? null : 0,
                  semanticsLabel: a.webLoading,
                ),
              ),
              if (state case WebLoginStuck(:final retried))
                _StuckNote(t: t, retried: retried, onRetry: _retry),
              Expanded(child: _content(t, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _content(Translations t, WebLoginState state) => switch (state) {
    WebLoginFailed() => EmptyState(
      icon: Icons.error_outline,
      title: t.accounts.webFailed,
      action: FilledButton.tonal(
        onPressed: () => unawaited(_retry()),
        child: Text(t.accounts.retry),
      ),
    ),
    WebLoginRestarting() || WebLoginDone() => const SizedBox.shrink(),
    // 卡住時 WebView 照樣留著：使用者看得到頁面停在哪裡。
    WebLoginShowing() || WebLoginStuck() => KeyedSubtree(
      key: ValueKey(_login.attempt),
      child: widget.webView.build(
        LoginWebViewSpec(url: widget.spec.url),
        onLoadStop: () => unawaited(_login.pageLoaded()),
        onError: _login.failed,
      ),
    ),
  };
}

/// 「登入沒有完成」：WebView 上方的警告色條，附「重試」。重試過還是這樣時改請使用者重開
/// App（R1：重開後登入頁那一端的登入狀態還在，再開登入頁就完成）。
class _StuckNote extends StatelessWidget {
  const _StuckNote({
    required this.t,
    required this.retried,
    required this.onRetry,
  });

  final Translations t;
  final bool retried;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final a = t.accounts;
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final colors = tokens.warning;
    final text = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onContainer,
    );
    // 一出現就念給螢幕閱讀器：焦點通常在 WebView 裡。
    return Semantics(
      container: true,
      liveRegion: true,
      child: ColoredBox(
        color: colors.container,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.x4,
            tokens.spacing.x3,
            tokens.spacing.x2,
            tokens.spacing.x1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sync_problem, color: colors.onContainer),
                  SizedBox(width: tokens.spacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.webStuckTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onContainer,
                          ),
                        ),
                        SizedBox(height: tokens.spacing.x1),
                        Text(
                          retried ? a.webStuckRestart : a.webStuckBody,
                          style: text,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onContainer,
                  ),
                  onPressed: () => unawaited(onRetry()),
                  child: Text(a.retry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
