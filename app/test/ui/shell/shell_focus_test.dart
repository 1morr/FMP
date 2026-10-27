import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/debug/debug_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

/// 視窗跨過外殼斷點（600、840）時，外殼換導覽元件、內容區的子樹搬家，每個巢狀 Navigator
/// 的 `Focus(autofocus)` 會再搶一次焦點。根 Navigator 上有別的 route 時，焦點要留在那個
/// route 裡（U PR 15 的後續）。
void main() {
  const wide = Size(1200, 800);
  const medium = Size(700, 800);
  const compact = Size(500, 800);
  final crossings = [
    ('1200 to 500', wide, compact),
    ('500 to 1200', compact, wide),
    ('1200 to 700', wide, medium),
    ('700 to 1200', medium, wide),
    ('700 to 500', medium, compact),
    ('500 to 700', compact, medium),
  ];

  bool focusIn<T extends Widget>() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<T>() !=
      null;

  /// 焦點在 [page] 所在的 route 的 focus scope 裡（不在被蓋住的外殼裡）。
  bool routeHasFocus(WidgetTester tester, Finder page) =>
      FocusScope.of(tester.element(page)).hasFocus;

  Future<ShellHarness> openDebug(WidgetTester tester, Size size) async {
    final h = ShellHarness(flavor: AppFlavor.dev);
    await h.pumpShell(tester, size: size, collapsePanel: true);
    await tester.runAsync(
      () => h
          .container(tester)
          .read(developerSettingsRepositoryProvider)
          .write(developerMode: true),
    );
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Debug'));
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
    expect(find.byType(DebugPage), findsOneWidget);
    return h;
  }

  group('a root route on top while crossing a shell breakpoint', () {
    for (final (name, from, to) in crossings) {
      testWidgets('the debug page keeps the focus ($name)', (tester) async {
        await openDebug(tester, from);

        tester.view.physicalSize = to;
        await tester.pumpAndSettle();
        expect(routeHasFocus(tester, find.byType(DebugPage)), isTrue);
        // F6 and Esc keep working from there: the page is still on top and the
        // focus is still inside it.
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        expect(routeHasFocus(tester, find.byType(DebugPage)), isTrue);
      });
    }

    for (final (name, from, to) in crossings) {
      testWidgets('a plain root route keeps its own focus ($name)', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: from, collapsePanel: true);
        final node = FocusNode();
        addTearDown(node.dispose);
        h.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Focus(
                focusNode: node,
                autofocus: true,
                child: const Text('x'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(node.hasPrimaryFocus, isTrue);

        tester.view.physicalSize = to;
        await tester.pumpAndSettle();

        expect(node.hasPrimaryFocus, isTrue);
      });
    }

    for (final (name, from, to) in crossings) {
      testWidgets('a dialog over a root route keeps its focus ($name)', (
        tester,
      ) async {
        await openDebug(tester, from);
        final node = FocusNode();
        addTearDown(node.dispose);
        showDialog<void>(
          context: tester.element(find.byType(DebugPage)),
          builder: (_) => AlertDialog(
            content: Focus(
              focusNode: node,
              autofocus: true,
              child: const Text('d'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(node.hasPrimaryFocus, isTrue);

        tester.view.physicalSize = to;
        await tester.pumpAndSettle();

        expect(node.hasPrimaryFocus, isTrue);
      });
    }
  });

  group('only the shell showing', () {
    for (final (name, from, to) in crossings) {
      testWidgets('focus stays in the content ($name)', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: from, collapsePanel: true);
        await tester.tap(find.text('Settings').first);
        await h.loadSettings(tester);

        tester.view.physicalSize = to;
        await tester.pumpAndSettle();

        expect(focusIn<AppShell>(), isTrue);
        expect(focusIn<DebugPage>(), isFalse);
      });
    }
  });
}
