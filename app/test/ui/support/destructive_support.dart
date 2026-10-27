import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 開著的確認框裡 [label] 那顆確認鈕是紅色（`showDestructiveConfirm`，ADR 0035，R7.9）：
/// 刪除或移除東西的確認框一律走共用元件，這裡逐個呼叫端驗它真的用了。
void expectDestructiveConfirm(WidgetTester tester, String label) {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label),
  );
  expect(button, findsOneWidget, reason: 'the confirm button "$label"');
  final scheme = Theme.of(tester.element(button)).colorScheme;
  final style = tester.widget<FilledButton>(button).style;
  expect(
    style?.backgroundColor?.resolve(const {}),
    scheme.error,
    reason: '"$label" is red',
  );
  expect(style?.foregroundColor?.resolve(const {}), scheme.onError);
}
