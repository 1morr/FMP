import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/player_tab.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_artwork.dart';
import '../support/shell_harness.dart';

// M2 PR 18a：播放頁（design §9.3、§9.5、§9.6）。每個測試從外殼開始，點播放列的曲名
// 與封面那一塊開頁，和使用者一樣。

const _close = 'Close the player (Esc)';
const _showLyrics = 'Show lyrics (Ctrl+L)';
const _more = 'More';

/// 播放列上的曲名（點它開播放頁）。
final _barTitle = find
    .descendant(of: find.byKey(PlayerBar.titleKey), matching: find.byType(Text))
    .first;

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// 外殼開好、佇列裡兩首（播第一首）；還沒開播放頁。
Future<ShellHarness> _pumpPlaying(
  WidgetTester tester, {
  Size size = const Size(1000, 700),
  ShellHarness? harness,
  bool playing = true,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpShell(tester, size: size);
  if (playing) {
    await h.play(tester, [summary('a'), summary('b')]);
  } else {
    h.controller.addToQueue([
      summary('a').toTrackInfo(),
      summary('b').toTrackInfo(),
    ]);
    await tester.pump();
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 200));
  return h;
}

/// 點播放列的曲名與封面那一塊開播放頁。
Future<void> _openByTap(WidgetTester tester) async {
  await tester.tap(_barTitle);
  await tester.pumpAndSettle();
  expect(find.byType(PlayerPage), findsOneWidget);
}

/// 記住的分頁（資料庫要真的事件迴圈）。
Future<PlayerTab?> _storedTab(WidgetTester tester, ShellHarness h) async {
  // 寫入與讀取都經資料庫的執行緒，先讓還沒完成的寫入跑完。
  final state = await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return h.container(tester).read(layoutStateRepositoryProvider).read();
  });
  return state!.playerTab;
}

Future<void> _rememberTab(
  WidgetTester tester,
  ShellHarness h,
  PlayerTab tab,
) async {
  await tester.runAsync(
    () => h
        .container(tester)
        .read(layoutStateRepositoryProvider)
        .write(playerTab: tab),
  );
  await h.loadSettings(tester);
}

void main() {
  group('opening and closing', () {
    testWidgets('tapping the title and artwork opens the page, a button does '
        'not', (tester) async {
      await _pumpPlaying(tester);
      expect(find.byType(PlayerPage), findsNothing);

      await tester.tap(find.byTooltip('Next (Ctrl+→)'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      await tester.tap(find.byTooltip('Shuffle (Ctrl+S)'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);

      await _openByTap(tester);
    });

    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
    ]) {
      testWidgets('the bar opens it at $name too', (tester) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);
      });
    }

    testWidgets('the collapse button closes it', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(find.byTooltip(_close), findsOneWidget);
      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('Esc closes it', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('with a dialog open Esc closes the dialog first', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(PlayerPage)),
          builder: (_) => const AlertDialog(content: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('Esc closes the speed menu before the page', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playback speed'));
      await tester.pumpAndSettle();
      expect(find.text('1.5×'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1.5×'), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('the back key closes only the page', (tester) async {
      await _pumpPlaying(tester);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await _openByTap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      // 外殼還停在歷史頁，沒有被返回鍵帶回搜尋。
      expect(find.text('No play history yet'), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('focus returns to the player bar after closing', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Open the player'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open the player');
    });

    // 關閉的轉場中播放頁不收點擊，點擊落到底下的播放列：這時再開的播放頁不能被舊的
    // route 在轉場結束、被丟掉時標成「沒開」，否則提示會回到播放列的高度、再按 Ctrl+L
    // 又會推第二個。
    testWidgets('reopening it while it is still closing keeps it open', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_barTitle, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(h.container(tester).read(playerPageOpenProvider), isTrue);

      await _chord(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);

      // The first page giving the focus back must not pull it out of the new
      // one: Esc still reaches the page.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('a page opened by Ctrl+Q gives the focus back to where it '
        'was', (tester) async {
      await _pumpPlaying(tester);
      // F6 puts the focus on the first item of the navigation region.
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      final before = FocusManager.instance.primaryFocus;
      expect(before, isNotNull);

      await _chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(before));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, before);
    });

    // 佇列在 push 之後、頁面第一次 build 之前就空了：頁面的 listen 看不到「變空」那一次，
    // 但也不能留下一個沒有收合鈕、沒有快捷鍵的空白頁。
    testWidgets('it closes itself when the queue is empty by its first frame', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await tester.tap(_barTitle);
      h.controller.clear();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
    });

    testWidgets('it closes itself when the queue is cleared', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      h.controller.clear();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+L and Ctrl+Q open the page when it is closed', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(await _storedTab(tester, h), PlayerTab.queue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);

      await _chord(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(await _storedTab(tester, h), PlayerTab.lyrics);
      expect(find.text('No lyrics'), findsOneWidget);
    });

    testWidgets('they do nothing while the queue is empty', (tester) async {
      await ShellHarness().pumpShell(tester);

      await _chord(tester, LogicalKeyboardKey.keyL);
      await _chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('Ctrl+L and Ctrl+Q switch the tabs on the page', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      await _chord(tester, LogicalKeyboardKey.keyQ);
      expect(find.text('Song b'), findsWidgets);
      expect(await _storedTab(tester, h), PlayerTab.queue);

      await _chord(tester, LogicalKeyboardKey.keyL);
      expect(await _storedTab(tester, h), PlayerTab.lyrics);
      expect(find.text('No lyrics'), findsOneWidget);
    });

    testWidgets('the playback keys work on the page', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      expect(h.controller.state, isA<Playing>());

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.state, isA<Paused>());

      await _chord(tester, LogicalKeyboardKey.keyS);
      expect(h.controller.queue.shuffleEnabled, isTrue);
      await _chord(tester, LogicalKeyboardKey.keyR);
      expect(h.controller.queue.loopMode, LoopMode.all);
      await _chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.volume, closeTo(0.95, 0.001));
    });

    testWidgets('F6 moves between the controls and the tabs and Tab stays in '
        'the region', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      // F6 cycles through the two regions and comes back.
      final scopes = <FocusScopeNode>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        scopes.add(FocusManager.instance.primaryFocus!.enclosingScope!);
      }
      expect(scopes[1], isNot(scopes[0]));
      expect(scopes[2], scopes[0]);

      // Tab only walks inside the region: after many presses the focus is
      // still within the same scope.
      final scope = FocusManager.instance.primaryFocus!.enclosingScope;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus!.enclosingScope, scope);
      }
    });

    testWidgets('at extraLarge Ctrl+L moves the focus into the lyrics column', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1800, 900));
      await _openByTap(tester);

      await _chord(tester, LogicalKeyboardKey.keyL);

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Player page lyrics column',
      );
    });
  });

  group('layouts', () {
    List<String> shown(Iterable<String> tooltips) => [
      for (final tooltip in tooltips)
        if (find.byTooltip(tooltip).evaluate().isNotEmpty) tooltip,
    ];

    const controls = [
      'Shuffle (Ctrl+S)',
      'Previous (Ctrl+←)',
      'Pause (Space)',
      'Next (Ctrl+→)',
      'Repeat: off (Ctrl+R)',
      _more,
      _close,
    ];

    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
    ]) {
      testWidgets('$name: artwork and lyrics swap, the controls are below, no '
          'tabs', (tester) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);

        // The five controls and the menu, also on a phone held upright.
        expect(shown(controls), controls);
        expect(find.byType(TabBar), findsNothing);
        expect(find.text('No lyrics'), findsNothing);

        await tester.tap(find.bySemanticsLabel(_showLyrics));
        await tester.pump();
        expect(find.text('No lyrics'), findsOneWidget);

        await tester.tap(find.text('No lyrics'));
        await tester.pump();
        expect(find.text('No lyrics'), findsNothing);
      });

      testWidgets('$name: Ctrl+L shows the lyrics, Ctrl+Q opens the queue '
          'sheet', (tester) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);

        await _chord(tester, LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);
        expect(find.text('No lyrics'), findsNothing);
        expect(find.byType(TabBar), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);

        await _chord(tester, LogicalKeyboardKey.keyL);
        expect(find.text('No lyrics'), findsOneWidget);
      });
    }

    for (final (name, size) in [
      ('expanded', const Size(1000, 700)),
      ('large', const Size(1400, 800)),
    ]) {
      testWidgets('$name: two halves with the tabs Lyrics, Queue and Details', (
        tester,
      ) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);

        expect(shown(controls), controls);
        for (final tab in ['Lyrics', 'Queue', 'Details']) {
          expect(find.widgetWithText(Tab, tab), findsOneWidget);
        }
        final half = size.width / 2;
        final tabs = tester.getRect(find.byType(TabBar));
        expect(tabs.left, greaterThanOrEqualTo(half));
        expect(find.text('No lyrics'), findsOneWidget);
      });
    }

    testWidgets('the artwork is at most 420 and fits the window', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1400, 1200));
      await _openByTap(tester);

      final sizes = [
        for (final artwork in tester.widgetList<ArtworkImage>(
          find.byType(ArtworkImage),
        ))
          artwork.size,
      ];
      expect(sizes, contains(420));
      expect(sizes.where((size) => size > 420), isEmpty);

      // A short window shrinks it instead of overflowing.
      tester.view.physicalSize = const Size(1400, 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final shrunk = tester
          .widgetList<ArtworkImage>(find.byType(ArtworkImage))
          .map((artwork) => artwork.size);
      expect(shrunk.where((size) => size > 256 && size < 420), isNotEmpty);
    });

    testWidgets('extraLarge: three columns, the tabs are Queue and Details', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1800, 900));
      await _openByTap(tester);

      expect(shown(controls), controls);
      expect(find.widgetWithText(Tab, 'Lyrics'), findsNothing);
      expect(find.widgetWithText(Tab, 'Queue'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Details'), findsOneWidget);
      // The lyrics are their own column.
      expect(find.text('No lyrics'), findsOneWidget);
      final lyrics = tester.getRect(find.text('No lyrics'));
      final tabs = tester.getRect(find.byType(TabBar));
      expect(lyrics.right, lessThan(tabs.left));
      // About 1 : 1.15 : 0.9.
      final lyricsColumn = tester.getSize(
        find
            .ancestor(
              of: find.text('No lyrics'),
              matching: find.byType(FocusScope),
            )
            .first,
      );
      final tabsColumn = tester.getSize(
        find
            .ancestor(
              of: find.byType(TabBar),
              matching: find.byType(FocusScope),
            )
            .first,
      );
      expect(lyricsColumn.width / tabsColumn.width, closeTo(1.15 / 0.9, 0.05));
    });

    testWidgets('the layout follows the window when it is resized', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1000, 700));
      await _openByTap(tester);
      expect(find.byType(TabBar), findsOneWidget);

      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });
  });

  group('tabs', () {
    testWidgets('the queue tab lists the queue, marks the current song and '
        'jumps on tap', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();

      final rows = find.byType(ListTile);
      expect(rows, findsNWidgets(2));
      expect(tester.widget<ListTile>(rows.at(0)).selected, isTrue);
      expect(tester.widget<ListTile>(rows.at(1)).selected, isFalse);

      await tester.tap(
        find.descendant(of: rows.at(1), matching: find.text('Song b')),
      );
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.currentIndex, 1);
      expect(tester.widget<ListTile>(rows.at(1)).selected, isTrue);
    });

    testWidgets('a long queue builds only the rows in view', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 900));
      expect(
        h.controller.addToQueue([
          for (var i = 0; i < 5000; i++) summary('t$i').toTrackInfo(),
        ]),
        isTrue,
      );
      await tester.pump();
      await tester.pump();
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile).evaluate().length, lessThan(40));
    });

    testWidgets('the queue tab opens two rows above the current song', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 900));
      await h.play(tester, [
        for (var i = 0; i < 200; i++) summary('t$i'),
      ], index: 100);
      await tester.pump(const Duration(milliseconds: 200));
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      expect(list.scrollController!.offset, 98 * list.itemExtent!);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Song t100')),
        isA<ListTile>().having((tile) => tile.selected, 'selected', isTrue),
      );
    });

    testWidgets('during a temporary play no queue row is marked current', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      unawaited(h.controller.playTemporary(summary('x').toTrackInfo()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();

      final rows = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(rows, hasLength(2));
      expect(rows.where((row) => row.selected), isEmpty);
    });

    testWidgets('the details tab shows the song and its source', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Details'));
      await tester.pumpAndSettle();

      expect(find.text('Song a'), findsWidgets);
      expect(find.text('Uploader a'), findsWidgets);
      expect(find.text('3:05'), findsWidgets);
      expect(find.text('Test Source'), findsOneWidget);
    });

    testWidgets('the details name a source that is not installed by its id', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpApp(
        tester,
        const Scaffold(
          body: TrackDetails(
            track: TrackInfo(
              sourceTypeId: 'gone-source',
              sourceId: '1',
              title: 'Lost song',
            ),
          ),
        ),
      );

      expect(find.text('gone-source'), findsOneWidget);
    });

    testWidgets('a tab chosen is stored and still there when the page opens '
        'again', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      expect(await _storedTab(tester, h), isNull);

      await tester.tap(find.widgetWithText(Tab, 'Details'));
      await tester.pumpAndSettle();
      expect(await _storedTab(tester, h), PlayerTab.details);

      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();
      await _openByTap(tester);

      expect(find.text('Test Source'), findsOneWidget);
      final controller = DefaultTabController.maybeOf(
        tester.element(find.byType(TabBar)),
      );
      expect(controller, isNull);
      expect(
        tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        PlayerTab.details.index,
      );
    });

    testWidgets('a tab chosen on the page wins over a stored value that '
        'arrives later', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.widgetWithText(Tab, 'Details'));
      await tester.pumpAndSettle();

      await _rememberTab(tester, h, PlayerTab.queue);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        PlayerTab.details.index,
      );
    });

    testWidgets('the remembered tab is used from the first frame', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await _rememberTab(tester, h, PlayerTab.queue);
      await h.play(tester, [summary('a'), summary('b')]);

      await _openByTap(tester);

      expect(
        tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        PlayerTab.queue.index,
      );
    });

    testWidgets('at extraLarge a remembered lyrics tab shows the queue and '
        'keeps the memory', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1800, 900));
      await _rememberTab(tester, h, PlayerTab.lyrics);
      await h.play(tester, [summary('a'), summary('b')]);

      await _openByTap(tester);

      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.controller!.length, 2);
      expect(tabs.controller!.index, 0, reason: 'Queue is the first tab');
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(await _storedTab(tester, h), PlayerTab.lyrics);

      // Choosing Details there is a real choice and overwrites it.
      await tester.tap(find.widgetWithText(Tab, 'Details'));
      await tester.pumpAndSettle();
      expect(await _storedTab(tester, h), PlayerTab.details);
    });
  });

  group('speed', () {
    Future<void> openSpeedMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playback speed'));
      await tester.pumpAndSettle();
    }

    bool checked(WidgetTester tester, String label) {
      final item = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, label),
      );
      return (item.leadingIcon! as Visibility).visible;
    }

    testWidgets('the menu has the seven speeds and checks the current one', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await openSpeedMenu(tester);

      const labels = [
        '0.5×',
        '0.75×',
        '1.0×',
        '1.25×',
        '1.5×',
        '1.75×',
        '2.0×',
      ];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        [for (final label in labels) checked(tester, label)],
        [false, false, true, false, false, false, false],
      );
    });

    testWidgets('choosing one calls the controller and moves the check', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      await openSpeedMenu(tester);

      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();

      expect(h.controller.speed, 1.5);
      expect(h.backend.speed, 1.5);

      await openSpeedMenu(tester);
      expect(checked(tester, '1.5×'), isTrue);
      expect(checked(tester, '1.0×'), isFalse);
    });
  });

  group('status and progress', () {
    testWidgets('waiting for the network is shown on the page', (tester) async {
      final h = ShellHarness();
      h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_barTitle);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Waiting for the network'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.textContaining('Waiting for the network'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('after a restore the page shows the restored position', (
      tester,
    ) async {
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

      await _openByTap(tester);

      expect(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.text('1:23'),
        ),
        findsOneWidget,
      );
    });
  });

  group('glass', () {
    testWidgets('the panels blur the background', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(find.byType(BackdropFilter), findsWidgets);
    });

    testWidgets('high contrast makes them opaque', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a song with artwork gets a backdrop of it', (tester) async {
      final h = ShellHarness(artworkManager: FakeArtworkManager());
      await h.pumpShell(tester);
      await h.play(tester, [
        summary('a', artwork: TestArtwork.lightest.artwork),
      ]);
      await _openByTap(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.byType(ArtworkImage), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('toasts', () {
    testWidgets('the toast sits on the safe area while the page is open', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester, size: const Size(1000, 700));
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pump();
      final container = h.container(tester);
      final withBar = container.read(toastBottomInsetProvider);
      expect(withBar, greaterThan(24), reason: 'the bar is below the toast');

      await _openByTap(tester);
      await tester.pump();
      expect(container.read(toastBottomInsetProvider), 24);

      h.toaster.warning('A toast over the page');
      await tester.pumpAndSettle();
      final toast = tester.getRect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Material),
        ),
      );
      // 16dp of margin above the safe area.
      expect(toast.bottom, closeTo(700 - 24 - 16, 1));

      await tester.pumpAndSettle(const Duration(seconds: 7));
      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();
      expect(container.read(toastBottomInsetProvider), withBar);
    });
  });
}
