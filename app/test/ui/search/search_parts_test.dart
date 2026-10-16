import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// B 站分 P 的搜尋結果列（M3 PR 20，design §11.1、ADR 0028 §決定 5）：展開鈕只在插件宣告
// `multiPart` 且分 P 數不是確定的 1 時出現（`partCount` 空是不知道，也顯示）、展開時
// 呼叫 `multiPart`、影片選單的「加入佇列」「下一首播放」在有多個分 P 時套用到全部，
// 還沒取過就先取，取不到時什麼都不加。

MultiPartResult _parts(int count) => MultiPartResult(
  parts: [
    for (var index = 1; index <= count; index++)
      MultiPart(
        cid: 10 + index,
        title: 'Part $index',
        duration: Duration(seconds: 30 * index),
        index: index,
      ),
  ],
);

/// 結果只有一首影片 `a`（標題 `Song a`）；分 P 數與取回的分 P 由參數決定。
ShellHarness _harness({
  int? partCount,
  bool multiPart = true,
  int parts = 3,
  bool mix = false,
}) {
  final h = ShellHarness(
    multiPart: multiPart,
    mix: mix,
    registryOfSources: true,
    onSearch: (_) =>
        SearchPage(items: [summary('a', partCount: partCount)], hasMore: false),
  );
  h.plugin.onMultiPart = (_) => _parts(parts);
  return h;
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'song');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

Finder get _show => find.byTooltip('Show parts');
Finder get _hide => find.byTooltip('Hide parts');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _tapMenu(WidgetTester tester, String item) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ListTile, 'Song a'),
      matching: find.byTooltip('More options'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, item));
  await _settle(tester);
}

List<String> _queued(ShellHarness h) => [
  for (final entry in h.controller.queue.entries)
    '${entry.track.sourceId}:${entry.track.cid}:${entry.track.partIndex}',
];

void main() {
  group('the expand button', () {
    testWidgets('is not there when the plugin does not declare multiPart', (
      tester,
    ) async {
      final h = _harness(partCount: 3, multiPart: false);
      await h.pumpShell(tester);
      await _search(tester);

      expect(find.text('Song a'), findsOneWidget);
      expect(_show, findsNothing);
    });

    testWidgets('is not there when the result has exactly one part', (
      tester,
    ) async {
      final h = _harness(partCount: 1);
      await h.pumpShell(tester);
      await _search(tester);

      expect(_show, findsNothing);
      expect(h.plugin.multiPartQueries, isEmpty);
    });

    for (final count in [3, null]) {
      testWidgets('is there when the count is $count', (tester) async {
        final h = _harness(partCount: count);
        await h.pumpShell(tester);
        await _search(tester);

        expect(_show, findsOneWidget);
        expect(h.plugin.multiPartQueries, isEmpty);
      });
    }
  });

  group('expanding', () {
    testWidgets('calls multiPart once and lists the parts with durations', (
      tester,
    ) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);

      await tester.tap(_show);
      await _settle(tester);

      expect(h.plugin.multiPartQueries.single.sourceId, 'a');
      expect(find.text('P1 Part 1'), findsOneWidget);
      expect(find.text('P2 Part 2'), findsOneWidget);
      expect(find.text('P3 Part 3'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      expect(_hide, findsOneWidget);

      await tester.tap(_hide);
      await _settle(tester);
      expect(find.text('P2 Part 2'), findsNothing);

      await tester.tap(_show);
      await _settle(tester);
      expect(find.text('P2 Part 2'), findsOneWidget);
      expect(
        h.plugin.multiPartQueries,
        hasLength(1),
        reason: 'the parts are not fetched again',
      );
    });

    testWidgets('a new search starts with the videos folded, and the parts '
        'are not fetched again', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);
      expect(find.text('P2 Part 2'), findsOneWidget);

      await _search(tester);

      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('P2 Part 2'), findsNothing);
      expect(_show, findsOneWidget);

      await tester.tap(_show);
      await _settle(tester);
      expect(find.text('P2 Part 2'), findsOneWidget);
      expect(h.plugin.multiPartQueries, hasLength(1));
    });

    testWidgets('a tap on a part plays it as a temporary track', (
      tester,
    ) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);

      await tester.tap(find.text('P2 Part 2'));
      await _settle(tester);

      final current = h.controller.queue.current!;
      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(current.sourceId, 'a');
      expect(current.cid, 12);
      expect(current.partIndex, 2);
      expect(current.parentTitle, 'Song a');
      expect(h.controller.queue.entries, isEmpty);
    });

    testWidgets('a part menu adds that part to the queue', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'P3 Part 3'),
          matching: find.byTooltip('More options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Add to queue'));
      await _settle(tester);

      expect(_queued(h), ['a:13:3']);
    });

    testWidgets('a tap on the video itself plays it without asking for parts', (
      tester,
    ) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);

      await tester.tap(find.text('Song a'));
      await _settle(tester);

      expect(h.controller.queue.current?.cid, isNull);
      expect(h.controller.queue.current?.partIndex, isNull);
      expect(h.plugin.multiPartQueries, isEmpty);
    });

    testWidgets('an unknown count with one part folds back and hides the '
        'button, with no error', (tester) async {
      final h = _harness(partCount: null, parts: 1);
      await h.pumpShell(tester);
      await _search(tester);

      await tester.tap(_show);
      await _settle(tester);

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(_show, findsNothing);
      expect(_hide, findsNothing);
      expect(find.text('P1 Part 1'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Too many requests'), findsNothing);
    });

    testWidgets('a failure shows a retry row and an error, and retry works', (
      tester,
    ) async {
      var fail = true;
      final h = _harness(partCount: 3);
      h.plugin.onMultiPart = (_) =>
          fail ? throw RateLimited(pluginId: 'fmp-test') : _parts(2);
      await h.pumpShell(tester);
      await _search(tester);

      await tester.tap(_show);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Couldn’t load the parts'), findsOneWidget);
      expect(find.textContaining('Too many requests'), findsWidgets);

      fail = false;
      await tester.tap(find.text('Retry'));
      await _settle(tester);

      expect(find.text('Couldn’t load the parts'), findsNothing);
      expect(find.text('P2 Part 2'), findsOneWidget);
      expect(h.plugin.multiPartQueries, hasLength(2));
      // 提示的計時器在樹拆掉前走完。
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('shows a spinner with a label while the parts load', (
      tester,
    ) async {
      final pending = Completer<MultiPartResult>();
      final h = _harness(partCount: 3);
      h.plugin.onMultiPart = (_) => pending.future;
      await h.pumpShell(tester);
      await _search(tester);

      await tester.tap(_show);
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator &&
              widget.semanticsLabel == 'Loading parts',
        ),
        findsOneWidget,
      );
      expect(_show, findsNothing);

      pending.complete(_parts(2));
      await _settle(tester);
      expect(find.text('P1 Part 1'), findsOneWidget);
    });
  });

  group('the video menu', () {
    testWidgets('add to queue with several known parts fetches them first '
        'and adds all of them', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(_queued(h), ['a:11:1', 'a:12:2', 'a:13:3']);
      expect(find.text('Added to queue'), findsOneWidget);
    });

    testWidgets('play next applies to all parts too', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await h.play(tester, [summary('x')]);
      await _search(tester);

      await _tapMenu(tester, 'Play next');

      expect(_queued(h), ['x:null:null', 'a:11:1', 'a:12:2', 'a:13:3']);
    });

    testWidgets('parts already fetched by expanding are not fetched again', (
      tester,
    ) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(_queued(h), ['a:11:1', 'a:12:2', 'a:13:3']);
    });

    testWidgets('an unknown count is fetched, and several parts are all '
        'added', (tester) async {
      final h = _harness(partCount: null, parts: 2);
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(_queued(h), ['a:11:1', 'a:12:2']);
    });

    testWidgets('an unknown count with one part adds the video as it is', (
      tester,
    ) async {
      final h = _harness(partCount: null, parts: 1);
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(_queued(h), ['a:null:null']);
      expect(_show, findsNothing);
    });

    testWidgets('a known single part adds the video without fetching', (
      tester,
    ) async {
      final h = _harness(partCount: 1);
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, isEmpty);
      expect(_queued(h), ['a:null:null']);
    });

    testWidgets('a plugin without multiPart adds the video without '
        'fetching', (tester) async {
      final h = _harness(partCount: 3, multiPart: false);
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');

      expect(h.plugin.multiPartQueries, isEmpty);
      expect(_queued(h), ['a:null:null']);
    });

    testWidgets('in a mix, play next and add to queue stay disabled for the '
        'video and its parts', (tester) async {
      final h = _harness(partCount: 3, mix: true);
      h.plugin.onMix = (_) => MixBatch(
        mixId: 'm1',
        title: 'Mix',
        tracks: [summary('m1'), summary('m2')],
        cursor: null,
      );
      await h.pumpShell(tester);
      unawaited(h.controller.startMix(summary('seed').toTrackInfo()));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.mode, QueueMode.mix);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);

      for (final row in ['Song a', 'P2 Part 2']) {
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, row),
            matching: find.byTooltip('More options'),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Play next (unavailable in a Mix)',
          'Add to queue (unavailable in a Mix)',
        ]) {
          expect(
            tester
                .widget<MenuItemButton>(
                  find.widgetWithText(MenuItemButton, label),
                )
                .onPressed,
            isNull,
            reason: '$label of $row',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(h.controller.queue.entries, hasLength(2));
    });

    testWidgets('a failure to fetch adds nothing and shows an error', (
      tester,
    ) async {
      final h = _harness(partCount: 3);
      h.plugin.onMultiPart = (_) => throw RateLimited(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await _search(tester);

      await _tapMenu(tester, 'Add to queue');
      await tester.pump(const Duration(milliseconds: 300));

      expect(h.controller.queue.entries, isEmpty);
      expect(find.text('Added to queue'), findsNothing);
      expect(find.textContaining('Too many requests'), findsWidgets);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  // 多選（M4 PR 5）：選了有多個分 P 的影片列就是全部分 P（同「加入歌單…」的取法），同一支影片
  // 另外選的分 P 不重複；取不到分 P 時提示、什麼都不加、選取留著。
  group('selecting', () {
    Future<void> addSelectedToQueue(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Add to queue'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a selected video adds all its parts, once even with one of '
        'its parts selected too', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);

      await tester.longPress(find.text('P2 Part 2'));
      await tester.pump();
      await tester.tap(find.text('Song a'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await addSelectedToQueue(tester);

      expect(_queued(h), ['a:11:1', 'a:12:2', 'a:13:3']);
      expect(h.plugin.multiPartQueries, hasLength(1));
    });

    testWidgets('selected parts are added on their own; a video not yet '
        'expanded fetches its parts first', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await addSelectedToQueue(tester);
      expect(_queued(h), ['a:11:1', 'a:12:2', 'a:13:3']);
      expect(h.plugin.multiPartQueries, hasLength(1));

      await tester.tap(_show);
      await _settle(tester);
      await tester.longPress(find.text('P3 Part 3'));
      await tester.tap(find.text('P1 Part 1'));
      await tester.pump();
      await addSelectedToQueue(tester);
      expect(_queued(h).skip(3), ['a:11:1', 'a:13:3']);
    });

    testWidgets('folding a video unselects its parts', (tester) async {
      final h = _harness(partCount: 3);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.tap(_show);
      await _settle(tester);
      await tester.longPress(find.text('Song a'));
      await tester.tap(find.text('P1 Part 1'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(_hide);
      await _settle(tester);

      expect(find.text('1 selected'), findsOneWidget);
    });

    // 動作在進行中（還在取分 P）時選取列的鈕停用：連按兩次只加入一次。
    testWidgets('while the parts are being fetched a second "Add to queue" '
        'does nothing', (tester) async {
      final h = _harness(partCount: 3);
      final fetched = Completer<MultiPartResult>();
      h.plugin.onMultiPart = (_) => fetched.future;
      await h.pumpShell(tester);
      await _search(tester);
      await tester.longPress(find.text('Song a'));
      await tester.pump();

      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      fetched.complete(_parts(3));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(_queued(h), ['a:11:1', 'a:12:2', 'a:13:3']);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a failure to fetch the parts adds nothing and keeps the '
        'selection', (tester) async {
      final h = _harness(partCount: 3);
      h.plugin.onMultiPart = (_) => throw RateLimited(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await _search(tester);

      await tester.longPress(find.text('Song a'));
      await tester.pump();
      await addSelectedToQueue(tester);

      expect(h.controller.queue.entries, isEmpty);
      expect(find.textContaining('Too many requests'), findsWidgets);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
