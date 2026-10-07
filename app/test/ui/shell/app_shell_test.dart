import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_audio_backend.dart';
import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

const _speakers = OutputDevice(id: 'wasapi/{a}', name: 'Speakers');

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
        // 三種導覽元件都是三個項目：搜尋、歷史、設定。
        final count = switch (expected) {
          NavigationBar =>
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .destinations
                .length,
          NavigationRail =>
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .destinations
                .length,
          _ =>
            tester
                .widget<NavigationDrawer>(find.byType(NavigationDrawer))
                .children
                .whereType<NavigationDrawerDestination>()
                .length,
        };
        expect(count, 3, reason: 'destinations at $width');
        for (final label in ['Search', 'History', 'Settings']) {
          expect(find.text(label), findsOneWidget, reason: '$label at $width');
        }
      });
    }

    testWidgets('selecting History shows the history page', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);

      await tester.tap(find.text('History'));
      await tester.pump();

      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
      expect(find.byType(SearchPage).hitTestable(), findsNothing);
    });

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

    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
    }) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    // 啟動恢復後還沒播：Shift+←／→ 移動的是恢復的起點（和拖進度條一樣）。先臨時
    // 播放再回到佇列時，以恢復的位置為準，不是臨時曲目最後的進度。
    testWidgets('Shift+arrows move the restored start, also after a temporary '
        'play', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      h.controller.restore(
        tracks: [summary('a').toTrackInfo()],
        currentIndex: 0,
        loopMode: LoopMode.off,
        shuffle: false,
        position: const Duration(seconds: 83),
        volume: 1,
        muted: false,
      );
      await tester.pump();
      await tester.pump();

      await chord(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(h.controller.restoredPosition, const Duration(seconds: 88));

      unawaited(h.controller.playTemporary(summary('b').toTrackInfo()));
      await tester.pump(const Duration(seconds: 2));
      unawaited(h.controller.next());
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Idle>());

      await chord(
        tester,
        LogicalKeyboardKey.arrowLeft,
        modifier: LogicalKeyboardKey.shiftLeft,
      );
      expect(h.controller.restoredPosition, const Duration(seconds: 83));
      expect(find.text('1:23'), findsOneWidget);
    });

    testWidgets('Ctrl+Up and Ctrl+Down change the volume by 5%, clamped', (
      tester,
    ) async {
      final h = await playing(tester);
      expect(h.controller.volume, 1);

      await chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.volume, 0.95);
      await chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.volume, 0.9);
      await chord(tester, LogicalKeyboardKey.arrowUp);
      await chord(tester, LogicalKeyboardKey.arrowUp);
      await chord(tester, LogicalKeyboardKey.arrowUp);
      expect(h.controller.volume, 1, reason: 'clamped at 100%');

      await h.controller.setVolume(0.02);
      await chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.volume, 0, reason: 'clamped at 0');
      expect(h.controller.muted, isFalse, reason: '0 is not mute');
    });

    testWidgets('Ctrl+Up while muted unmutes and adjusts', (tester) async {
      final h = await playing(tester);
      await h.controller.setVolume(0.5);
      await h.controller.toggleMute();
      expect(h.controller.muted, isTrue);

      await chord(tester, LogicalKeyboardKey.arrowUp);
      expect(h.controller.muted, isFalse);
      expect(h.controller.volume, 0.55);
    });

    testWidgets('Ctrl+S switches shuffle and Ctrl+R cycles the loop mode', (
      tester,
    ) async {
      final h = await playing(tester);

      await chord(tester, LogicalKeyboardKey.keyS);
      expect(h.controller.queue.shuffleEnabled, isTrue);
      await chord(tester, LogicalKeyboardKey.keyS);
      expect(h.controller.queue.shuffleEnabled, isFalse);

      for (final mode in [LoopMode.all, LoopMode.one, LoopMode.off]) {
        await chord(tester, LogicalKeyboardKey.keyR);
        expect(h.controller.queue.loopMode, mode);
      }
    });

    // 輸入框裡的規則：導覽類（Esc、F6、Ctrl+F、Ctrl+,）有效，其餘讓給輸入框。
    testWidgets('in the search field Ctrl+S, Ctrl+R and Ctrl+Up stay with the '
        'field; Esc leaves it', (tester) async {
      final h = await playing(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final field = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(field.hasPrimaryFocus, isTrue);

      await chord(tester, LogicalKeyboardKey.keyS);
      await chord(tester, LogicalKeyboardKey.keyR);
      await chord(tester, LogicalKeyboardKey.arrowUp);
      await chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.queue.shuffleEnabled, isFalse);
      expect(h.controller.queue.loopMode, LoopMode.off);
      expect(h.controller.volume, 1);
      expect(field.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field.hasFocus, isFalse, reason: 'Esc leaves the field');
      expect(h.controller.state, isA<Playing>());

      // 離開之後，同樣的鍵又是播放的快捷鍵。
      await chord(tester, LogicalKeyboardKey.keyS);
      expect(h.controller.queue.shuffleEnabled, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Esc outside an input does nothing to playback', (
      tester,
    ) async {
      final h = await playing(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(h.controller.state, isA<Playing>());
      expect(find.byType(AppShell), findsOneWidget);
    });

    // 對話框是另一個 route，焦點在它裡面：播放快捷鍵照 M1 不作用，Esc 由 Flutter
    // 內建的對話框行為關閉它。
    testWidgets('with a dialog open playback shortcuts do nothing and Esc '
        'closes the dialog', (tester) async {
      final h = await playing(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AppShell)),
          builder: (_) => const AlertDialog(title: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsOneWidget);

      await chord(tester, LogicalKeyboardKey.keyS);
      await chord(tester, LogicalKeyboardKey.keyR);
      await chord(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isFalse);
      expect(h.controller.queue.loopMode, LoopMode.off);
      expect(h.controller.volume, 1);
      expect(h.controller.state, isA<Playing>());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsNothing);
    });

    // 彈出的選單是 overlay，不是 route：以滑鼠打開的也要能以 Esc 關掉，焦點剛在
    // 搜尋框裡也一樣（外殼的 Esc 只在輸入框裡作用）。
    for (final (width, opener, item) in [
      (1000.0, 'Output device', 'System default'),
      (720.0, 'More', 'Shuffle'),
      (720.0, 'Volume (Ctrl+↑/↓)', null),
    ]) {
      testWidgets('Esc closes the "$opener" menu at $width', (tester) async {
        final h = ShellHarness(
          outputDeviceSelection: true,
          outputDevices: FakeOutputDevices(const [_speakers]),
        );
        await h.pumpShell(tester, size: Size(width, 700));
        await h.play(tester, [summary('a')]);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byType(TextField));
        await tester.pump();

        Finder opened() => item == null
            ? find.byTooltip('Mute')
            : find.widgetWithText(MenuItemButton, item);
        await tester.tap(find.byTooltip(opener));
        await tester.pump();
        expect(
          item == null ? opened() : find.text(item),
          findsWidgets,
          reason: 'the menu is open',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          item == null ? opened() : find.text(item),
          findsNothing,
          reason: 'Esc closes it',
        );
        expect(h.controller.state, isA<Playing>());
      });
    }

    testWidgets('the shortcuts are in the tooltips', (tester) async {
      await playing(tester);

      expect(find.byTooltip('Shuffle (Ctrl+S)'), findsOneWidget);
      expect(find.byTooltip('Repeat: off (Ctrl+R)'), findsOneWidget);
      expect(find.byTooltip('Previous (Ctrl+←)'), findsOneWidget);
      expect(find.byTooltip('Next (Ctrl+→)'), findsOneWidget);
      expect(find.byTooltip('Pause (Space)'), findsOneWidget);
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

  // design §7.9：控制器的事件在外殼轉成提示；文字依錯誤類別（ADR 0013）。
  group('playback toasts', () {
    testWidgets('a skipped song is named with the reason', (tester) async {
      final h = ShellHarness();
      h.plugin.respond = (request) => request.sourceId == 'a'
          ? throw Unavailable(
              reason: UnavailableReason.copyright,
              pluginId: 'fmp-test',
            )
          : [candidate('${request.sourceId}.m4a')];
      await h.pumpShell(tester);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.controller.queue.current?.sourceId, 'b');
      expect(
        find.text('Skipped "Song a": Not available: copyright restriction'),
        findsOneWidget,
      );
    });

    testWidgets('stopping at the only song says which and why', (tester) async {
      final h = ShellHarness();
      h.plugin.respond = (_) => throw NotFound(pluginId: 'fmp-test');
      await h.pumpShell(tester);

      await h.play(tester, [summary('a')]);
      await tester.pumpAndSettle();

      expect(h.controller.state, isA<Failed>());
      expect(
        find.text(
          "Can't play \"Song a\": Not found. It may have been removed.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('stopping after songs in a row says playback stopped', (
      tester,
    ) async {
      final h = ShellHarness();
      h.plugin.respond = (_) => throw NotFound(pluginId: 'fmp-test');
      await h.pumpShell(tester);

      await h.play(tester, [summary('a'), summary('b'), summary('c')]);
      await tester.pumpAndSettle();

      expect(h.controller.state, isA<Failed>());
      // 新的提示取代舊的：最後看到的是停下的那一則。
      expect(
        find.text('3 songs in a row could not be played; playback stopped'),
        findsOneWidget,
      );
    });

    testWidgets('a preview clip played as one is announced and marked', (
      tester,
    ) async {
      final h = ShellHarness();
      h.plugin.previewOnly = (_) => true;
      await h.pumpShell(tester);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playbackPreferencesProvider.notifier)
            .setSkipPreviewClips(false),
      );
      await h.loadSettings(tester);

      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.controller.state, isA<Playing>());
      expect(
        find.text('Only a preview of "Song a" is available'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.textContaining('Preview'),
        ),
        findsOneWidget,
      );
    });

    // design §7.5：輸出裝置失敗暫停並提示，不跳過。失敗的本來就是系統預設（沒有
    // 選過裝置）時沒有可以改用的，提示照 PR 13 說已暫停，不說改用系統預設。
    testWidgets('a failed system default output says playback paused', (
      tester,
    ) async {
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: FakeOutputDevices(const [_speakers]),
      );
      await h.pumpShell(tester);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));
      h.backend.failOutputDevice();
      await tester.pump();
      await tester.pump();

      expect(h.controller.state, isA<Paused>());
      expect(h.controller.queue.current?.sourceId, 'a');
      expect(
        find.text('The audio output device is unavailable; playback paused'),
        findsOneWidget,
      );
      expect(
        find.textContaining('switched to the system default'),
        findsNothing,
      );
    });

    // 擁有者 2026-10-07：選過的裝置失敗時暫停、這次改用系統預設並提示，偏好不清掉。
    testWidgets('a failed output device falls back to the system default', (
      tester,
    ) async {
      final devices = FakeOutputDevices(const [_speakers]);
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: devices,
      );
      await h.pumpShell(tester);
      await tester.runAsync(() => h.controller.selectOutputDevice(_speakers));
      await h.loadSettings(tester);
      expect(h.controller.outputDeviceState.selected, _speakers);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));
      h.backend.failOutputDevice();
      await tester.pump();
      await tester.pump();

      expect(h.controller.state, isA<Paused>());
      expect(h.controller.queue.current?.sourceId, 'a');
      expect(
        find.text(
          'The audio output device is unavailable; '
          'switched to the system default',
        ),
        findsOneWidget,
      );
      expect(devices.selections, [_speakers, null]);
      expect(h.controller.outputDeviceState.selected, isNull);
      // 記住的偏好還在。
      final preferences = await tester.runAsync(
        () => h.container(tester).read(playbackPreferencesProvider.future),
      );
      expect(preferences!.outputDevice, _speakers);

      // 按播放：從原位置繼續，不再選回失敗的裝置。
      await tester.tap(find.byTooltip('Play (Space)'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Playing>());
      expect(devices.selections, [_speakers, null]);
    });

    testWidgets('waiting for the network shows no toast', (tester) async {
      final h = ShellHarness();
      h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(minutes: 1));

      expect(
        h.controller.state,
        isA<Retrying>().having((s) => s.waitingForNetwork, 'waiting', true),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.textContaining('Waiting for the network'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('adding past the queue limit shows a toast each time', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    final tooMany = [
      for (var i = 0; i <= QueueModel.maxLength; i++)
        TrackInfo(sourceTypeId: 'fmp-test', sourceId: '$i', title: '$i'),
    ];
    const message =
        'The queue is full (10,000 songs at most); nothing was added';

    expect(h.controller.addToQueue(tooMany), isFalse);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(h.controller.queue.entries, isEmpty);

    // 提示消失、過了去重的 5 秒之後再試一次：同樣的事件也要送到。
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(h.controller.playNext(tooMany), isFalse);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
  });

  // ADR 0016 §決定 7：一個全域離線提示，在內容區頂端，不是 toast。
  group('the offline banner', () {
    Finder banner(String text) => find.descendant(
      of: find.byType(OfflineBanner),
      matching: find.text(text),
    );

    testWidgets('shows while offline, on every page, and goes away online', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(
        tester.getSize(find.byType(OfflineBanner)).height,
        0,
        reason: 'online takes no space',
      );

      await h.setNetwork(tester, NetworkStatus.noInterface);
      expect(banner('No network connection'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // 在內容區頂端：搜尋框在它下面。
      expect(
        tester.getBottomLeft(find.byType(OfflineBanner)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
      );

      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(banner('No network connection'), findsOneWidget);

      await h.setNetwork(tester, NetworkStatus.online);
      await h.setNetwork(tester, NetworkStatus.unreachable);
      expect(banner("Can't reach the network"), findsOneWidget);

      h
          .container(tester)
          .read(networkStatusProvider.notifier)
          .report(RequestOutcome.responded);
      await tester.pump();
      expect(find.text("Can't reach the network"), findsNothing);
      expect(find.text('No network connection'), findsNothing);
    });

    testWidgets('screen readers hear it when it appears', (tester) async {
      final handle = tester.ensureSemantics();
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);

      expect(
        tester.getSemantics(find.byType(OfflineBanner)),
        isSemantics(isLiveRegion: true, label: 'No network connection'),
      );
      handle.dispose();
    });
  });
  group('the back key (design §9.1)', () {
    // 在第一個分頁放行：根 route 沒得 pop，Flutter 呼叫 SystemNavigator.pop。
    Future<List<MethodCall>> recordSystemPops(WidgetTester tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    for (final label in ['History', 'Settings']) {
      testWidgets('on $label it goes back to Search', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester);
        final pops = await recordSystemPops(tester);

        await tester.tap(find.text(label));
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
        expect(pops, isEmpty);
      });
    }

    testWidgets('on Search it lets the system leave the app', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      final pops = await recordSystemPops(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(pops, hasLength(1));
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
    });
  });
}
