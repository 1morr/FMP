import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';
import '../support/home_shown.dart';

/// 目前畫面上（該目的地可見的）頁頂。
Finder _bar() => find.byType(PageAppBar).hitTestable();

void main() {
  group('every destination has a centered title (ADR 0035 §決定 2)', () {
    for (final (destination, title) in [
      (ShellDestination.home, 'Home'),
      (ShellDestination.library, 'Library'),
      (ShellDestination.queue, 'Queue'),
      (ShellDestination.radio, 'Radio'),
      (ShellDestination.settings, 'Settings'),
    ]) {
      for (final width in [400.0, 1000.0]) {
        testWidgets('${destination.name} at $width', (tester) async {
          final h = ShellHarness();
          await h.pumpShell(
            tester,
            size: Size(width, 800),
            at: ShellDestination.home,
            collapsePanel: true,
          );
          await h.open(tester, destination);
          await tester.pumpAndSettle();

          final bar = _bar();
          expect(bar, findsOneWidget);
          final titleText = find.descendant(
            of: bar,
            matching: find.text(title),
          );
          expect(titleText, findsOneWidget);
          expect(
            tester.getCenter(titleText).dx,
            closeTo(tester.getCenter(bar).dx, 1),
          );
        });
      }
    }
  });

  testWidgets('the search page puts the field in the bar, like the old app', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester, collapsePanel: true);

    expect(
      find.descendant(of: _bar(), matching: find.byType(TextField)),
      findsOneWidget,
    );
  });

  testWidgets('an inner page gets a back button, a root page does not', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester, collapsePanel: true);
    await h.open(tester, ShellDestination.library);
    expect(find.byTooltip('Back (Esc)'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'History'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back (Esc)'), findsOneWidget);
    expect(
      find.descendant(of: _bar(), matching: find.text('Play history')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back (Esc)'), findsNothing);
  });

  // 頁面不在自己的 Scaffold 裡：沒有每頁的 ScrollNotificationObserver 時，頁頂聽的是外殼的，
  // 側欄或別的頁一捲，這一頁的頁頂就變色（`PageSurface`）。
  testWidgets("only the page's own list scrolling under the bar tints it", (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(
      tester,
      size: const Size(914, 360),
      at: ShellDestination.home,
      expandRail: true,
      collapsePanel: true,
    );
    expect(_elevation(tester), 0);

    // 側欄（展開時是清單，矮視窗可捲）。
    await tester.dragFrom(const Offset(100, 300), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_elevation(tester), 0, reason: 'the rail scrolled');

    await h.open(tester, ShellDestination.settings);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(600, 300), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_elevation(tester), greaterThan(0), reason: 'its own list');

    // 側欄捲下去了：「首頁」先捲回來才點得到。
    await tester.ensureVisible(
      ShellHarness.navigationItem(ShellDestination.home),
    );
    await tester.pumpAndSettle();
    await h.open(tester, ShellDestination.home);
    await tester.pumpAndSettle();
    expect(homeShown, findsOneWidget);
    expect(_elevation(tester), 0, reason: 'another page scrolled');
  });
}

/// 頁頂的 Material 高度：清單捲到它下面時是主題的 `scrolledUnderElevation`。
double _elevation(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(of: _bar(), matching: find.byType(Material)).first,
    )
    .elevation;
