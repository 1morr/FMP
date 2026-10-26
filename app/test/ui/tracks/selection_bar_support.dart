import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 選取列上一個動作的狀態。
enum SelectionActionState { absent, disabled, enabled }

final _bar = find.byWidgetPredicate((w) => w is TrackSelectionBar);

Finder _moreButton() => find.descendant(
  of: _bar,
  matching: find.byWidgetPredicate((w) => w is PopupMenuButton),
);

Finder _barButton(String label) =>
    find.descendant(of: _bar, matching: find.byTooltip(label));

Finder _menuItem(String label) =>
    find.widgetWithText(PopupMenuItem<void>, label);

/// 窄版放不下的動作收在選取列尾端的「⋯」；有就打開它，回傳有沒有打開。
Future<bool> openSelectionMenu(WidgetTester tester) async {
  if (_moreButton().evaluate().isEmpty) return false;
  await tester.tap(_moreButton());
  await tester.pumpAndSettle();
  return true;
}

Future<void> _closeMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(1, 1));
  await tester.pumpAndSettle();
}

/// 按選取列上標籤是 [label] 的動作：在列上就直接按，否則打開「⋯」選單再選。
Future<void> tapSelectionAction(WidgetTester tester, String label) async {
  final button = _barButton(label);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    expect(await openSelectionMenu(tester), isTrue, reason: 'no ⋯ menu');
    await tester.tap(_menuItem(label));
  }
  await tester.pumpAndSettle();
}

/// 選取列上動作 [label] 的狀態（列上的圖示鈕或「⋯」裡的選單項目都找）。
/// 窄版時項目的文字就是動作的標籤，所以「寫原因的標籤」兩種形式都對得上。
Future<SelectionActionState> selectionActionState(
  WidgetTester tester,
  String label,
) async {
  final button = _barButton(label);
  if (button.evaluate().isNotEmpty) {
    final icon = tester.widget<IconButton>(
      find.ancestor(of: button, matching: find.byType(IconButton)).first,
    );
    return icon.onPressed == null
        ? SelectionActionState.disabled
        : SelectionActionState.enabled;
  }
  if (!await openSelectionMenu(tester)) return SelectionActionState.absent;
  final item = _menuItem(label);
  final state = item.evaluate().isEmpty
      ? SelectionActionState.absent
      : tester.widget<PopupMenuItem<void>>(item).enabled
      ? SelectionActionState.enabled
      : SelectionActionState.disabled;
  await _closeMenu(tester);
  return state;
}
