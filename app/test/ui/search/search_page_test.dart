import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../tracks/marker_support.dart';
import '../support/shell_harness.dart';

void main() {
  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
  }

  group('states', () {
    testWidgets('before searching, while loading, with no results', (
      tester,
    ) async {
      final pending = Completer<SearchPage>();
      final h = ShellHarness(onSearch: (_) => pending.future);
      await h.pumpShell(tester);
      expect(find.text('Type a keyword to search'), findsOneWidget);

      await search(tester, '  nothing  ');
      expect(
        find.bySemanticsLabel('Searching'),
        findsOneWidget,
        reason: 'the spinner has a label',
      );
      expect(h.plugin.searches.single.keyword, 'nothing');

      pending.complete(const SearchPage(items: [], hasMore: false));
      await tester.pump();
      expect(find.text('No results for “nothing”'), findsOneWidget);
    });

    testWidgets('only spaces does not search', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);

      await search(tester, '   ');
      expect(h.plugin.searches, isEmpty);
      expect(find.text('Type a keyword to search'), findsOneWidget);
    });
  });

  // tooltip 是「⋯」唯一的名稱：Icon 再給 semanticLabel 會念成「More. More」。
  testWidgets('the more button is named once, by its tooltip', (tester) async {
    final handle = tester.ensureSemantics();
    final h = ShellHarness();
    await h.pumpShell(tester);
    await search(tester, 'song');

    final node = tester.getSemantics(
      find.widgetWithIcon(IconButton, Icons.more_vert).first,
    );
    expect(node.tooltip, 'More options');
    expect(node.label, isEmpty);
    handle.dispose();
  });

  testWidgets('results show artwork, title, uploader and duration', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);

    await search(tester, 'song');

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Uploader a'), findsOneWidget);
    expect(find.text('3:05'), findsNWidgets(3));
    // 沒有封面時是佔位圖，不發請求。
    expect(find.byIcon(Icons.music_note), findsNWidgets(3));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an error goes to a toast, and retry searches again', (
    tester,
  ) async {
    var fail = true;
    final h = ShellHarness(
      onSearch: (query) => fail
          ? throw RateLimited(pluginId: 'fmp-test')
          : SearchPage(items: [summary('a')], hasMore: false),
    );
    await h.pumpShell(tester);

    await search(tester, 'song');
    await tester.pumpAndSettle();
    expect(
      find.text('Too many requests to fmp-test. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Search failed'), findsOneWidget);
    expect(
      h.log.history.where((record) => record.message == 'Search failed'),
      hasLength(1),
    );

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Song a'), findsOneWidget);
    expect(h.plugin.searches, hasLength(2));
  });

  // design §5.4、ADR 0016 §決定 7 的更正：沒有介面、連不上都照常送出使用者的
  // 搜尋，失敗時才顯示離線空狀態。
  group('offline', () {
    Finder offlineMessage(String title) => find.descendant(
      of: find.byType(OfflineMessage),
      matching: find.text(title),
    );

    testWidgets('without an interface the results stay and the search is '
        'still sent; a failure shows the offline state with retry', (
      tester,
    ) async {
      var fail = false;
      final h = ShellHarness(
        onSearch: (query) => fail
            ? throw NetworkError(pluginId: 'fmp-test')
            : SearchPage(items: [summary(query.keyword)], hasMore: false),
      );
      await h.pumpShell(tester);
      await search(tester, 'a');
      expect(find.text('Song a'), findsOneWidget);

      // 系統回報可能是錯的（Windows 的 NCSI）：不擋使用者，已有的結果照常顯示。
      await h.setNetwork(tester, NetworkStatus.noInterface);
      expect(find.text('Song a'), findsOneWidget);
      expect(find.byType(OfflineMessage), findsNothing);

      fail = true;
      await search(tester, 'b');
      await tester.pumpAndSettle();
      expect(h.plugin.searches.map((query) => query.keyword), ['a', 'b']);
      expect(offlineMessage('No network connection'), findsOneWidget);
      expect(find.text('Search failed'), findsNothing);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(h.plugin.searches, hasLength(3));
      expect(find.text('Song b'), findsOneWidget);
    });

    testWidgets('unreachable still sends the search; a failure shows the '
        'offline state with retry', (tester) async {
      var fail = true;
      final h = ShellHarness(
        onSearch: (query) => fail
            ? throw NetworkError(pluginId: 'fmp-test')
            : SearchPage(items: [summary('a')], hasMore: false),
      );
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.unreachable);

      await search(tester, 'song');
      await tester.pumpAndSettle();
      expect(h.plugin.searches, hasLength(1));
      expect(offlineMessage("Can't reach the network"), findsOneWidget);
      expect(find.text('Search failed'), findsNothing);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(h.plugin.searches, hasLength(2));
      expect(find.text('Song a'), findsOneWidget);
    });

    testWidgets('a failure while online is the usual failure', (tester) async {
      final h = ShellHarness(
        onSearch: (query) => throw NetworkError(pluginId: 'fmp-test'),
      );
      await h.pumpShell(tester);

      await search(tester, 'song');
      await tester.pumpAndSettle();
      expect(find.text('Search failed'), findsOneWidget);
      expect(find.byType(OfflineMessage), findsNothing);
    });
  });

  group('now playing marker', () {
    testWidgets('only the playing result has the overlay and the bold title', (
      tester,
    ) async {
      reduceMotion(tester);
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');
      expect(find.byKey(NowPlayingOverlay.overlayKey), findsNothing);

      await tester.tap(find.text('Song b'));
      await tester.pumpAndSettle();

      final b = find.widgetWithText(ListTile, 'Song b');
      expect(overlayIn(b), findsOneWidget);
      expect(find.byKey(NowPlayingOverlay.overlayKey), findsOneWidget);
      expect(
        isPlayingTitle(
          tester,
          find.descendant(of: b, matching: find.text('Song b')),
        ),
        isTrue,
      );
      final a = find.widgetWithText(ListTile, 'Song a');
      expect(
        isPlayingTitle(
          tester,
          find.descendant(of: a, matching: find.text('Song a')),
        ),
        isFalse,
      );

      // 播另一首：標示跟著走。
      await tester.tap(find.text('Song a'));
      await tester.pumpAndSettle();
      expect(overlayIn(a), findsOneWidget);
      expect(overlayIn(b), findsNothing);
    });
  });

  group('auto load', () {
    testWidgets('the last row loads the next page once per page and ends '
        'with a line', (tester) async {
      final h = ShellHarness(
        onSearch: (query) => SearchPage(
          items: [summary('p${query.page}')],
          hasMore: query.page < 3,
        ),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.pumpAndSettle();

      for (final id in ['p1', 'p2', 'p3']) {
        expect(find.text('Song $id'), findsOneWidget);
      }
      expect([for (final query in h.plugin.searches) query.page], [1, 2, 3]);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('All loaded'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(h.plugin.searches, hasLength(3), reason: 'nothing more to load');
    });

    testWidgets('the next page waits until the last row is built', (
      tester,
    ) async {
      final h = ShellHarness(
        onSearch: (query) => SearchPage(
          items: [for (var i = 0; i < 30; i++) summary('p${query.page}-$i')],
          hasMore: query.page < 2,
        ),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.pumpAndSettle();
      expect(h.plugin.searches, hasLength(1), reason: 'the last row is far');
      expect(find.text('All loaded'), findsNothing);

      await tester.drag(find.byType(ListView).last, const Offset(0, -20000));
      await tester.pumpAndSettle();

      expect(h.plugin.searches, hasLength(2));
    });

    testWidgets('a failed page keeps the button as the retry and does not '
        'load again by itself', (tester) async {
      var fail = true;
      final h = ShellHarness(
        onSearch: (query) => query.page == 2 && fail
            ? throw RateLimited(pluginId: 'fmp-test')
            : SearchPage(
                items: [summary('p${query.page}')],
                hasMore: query.page < 2,
              ),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.pumpAndSettle();

      expect(h.plugin.searches, hasLength(2));
      expect(find.text('Song p1'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
      expect(find.text('All loaded'), findsNothing);

      fail = false;
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect([for (final query in h.plugin.searches) query.page], [1, 2, 2]);
      expect(find.text('Song p2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('All loaded'), findsOneWidget);
    });

    testWidgets('a page with no new rows stops auto-loading; a manual page '
        'with rows resumes it', (tester) async {
      // 第 2 頁是空的但說還有下一頁；第 3 頁（手動）有結果、第 4 頁（自動）是最後一頁。
      final h = ShellHarness(
        onSearch: (query) => switch (query.page) {
          1 => SearchPage(items: [summary('p1')], hasMore: true),
          2 => const SearchPage(items: [], hasMore: true),
          3 => SearchPage(items: [summary('p3')], hasMore: true),
          _ => SearchPage(items: [summary('p4')], hasMore: false),
        },
      );
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.pumpAndSettle();

      expect(
        [for (final query in h.plugin.searches) query.page],
        [1, 2],
        reason: 'the empty page is loaded once, not in a loop',
      );
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect([for (final query in h.plugin.searches) query.page], [1, 2, 3, 4]);
      expect(find.text('Song p4'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('All loaded'), findsOneWidget);
    });

    testWidgets('a results list with no more pages ends with the line', (
      tester,
    ) async {
      final h = ShellHarness(
        onSearch: (_) => SearchPage(items: [summary('a')], hasMore: false),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');

      expect(find.text('All loaded'), findsOneWidget);
    });
  });

  // 排序在兩次請求之間變了時，下一頁會重複上一頁已有的曲目（B 站搜尋會）。
  testWidgets('load more skips tracks already in the list', (tester) async {
    final h = ShellHarness(
      onSearch: (query) => SearchPage(
        items: [
          if (query.page == 1) ...[summary('a'), summary('b')],
          if (query.page == 2) ...[summary('b'), summary('c')],
        ],
        hasMore: query.page < 2,
      ),
    );
    await h.pumpShell(tester);
    await search(tester, 'song');
    await tester.pumpAndSettle();

    for (final id in ['a', 'b', 'c']) {
      expect(find.text('Song $id'), findsOneWidget);
    }
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('a newer search wins over a slower older one', (tester) async {
    final slow = Completer<SearchPage>();
    final h = ShellHarness(
      onSearch: (query) => query.keyword == 'old'
          ? slow.future
          : SearchPage(items: [summary('new')], hasMore: false),
    );
    await h.pumpShell(tester);

    await search(tester, 'old');
    await search(tester, 'new');
    slow.complete(SearchPage(items: [summary('old')], hasMore: false));
    await tester.pump();

    expect(find.text('Song new'), findsOneWidget);
    expect(find.text('Song old'), findsNothing);
  });

  group('playing a result', () {
    /// 列 [title] 的「⋯」。
    Finder moreOf(String title) => find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byTooltip('More options'),
    );

    List<String> queued(ShellHarness h) => [
      for (final entry in h.controller.queue.entries) entry.track.sourceId,
    ];

    // 選單是 overlay：以滑鼠或點按打開的也要能以 Esc 關掉（design §9.5）。
    testWidgets('Esc closes the menu opened from "⋯"', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');

      await tester.tap(moreOf('Song a'));
      await tester.pump();
      expect(find.text('Play next'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Play next'), findsNothing);
      expect(h.controller.queue.entries, isEmpty);
    });

    testWidgets('tapping a result plays it on its own (temporary play)', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');

      await tester.tap(find.text('Song b'));
      await tester.pump();
      await tester.pump();

      final queue = h.controller.queue;
      expect(queue.mode, QueueMode.temporary);
      expect(
        queue.current?.key,
        const TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'b'),
      );
      expect(queue.entries, isEmpty, reason: 'the queue is untouched');
      // 播放列讀佇列項目的顯示資料。
      expect(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.text('Song b'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the menu adds to the queue, plays next, and plays', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');

      await tester.tap(moreOf('Song a'));
      await tester.pump();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(queued(h), ['a']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Added to queue'), findsOneWidget);
      expect(h.controller.state, isA<Idle>(), reason: 'adding does not play');

      await tester.tap(moreOf('Song c'));
      await tester.pump();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      await tester.tap(moreOf('Song b'));
      await tester.pump();
      await tester.tap(find.text('Play next'));
      await tester.pump();
      expect(queued(h), ['a', 'b', 'c']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Added to play next'), findsOneWidget);

      await tester.tap(moreOf('Song c'));
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump();
      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.sourceId, 'c');
      expect(queued(h), ['a', 'b', 'c']);
    });

    // 長按是多選（見 `selecting`），選單在右鍵與「⋯」。
    testWidgets('right click and "⋯" open the same menu', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');

      await tester.tap(find.text('Song a'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pump();
      expect(queued(h), ['a']);

      await tester.tap(moreOf('Song b'));
      await tester.pump();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(queued(h), ['a', 'b']);
    });
  });

  group('source chips', () {
    testWidgets('switching the source searches it again', (tester) async {
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        name: 'Other Source',
        onSearch: (_) => const SearchPage(items: [], hasMore: false),
      );
      final h = ShellHarness();
      h.sources.add(other);
      await h.pumpShell(tester);
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips.map((chip) => chip.selected), [true, false]);

      await search(tester, 'song');
      await tester.tap(find.text('Other Source'));
      await tester.pump();
      await tester.pump();

      expect(other.searches.single.keyword, 'song');
      expect(find.text('No results for “song”'), findsOneWidget);
    });

    testWidgets('tapping the selected chip does not search again', (
      tester,
    ) async {
      final h = ShellHarness();
      h.sources.add(
        FakeSourcePlugin(
          (_) => const [],
          id: 'other',
          name: 'Other Source',
          onSearch: (_) => const SearchPage(items: [], hasMore: false),
        ),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');

      // 還沒點過任何 chip：選的是清單的第一個。
      await tester.tap(find.text('Test Source'));
      await tester.pump();
      await tester.pump();

      expect(h.plugin.searches, hasLength(1));
      expect(find.text('Song a'), findsOneWidget);
    });

    testWidgets('the row scrolls sideways on a narrow window', (tester) async {
      final h = ShellHarness(sources: []);
      for (var i = 0; i < 8; i++) {
        h.sources.add(
          FakeSourcePlugin(
            (_) => const [],
            id: 'source-$i',
            name: 'Source number $i',
            onSearch: (_) => const SearchPage(items: [], hasMore: false),
          ),
        );
      }
      await h.pumpShell(tester, size: const Size(400, 800));
      final last = find.text('Source number 7');
      expect(last.hitTestable(), findsNothing);

      await tester.scrollUntilVisible(
        last,
        200,
        scrollable: find
            .ancestor(of: last, matching: find.byType(Scrollable))
            .first,
      );
      expect(last.hitTestable(), findsOneWidget);
    });
  });

  // ToastHost 在 Navigator 外面多包了一個 Overlay，它成了 root overlay：文字
  // 選取工具列與放大鏡插在那裡（12a 審查留下的）。
  group('text selection over the toast host', () {
    testWidgets('long press shows the toolbar and the magnifier', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final field = find.byType(EditableText);
      final gesture = await tester.startGesture(
        tester.getTopLeft(field) + const Offset(10, 10),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(find.byType(TextMagnifier), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      final selectAll = find.text('Select all');
      expect(selectAll.hitTestable(), findsOneWidget);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      final selection = tester.widget<EditableText>(field).controller.selection;
      expect((selection.start, selection.end), (0, 'hello world'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('right click shows the context menu', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final field = find.byType(EditableText);
      await tester.tapAt(
        tester.getTopLeft(field) + const Offset(10, 10),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final selectAll = find.text('Select all');
      expect(selectAll.hitTestable(), findsOneWidget);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      final selection = tester.widget<EditableText>(field).controller.selection;
      expect((selection.start, selection.end), (0, 'hello world'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  // 多選（M4 PR 5，design §10.7）：輸入框留著，音源 chip 列換成選取列。多分 P 影片的取法在
  // `search_parts_test.dart` 的 `selecting`。
  group('selecting', () {
    List<String> queued(ShellHarness h) => [
      for (final entry in h.controller.queue.entries) entry.track.sourceId,
    ];

    Future<void> ctrlA(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('a long press enters; the field stays and the bar replaces '
        'the source chips; a tap checks instead of playing', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');

      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('Song c'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(h.controller.queue.current, isNull, reason: 'nothing played');

      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      await tester.pump();
      expect(queued(h), ['b', 'c']);
      expect(find.byType(ChoiceChip), findsOneWidget);
    });

    testWidgets('Ctrl+A in the search field selects its text; outside it, '
        'every result', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await ctrlA(tester);
      expect(
        field.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(find.text('1 selected'), findsOneWidget);

      // Esc 先離開輸入框（外殼的規則），焦點回到頁面上（不用先點一列），Ctrl+A 是全選。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await ctrlA(tester);
      expect(find.text('3 selected'), findsOneWidget);

      // 再一次 Esc 離開選取模式。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(ChoiceChip), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('the back key leaves selection mode first, then Search', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Song b'), findsOneWidget, reason: 'still on Search');

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Song b').hitTestable(), findsNothing);
    });

    // 再點一次目前的導覽項退回根頁；已經在根頁時什麼都不動，根頁上的選取模式（`LocalHistoryEntry`）照舊留著
    // （M4 PR 19 的審查：外殼只對不放行的內頁 `maybePop`）。
    testWidgets('tapping Search again keeps the selection', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await h.open(tester, ShellDestination.search);
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('a new search leaves selection mode', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await search(tester, 'song');
      await tester.longPress(find.text('Song a'));
      await tester.pumpAndSettle();

      // 同樣的結果：位置一樣，但已經是另一份結果。
      await search(tester, 'song');
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ChoiceChip), findsOneWidget);
    });
  });
}
