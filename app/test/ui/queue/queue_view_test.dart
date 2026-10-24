import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// M2 PR 18b：可編輯的佇列清單（design §7.3）；ADR 0035 起是佇列目的地的整頁。每個動作都經
// 控制器，從外殼開始，切到「佇列」導覽項，和使用者一樣。

const _clearTooltip = 'Clear the queue';
const _more = 'More options';

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// 佇列 [ids]（播第一首），切到佇列目的地。
Future<ShellHarness> _openQueue(
  WidgetTester tester, {
  Size size = const Size(1000, 800),
  List<String> ids = const ['a', 'b', 'c', 'd'],
  ShellHarness? harness,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpShell(tester, size: size);
  await h.play(tester, [for (final id in ids) summary(id)]);
  await tester.pump(const Duration(milliseconds: 200));
  await h.openQueue(tester);
  expect(find.byType(QueueView), findsOneWidget);
  return h;
}

List<String> _ids(ShellHarness h) => [
  for (final entry in h.controller.queue.entries) entry.track.sourceId,
];

Finder _row(String id) => find.widgetWithText(ListTile, 'Song $id');

Finder _moreOf(String id) =>
    find.descendant(of: _row(id), matching: find.byTooltip(_more));

Finder _handleOf(String id) =>
    find.descendant(of: _row(id), matching: find.byIcon(Icons.drag_handle));

/// 拖動 [id] 的把手 [rows] 列（正數往下），分幾步移動讓清單跟得上。
Future<void> _drag(WidgetTester tester, String id, int rows) async {
  final gesture = await tester.startGesture(tester.getCenter(_handleOf(id)));
  for (var step = 0; step < 8; step++) {
    await gesture.moveBy(Offset(0, rows * 64.0 / 8));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _setAutoScroll(WidgetTester tester, ShellHarness h) async {
  await tester.runAsync(
    () => h
        .container(tester)
        .read(playbackSettingsRepositoryProvider)
        .write(autoScrollToCurrent: true),
  );
  await h.loadSettings(tester);
}

class _ReasonNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

void main() {
  group('the list', () {
    testWidgets('a song of a source that cannot be used shows why instead of '
        'the uploader', (tester) async {
      final h = await _openQueue(
        tester,
        ids: ['a'],
        harness: ShellHarness(
          sourceUnavailable: (ref, id) =>
              id == 'gone' ? 'Source disabled' : null,
        ),
      );
      expect(
        h.controller.addToQueue([
          const TrackInfo(
            sourceTypeId: 'gone',
            sourceId: 'x',
            title: 'Song x',
            uploader: 'Someone',
          ),
        ]),
        isTrue,
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: _row('x'), matching: find.text('Source disabled')),
        findsOneWidget,
      );
      expect(find.text('Someone'), findsNothing);
      expect(
        find.descendant(of: _row('a'), matching: find.text('Uploader a')),
        findsOneWidget,
      );
    });

    testWidgets('the reason follows the source becoming unavailable', (
      tester,
    ) async {
      final unavailable = NotifierProvider<_ReasonNotifier, String?>(
        _ReasonNotifier.new,
      );
      final h = await _openQueue(
        tester,
        ids: ['a'],
        harness: ShellHarness(
          sourceUnavailable: (ref, id) => ref.watch(unavailable),
        ),
      );
      expect(
        find.descendant(of: _row('a'), matching: find.text('Uploader a')),
        findsOneWidget,
      );

      h.container(tester).read(unavailable.notifier).set('Source disabled');
      await tester.pump();

      expect(
        find.descendant(of: _row('a'), matching: find.text('Source disabled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row('a'), matching: find.text('Uploader a')),
        findsNothing,
      );
    });

    testWidgets('shows the count and one row per song, current marked', (
      tester,
    ) async {
      await _openQueue(tester);

      expect(find.text('4 in queue'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(tester.widget<ListTile>(_row('a')).selected, isTrue);
      expect(tester.widget<ListTile>(_row('b')).selected, isFalse);
    });

    testWidgets('tapping a row jumps to it', (tester) async {
      final h = await _openQueue(tester);

      await tester.tap(find.text('Song c'));
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.currentIndex, 2);
      expect(tester.widget<ListTile>(_row('c')).selected, isTrue);
    });

    testWidgets('the same song twice is two rows that move on their own', (
      tester,
    ) async {
      final h = await _openQueue(tester, ids: ['a', 'b', 'a', 'c']);
      final second = h.controller.queue.entries[2];

      expect(find.byType(ListTile), findsNWidgets(4));
      await tester.tap(
        find.descendant(of: _row('a').at(1), matching: find.byTooltip(_more)),
      );
      await tester.pump();
      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();

      expect(_ids(h), ['a', 'b', 'c']);
      expect(
        h.controller.queue.entries.any((entry) => identical(entry, second)),
        isFalse,
      );
      expect(tester.widget<ListTile>(_row('a')).selected, isTrue);
    });

    testWidgets('ten thousand songs build only the rows in view', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 900));
      expect(
        h.controller.addToQueue([
          for (var i = 0; i < QueueModel.maxLength; i++)
            summary('t$i').toTrackInfo(),
        ]),
        isTrue,
      );
      await tester.pump();
      await tester.pump();
      await h.openQueue(tester);

      expect(find.text('10000 in queue'), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
    });
  });

  group('dragging', () {
    testWidgets('a song dragged down lands where it was dropped', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      await _drag(tester, 'a', 2);

      expect(_ids(h), ['b', 'c', 'a', 'd']);
      // The song that was playing is still the current one, at its new place.
      expect(h.controller.queue.currentIndex, 2);
      expect(tester.widget<ListTile>(_row('a')).selected, isTrue);
    });

    testWidgets('a song dragged up lands where it was dropped', (tester) async {
      final h = await _openQueue(tester);

      await _drag(tester, 'd', -2);

      expect(_ids(h), ['a', 'd', 'b', 'c']);
      expect(h.controller.queue.currentIndex, 0);
    });

    testWidgets('only the handle drags, the rest of the row does not', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      await tester.drag(_row('a'), const Offset(0, 128));
      await tester.pumpAndSettle();

      expect(_ids(h), ['a', 'b', 'c', 'd']);
    });

    testWidgets('with shuffle on, the next song is the one at the next rank '
        'even after a drag', (tester) async {
      final h = await _openQueue(tester, ids: ['a', 'b', 'c', 'd', 'e', 'f']);
      h.controller.setShuffle(true);
      await tester.pump();

      await _drag(tester, 'a', 3);
      await _drag(tester, 'f', -2);

      // What the queue says plays next: the song at the next rank in the order.
      final queue = h.controller.queue;
      final order = queue.shuffleOrder!;
      final next =
          queue.entries[order[order.indexOf(queue.currentIndex!) + 1]].track;
      unawaited(h.controller.next());
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.current, next);
      expect(
        tester.widget<ListTile>(_row(next.sourceId)).selected,
        isTrue,
        reason: 'the row marked on screen is the song that plays',
      );
    });
  });

  group('the menu', () {
    testWidgets('Play next moves the song after the current one', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      await tester.tap(_moreOf('c'));
      await tester.pump();
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();

      expect(_ids(h), ['a', 'c', 'b', 'd']);
      expect(h.controller.queue.currentIndex, 0);
    });

    testWidgets('Play next after shuffle plays that song next', (tester) async {
      final h = await _openQueue(tester, ids: ['a', 'b', 'c', 'd', 'e', 'f']);
      h.controller.setShuffle(true);
      await tester.pump();

      await tester.tap(_moreOf('e'));
      await tester.pump();
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();
      unawaited(h.controller.next());
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.current?.sourceId, 'e');
    });

    testWidgets('the current song has no Play next', (tester) async {
      await _openQueue(tester);

      await tester.tap(_moreOf('a'));
      await tester.pump();

      expect(find.text('Remove from queue'), findsOneWidget);
      expect(find.text('Play next'), findsNothing);
    });

    testWidgets('Remove takes the song out without a toast', (tester) async {
      final h = await _openQueue(tester);

      await tester.tap(_moreOf('b'));
      await tester.pump();
      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();

      expect(_ids(h), ['a', 'c', 'd']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('right click, long press and the button open the same menu', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      await tester.tap(find.text('Song c'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Remove from queue'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();
      expect(_ids(h), ['a', 'c', 'b', 'd']);

      await tester.longPress(find.text('Song c'));
      await tester.pump();
      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();
      expect(_ids(h), ['a', 'b', 'd']);

      await tester.tap(_moreOf('d'));
      await tester.pump();
      expect(find.text('Remove from queue'), findsOneWidget);
    });

    testWidgets('Esc closes the menu opened from the button', (tester) async {
      final h = await _openQueue(tester);

      await tester.tap(_moreOf('b'));
      await tester.pump();
      expect(find.text('Remove from queue'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('Remove from queue'), findsNothing);
      expect(find.byType(QueueView), findsOneWidget);
      expect(_ids(h), ['a', 'b', 'c', 'd']);
    });
  });

  group('clearing', () {
    testWidgets('cancelling leaves the queue alone', (tester) async {
      final h = await _openQueue(tester);

      await tester.tap(find.byTooltip(_clearTooltip));
      await tester.pumpAndSettle();
      expect(find.text('Clear the queue?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(_ids(h), ['a', 'b', 'c', 'd']);
      expect(find.byType(QueueView), findsOneWidget);
    });

    testWidgets('confirming clears the queue and says so', (tester) async {
      final h = await _openQueue(tester);

      await tester.tap(find.byTooltip(_clearTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(h.controller.queue.entries, isEmpty);
      expect(find.text('Queue cleared'), findsOneWidget);
    });
  });

  group('the shuffle note', () {
    testWidgets('is there only while shuffle is on', (tester) async {
      final h = await _openQueue(tester);
      const note =
          'The shuffle order follows positions; dragging only swaps songs, '
          'not the order';
      expect(find.text(note), findsNothing);

      h.controller.setShuffle(true);
      await tester.pump();
      await tester.pump();
      expect(find.text(note), findsOneWidget);

      h.controller.setShuffle(false);
      await tester.pump();
      await tester.pump();
      expect(find.text(note), findsNothing);
    });
  });

  group('the queue page', () {
    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
      ('expanded', const Size(1000, 800)),
    ]) {
      testWidgets('$name: a full page in the shell, back goes to Home', (
        tester,
      ) async {
        await _openQueue(tester, size: size);
        expect(find.byType(PlayerPage), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);
      });

      testWidgets('$name: Ctrl+Q opens it, once, and focuses the page', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: size);
        await h.play(tester, [summary('a'), summary('b')]);
        expect(find.byType(QueueView), findsNothing);

        // Pressed twice: still one page, nothing else opens.
        await _chord(tester, LogicalKeyboardKey.keyQ);
        await _chord(tester, LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();

        expect(find.byType(QueueView), findsOneWidget);
        expect(find.byType(PlayerPage), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<QueueView>(),
          isNotNull,
        );
      });

      testWidgets('$name: the playback keys work on the page', (tester) async {
        final h = await _openQueue(tester, size: size);
        await _chord(tester, LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();
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

      testWidgets(
        '$name: Space on a focused row plays or pauses, Enter jumps',
        (tester) async {
          final h = await _openQueue(tester, size: size);
          Focus.of(tester.element(find.text('Song c'))).requestFocus();
          await tester.pump();

          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(h.controller.queue.currentIndex, 0);
          expect(h.controller.state, isA<Paused>());

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.pump();
          expect(h.controller.queue.currentIndex, 2);
        },
      );

      testWidgets('$name: clearing the queue shows the empty state', (
        tester,
      ) async {
        final h = await _openQueue(tester, size: size);

        unawaited(h.controller.clear());
        await tester.pumpAndSettle();

        expect(find.byType(QueueView), findsNothing);
        expect(find.text('The queue is empty'), findsOneWidget);
        // Nothing is left on top of the shell: it takes input again.
        await tester.tap(find.text('Settings').first);
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsWidgets);
      });

      testWidgets('$name: the page edits the queue', (tester) async {
        final h = await _openQueue(tester, size: size);

        await _drag(tester, 'a', 2);
        expect(_ids(h), ['b', 'c', 'a', 'd']);

        // 'b' is before the current song: it moves past it.
        await tester.tap(_moreOf('b'));
        await tester.pump();
        await tester.tap(find.text('Play next'));
        await tester.pumpAndSettle();
        expect(_ids(h), ['c', 'a', 'b', 'd']);
        expect(h.controller.queue.current?.sourceId, 'a');
      });

      testWidgets('$name: clearing from the page empties it and says so', (
        tester,
      ) async {
        final h = await _openQueue(tester, size: size);

        await tester.tap(find.byTooltip(_clearTooltip));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        expect(h.controller.queue.entries, isEmpty);
        expect(find.byType(QueueView), findsNothing);
        expect(find.text('The queue is empty'), findsOneWidget);
        expect(find.text('Queue cleared'), findsOneWidget);
        // The toast sits above the bottom navigation bar.
        final navigation = find.byType(NavigationBar);
        if (navigation.evaluate().isNotEmpty) {
          expect(
            tester.getRect(find.text('Queue cleared')).bottom,
            lessThanOrEqualTo(tester.getRect(navigation).top),
          );
        }
      });
    }

    testWidgets('an empty queue shows the empty state', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(400, 800));

      await h.openQueue(tester);

      expect(find.text('The queue is empty'), findsOneWidget);
      expect(find.byType(QueueView), findsNothing);
    });

    testWidgets('a queue that is still loading shows nothing, not the empty '
        'state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(AppLocale.en.buildSync()),
            playbackQueueProvider.overrideWithValue(const AsyncLoading()),
          ],
          child: const MaterialApp(home: QueuePage(visible: true)),
        ),
      );

      expect(find.text('The queue is empty'), findsNothing);
      expect(find.byType(QueueView), findsNothing);
    });

    testWidgets('the list opens near the current song every time', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 900));
      await h.play(tester, [
        for (var i = 0; i < 200; i++) summary('t$i'),
      ], index: 100);
      await tester.pump(const Duration(milliseconds: 200));

      await h.openQueue(tester);

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      expect(list.scrollController!.offset, 98 * list.itemExtent!);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Song t100')),
        isA<ListTile>().having((tile) => tile.selected, 'selected', isTrue),
      );

      // Away from the queue the song changes; coming back opens near the new
      // one, not where the list was left.
      await h.open(tester, ShellDestination.home);
      await tester.pumpAndSettle();
      unawaited(h.controller.jumpTo(150));
      await tester.pump(const Duration(milliseconds: 200));
      await h.openQueue(tester);

      final again = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      expect(again.scrollController!.offset, 148 * again.itemExtent!);
    });

    testWidgets('during a temporary play no queue row is marked current', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      unawaited(h.controller.playTemporary(summary('x').toTrackInfo()));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final rows = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(rows, hasLength(4));
      expect(rows.where((row) => row.selected), isEmpty);
    });

    // 直播時 `currentIndex` 也是回到佇列時的位置；佇列頁照常顯示原佇列（M3 design §9.4）。
    testWidgets('in a live room no queue row is marked current', (
      tester,
    ) async {
      final h = ShellHarness();
      h.plugin.onResolveLive = (request) => [
        candidate('${request.roomId}.flv'),
      ];
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));
      await h.openQueue(tester);
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .where((row) => row.selected),
        hasLength(1),
      );

      unawaited(
        h.controller.playLive(
          const LiveTarget(pluginId: 'fmp-test', roomId: 'r', title: 'Room'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final rows = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(rows, hasLength(2));
      expect(rows.where((row) => row.selected), isEmpty);
    });
  });

  group('scrolling to the current song', () {
    Future<(ShellHarness, ScrollController)> openLong(
      WidgetTester tester, {
      required bool autoScroll,
    }) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 900));
      if (autoScroll) await _setAutoScroll(tester, h);
      await h.play(tester, [for (var i = 0; i < 200; i++) summary('t$i')]);
      await tester.pump(const Duration(milliseconds: 200));
      await h.openQueue(tester);
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      return (h, list.scrollController!);
    }

    testWidgets('on: a new current song scrolls two rows above it', (
      tester,
    ) async {
      final (h, scroll) = await openLong(tester, autoScroll: true);
      expect(scroll.offset, 0);

      unawaited(h.controller.jumpTo(100));
      await tester.pumpAndSettle();

      expect(scroll.offset, 98 * 64.0);
    });

    testWidgets('on: playing through to the next song scrolls too', (
      tester,
    ) async {
      final (h, scroll) = await openLong(tester, autoScroll: true);
      unawaited(h.controller.jumpTo(100));
      await tester.pumpAndSettle();

      unawaited(h.controller.jumpTo(150));
      await tester.pumpAndSettle();

      expect(scroll.offset, 148 * 64.0);
    });

    testWidgets('off: the list stays where it is', (tester) async {
      final (h, scroll) = await openLong(tester, autoScroll: false);

      unawaited(h.controller.jumpTo(100));
      await tester.pumpAndSettle();

      expect(scroll.offset, 0);
    });

    testWidgets('on: moving the current song does not count as a new song', (
      tester,
    ) async {
      final (h, scroll) = await openLong(tester, autoScroll: true);
      unawaited(h.controller.jumpTo(100));
      await tester.pumpAndSettle();
      scroll.jumpTo(10 * 64.0);
      await tester.pump();

      h.controller.move(100, 150);
      await tester.pumpAndSettle();

      expect(h.controller.queue.currentIndex, 150);
      expect(scroll.offset, 10 * 64.0);
    });

    testWidgets('on: nothing scrolls while a drag is in progress', (
      tester,
    ) async {
      final (h, scroll) = await openLong(tester, autoScroll: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 50));

      unawaited(h.controller.jumpTo(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, lessThan(98 * 64.0));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('on: a cancelled drag does not stop later scrolling', (
      tester,
    ) async {
      final (h, scroll) = await openLong(tester, autoScroll: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_ids(h).first, 't0', reason: 'the cancelled drag moved nothing');

      unawaited(h.controller.jumpTo(100));
      await tester.pumpAndSettle();

      expect(scroll.offset, 98 * 64.0);
    });
  });
}
