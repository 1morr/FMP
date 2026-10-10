import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/login_webview/flutter_inappwebview_login.dart';

// 登入 WebView 的平台實作（ADR 0029 §決定 9）：UA 的轉換與 cookie 的讀、清。套件的
// CookieManager 以假的換掉（建構子注入），不碰平台通道；WebView 本身與真正的刪除只能實機驗。

/// 假的 CookieManager：cookie 以網址的主機名稱存，`getCookies` 只回那一台的。
final class _FakeCookieManager implements CookieManager {
  /// 主機名稱 → 那一台讀得到的 cookie。
  final cookies = <String, List<Cookie>>{};
  var deletedAll = 0;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async => [...?cookies[url.host]];

  @override
  Future<bool> deleteAllCookies() async {
    deletedAll++;
    cookies.clear();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _site = Uri.parse('https://www.example.test');
final _page = Uri.parse('https://accounts.example.test/login?continue=x');

InAppLoginWebView _webView(_FakeCookieManager manager) => InAppLoginWebView(
  userAgent: () async => null,
  createEnvironment: null,
  cookieManager: (_) => manager,
);

void main() {
  group('the Android user agent', () {
    const system =
        'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_x86_64 Build/BE2A; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/153.0.8010.36 Mobile Safari/537.36';
    const expected =
        'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_x86_64 Build/BE2A) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/153.0.8010.36 Mobile Safari/537.36';

    test('drops "; wv" and keeps everything else', () {
      expect(androidLoginUserAgent(system), expected);
    });

    test('drops ";wv" without a space', () {
      expect(
        androidLoginUserAgent(system.replaceFirst('; wv', ';wv')),
        expected,
      );
    });

    test('a user agent without the marker is unchanged', () {
      expect(androidLoginUserAgent(expected), expected);
      // 長得像但不是標記的不動。
      const lookalike = 'Mozilla/5.0 (Linux; wvx) Foo/1.0 (; wv-like)';
      expect(androidLoginUserAgent(lookalike), lookalike);
    });
  });

  group('cookies', () {
    test('only the asked hosts, the first host wins a name', () async {
      final manager = _FakeCookieManager()
        ..cookies['www.example.test'] = [
          Cookie(name: 'SID', value: 'FAKE_SITE_SID', domain: '.example.test'),
          Cookie(name: 'PREF', value: 'f6=8', domain: 'www.example.test'),
        ]
        ..cookies['accounts.example.test'] = [
          Cookie(name: 'SID', value: 'FAKE_PAGE_SID', domain: '.example.test'),
          Cookie(name: 'LSID', value: 'FAKE_PAGE_LSID'),
        ];
      final webView = _webView(manager);

      expect(await webView.cookies([_site]), {
        'SID': 'FAKE_SITE_SID',
        'PREF': 'f6=8',
      });
      expect(await webView.cookies([_site, _page]), {
        'SID': 'FAKE_SITE_SID',
        'PREF': 'f6=8',
        'LSID': 'FAKE_PAGE_LSID',
      });
      expect(await webView.cookies([Uri.parse('https://other.test')]), isEmpty);
    });
  });

  group('clearAll', () {
    test('deletes every cookie', () async {
      final manager = _FakeCookieManager()
        ..cookies['www.example.test'] = [
          Cookie(name: 'SID', value: 'FAKE_SID', domain: '.example.test'),
        ]
        ..cookies['other.test'] = [
          Cookie(name: 'KEEP', value: 'FAKE_KEEP', domain: 'other.test'),
        ];
      await _webView(manager).clearAll();
      expect(manager.deletedAll, 1);
      expect(manager.cookies, isEmpty);
    });
  });
}
