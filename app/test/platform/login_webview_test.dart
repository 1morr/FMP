import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/login_webview/flutter_inappwebview_login.dart';

// 登入 WebView 的平台實作（ADR 0029 §決定 9）：UA 的轉換與 cookie 的讀、刪。套件的
// CookieManager 以假的換掉（建構子注入），不碰平台通道；WebView 本身只能實機驗。

/// 假的 CookieManager：cookie 以網址的主機名稱存，`getCookies` 只回那一台的。刪除照名稱、
/// domain、path 比對（cookie 的身分）。[chromium] 時照 Android（Chromium）設定 cookie 的
/// 規則：帶 `Domain` 的一律是網域 cookie（前面補 `.`，和 host-only 的不是同一個）；
/// `__Secure-`／`__Host-` 開頭而不帶 `Secure`、`__Host-` 帶 `Domain` 的整個拒收。
final class _FakeCookieManager implements CookieManager {
  _FakeCookieManager({this.chromium = false});

  final bool chromium;

  /// 主機名稱 → 那一台讀得到的 cookie。host-only 的 cookie 的 domain 是主機名稱（不以
  /// `.` 開頭），和兩個平台回報的一樣。
  final cookies = <String, List<Cookie>>{};

  /// 每次刪除（`setCookie` 過期或 `deleteCookie`）的參數。
  final deletions = <String>[];
  var deletedAll = 0;

  /// 為真時刪除什麼都不做（平台默默失敗）。
  var ignoreDeletes = false;

  void _delete(WebUri url, String name, String? domain, String path) {
    if (ignoreDeletes) return;
    final identity = domain == null
        ? url.host
        : chromium && !domain.startsWith('.')
        ? '.$domain'
        : domain;
    for (final list in cookies.values) {
      list.removeWhere(
        (c) =>
            c.name == name && c.domain == identity && (c.path ?? '/') == path,
      );
    }
  }

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async => [...?cookies[url.host]];

  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async {
    deletions.add(
      'expire ${url.host} $name domain=$domain path=$path '
      'maxAge=$maxAge secure=$isSecure value="$value"',
    );
    final prefixed = name.startsWith('__Secure-') || name.startsWith('__Host-');
    if (chromium &&
        ((prefixed && isSecure != true) ||
            (name.startsWith('__Host-') && domain != null))) {
      return false;
    }
    if (value.isEmpty && (maxAge ?? 0) < 0) _delete(url, name, domain, path);
    return true;
  }

  @override
  Future<bool> deleteCookie({
    required WebUri url,
    required String name,
    String path = '/',
    String? domain,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async {
    deletions.add('delete ${url.host} $name domain=$domain path=$path');
    _delete(url, name, domain, path);
    return true;
  }

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

InAppLoginWebView _webView(
  _FakeCookieManager manager, {
  DeleteCookie deleteCookie = deleteCookieByName,
}) => InAppLoginWebView(
  userAgent: () async => null,
  createEnvironment: null,
  deleteCookie: deleteCookie,
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

  group('clear', () {
    _FakeCookieManager signedIn({bool chromium = false}) =>
        _FakeCookieManager(chromium: chromium)
          ..cookies['www.example.test'] = [
            Cookie(name: 'SID', value: 'FAKE_SID', domain: '.example.test'),
            Cookie(
              name: '__Secure-1PSID',
              value: 'FAKE_PSID',
              domain: '.example.test',
              path: '/',
            ),
            Cookie(
              name: '__Host-GAPS',
              value: 'FAKE_GAPS',
              domain: 'www.example.test',
              path: '/',
            ),
          ]
          ..cookies['accounts.example.test'] = [
            Cookie(
              name: 'LSID',
              value: 'FAKE_LSID',
              domain: 'accounts.example.test',
              path: '/login',
            ),
          ]
          ..cookies['other.test'] = [
            Cookie(name: 'KEEP', value: 'FAKE_KEEP', domain: 'other.test'),
          ];

    test('Windows deletes each cookie by name, domain and path', () async {
      final manager = signedIn();
      final webView = _webView(manager);

      await webView.clear([_site, _page]);

      expect(manager.deletions, [
        'delete www.example.test SID domain=.example.test path=/',
        'delete www.example.test __Secure-1PSID domain=.example.test path=/',
        'delete www.example.test __Host-GAPS domain=www.example.test path=/',
        'delete accounts.example.test LSID domain=accounts.example.test '
            'path=/login',
      ]);
      expect(await webView.cookies([_site, _page]), isEmpty);
      expect(manager.cookies['other.test'], hasLength(1));
      // 再清一次沒有東西可刪。
      await webView.clear([_site, _page]);
      expect(manager.deletions, hasLength(4));
    });

    test('Android expires each cookie as Secure, a host-only one without a '
        'Domain', () async {
      final manager = signedIn(chromium: true);
      final webView = _webView(manager, deleteCookie: expireCookie);

      await webView.clear([_site, _page]);

      expect(manager.deletions, [
        'expire www.example.test SID domain=.example.test path=/ '
            'maxAge=-1 secure=true value=""',
        'expire www.example.test __Secure-1PSID domain=.example.test path=/ '
            'maxAge=-1 secure=true value=""',
        'expire www.example.test __Host-GAPS domain=null path=/ '
            'maxAge=-1 secure=true value=""',
        'expire accounts.example.test LSID domain=null path=/login '
            'maxAge=-1 secure=true value=""',
      ]);
      expect(await webView.cookies([_site, _page]), isEmpty);
    });

    test(
      "Android: the package's deleteCookie would leave cookies behind",
      () async {
        // 對照組：套件的 deleteCookie（不帶 Secure、host-only 也帶 Domain）在 Chromium 規則下
        // 刪不掉 __Secure- 與 host-only 的 cookie，clear 讀回來發現就丟錯。
        final manager = signedIn(chromium: true);
        final webView = _webView(manager);

        await expectLater(webView.clear([_site]), throwsA(isA<StateError>()));
      },
    );

    test('a cookie the platform could not delete is an error without '
        'values', () async {
      final manager = signedIn()..ignoreDeletes = true;
      final webView = _webView(manager);

      await expectLater(
        webView.clear([_site]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('3'), isNot(contains('FAKE_'))),
          ),
        ),
      );
    });

    test('clearAll deletes every cookie', () async {
      final manager = signedIn();
      await _webView(manager).clearAll();
      expect(manager.deletedAll, 1);
      expect(manager.cookies, isEmpty);
    });
  });
}
