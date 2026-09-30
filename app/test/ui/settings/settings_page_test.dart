import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  Future<void> openSettings(WidgetTester tester, double width) async {
    final h = ShellHarness();
    await h.pumpShell(tester, size: Size(width, 800));
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    expect(find.byType(AppearanceControls), findsOneWidget);
    expect(find.byType(RadioListTile<LocaleSetting?>), findsNWidgets(4));
  }

  // 內容區的寬度：視窗減掉導覽（rail 80、抽屜 360）。
  testWidgets(
    'expanded and wider: groups on the left, the group on the right',
    (tester) async {
      await openSettings(tester, 1000);

      final group = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Appearance'),
      );
      expect(group.selected, isTrue);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(
        tester.getCenter(find.widgetWithText(ListTile, 'Appearance')).dx,
        lessThan(tester.getTopLeft(find.byType(AppearanceControls)).dx),
      );
    },
  );

  for (final width in [400.0, 700.0]) {
    testWidgets('$width wide: one column', (tester) async {
      await openSettings(tester, width);

      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsNothing);
      expect(find.text('Appearance'), findsOneWidget, reason: 'the heading');
    });
  }

  testWidgets('both settings can go back to following the system', (
    tester,
  ) async {
    await openSettings(tester, 1000);

    expect(find.text('System'), findsOneWidget, reason: 'theme');
    expect(find.text('System default'), findsOneWidget, reason: 'language');
  });
}
