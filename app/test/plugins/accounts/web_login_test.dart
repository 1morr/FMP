import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/accounts/web_login.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

import '../../support/fake_login_webview.dart';

// 網頁登入的完成與卡住（ADR 0029 §決定 9，design §6.4）。網站是 R1 的形狀：登入頁在
// accounts 那一台，帳號的 cookie 也在那一台；完成要看的是 www 那一台（cookieHosts）。

final _page = Uri.parse('https://accounts.example.test/login?continue=x');
final _site = Uri.parse('https://www.example.test');

final _spec = PluginLoginWebView(
  url: _page,
  cookieHosts: [_site],
  doneCookies: const ['SID', 'HSID'],
);

/// 登入頁那一端登入完成的 cookie（假值）。
const _signedIn = {'SID': 'FAKE_PAGE_SID_123', 'HSID': 'FAKE_PAGE_HSID_123'};

/// 網站那一端登入完成的 cookie（假值），加一個不在 doneCookies 的。
const _siteCookies = {
  'SID': 'FAKE_SITE_SID_123',
  'HSID': 'FAKE_SITE_HSID_123',
  'PREF': 'FAKE_SITE_PREF_123',
};

final class _Setup {
  _Setup() {
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    login = WebLogin(webView: webView, spec: _spec, log: log);
  }

  final webView = FakeLoginWebView();
  late final Log log;
  late final WebLogin login;

  /// 畫面上的 WebView 載入完一頁。
  void load(FakeAsync async) {
    unawaited(login.pageLoaded());
    async.flushMicrotasks();
  }

  void retry(FakeAsync async) {
    unawaited(login.retry(webViewRemoved: () async {}));
    async.flushMicrotasks();
  }
}

void main() {
  test('completes when the cookie hosts have every done cookie, with all '
      'their cookies', () {
    fakeAsync((async) {
      final setup = _Setup();
      expect(setup.login.value, isA<WebLoginShowing>());

      setup.load(async);
      expect(
        setup.login.value,
        isA<WebLoginShowing>().having((s) => s.loaded, 'loaded', isTrue),
      );

      setup.webView.setCookies(_site, _siteCookies);
      setup.load(async);

      expect(
        setup.login.value,
        isA<WebLoginDone>().having(
          (s) => s.credentials,
          'credentials',
          const LoginCredentials(cookies: _siteCookies),
        ),
      );
      // 完成之後的載入什麼都不做。
      setup.load(async);
      expect(setup.login.value, isA<WebLoginDone>());
      expect(async.pendingTimers, isEmpty);
      setup.login.dispose();
    });
  });

  test('the same cookies on another host, or an empty value, do not count', () {
    fakeAsync((async) {
      final setup = _Setup();
      // 登入頁那一台（Google 帳號那一端）先有同名的 cookie：不算完成。
      setup.webView.setCookies(_page, _signedIn);
      setup.load(async);
      expect(setup.login.value, isA<WebLoginShowing>());
      expect(setup.webView.asked.first, [_site]);

      setup.webView.setCookies(_site, {'SID': 'FAKE_SITE_SID_123', 'HSID': ''});
      setup.load(async);
      expect(setup.login.value, isA<WebLoginShowing>());

      setup.webView.setCookies(_site, _siteCookies);
      setup.load(async);
      expect(setup.login.value, isA<WebLoginDone>());
      setup.login.dispose();
    });
  });

  test('two page loads in a row complete once', () {
    fakeAsync((async) {
      final setup = _Setup();
      var done = 0;
      setup.login.addListener(() {
        if (setup.login.value is WebLoginDone) done++;
      });
      setup.webView.setCookies(_site, _siteCookies);
      // 兩次載入完成都在讀 cookie 的途中（還沒 flush）。
      unawaited(setup.login.pageLoaded());
      unawaited(setup.login.pageLoaded());
      async.flushMicrotasks();

      expect(setup.login.value, isA<WebLoginDone>());
      expect(done, 1);
      setup.login.dispose();
    });
  });

  test('leaving while the cookies are being read does nothing', () {
    fakeAsync((async) {
      final setup = _Setup();
      setup.webView.setCookies(_site, _siteCookies);
      setup.webView.setCookies(_page, _signedIn);
      unawaited(setup.login.pageLoaded());
      // 讀 cookie 回來之前離開：之後不改值（dispose 後改值會丟錯）、不起計時器。
      setup.login.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  group('a stuck redirect', () {
    test('is reported 15 seconds after the sign-in page has signed in', () {
      fakeAsync((async) {
        final setup = _Setup();
        setup.webView.setCookies(_page, _signedIn);
        setup.load(async);

        async.elapse(webLoginStuckAfter - const Duration(seconds: 1));
        expect(setup.login.value, isA<WebLoginShowing>());
        // 之後的載入不重新起算。
        setup.load(async);
        expect(async.pendingTimers, hasLength(1));

        async.elapse(const Duration(seconds: 1));
        expect(
          setup.login.value,
          isA<WebLoginStuck>().having((s) => s.retried, 'retried', isFalse),
        );
        expect(async.pendingTimers, isEmpty);

        // 卡住之後 cookie 還是可能齊（頁面自己走完了）。
        setup.webView.setCookies(_site, _siteCookies);
        setup.load(async);
        expect(setup.login.value, isA<WebLoginDone>());
        setup.login.dispose();
      });
    });

    test('is not reported while the user is still signing in', () {
      fakeAsync((async) {
        final setup = _Setup();
        // 登入頁一打開就有 cookie，只是還沒登入（沒有 doneCookies）。
        setup.webView.setCookies(_page, {'NID': 'FAKE_PAGE_NID_123'});
        setup.load(async);
        async.elapse(const Duration(minutes: 5));
        expect(setup.login.value, isA<WebLoginShowing>());
        expect(async.pendingTimers, isEmpty);
        setup.login.dispose();
      });
    });

    test('looks at the cookies again when the time is up', () {
      fakeAsync((async) {
        final setup = _Setup();
        setup.webView.setCookies(_page, _signedIn);
        setup.load(async);
        // 跳轉在沒有再觸發載入完成的情況下走完了。
        setup.webView.setCookies(_site, _siteCookies);
        async.elapse(webLoginStuckAfter);
        expect(setup.login.value, isA<WebLoginDone>());
        setup.login.dispose();
      });
    });

    test('a retry resets the web view after it left the screen, then asks '
        'for a restart if it is stuck again', () {
      fakeAsync((async) {
        final setup = _Setup();
        setup.webView.setCookies(_page, _signedIn);
        setup.load(async);
        async.elapse(webLoginStuckAfter);
        expect(setup.login.value, isA<WebLoginStuck>());
        expect(setup.login.attempt, 0);

        var removed = false;
        unawaited(
          setup.login.retry(
            webViewRemoved: () async {
              // 先拿掉 WebView，才丟掉環境。
              expect(setup.login.value, isA<WebLoginRestarting>());
              expect(setup.webView.resets, 0);
              removed = true;
            },
          ),
        );
        async.flushMicrotasks();
        expect(removed, isTrue);
        expect(setup.webView.resets, 1);
        expect(setup.login.attempt, 1);
        expect(
          setup.login.value,
          isA<WebLoginShowing>().having((s) => s.loaded, 'loaded', isFalse),
        );

        setup.load(async);
        async.elapse(webLoginStuckAfter);
        expect(
          setup.login.value,
          isA<WebLoginStuck>().having((s) => s.retried, 'retried', isTrue),
        );
        setup.login.dispose();
      });
    });

    test('a timer of a replaced web view does nothing', () {
      fakeAsync((async) {
        final setup = _Setup();
        setup.webView.setCookies(_page, _signedIn);
        setup.load(async);
        setup.retry(async);
        async.elapse(webLoginStuckAfter * 2);
        expect(setup.login.value, isA<WebLoginShowing>());
        expect(async.pendingTimers, isEmpty);
        setup.login.dispose();
      });
    });

    test('leaving the screen cancels the timer', () {
      fakeAsync((async) {
        final setup = _Setup();
        setup.webView.setCookies(_page, _signedIn);
        setup.load(async);
        expect(async.pendingTimers, hasLength(1));

        setup.login.dispose();

        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  test('a web view that cannot start is logged and can be retried', () {
    fakeAsync((async) {
      final setup = _Setup();
      setup.login.failed(StateError('no WebView2 runtime'), StackTrace.current);
      expect(setup.login.value, isA<WebLoginFailed>());
      expect(
        setup.log.history.where((r) => r.message.contains('failed to start')),
        hasLength(1),
      );

      setup.retry(async);
      expect(setup.login.value, isA<WebLoginShowing>());
      expect(setup.login.attempt, 1);
      setup.login.dispose();
    });
  });

  test('cookie values never reach the log', () {
    fakeAsync((async) {
      final setup = _Setup();
      setup.webView.setCookies(_page, _signedIn);
      setup.load(async);
      async.elapse(webLoginStuckAfter);
      setup.retry(async);
      setup.webView.setCookies(_site, _siteCookies);
      setup.load(async);
      expect(setup.login.value, isA<WebLoginDone>());

      final values = [..._signedIn.values, ..._siteCookies.values];
      for (final record in setup.log.history) {
        final text = '${record.message} ${record.fields} ${record.error}';
        for (final value in values) {
          expect(text, isNot(contains(value)));
        }
      }
      setup.login.dispose();
    });
  });
}
