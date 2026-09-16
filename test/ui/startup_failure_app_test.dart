import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fmp/ui/startup_failure_app.dart';

/// `main.dart` 自己不可測 —— `main()` 會裝上全域錯誤處理器、開 Isar、初始化
/// 平台外掛，一個 `flutter_test` 程序跑不起來也還原不回去。所以可測的部分被切
/// 成這個獨立的 widget：`main.dart` 剩下的是「旗標為 false 時把它交給
/// `runApp()`」這一句，由 Windows 實機驗證覆蓋（issue #37）。
void main() {
  group('StartupFailureApp', () {
    testWidgets('shows the exception, the log path and the issues URL', (
      tester,
    ) async {
      await tester.pumpWidget(
        StartupFailureApp(
          error: StateError('startup probe'),
          logFilePath: r'C:\Users\someone\Documents\FMP\logs\fmp.log',
        ),
      );

      // 兩種語言的標題都在，因為這個畫面讀不到使用者的語言設定。
      expect(find.text('FMP failed to start'), findsOneWidget);
      expect(find.text('FMP 啟動失敗'), findsOneWidget);

      expect(
        find.text('Bad state: startup probe'),
        findsOneWidget,
        reason: 'the raw exception text is the user only clue at this point',
      );
      expect(
        find.text(r'C:\Users\someone\Documents\FMP\logs\fmp.log'),
        findsOneWidget,
      );
      expect(find.text(kFmpIssuesUrl), findsOneWidget);
    });

    testWidgets('every piece of text can be selected and copied', (
      tester,
    ) async {
      await tester.pumpWidget(
        StartupFailureApp(
          error: StateError('startup probe'),
          logFilePath: '/data/user/0/com.personal.fmp/files/FMP/logs/fmp.log',
        ),
      );

      // 沒有 URL launcher —— 使用者要靠選取複製把這三樣東西帶進 issue 裡。
      expect(find.byType(SelectableText), findsNWidgets(3));
    });

    testWidgets('omits the log section when no sink is attached', (
      tester,
    ) async {
      await tester.pumpWidget(
        StartupFailureApp(error: StateError('startup probe')),
      );

      expect(find.textContaining('Log file'), findsNothing);
      expect(find.text(kFmpIssuesUrl), findsOneWidget);
    });

    testWidgets('a long exception scrolls instead of overflowing', (
      tester,
    ) async {
      // 例外訊息可以是一整段 stack-ish 的文字，而 Windows 的最小視窗只有
      // 400x500 —— 溢位的紅黃條紋會蓋掉正要傳達的訊息。
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        StartupFailureApp(
          error: StateError(List.filled(40, 'a very long failure').join(' ')),
          logFilePath: r'C:\Users\someone\Documents\FMP\logs\fmp.log',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
