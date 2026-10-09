import 'package:flutter/widgets.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';

/// 假的登入 WebView：cookie 以網址的主機名稱存（[setCookies]），讀的時候只回問到的網址那一台
/// 主機的——和真的一樣，別的網域的同名 cookie 讀不到。記下每次 [build]、[clear]、
/// [clearAll]、[reset]。畫面是一塊空白（[key]），以 [loadPage] 模擬一頁載入完成。
final class FakeLoginWebView implements LoginWebView {
  /// [build] 回傳的 widget 的 key。
  static const key = ValueKey('fake-login-web-view');

  /// 主機名稱 → cookie。
  final _cookies = <String, Map<String, String>>{};

  /// 每次 [build] 的頁。
  final built = <LoginWebViewSpec>[];

  /// 每次 [clear] 的網址。
  final cleared = <List<Uri>>[];
  var clearedAll = 0;
  var resets = 0;

  /// 每次 [cookies] 問的網址（看有沒有問別的網域）。
  final asked = <List<Uri>>[];

  /// 非空時 [clear] 拋這個。
  Object? clearError;

  VoidCallback? _onLoadStop;
  void Function(Object error, StackTrace stackTrace)? _onError;

  /// [url] 那台主機讀得到 [cookies]（蓋掉之前的）。
  void setCookies(Uri url, Map<String, String> cookies) =>
      _cookies[url.host] = {...cookies};

  /// 最近一次 [build] 的 WebView 載入完一頁。
  void loadPage() => _onLoadStop!();

  /// 最近一次 [build] 的 WebView 準備不起來。
  void fail(Object error) => _onError!(error, StackTrace.current);

  @override
  Widget build(
    LoginWebViewSpec spec, {
    required VoidCallback onLoadStop,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    built.add(spec);
    _onLoadStop = onLoadStop;
    _onError = onError;
    return const SizedBox.expand(key: key);
  }

  @override
  Future<Map<String, String>> cookies(List<Uri> hosts) async {
    asked.add(hosts);
    final result = <String, String>{};
    for (final host in hosts) {
      for (final MapEntry(:key, :value)
          in (_cookies[host.host] ?? {}).entries) {
        result.putIfAbsent(key, () => value);
      }
    }
    return result;
  }

  @override
  Future<void> clear(List<Uri> hosts) async {
    if (clearError case final error?) throw error;
    cleared.add(hosts);
    for (final host in hosts) {
      _cookies.remove(host.host);
    }
  }

  @override
  Future<void> clearAll() async {
    clearedAll++;
    _cookies.clear();
  }

  @override
  Future<void> reset() async => resets++;
}
