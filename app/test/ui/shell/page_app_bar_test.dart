import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

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
}
