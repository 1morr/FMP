import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  group('navigation per window class (ADR 0024 §決定 3)', () {
    for (final (width, expected) in [
      (400.0, NavigationBar),
      (700.0, NavigationRail),
      (1000.0, NavigationRail),
      (1400.0, NavigationDrawer),
      (1700.0, NavigationDrawer),
    ]) {
      testWidgets('$width wide uses $expected', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: Size(width, 800));

        for (final type in [NavigationBar, NavigationRail, NavigationDrawer]) {
          expect(
            find.byType(type),
            type == expected ? findsOneWidget : findsNothing,
            reason: '$type at $width',
          );
        }
      });
    }

    testWidgets('selecting a destination switches the page', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
      expect(find.byType(SearchPage).hitTestable(), findsNothing);
    });

    testWidgets('pages read the width of the content area', (tester) async {
      final h = ShellHarness();
      // 視窗 900 是 expanded，扣掉導覽列之後的內容區是 medium。
      await h.pumpShell(tester, size: const Size(900, 700));
      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(find.byType(VerticalDivider), findsNothing);
    });
  });

  group('the bottom inset for toasts (ADR 0023 §決定 2)', () {
    double inset(WidgetTester tester, ShellHarness h) =>
        h.container(tester).read(toastBottomInsetProvider);

    testWidgets('compact: the player bar and the navigation bar', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(400, 800));
      await tester.pump();
      final navigationBar = tester.getSize(find.byType(NavigationBar)).height;
      expect(inset(tester, h), navigationBar);

      await h.play(tester, [summary('a')]);
      await tester.pump();
      final playerBar = tester.getSize(find.byType(PlayerBar)).height;
      expect(playerBar, greaterThan(0));
      expect(inset(tester, h), navigationBar + playerBar);
    });

    testWidgets('wider: only the player bar, 0 without one', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.pump();
      expect(inset(tester, h), 0);

      await h.play(tester, [summary('a')]);
      await tester.pump();
      expect(inset(tester, h), tester.getSize(find.byType(PlayerBar)).height);
    });

    testWidgets('a toast sits above the player bar', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump();

      h.toaster.info('Above the bar');
      await tester.pumpAndSettle();
      final toast = tester.getRect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Material),
        ),
      );
      expect(
        toast.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(PlayerBar)).top),
      );
    });
  });

  group('shortcuts (ADR 0024 §決定 8)', () {
    Duration position(ShellHarness h, WidgetTester tester) =>
        h.container(tester).read(playbackProgressProvider).value!.position;

    Future<ShellHarness> playing(WidgetTester tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b'), summary('c')]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.state, isA<Playing>());
      return h;
    }

    testWidgets('space toggles playback outside an input', (tester) async {
      final h = await playing(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.state, isA<Paused>());
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.state, isA<Playing>());
    });

    testWidgets('text-editing keys in the search field stay in the field', (
      tester,
    ) async {
      final h = await playing(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'lofi');

      // 外殼不處理，交給 App 根的文字編輯快捷鍵（停止傳遞、不算處理），
      // 平台再把字元送進輸入框。
      final space = await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(space, isFalse, reason: 'left to the text input');
      tester.testTextInput.enterText('lofi beats');
      await tester.pump();
      expect(h.controller.state, isA<Playing>());
      expect(find.text('lofi beats'), findsOneWidget);

      // Ctrl／Shift 加方向鍵在輸入框裡是移動游標與選取。
      final before = position(h, tester);
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(h.controller.queue.currentIndex, 0);
      expect(h.backend.openedAt, hasLength(1));
      // 只有播放本身前進的 0.4 秒，沒有快轉 5 秒。
      expect(
        position(h, tester) - before,
        lessThan(const Duration(seconds: 1)),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Ctrl+arrows change the track, Shift+arrows seek', (
      tester,
    ) async {
      final h = await playing(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.currentIndex, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.currentIndex, 0);

      await tester.pump(const Duration(seconds: 10));
      final before = h.backend.openedAt.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 60));
      expect(h.backend.openedAt, hasLength(before), reason: 'no reload');
      final forward = position(h, tester);
      expect(forward, greaterThanOrEqualTo(const Duration(seconds: 15)));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 60));
      expect(position(h, tester), lessThan(forward));
    });

    testWidgets('Ctrl+F goes to search and focuses the field', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.tap(find.text('Settings'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();

      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    // 已經在那一頁時不換頁、不重建：焦點不能等下一幀（閒著時不會有下一幀）。
    testWidgets('Ctrl+F and Ctrl+, on their own page move focus at once', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      final field = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;

      Future<void> ctrl(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pumpAndSettle();
        expect(field.hasFocus, isFalse, reason: 'F6 went to the navigation');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.idle();
      }

      await ctrl(LogicalKeyboardKey.keyF);
      expect(field.hasPrimaryFocus, isTrue);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      await ctrl(LogicalKeyboardKey.comma);
      final focus = FocusManager.instance.primaryFocus?.context;
      expect(focus?.findAncestorWidgetOfExactType<SettingsPage>(), isNotNull);
    });

    testWidgets('Ctrl+, goes to settings, also from the search field', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();

      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.byType(EditableText, skipOffstage: false),
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
    });
  });

  group('focus regions (ADR 0024 §決定 8)', () {
    /// 焦點在哪一區：導覽、內容、播放列。
    String? region(WidgetTester tester) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return null;
      if (context.findAncestorWidgetOfExactType<NavigationRail>() != null) {
        return 'navigation';
      }
      if (context.findAncestorWidgetOfExactType<PlayerBar>() != null) {
        return 'player bar';
      }
      if (context.findAncestorWidgetOfExactType<SearchPage>() != null ||
          context.findAncestorWidgetOfExactType<SettingsPage>() != null) {
        return 'content';
      }
      return null;
    }

    Future<void> f6(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
    }

    testWidgets('F6 cycles navigation, content and player bar', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));

      await f6(tester);
      expect(region(tester), 'navigation');
      await f6(tester);
      expect(region(tester), 'content');
      await f6(tester);
      expect(region(tester), 'player bar');
      await f6(tester);
      expect(region(tester), 'navigation');
    });

    testWidgets('F6 skips the player bar while nothing is queued', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);

      await f6(tester);
      expect(region(tester), 'navigation');
      await f6(tester);
      expect(region(tester), 'content');
      await f6(tester);
      expect(region(tester), 'navigation');
    });

    testWidgets('Tab stays inside a region', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));
      await f6(tester);
      await f6(tester);
      await f6(tester);
      expect(region(tester), 'player bar');

      final seen = <String?>{};
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(region(tester));
      }
      expect(seen, {'player bar'});
    });
  });

  testWidgets('playback that stops failed shows a toast', (tester) async {
    final h = ShellHarness();
    h.plugin.respond = (_) => throw NotFound(pluginId: 'fmp-test');
    await h.pumpShell(tester);

    await h.play(tester, [summary('a')]);
    await tester.pumpAndSettle();

    expect(h.controller.state, isA<Failed>());
    expect(find.text('Not found. It may have been removed.'), findsOneWidget);
  });
}
