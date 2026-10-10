import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:fmp/platform/login_webview/login_webview.dart';

/// Android 系統 WebView 的 UA 標記（`…Build/xxx; wv) AppleWebKit…`）。
final _webViewMarker = RegExp(r'; ?wv(?=[;)])');

/// Android 登入頁用的 UA：系統 WebView 的 UA 拿掉 `; wv`（也處理沒有空白的 `;wv`），
/// 其他不動（R1：Google 擋嵌入式 WebView 的 `; wv`，也擋桌面 Chrome 的 UA）。
String androidLoginUserAgent(String systemUserAgent) =>
    systemUserAgent.replaceAll(_webViewMarker, '');

/// [LoginWebView] 的實作，Android 與 Windows 共用：`flutter_inappwebview` 6.2.0-beta.3
/// （ADR 0029 §決定 9）。兩個平台的差異從建構子注入：
///
/// - UA：Android 是系統 WebView 的 UA 拿掉 `; wv`（[androidLoginUserAgent]）；Windows
///   不設，用 WebView2 的預設（R1：預設就能登入）。
/// - 環境：Windows 的 WebView2 環境以資料目錄下的 [loginWebViewDirectoryName] 當使用者
///   資料目錄（不給的話 WebView2 用程式旁的 `fmp.exe.WebView2`，dev 與 prod 混在一起）。
///   第一次用到才建立，[reset] 之後重建。Android 沒有環境（WebView 的資料在 App 的私有
///   目錄，dev 與 prod 以 applicationId 分開）。
final class InAppLoginWebView implements LoginWebView {
  InAppLoginWebView({
    required this._userAgent,
    required this._createEnvironment,
    this._cookieManager = _systemCookieManager,
  });

  /// Android 的實作。
  factory InAppLoginWebView.android() => InAppLoginWebView(
    userAgent: () async => androidLoginUserAgent(
      await InAppWebViewController.getDefaultUserAgent(),
    ),
    createEnvironment: null,
  );

  /// Windows 的實作；[userDataFolder] 是 WebView2 的使用者資料目錄。
  factory InAppLoginWebView.windows({
    required Future<String> Function() userDataFolder,
  }) => InAppLoginWebView(
    userAgent: () async => null,
    createEnvironment: () async => WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: await userDataFolder(),
      ),
    ),
  );

  static CookieManager _systemCookieManager(WebViewEnvironment? environment) =>
      CookieManager.instance(webViewEnvironment: environment);

  /// 登入頁的 UA；`null` 是不設（平台預設）。
  final Future<String?> Function() _userAgent;

  /// 建立 WebView2 的環境；`null` 是這個平台沒有環境。
  final Future<WebViewEnvironment> Function()? _createEnvironment;
  final CookieManager Function(WebViewEnvironment? environment) _cookieManager;

  Future<WebViewEnvironment>? _environment;

  /// 目前的環境；沒有就建立。建立失敗時不留下失敗的那一個，下次再試。
  Future<WebViewEnvironment?> _currentEnvironment() async {
    final create = _createEnvironment;
    if (create == null) return null;
    final pending = _environment ??= create();
    try {
      return await pending;
    } on Object {
      if (identical(_environment, pending)) _environment = null;
      rethrow;
    }
  }

  Future<CookieManager> _manager() async =>
      _cookieManager(await _currentEnvironment());

  @override
  Widget build(
    LoginWebViewSpec spec, {
    required VoidCallback onLoadStop,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) => _LoginWebView(
    spec: spec,
    prepare: () async => (
      userAgent: await _userAgent(),
      environment: await _currentEnvironment(),
    ),
    onLoadStop: onLoadStop,
    onError: onError,
  );

  @override
  Future<Map<String, String>> cookies(List<Uri> hosts) async {
    final manager = await _manager();
    final result = <String, String>{};
    for (final host in hosts) {
      for (final cookie in await manager.getCookies(url: WebUri.uri(host))) {
        result.putIfAbsent(cookie.name, () => '${cookie.value ?? ''}');
      }
    }
    return result;
  }

  @override
  Future<void> clearAll() async {
    await (await _manager()).deleteAllCookies();
  }

  @override
  Future<void> reset() async {
    final pending = _environment;
    _environment = null;
    if (pending == null) return;
    final WebViewEnvironment environment;
    try {
      environment = await pending;
    } on Object {
      // 本來就沒建起來：沒有東西要丟。
      return;
    }
    await environment.dispose();
  }
}

typedef _Prepared = ({String? userAgent, WebViewEnvironment? environment});

/// 準備好 UA 與環境之後才建 WebView：兩者都要在建立時給。
class _LoginWebView extends StatefulWidget {
  const _LoginWebView({
    required this.spec,
    required this.prepare,
    required this.onLoadStop,
    required this.onError,
  });

  final LoginWebViewSpec spec;
  final Future<_Prepared> Function() prepare;
  final VoidCallback onLoadStop;
  final void Function(Object error, StackTrace stackTrace) onError;

  @override
  State<_LoginWebView> createState() => _LoginWebViewState();
}

class _LoginWebViewState extends State<_LoginWebView> {
  _Prepared? _prepared;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final _Prepared prepared;
    try {
      prepared = await widget.prepare();
    } on Object catch (error, stackTrace) {
      if (mounted) widget.onError(error, stackTrace);
      return;
    }
    if (mounted) setState(() => _prepared = prepared);
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _prepared;
    if (prepared == null) return const SizedBox.expand();
    return InAppWebView(
      webViewEnvironment: prepared.environment,
      initialUrlRequest: URLRequest(url: WebUri.uri(widget.spec.url)),
      initialSettings: InAppWebViewSettings(userAgent: prepared.userAgent),
      onLoadStop: (_, _) => widget.onLoadStop(),
    );
  }
}
