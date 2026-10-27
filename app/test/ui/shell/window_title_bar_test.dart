import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/window_title_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_window_chrome.dart';
import '../support/shell_harness.dart';

// U PR 15：Windows 的自繪標題列（ADR 0035 §決定 6，design §10）。視窗動作經假的 `WindowChrome`。

/// 語意樹裡以 [name] 為標籤或 tooltip 的節點（IconButton 的 tooltip 進 `tooltip`）。
SemanticsFinder _semanticsNamed(String name) => find.semantics.byPredicate(
  (node) => node.label == name || node.tooltip == name,
);

void main() {
  for (final (name, size) in [
    ('compact', const Size(400, 800)),
    ('medium', const Size(700, 800)),
    ('large', const Size(1400, 800)),
  ]) {
    testWidgets('the shell has a 36dp bar with the app name at the top at '
        '$name', (tester) async {
      final chrome = FakeWindowChrome();
      await ShellHarness(windowChrome: chrome)
          .pumpShell(tester, size: size, at: ShellDestination.home);

      final bar = find.byType(WindowTitleBar);
      expect(bar, findsOneWidget);
      expect(tester.getTopLeft(bar), Offset.zero);
      expect(tester.getSize(bar), Size(size.width, 36));
      expect(
        find.descendant(of: bar, matching: find.text('FMP')),
        findsOneWidget,
      );
    });
  }

  testWidgets('a platform without a custom title bar has none', (tester) async {
    await ShellHarness().pumpShell(tester, at: ShellDestination.home);

    expect(find.byType(WindowTitleBar), findsNothing);
  });

  testWidgets('the three buttons call the window', (tester) async {
    final chrome = FakeWindowChrome();
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);

    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Maximize'));
    await tester.pump();
    // 最大化之後這顆鈕變成還原。
    expect(find.byTooltip('Maximize'), findsNothing);
    await tester.tap(find.byTooltip('Restore'));
    await tester.tap(find.byTooltip('Close'));

    expect(chrome.calls, [
      'minimize',
      'toggleMaximize',
      'toggleMaximize',
      'close',
    ]);
  });

  testWidgets('the maximize button follows the window being maximized', (
    tester,
  ) async {
    final chrome = FakeWindowChrome(maximized: true);
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);
    expect(find.byTooltip('Restore'), findsOneWidget);

    // 系統自己還原（拖離螢幕邊緣、Win＋↓）。
    chrome.setMaximized(false);
    await tester.pump();

    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(chrome.calls, isEmpty);
  });

  testWidgets('double tapping the empty bar toggles maximize', (tester) async {
    final chrome = FakeWindowChrome();
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);

    // 名稱右邊的空白處。
    final spot = tester.getCenter(find.byType(WindowTitleBar));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(chrome.calls, ['toggleMaximize']);
  });

  testWidgets('dragging the empty bar moves the window', (tester) async {
    final chrome = FakeWindowChrome();
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);

    await tester.dragFrom(
      tester.getCenter(find.byType(WindowTitleBar)),
      const Offset(60, 20),
    );
    // 雙擊辨識器的計時器。
    await tester.pump(const Duration(milliseconds: 500));

    expect(chrome.calls, ['startDragging']);
  });

  testWidgets('dragging a window button does not move the window', (
    tester,
  ) async {
    final chrome = FakeWindowChrome();
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);

    await tester.drag(find.byTooltip('Minimize'), const Offset(-60, 0));
    await tester.pump();

    expect(chrome.calls, isNot(contains('startDragging')));
  });

  testWidgets('the bar is not a stop on the Tab order', (tester) async {
    final chrome = FakeWindowChrome();
    await ShellHarness(windowChrome: chrome)
        .pumpShell(tester, at: ShellDestination.home);

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus?.context;
      expect(
        focus?.findAncestorWidgetOfExactType<WindowTitleBar>(),
        isNull,
        reason: 'Tab $i',
      );
    }
  });

  // ADR 0035 §決定 6：標題列在根 Navigator 外面（`WindowFrame`），所有 route 共用同一條。
  group('over every route', () {
    Future<void> pushFullScreen(WidgetTester tester) async {
      unawaited(
        Navigator.of(
          tester.element(find.byType(AppShell)),
          rootNavigator: true,
        ).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Full screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Full screen'), findsOneWidget);
    }

    testWidgets('a root full-screen route has the bar, exactly once', (
      tester,
    ) async {
      final chrome = FakeWindowChrome();
      await ShellHarness(windowChrome: chrome)
          .pumpShell(tester, at: ShellDestination.home);

      await pushFullScreen(tester);

      expect(find.byType(WindowTitleBar), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      expect(chrome.calls, ['close']);
    });

    testWidgets('the buttons stay in the semantics tree while a dialog is '
        'open', (tester) async {
      final handle = tester.ensureSemantics();
      await ShellHarness(windowChrome: FakeWindowChrome())
          .pumpShell(tester, at: ShellDestination.home);
      expect(_semanticsNamed('Minimize'), findsOneWidget, reason: 'no dialog');
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AppShell)),
          builder: (_) => const AlertDialog(title: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsOneWidget);

      for (final label in ['Minimize', 'Maximize', 'Close']) {
        expect(_semanticsNamed(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('a tooltip shows on hover without an Overlay error', (
      tester,
    ) async {
      await ShellHarness(windowChrome: FakeWindowChrome())
          .pumpShell(tester, at: ShellDestination.home);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Minimize')));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Minimize'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    });

    testWidgets('the toast still floats at the bottom, not under the bar', (
      tester,
    ) async {
      final h = ShellHarness(windowChrome: FakeWindowChrome());
      await h.pumpShell(tester, at: ShellDestination.home);

      h.toaster.info('Saved');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final toast = tester.getRect(find.text('Saved'));
      final bar = tester.getRect(find.byType(WindowTitleBar));
      expect(toast.top, greaterThan(bar.bottom));
      expect(toast.bottom, lessThanOrEqualTo(700));
      expect(toast.center.dy, greaterThan(350));
    });
  });
}
