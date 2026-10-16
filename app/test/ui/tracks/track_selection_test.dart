import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/tracks/track_selection.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 共用的多選（M4 PR 5，ADR 0033 §決定 10，design §10.7）的機制：取消到不剩就離開、Shift＋點選的
// 範圍、列消失後不再算選了（也不搬走對話框的焦點）、Ctrl+A 只在選取模式內且不在輸入框裡、返回鍵先離開選取模式、選取
// 模式的列是一個勾選的語意節點。三個頁面各自的進入、離開與動作在它們的測試裡。

/// 一頁 a…e 五列（標題 `Song x`），上面一個輸入框；列可以從外面拿掉（[_ListPageState.remove]）。
class _ListPage extends StatefulWidget {
  const _ListPage({super.key});

  @override
  State<_ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<_ListPage> {
  final selection = TrackSelection<String>();
  var items = ['a', 'b', 'c', 'd', 'e'];

  /// 選取列的「加入佇列」收到的鍵。
  final added = <List<String>>[];

  void remove(String item) => setState(() => items = [...items]..remove(item));

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TrackSelectionScope<String>(
    selection: selection,
    keys: items,
    child: Column(
      children: [
        TrackSelectionBar<String>(
          tracks: (keys) async {
            added.add(keys);
            return [
              for (final key in keys)
                TrackInfo(sourceTypeId: 'fmp-test', sourceId: key, title: key),
            ];
          },
          child: const Text('Title'),
        ),
        const TextField(),
        Expanded(
          child: ListView(
            children: [
              for (final item in items)
                SelectableTrackRow<String>(
                  key: ValueKey(item),
                  selectionKey: item,
                  menuChildren: const [],
                  moreTooltip: 'More options',
                  builder: (context, row) => ListTile(
                    selected: row.selected,
                    title: Text('Song $item'),
                    trailing: row.trailing,
                    onTap: row.onTap ?? () {},
                    onLongPress: row.onLongPress,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

final _page = GlobalKey<_ListPageState>();

Future<_ListPageState> _pump(WidgetTester tester) async {
  await ShellHarness().pumpApp(tester, _ListPage(key: _page));
  return _page.currentState!;
}

Future<void> _ctrlA(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _shiftTap(WidgetTester tester, String title) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(find.text(title));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('a long press enters with that row; unchecking the last row '
      'leaves', (tester) async {
    final page = await _pump(tester);

    await tester.longPress(find.text('Song b'));
    await tester.pump();
    expect(page.selection.active, isTrue);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Title'), findsNothing, reason: 'the bar replaces it');

    await tester.tap(find.text('Song d'));
    await tester.pump();
    expect(page.selection.selected, ['b', 'd']);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Song b'));
    await tester.tap(find.text('Song d'));
    await tester.pump();
    expect(page.selection.active, isFalse);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('Shift+click sets every row from the last clicked one to the '
      'state of the clicked row', (tester) async {
    final page = await _pump(tester);

    await tester.longPress(find.text('Song b'));
    await tester.pump();
    await _shiftTap(tester, 'Song d');
    expect(page.selection.selected, ['b', 'c', 'd']);

    // 範圍的起點換成上一次點的 d；往回選到 a。
    await _shiftTap(tester, 'Song a');
    expect(page.selection.selected, ['a', 'b', 'c', 'd']);

    // 點一個已選的：從 a 到 c 都取消。
    await _shiftTap(tester, 'Song c');
    expect(page.selection.selected, ['d']);

    // 沒按 Shift：只切換那一列。
    await tester.tap(find.text('Song e'));
    await tester.pump();
    expect(page.selection.selected, ['d', 'e']);
  });

  testWidgets('a selected row that goes away is no longer selected; when none '
      'is left the mode ends', (tester) async {
    final page = await _pump(tester);

    await tester.longPress(find.text('Song b'));
    await tester.tap(find.text('Song c'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    page.remove('b');
    await tester.pump();
    await tester.pump();
    expect(page.selection.selected, ['c']);
    expect(find.text('1 selected'), findsOneWidget);

    page.remove('c');
    await tester.pump();
    await tester.pump();
    expect(page.selection.active, isFalse);
  });

  // 列換了不是使用者點的（例如背景刷新刪掉一首）：上面開著的對話框留著焦點。
  testWidgets('a selected row that goes away under a dialog leaves the focus '
      'in the dialog', (tester) async {
    final page = await _pump(tester);
    await tester.longPress(find.text('Song b'));
    await tester.tap(find.text('Song c'));
    await tester.pump();
    final dialogField = GlobalKey();
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(_ListPage)),
        builder: (_) =>
            Dialog(child: TextField(key: dialogField, autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    final focused = tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(dialogField),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;
    expect(focused.hasPrimaryFocus, isTrue);

    page.remove('b');
    await tester.pump();
    await tester.pump();

    expect(page.selection.selected, ['c']);
    expect(focused.hasPrimaryFocus, isTrue);
  });

  group('Ctrl+A', () {
    testWidgets('outside selection mode does nothing, also with the focus '
        'in the list', (tester) async {
      final page = await _pump(tester);
      Focus.of(tester.element(find.byIcon(Icons.more_vert).first))
          .requestFocus();
      await tester.pump();

      await _ctrlA(tester);

      expect(page.selection.active, isFalse);
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('in selection mode selects every row (entering moved the '
        'focus into the page)', (tester) async {
      final page = await _pump(tester);
      await tester.longPress(find.text('Song b'));
      await tester.pump();

      await _ctrlA(tester);

      expect(page.selection.selected, ['a', 'b', 'c', 'd', 'e']);
      expect(find.text('5 selected'), findsOneWidget);
    });

    testWidgets('in a text field selects the text, not the rows', (
      tester,
    ) async {
      final page = await _pump(tester);
      await tester.longPress(find.text('Song b'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await _ctrlA(tester);

      expect(page.selection.selected, ['b']);
      expect(
        field.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
    });
  });

  testWidgets('"Select all" and the cancel button; the back key leaves '
      'selection mode before the page', (tester) async {
    final page = await _pump(tester);
    await tester.longPress(find.text('Song b'));
    await tester.pump();

    await tester.tap(find.byTooltip('Select all (Ctrl+A)'));
    await tester.pump();
    expect(page.selection.count, 5);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.select_all))
          .onPressed,
      isNull,
      reason: 'everything is selected',
    );

    await tester.tap(find.byTooltip('Cancel selection (Esc)'));
    await tester.pump();
    expect(page.selection.active, isFalse);

    await tester.longPress(find.text('Song c'));
    await tester.pump();
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(handled, isTrue);
    expect(page.selection.active, isFalse);
    expect(find.byType(_ListPage), findsOneWidget);
  });

  testWidgets('an action gets the selected keys in screen order and ends the '
      'mode when it is done', (tester) async {
    final h = ShellHarness();
    await h.pumpApp(tester, _ListPage(key: _page));
    final page = _page.currentState!;
    await tester.longPress(find.text('Song d'));
    await tester.tap(find.text('Song a'));
    await tester.pump();

    await tester.tap(find.byTooltip('Add to queue'));
    await tester.pump();
    await tester.pump();

    expect(page.added, [
      ['a', 'd'],
    ]);
    expect(
      [for (final entry in h.controller.queue.entries) entry.track.sourceId],
      ['a', 'd'],
    );
    expect(page.selection.active, isFalse);
    expect(find.text('Added to the queue'), findsOneWidget);
  });

  testWidgets('a row in selection mode is one checked semantics node; the '
      'checkbox is neither a node nor a tab stop', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.longPress(find.text('Song b'));
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Song b')),
      isSemantics(
        label: 'Song b',
        hasCheckedState: true,
        isChecked: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Song c')),
      isSemantics(
        label: 'Song c',
        hasCheckedState: true,
        isChecked: false,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    // 勾選框沒有自己的節點：找它的語意節點得到的是整列的。
    final checkboxOfB = find.descendant(
      of: find.widgetWithText(ListTile, 'Song b'),
      matching: find.byType(Checkbox),
    );
    expect(
      tester.getSemantics(checkboxOfB).id,
      tester.getSemantics(find.text('Song b')).id,
    );
    // 也要不到焦點（不在 Tab 順序裡）。
    final checkboxFocus = Focus.of(
      tester.element(
        find
            .descendant(of: checkboxOfB, matching: find.byType(CustomPaint))
            .first,
      ),
    );
    expect(checkboxFocus.canRequestFocus, isFalse);
    handle.dispose();
  });
}
