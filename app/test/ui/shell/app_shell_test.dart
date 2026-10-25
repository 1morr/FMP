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
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/radio/radio_page.dart';
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
  group('navigation per window class (ADR 0024 §決定 3, ADR 0033 §決定 5)', () {
    const labels = ['Home', 'Search', 'Library', 'Queue', 'Radio', 'Settings'];
    testWidgets('a short landscape phone scrolls the rail instead of '
        'overflowing', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(
        tester,
        // 橫向手機扣掉狀態列與手勢列後約 370dp。
        size: const Size(914, 360),
        at: ShellDestination.home,
      );
      expect(tester.takeException(), isNull);

      final settings = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Settings'),
      );
      await tester.ensureVisible(settings);
      await tester.pumpAndSettle();
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        ShellDestination.settings.index,
      );
    });

    for (final (width, expected) in [
      (400.0, NavigationBar),
      (700.0, NavigationRail),
      (1000.0, NavigationRail),
      (1400.0, NavigationDrawer),
      (1700.0, NavigationDrawer),
    ]) {
      testWidgets('$width wide uses $expected', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(
          tester,
          size: Size(width, 800),
          at: ShellDestination.home,
        );

        for (final type in [NavigationBar, NavigationRail, NavigationDrawer]) {
          expect(
            find.byType(type),
            type == expected ? findsOneWidget : findsNothing,
            reason: '$type at $width',
          );
        }
        // 三種導覽元件都是同樣六個項目（ADR 0035 §決定 2）。
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
        expect(count, 6, reason: 'destinations at $width');
        for (final label in labels) {
          expect(
            find.descendant(
              of: find.byType(expected),
              matching: find.text(label),
            ),
            findsOneWidget,
            reason: '$label at $width',
          );
        }
        // 順序：首頁｜搜尋｜音樂庫｜佇列｜電台｜設定。
        final xs = [
          for (final label in labels)
            tester.getCenter(
              find.descendant(
                of: find.byType(expected),
                matching: find.text(label),
              ),
            ),
        ];
        final along = expected == NavigationBar
            ? [for (final offset in xs) offset.dx]
            : [for (final offset in xs) offset.dy];
        expect(along, orderedEquals([...along]..sort()), reason: 'order');
      });
    }

    testWidgets('the app opens on Home', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);

      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        ShellDestination.home.index,
      );
    });

    for (final (destination, page) in [
      (ShellDestination.search, SearchPage),
      (ShellDestination.library, LibraryPage),
      (ShellDestination.queue, QueuePage),
      (ShellDestination.radio, RadioPage),
      (ShellDestination.settings, SettingsPage),
    ]) {
      testWidgets('selecting ${destination.name} shows its page', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(
          tester,
          at: ShellDestination.home,
          collapsePanel: true,
        );

        await h.open(tester, destination);

        expect(find.byType(page).hitTestable(), findsOneWidget);
        expect(find.byType(HomePage).hitTestable(), findsNothing);
      });
    }

    testWidgets('pages read the width of the content area', (tester) async {
      final h = ShellHarness();
      // 視窗 900 是 expanded，扣掉導覽列之後的內容區是 medium。
      await h.pumpShell(tester, size: const Size(900, 700));
      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(find.byType(VerticalDivider), findsNothing);
    });
  });

  // ADR 0033 §決定 5：每個目的地有自己的巢狀 Navigator，內頁在內容區裡開。
  group('nested navigation', () {
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

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(400, 800), Size(1400, 800)]) {
      testWidgets('at ${size.width} History opens inside Library; the '
          'navigation and the player bar stay', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: size, at: ShellDestination.home);
        await h.play(tester, [summary('a')]);
        await h.openHistory(tester);

        // 看頁首的標題：頁面正中央可能是頁首與空狀態之間的空白，那裡不接點擊。
        expect(
          find
              .descendant(
                of: find.byType(HistoryPage),
                matching: find.text('Play history'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(LibraryPage).hitTestable(), findsNothing);
        expect(find.byType(PlayerBar).hitTestable(), findsOneWidget);
        expect(
          ShellHarness.navigationItem(ShellDestination.library).hitTestable(),
          findsOneWidget,
        );
        // 內頁在內容區裡：在導覽元件旁邊或上面，不蓋住它。
        final page = tester.getRect(find.byType(HistoryPage));
        final player = tester.getRect(find.byType(PlayerBar));
        expect(page.bottom, lessThanOrEqualTo(player.top));
      });
    }

    // 頁面轉場在頁外包一層有底色的 `ColoredBox`：頁面沒有自己的 Material 時，`ListTile` 的
    // 水波畫在外殼的 Material 上、被它蓋住（除錯版的斷言見 `import_ui_test.dart` 的匯入案例）。
    testWidgets('every page of a nested navigator paints on its own Material', (
      tester,
    ) async {
      MaterialType nearestMaterial(Finder page) => tester
          .widget<Material>(
            find.ancestor(of: page, matching: find.byType(Material)).first,
          )
          .type;

      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      for (final (destination, page) in [
        (ShellDestination.home, HomePage),
        (ShellDestination.search, SearchPage),
        (ShellDestination.library, LibraryPage),
        (ShellDestination.queue, QueuePage),
        (ShellDestination.radio, RadioPage),
        (ShellDestination.settings, SettingsPage),
      ]) {
        await h.open(tester, destination);
        expect(
          nearestMaterial(find.byType(page)),
          MaterialType.transparency,
          reason: '$page',
        );
      }

      await h.openHistory(tester);
      expect(
        nearestMaterial(find.byType(HistoryPage)),
        MaterialType.transparency,
      );
      await back(tester);

      await tester.runAsync(
        () => h
            .container(tester)
            .read(playlistRepositoryProvider)
            .create(name: 'Mine'),
      );
      for (var i = 0; i < 3; i++) {
        await h.loadSettings(tester);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();
      expect(
        nearestMaterial(find.byType(PlaylistDetailPage)),
        MaterialType.transparency,
      );
    });

    testWidgets('the back key closes the inner page first, then goes Home', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      final pops = await recordSystemPops(tester);
      await h.openHistory(tester);

      await back(tester);
      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
      expect(find.byType(HistoryPage), findsNothing);

      await back(tester);
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
      expect(pops, isEmpty);
    });

    testWidgets('on Home the back key closes "View all" before leaving', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playHistoryRepositoryProvider)
            .record(
              summary('a').toTrackInfo(),
              playedAt: DateTime(2026, 10, 15, 12),
              limit: 100,
            ),
      );
      await h.loadSettings(tester);
      final pops = await recordSystemPops(tester);

      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
      expect(find.byType(HomePage).hitTestable(), findsNothing);

      await back(tester);
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
      expect(pops, isEmpty, reason: 'the inner page held the back key');

      await back(tester);
      expect(pops, hasLength(1));
    });

    testWidgets('Esc closes the inner page; at the root it does nothing', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
      expect(find.byType(HistoryPage), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
    });

    testWidgets('the back button of the inner page closes it', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await tester.tap(find.byTooltip('Back (Esc)'));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
      expect(find.byTooltip('Back (Esc)'), findsNothing);
    });

    testWidgets('selecting the current destination again goes back to its '
        'root', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await h.open(tester, ShellDestination.library);
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
      expect(find.byType(HistoryPage), findsNothing);
    });

    testWidgets('another destination keeps its inner page', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await h.open(tester, ShellDestination.search);
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
      await h.open(tester, ShellDestination.library);

      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
    });

    // 選單開在巢狀 Navigator 的 overlay 裡（在外殼的快捷鍵底下）：以滑鼠打開時焦點在「⋯」上，
    // Esc 要先關選單，不是退出內頁。
    testWidgets('Esc closes a menu on an inner page before the page', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playHistoryRepositoryProvider)
            .record(
              summary('a').toTrackInfo(),
              playedAt: DateTime(2026, 10, 15, 12),
              limit: 100,
            ),
      );
      await h.loadSettings(tester);
      await h.openHistory(tester);

      await tester.tap(find.byTooltip('More options').first);
      await tester.pump();
      expect(find.text('Remove from history'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Remove from history'), findsNothing);
      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage), findsNothing);
    });

    // 對話框與播放頁在根 Navigator 上，蓋住整個外殼：返回鍵與 Esc 先關它們，內頁留著。
    testWidgets('a dialog over an inner page closes first', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(HistoryPage)),
          builder: (_) => const AlertDialog(title: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsNothing);
      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(HistoryPage)),
          builder: (_) => const AlertDialog(title: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('A dialog'), findsNothing);
      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
    });

    testWidgets('the player page over an inner page closes first', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.play(tester, [summary('a')]);
      await h.openHistory(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(PlayerBar.titleKey),
              matching: find.byType(Text),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);

      await back(tester);

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
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

    testWidgets('Ctrl+F from an inner page of another destination', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    // 搜尋框在搜尋目的地的根頁：搜尋自己有內頁時，Ctrl+F 先退回根。
    testWidgets('Ctrl+F from an inner page of Search goes back to its root', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(SearchPage))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Center(child: Text('Inner page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inner page').hitTestable(), findsOneWidget);

      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(find.text('Inner page'), findsNothing);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    // ADR 0035 §決定 7：Ctrl+Q 切到佇列目的地（不再開播放頁），焦點進內容區。
    testWidgets('Ctrl+Q selects the queue destination and focuses its page', (
      tester,
    ) async {
      final h = await playing(tester);
      // 在播那一列的指示器會一直動，`pumpAndSettle` 會一路等到歌播完：先減少動態。
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(QueueView).hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        ShellDestination.queue.index,
      );
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(focused.findAncestorWidgetOfExactType<QueueView>(), isNotNull);
      expect(h.controller.state, isA<Playing>());
    });

    testWidgets('Ctrl+Q with nothing queued shows the empty queue page', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);

      await chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
      expect(find.text('The queue is empty'), findsOneWidget);
    });

    testWidgets('Ctrl+Q from an inner page of another destination', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
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
      await h.pumpShell(tester, collapsePanel: true);
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
      // 頁面都在內容區的 IndexedStack 裡（目的地的根頁與巢狀導覽的內頁）。
      if (context.findAncestorWidgetOfExactType<IndexedStack>() != null) {
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

    // 內頁是巢狀 Navigator 裡的 route（自己的 FocusScope）：F6 進內容區要落在頁面的項目上，
    // 不是停在 route 的 scope 本身。
    testWidgets('F6 goes into an inner page and out again', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.openHistory(tester);

      await f6(tester);
      expect(region(tester), 'navigation');
      await f6(tester);
      expect(region(tester), 'content');
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(focused.findAncestorWidgetOfExactType<HistoryPage>(), isNotNull);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await f6(tester);
      expect(region(tester), 'navigation');
    });

    testWidgets('F6 goes into the queue page', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));
      await h.openQueue(tester);

      await f6(tester);
      expect(region(tester), 'navigation');
      await f6(tester);
      expect(region(tester), 'content');
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(focused.findAncestorWidgetOfExactType<QueueView>(), isNotNull);
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

    testWidgets(
      'a song of a disabled source is skipped with that as the reason',
      (tester) async {
        final h = ShellHarness(
          sourceUnavailable: (ref, id) =>
              id == 'fmp-test' ? 'Source disabled' : null,
        );
        h.plugin.respond = (request) => request.sourceId == 'a'
            ? throw Unsupported(pluginId: 'fmp-test')
            : [candidate('${request.sourceId}.m4a')];
        await h.pumpShell(tester);

        await h.play(tester, [summary('a'), summary('b')]);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Skipped "Song a": Source disabled'), findsOneWidget);
      },
    );

    // 下面兩個是防過度套用的負面測試：還原改動後它們不會變紅，這是預期的。
    testWidgets('only an unsupported error is reworded for a disabled source', (
      tester,
    ) async {
      final h = ShellHarness(sourceUnavailable: (ref, id) => 'Source disabled');
      h.plugin.respond = (request) => request.sourceId == 'a'
          ? throw NotFound(pluginId: 'fmp-test')
          : [candidate('${request.sourceId}.m4a')];
      await h.pumpShell(tester);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Skipped "Song a": Not found. It may have been removed.'),
        findsOneWidget,
      );
    });

    testWidgets('a generic unsupported error keeps the generic reason', (
      tester,
    ) async {
      final h = ShellHarness();
      h.plugin.respond = (request) => request.sourceId == 'a'
          ? throw Unsupported(pluginId: 'fmp-test')
          : [candidate('${request.sourceId}.m4a')];
      await h.pumpShell(tester);

      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Skipped "Song a": Something went wrong.'),
        findsOneWidget,
      );
    });

    testWidgets('stopping at the only song of a disabled source says so', (
      tester,
    ) async {
      final h = ShellHarness(sourceUnavailable: (ref, id) => 'Source disabled');
      h.plugin.respond = (_) => throw Unsupported(pluginId: 'fmp-test');
      await h.pumpShell(tester);

      await h.play(tester, [summary('a')]);
      await tester.pumpAndSettle();

      expect(
        find.text("Can't play \"Song a\": Source disabled"),
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
    // 在第一個目的地放行：根 route 沒得 pop，Flutter 呼叫 SystemNavigator.pop。
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

    for (final destination in [
      ShellDestination.search,
      ShellDestination.library,
      ShellDestination.queue,
      ShellDestination.radio,
      ShellDestination.settings,
    ]) {
      testWidgets('on ${destination.name} it goes back to Home', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, at: ShellDestination.home);
        final pops = await recordSystemPops(tester);

        await h.open(tester, destination);
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(find.byType(HomePage).hitTestable(), findsOneWidget);
        expect(pops, isEmpty);
      });
    }

    testWidgets('on Home it lets the system leave the app', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      final pops = await recordSystemPops(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(pops, hasLength(1));
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
    });
  });
}
