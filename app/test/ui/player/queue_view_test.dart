import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// M2 PR 18b：可編輯的佇列清單（分頁與底部面板，design §7.3）。每個動作都經控制器，
// 從外殼開始，點播放列的曲名開播放頁，和使用者一樣。

const _clearTooltip = 'Clear the queue';
const _more = 'More options';

final _barTitle = find
    .descendant(of: find.byKey(PlayerBar.titleKey), matching: find.byType(Text))
    .first;

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// 佇列 [ids]（播第一首）、播放頁開著；寬版切到佇列分頁，compact、medium 開底部面板。
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
  await tester.tap(_barTitle);
  await tester.pumpAndSettle();
  if (size.width < 840) {
    await tester.tap(find.byKey(PlayerPage.queueKey));
  } else {
    await tester.tap(find.widgetWithText(Tab, 'Queue'));
  }
  await tester.pumpAndSettle();
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

void main() {
  group('the list', () {
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
      await tester.tap(_barTitle);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();

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
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('confirming clears, closes the page and says so', (
      tester,
    ) async {
      final h = await _openQueue(tester);

      await tester.tap(find.byTooltip(_clearTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(h.controller.queue.entries, isEmpty);
      expect(find.byType(PlayerPage), findsNothing);
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

  group('the bottom sheet', () {
    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
    ]) {
      testWidgets('$name: the button opens it, back and Esc close only it', (
        tester,
      ) async {
        await _openQueue(tester, size: size);
        expect(find.byType(PlayerPage), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(PlayerPage), findsOneWidget);

        await tester.tap(find.byKey(PlayerPage.queueKey));
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(PlayerPage), findsOneWidget);
      });

      testWidgets('$name: Ctrl+Q opens it from the page, once', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: size);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.tap(_barTitle);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);

        await _chord(tester, LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);
      });

      testWidgets('$name: the playback keys work in the sheet', (tester) async {
        final h = await _openQueue(tester, size: size);
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
        // Ctrl+L does nothing here: the sheet stays, the page is unchanged.
        await _chord(tester, LogicalKeyboardKey.keyL);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);
        expect(find.text('No lyrics'), findsNothing);
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

      testWidgets('$name: Ctrl+Q pressed twice opens one sheet', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: size);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.tap(_barTitle);
        await tester.pumpAndSettle();

        // Both presses reach the page before the sheet takes the focus.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(PlayerPage), findsOneWidget);
      });

      testWidgets('$name: Ctrl+Q with the page closed opens the page and the '
          'sheet', (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: size);
        await h.play(tester, [summary('a'), summary('b')]);

        await _chord(tester, LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();

        expect(find.byType(PlayerPage), findsOneWidget);
        expect(find.byType(QueueView), findsOneWidget);
      });

      testWidgets('$name: clearing the queue closes the sheet and the page', (
        tester,
      ) async {
        final h = await _openQueue(tester, size: size);

        unawaited(h.controller.clear());
        await tester.pumpAndSettle();

        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(PlayerPage), findsNothing);
        // Nothing is left on top of the shell: it takes input again.
        await tester.tap(find.text('Settings').first);
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsWidgets);
      });

      testWidgets('$name: the sheet edits the queue too', (tester) async {
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

      testWidgets('$name: clearing from the sheet closes the sheet and the '
          'page', (tester) async {
        final h = await _openQueue(tester, size: size);

        await tester.tap(find.byTooltip(_clearTooltip));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        expect(h.controller.queue.entries, isEmpty);
        expect(find.byType(QueueView), findsNothing);
        expect(find.byType(PlayerPage), findsNothing);
        expect(find.text('Queue cleared'), findsOneWidget);
        // The toast is placed for the shell, not for the page that just closed:
        // it stays above the bottom navigation bar.
        final navigation = find.byType(NavigationBar);
        if (navigation.evaluate().isNotEmpty) {
          expect(
            tester.getRect(find.text('Queue cleared')).bottom,
            lessThanOrEqualTo(tester.getRect(navigation).top),
          );
        }
        // Nothing is left on top of the shell: it takes input again.
        await tester.tap(find.text('Settings').first);
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsWidgets);
      });
    }

    testWidgets('a wide window has no button, the tab is the queue', (
      tester,
    ) async {
      await _openQueue(tester);

      expect(find.byKey(PlayerPage.queueKey), findsNothing);
    });

    testWidgets('the button has a tooltip with the shortcut', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(400, 800));
      await h.play(tester, [summary('a')]);
      await tester.tap(_barTitle);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Queue (Ctrl+Q)'), findsOneWidget);
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
      await tester.tap(_barTitle);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Queue'));
      await tester.pumpAndSettle();
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
