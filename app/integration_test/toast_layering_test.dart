import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_material.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/ui/support/shell_harness.dart';

// ADR 0023 §如何確認的實機那一項：提示在全螢幕頁與對話框之上看得到。外殼、
// ToastHost 與 MaterialApp 和 App 相同（FmpApp 的 builder），視窗是裝置自己的
// 大小；插件與播放後端用測試的假實作（不連網、不出聲）。同一組斷言在
// `test/ui/toast/toast_host_test.dart` 的 `above every route` 以 flutter test
// 跑；這裡在真的引擎與平台上再跑一次：
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
  Future<void> expectToastOnTop(WidgetTester tester, ShellHarness h) async {
    const message = 'Toast above the route';
    h.toaster.warning(message);
    await tester.pumpAndSettle();
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
}
