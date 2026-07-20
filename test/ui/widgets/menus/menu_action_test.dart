import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/menus/menu_action.dart';

void main() {
  const actions = [
    MenuAction(
      id: 'delete',
      icon: Icons.delete,
      label: 'Delete',
      destructive: true,
    ),
    MenuAction(id: 'rename', icon: Icons.edit, label: 'Rename'),
  ];

  test('popup entries use ListTile with destructive coloring', () {
    final entries = buildMenuActionPopupEntries(actions, Colors.red);

    expect(entries, hasLength(2));

    final first = entries[0] as PopupMenuItem<String>;
    expect(first.value, 'delete');
    final firstTile = first.child as ListTile;
    expect((firstTile.leading as Icon).color, Colors.red);
    expect((firstTile.title as Text).style?.color, Colors.red);
    expect(firstTile.contentPadding, EdgeInsets.zero);

    final second = entries[1] as PopupMenuItem<String>;
    expect(second.value, 'rename');
    final secondTile = second.child as ListTile;
    expect((secondTile.leading as Icon).color, isNull);
    expect((secondTile.title as Text).style, isNull);
  });

  testWidgets('list tiles pop the sheet and dispatch the action id',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: buildMenuActionListTiles(
                    sheetContext,
                    actions.sublist(0, 1),
                    (id) => selected = id,
                    Colors.red,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.delete));
    expect(icon.color, Colors.red);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(selected, 'delete');
    expect(find.text('Delete'), findsNothing);
  });
}
