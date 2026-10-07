import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  Future<ShellHarness> openSettings(WidgetTester tester, double width) async {
    final h = ShellHarness();
    await h.pumpShell(tester, size: Size(width, 800));
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    return h;
  }

  // 內容區的寬度：視窗減掉導覽（rail 80、抽屜 360）。
  testWidgets(
    'expanded and wider: groups on the left, the first group on the right',
    (tester) async {
      final h = await openSettings(tester, 1000);

      expect(find.byType(AppearanceControls), findsOneWidget);
      expect(find.byType(RadioListTile<LocaleSetting?>), findsNWidgets(4));
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Appearance'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
            .selected,
        isFalse,
      );
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(
        tester.getCenter(find.widgetWithText(ListTile, 'Appearance')).dx,
        lessThan(tester.getTopLeft(find.byType(AppearanceControls)).dx),
      );

      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(find.byType(NetworkControls), findsOneWidget);
      expect(find.byType(AppearanceControls), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
            .selected,
        isTrue,
      );
    },
  );

  for (final width in [400.0, 700.0]) {
    testWidgets('$width wide: the list, then one group, then back', (
      tester,
    ) async {
      final h = await openSettings(tester, width);

      // 清單：沒有內容、沒有分隔線。
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.byType(AppearanceControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Network'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(find.byType(NetworkControls), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsNothing);
      expect(find.text('Network'), findsOneWidget, reason: 'the heading');

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.byType(NetworkControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsOneWidget);
    });
  }

  testWidgets(
    '400 wide: the system back key returns from a group to the list',
    (tester) async {
      final h = await openSettings(tester, 400);
      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();

      expect(find.byType(NetworkControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Network'), findsOneWidget);
      // 回到清單之後返回鍵歸外殼：回到第一個分頁（搜尋），設定頁看不到了。
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
    },
  );

  // 外殼以 IndexedStack 留著沒選的頁面：看不到的設定頁不能攔返回鍵。
  testWidgets('400 wide: a group left open does not hold the back key on '
      'another page', (tester) async {
    final h = await openSettings(tester, 400);
    await tester.tap(find.widgetWithText(ListTile, 'Network'));
    await h.loadSettings(tester);

    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();

    expect(await tester.binding.handlePopRoute(), isFalse);

    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    expect(find.byType(NetworkControls), findsOneWidget);
  });

  testWidgets('the group stays when the window crosses a breakpoint', (
    tester,
  ) async {
    final h = await openSettings(tester, 700);
    await tester.tap(find.widgetWithText(ListTile, 'Network'));
    await h.loadSettings(tester);

    tester.view.physicalSize = const Size(1400, 800);
    await tester.pump();
    await h.loadSettings(tester);

    expect(find.byType(NetworkControls), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
          .selected,
      isTrue,
    );
  });

  testWidgets('both appearance settings can go back to following the system', (
    tester,
  ) async {
    await openSettings(tester, 1000);

    expect(find.text('System'), findsOneWidget, reason: 'theme');
    expect(find.text('System default'), findsOneWidget, reason: 'language');
  });
}
