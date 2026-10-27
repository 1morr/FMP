import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/dialogs/destructive_confirm.dart';
import 'package:material_ui/material_ui.dart';

import '../support/destructive_support.dart';
import '../support/shell_harness.dart';

// 共用的刪除確認與選單項目（U PR 13，ADR 0035，R7.9，舊版 L-19、L-34）。各呼叫端用了它，
// 在各自的測試裡以 `expectDestructiveConfirm` 驗。

Future<void> _open(WidgetTester tester, Widget Function(BuildContext) body) =>
    ShellHarness().pumpApp(tester, Scaffold(body: Builder(builder: body)));

void main() {
  group('showDestructiveConfirm', () {
    Future<void> show(WidgetTester tester, List<bool> answers) async {
      await _open(
        tester,
        (context) => TextButton(
          onPressed: () async => answers.add(
            await showDestructiveConfirm(
              context,
              title: 'Delete it?',
              body: 'It cannot be undone.',
              confirmLabel: 'Delete',
              cancelLabel: 'Keep',
            ),
          ),
          child: const Text('Open'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('has a red confirm button and a plain cancel', (tester) async {
      await show(tester, []);

      expect(find.text('Delete it?'), findsOneWidget);
      expect(find.text('It cannot be undone.'), findsOneWidget);
      expectDestructiveConfirm(tester, 'Delete');
      expect(find.widgetWithText(TextButton, 'Keep'), findsOneWidget);
    });

    testWidgets('confirming answers true, cancelling or dismissing false', (
      tester,
    ) async {
      final answers = <bool>[];
      await show(tester, answers);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(answers, [true, false, false]);
    });
  });

  group('DestructiveMenuItem', () {
    Future<void> menu(WidgetTester tester, {required bool enabled}) => _open(
      tester,
      (context) => MenuAnchor(
        menuChildren: [
          DestructiveMenuItem(
            icon: Icons.delete_outline,
            onPressed: enabled ? () {} : null,
            child: const Text('Remove'),
          ),
          MenuItemButton(onPressed: () {}, child: const Text('Other')),
        ],
        builder: (context, controller, _) =>
            TextButton(onPressed: controller.open, child: const Text('Menu')),
      ),
    );

    MenuItemButton item(WidgetTester tester, String label) =>
        tester.widget(find.widgetWithText(MenuItemButton, label));

    Color? textColor(WidgetTester tester, String label) {
      final button = item(tester, label);
      return button.style?.foregroundColor?.resolve({
        if (button.onPressed == null) WidgetState.disabled,
      });
    }

    testWidgets('the text and the icon are the error color, other items '
        'are not', (tester) async {
      await menu(tester, enabled: true);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      final scheme = Theme.of(tester.element(find.text('Remove'))).colorScheme;
      expect(textColor(tester, 'Remove'), scheme.error);
      expect(
        item(tester, 'Remove').style?.iconColor?.resolve(const {}),
        scheme.error,
      );
      expect(textColor(tester, 'Other'), isNull);
    });

    testWidgets('a disabled item keeps the ordinary disabled look', (
      tester,
    ) async {
      await menu(tester, enabled: false);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Remove'), isNull);
    });
  });
}
