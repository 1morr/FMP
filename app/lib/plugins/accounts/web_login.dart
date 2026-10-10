import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

/// 登入頁那一端已經登入、`cookieHosts` 卻一直等不到時，多久之後算卡住（design §6.4）。
const webLoginStuckAfter = Duration(seconds: 15);

/// App 內網頁登入走到哪一步（[WebLogin.value]）。
sealed class WebLoginState {
  const WebLoginState();
}

/// WebView 開著，等使用者在頁面上登入。
final class WebLoginShowing extends WebLoginState {
  const WebLoginShowing({required this.loaded});

  /// 至少有一頁載入完成了（之前畫面上是空的）。
  final bool loaded;
}

/// 登入頁那一端已經登入，`cookieHosts` 過了 [webLoginStuckAfter] 還沒齊：頁面停在跳轉中
/// （R1 在 Windows 看到）。[retried] 是重試過了還是這樣：該請使用者重開 App。
final class WebLoginStuck extends WebLoginState {
  const WebLoginStuck({required this.retried});

  final bool retried;
}

/// [WebLogin.retry] 正在重建 WebView 的環境；畫面上不放 WebView。
final class WebLoginRestarting extends WebLoginState {
  const WebLoginRestarting();
}

/// `cookieHosts` 的 `doneCookies` 齊了。[credentials] 是 `cookieHosts` 讀得到的全部 cookie，
/// 交給 `AccountService.login`（`loginVerify` 通過才寫入）。
final class WebLoginDone extends WebLoginState {
  const WebLoginDone(this.credentials);

  final LoginCredentials credentials;
}

/// WebView 準備不起來（已經 `log.report`）；[WebLogin.retry] 重來。
final class WebLoginFailed extends WebLoginState {
  const WebLoginFailed();
}

/// 一次 App 內網頁登入（ADR 0029 §決定 9，design §6.4）。登入畫面持有它、離開時 [dispose]。
///
/// - **完成只看 cookie**：每一頁載入完成（[pageLoaded]）就讀 `cookieHosts` 的 cookie，
///   `doneCookies` 都有值就是 [WebLoginDone]。不看網址：Android 登入後會先插入 Google 的
///   提示頁，最後落在 `m.youtube.com`。也只看 `cookieHosts`：Google 帳號的同名 cookie 在
///   `.google.com`，跳回 YouTube 之前就有了。
/// - **跳轉卡住**：登入頁 `url` 讀得到的 cookie 已經有全部 `doneCookies`（登入頁那一端已經
///   登入，R1 看到的「google.com 已有必要 cookie」）、`cookieHosts` 卻在 [webLoginStuckAfter]
///   內沒齊，就是 [WebLoginStuck]。只看「`url` 有 cookie」會把還在輸入密碼的使用者當成卡住：
///   登入頁一打開就有 cookie。計時器是一次性的 `Timer`，到時再讀一次 cookie 才下結論（卡住時
///   頁面不會再載入完成，不會有下一次 [pageLoaded]）。
/// - cookie 的值不寫進 log：讀取失敗只記錯誤本身。
final class WebLogin extends ValueNotifier<WebLoginState> {
  WebLogin({
    required this._webView,
    required this._spec,
    required this._log,
    this._stuckAfter = webLoginStuckAfter,
  }) : super(const WebLoginShowing(loaded: false));

  final LoginWebView _webView;
  final PluginLoginWebView _spec;
  final Log _log;
  final Duration _stuckAfter;

  Timer? _stuckTimer;

  /// 第幾個 WebView（[retry] 加一）：畫面以它當 key 重建 WebView，舊 WebView 的結果靠它
  /// 認出來丟掉。
  int get attempt => _attempt;
  int _attempt = 0;

  var _retried = false;
  var _disposed = false;

  bool get _finished => value is WebLoginDone;

  /// WebView 的一頁載入完成（`onLoadStop`）。
  Future<void> pageLoaded() async {
    if (_disposed || _finished) return;
    if (value case WebLoginShowing(loaded: false)) {
      value = const WebLoginShowing(loaded: true);
    }
    await _check(_attempt, stuckCheck: false);
  }

  /// WebView 準備不起來（`LoginWebView.build` 的 `onError`）。
  void failed(Object error, StackTrace stackTrace) {
    if (_disposed || _finished) return;
    _log.error(
      'The login web view failed to start',
      tag: 'accounts',
      error: error,
      stackTrace: stackTrace,
    );
    _stuckTimer?.cancel();
    _stuckTimer = null;
    value = const WebLoginFailed();
  }

  /// 丟掉目前的 WebView 與它的環境，重開登入頁（卡住或失敗之後）。先轉成
  /// [WebLoginRestarting]（畫面拿掉 WebView），等 [webViewRemoved]（舊的 WebView 真的拆掉）
  /// 才 `LoginWebView.reset`：環境不能在還有 WebView 用它時丟掉。登入頁那一端的登入狀態
  /// 留著，重開後通常一載入就完成。
  Future<void> retry({required Future<void> Function() webViewRemoved}) async {
    if (_disposed || _finished || value is WebLoginRestarting) return;
    _retried = _retried || value is WebLoginStuck;
    _stuckTimer?.cancel();
    _stuckTimer = null;
    value = const WebLoginRestarting();
    await webViewRemoved();
    if (_disposed) return;
    try {
      await _webView.reset();
    } on Object catch (error, stackTrace) {
      // 重建失敗照樣開新的 WebView：它準備不起來時會走 failed。
      _log.warning(
        'Failed to reset the login web view',
        tag: 'accounts',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (_disposed) return;
    _attempt++;
    value = const WebLoginShowing(loaded: false);
  }

  Future<void> _check(int attempt, {required bool stuckCheck}) async {
    final Map<String, String> cookies;
    try {
      cookies = await _webView.cookies(_spec.cookieHosts);
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to read the login web view cookies',
        tag: 'accounts',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (!_isCurrent(attempt)) return;
    if (_hasDoneCookies(cookies)) {
      _stuckTimer?.cancel();
      _stuckTimer = null;
      value = WebLoginDone(LoginCredentials(cookies: cookies));
      return;
    }
    if (stuckCheck) {
      value = WebLoginStuck(retried: _retried);
      return;
    }
    if (_stuckTimer != null || value is WebLoginStuck) return;
    final Map<String, String> loginPage;
    try {
      loginPage = await _webView.cookies([_spec.url]);
    } on Object {
      // 只影響卡住的提示；上面讀過一次失敗已經記了。
      return;
    }
    if (!_isCurrent(attempt) || _stuckTimer != null) return;
    if (_hasDoneCookies(loginPage)) {
      _stuckTimer = Timer(_stuckAfter, () {
        _stuckTimer = null;
        unawaited(_check(attempt, stuckCheck: true));
      });
    }
  }

  bool _hasDoneCookies(Map<String, String> cookies) =>
      _spec.doneCookies.every((name) => cookies[name]?.isNotEmpty ?? false);

  /// 還在等 [attempt] 那個 WebView 的結果：沒有離開、沒有完成、沒有失敗或正在重建。
  bool _isCurrent(int attempt) =>
      !_disposed &&
      attempt == _attempt &&
      (value is WebLoginShowing || value is WebLoginStuck);

  @override
  void dispose() {
    _disposed = true;
    _stuckTimer?.cancel();
    _stuckTimer = null;
    super.dispose();
  }
}
