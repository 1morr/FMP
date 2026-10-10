import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/platform/platform.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/accounts/web_login_page.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/ui/support/shell_harness.dart';

// ADR 0023 §如何確認的實機那一項：提示在全螢幕頁與對話框之上看得到。外殼、
// ToastHost 與 MaterialApp 和 App 相同（FmpApp 的 builder），視窗是裝置自己的
// 大小；插件與播放後端用測試的假實作（不連網、不出聲）。同一組斷言在
// `test/ui/toast/toast_host_test.dart` 的 `above every route` 以 flutter test
// 跑；這裡在真的引擎與平台上再跑一次（含播放頁，M2 PR 18a；網頁登入的 WebView，M3 PR 9）：
//
//   flutter test integration_test/toast_layering_test.dart -d windows
//   flutter test integration_test/toast_layering_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 開外殼；回傳外殼的 context（開對話框、推路由用）。
  Future<(ShellHarness, BuildContext)> pumpShell(WidgetTester tester) async {
    final h = ShellHarness();
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: fmpMaterialApp(
          title: 'FMP Dev',
          locale: LocaleSetting.en,
          themeMode: ThemeMode.light,
          fontFamilyFallback: const [],
          builder: (context, navigator) =>
              WindowClassScope(child: ToastHost(child: navigator!)),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (h, tester.element(find.byType(AppShell)));
  }

  /// 送出一則提示，斷言它在最上層：點在文字中央打到的是提示本身，沒有被
  /// 路由或遮罩蓋住，而且整則在視窗內。
  Future<void> expectToastOnTop(
    WidgetTester tester,
    ShellHarness h, {
    bool settle = true,
  }) async {
    const message = 'Toast above the route';
    h.toaster.warning(message);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // 頁面上有一直在動的東西時：提示出現的動畫走完就好。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.text(message).hitTestable(), findsOneWidget);
    final view = tester.view;
    final window = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final toast = tester.getRect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(Material),
      ),
    );
    expect(window.contains(toast.topLeft), isTrue, reason: '$toast in $window');
    expect(
      window.contains(toast.bottomRight - const Offset(1, 1)),
      isTrue,
      reason: '$toast in $window',
    );
  }

  testWidgets('a toast shows above a dialog', (tester) async {
    final (h, shell) = await pumpShell(tester);
    unawaited(
      showDialog<void>(
        context: shell,
        builder: (_) => const AlertDialog(content: Text('A dialog')),
      ),
    );
    await tester.pumpAndSettle();

    await expectToastOnTop(tester, h);
    expect(find.text('A dialog'), findsOneWidget);
  });

  testWidgets('a toast shows above a full-screen route', (tester) async {
    final (h, shell) = await pumpShell(tester);
    unawaited(
      Navigator.of(shell).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              const Scaffold(body: Center(child: Text('A full-screen page'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectToastOnTop(tester, h);
    expect(find.text('A full-screen page'), findsOneWidget);
  });

  // 網頁登入（M3 PR 9）：全螢幕頁裡是平台真的 WebView（Android 的系統 WebView、Windows 的
  // WebView2），提示要在它之上。開的是 about:blank，不連網；平台沒有登入 WebView（Linux、macOS）時
  // 跳過。WebView 起不來時頁面換成錯誤狀態，提示照樣要在最上層。
  final loginWebView = AppPlatform.current(AppFlavor.dev).loginWebView;
  testWidgets('a toast shows above the web login', (tester) async {
    final (h, shell) = await pumpShell(tester);
    unawaited(
      showWebLogin(
        shell,
        webView: loginWebView!,
        spec: PluginLoginWebView(
          url: Uri.parse('about:blank'),
          cookieHosts: [Uri.parse('https://example.test')],
          doneCookies: const ['SID'],
        ),
        name: 'Test Source',
      ),
    );
    // 載入中的進度條一直在動：不等 settle。改成等到第一頁載入完成（進度條不再是不定長度）
    // 或頁面換成 WebView 失敗狀態（兩者進度條都是 determinate）。flutter_inappwebview_windows
    // 的 CustomPlatformView 初始化是非同步的，完成時不檢查 mounted 就 setState；初始化還沒
    // 完成就結束測試、拆掉 WebView，會在測試之後丟出 setState() after dispose()。
    var waited = Duration.zero;
    while (true) {
      await tester.pump(const Duration(milliseconds: 100));
      waited += const Duration(milliseconds: 100);
      final indicator = find.descendant(
        of: find.byType(WebLoginPage),
        matching: find.byType(LinearProgressIndicator),
      );
      if (indicator.evaluate().isNotEmpty &&
          tester.widget<LinearProgressIndicator>(indicator).value != null) {
        break;
      }
      if (waited >= const Duration(seconds: 30)) {
        fail('The web login did not finish its first page load in 30 s');
      }
    }
    expect(find.byType(WebLoginPage), findsOneWidget);

    await expectToastOnTop(tester, h, settle: false);
    expect(find.byType(WebLoginPage), findsOneWidget);
  }, skip: loginWebView == null);

  // 播放頁蓋住外殼的播放列與導覽：提示的底部位移只剩底部安全區（ADR 0023 §決定 2），
  // 關掉播放頁後回到外殼量到的高度。
  testWidgets('a toast shows above the player page, on the safe area', (
    tester,
  ) async {
    final (h, _) = await pumpShell(tester);
    await h.play(tester, [summary('a'), summary('b')]);
    await tester.pump(const Duration(milliseconds: 200));
    final container = h.container(tester);
    final withBar = container.read(toastBottomInsetProvider);
    expect(withBar, greaterThan(0));

    await tester.tap(
      find
          .descendant(
            of: find.byKey(PlayerBar.titleKey),
            matching: find.byType(Text),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    final safeArea = MediaQuery.viewPaddingOf(
      tester.element(find.byType(PlayerPage)),
    ).bottom;
    expect(container.read(toastBottomInsetProvider), safeArea);

    await expectToastOnTop(tester, h);
    expect(find.byType(PlayerPage), findsOneWidget);

    // 提示照時長消失之後關掉播放頁。
    await tester.pump(const Duration(seconds: 7));
    await tester.tap(find.byKey(PlayerPage.closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(container.read(toastBottomInsetProvider), withBar);
  });
}
