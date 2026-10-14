import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/debug/debug_health.dart';
import 'package:material_ui/material_ui.dart';

import '../support/health_page.dart';

// Debug 頁的音源健康檢查區塊（M3 PR 16a，ADR 0025 §決定 6）。檢查本身的規則在
// test/plugins/health/health_check_test.dart，這裡看清單、進度與結果的呈現。

void main() {
  testWidgets('lists every installed plugin with its state', (tester) async {
    await openHealth(tester);
    expect(find.byType(DebugHealth), findsOneWidget);
    expect(find.text('Plugin plugin-a'), findsOneWidget);
    expect(find.text('1.0.0 · Cases: 2'), findsNWidgets(2));
    // 沒有 checks_json 的插件與停用的插件。
    expect(find.text('1.0.0 · No check cases'), findsOneWidget);
    expect(find.text('1.0.0 · Disabled'), findsOneWidget);
    final buttons = tester.widgetList<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Check'),
    );
    expect(buttons.map((b) => b.onPressed != null), [true, false, false, true]);
  });

  testWidgets('checking one plugin shows passed and skipped cases', (
    tester,
  ) async {
    await openHealth(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Check').first);
    await tester.pump();
    // 進度：跑的期間不能再開一輪。
    expect(find.text('Checking…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check all'))
          .onPressed,
      isNull,
    );
    await settleHealth(tester);
    expect(find.textContaining('search · Passed · '), findsOneWidget);
    expect(
      find.textContaining('login · Skipped (not logged in) · '),
      findsOneWidget,
    );
    expect(find.text('Checking…'), findsNothing);
  });

  testWidgets('a failed case shows the error type and the problem', (
    tester,
  ) async {
    await openHealth(tester);
    await tester.tap(find.text('Check all'));
    await settleHealth(tester);
    expect(find.textContaining('search · Failed · '), findsOneWidget);
    expect(find.textContaining('Error type: RateLimited'), findsOneWidget);
  });

  testWidgets('unreadable check cases can still be run to see why', (
    tester,
  ) async {
    await openHealth(tester, unreadable: true);
    expect(find.text('1.0.0 · Check cases cannot be read'), findsOneWidget);
    final check = find.widgetWithText(OutlinedButton, 'Check').last;
    expect(tester.widget<OutlinedButton>(check).onPressed, isNotNull);
    await tester.tap(check);
    await settleHealth(tester);
    expect(find.textContaining('Cannot check: '), findsOneWidget);
  });
}
