import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/plugins/source_icon.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 「全部音源」搜尋（U PR 17，ADR 0035 §決定 9）：預設選「全部音源」，每個音源一組，各組自己的
// 載入、失敗與下一頁。引擎本身的規則在 `test/plugins/search/all_sources_search_test.dart`。
// 假插件：`fmp-test`（Test Source，harness 內建）與 `other`（Other Source）。

TrackSummary _otherTrack(String id) => TrackSummary(
  sourceTypeId: 'other',
  sourceId: id,
  title: 'Other song $id',
  uploader: 'Other uploader',
  duration: const Duration(minutes: 2),
  artwork: const [],
);

FakeSourcePlugin _other(
  FutureOr<SearchPage> Function(SearchQuery query) onSearch, {
  bool live = false,
}) => FakeSourcePlugin(
  (_) => const [],
  id: 'other',
  name: 'Other Source',
  onSearch: onSearch,
  live: live,
);

Future<void> _search(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

/// 結果列表裡的組標題。harness 只替內建的音源解析名稱，其他音源的標題退回插件 id。
Finder _header(String name) => find.text(name).last;

void main() {
  testWidgets('the all-sources chip comes first and is selected by default', (
    tester,
  ) async {
    final h = ShellHarness();
    h.sources.add(_other((_) => const SearchPage(items: [], hasMore: false)));
    await h.pumpShell(tester);

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(chips.map((chip) => (chip.label as Text).data), [
      'All sources',
      'Test Source',
      'Other Source',
    ]);
    expect(chips.map((chip) => chip.selected), [true, false, false]);
    expect(h.container(tester).read(searchProvider).sourceId, isNull);
  });

  testWidgets('results are grouped under each source, in the chip order', (
    tester,
  ) async {
    final pending = Completer<SearchPage>();
    final h = ShellHarness(onSearch: (_) => pending.future);
    final other = _other(
      (_) => SearchPage(items: [_otherTrack('o1')], hasMore: false),
    );
    h.sources.add(other);
    await h.pumpShell(tester);
    await _search(tester, 'song');

    // 第二個音源先回來：它的標題仍排在第一個音源之後；第一個還在轉圈。
    expect(other.searches.single.keyword, 'song');
    expect(h.plugin.searches.single.keyword, 'song');
    expect(find.text('Other song o1'), findsOneWidget);
    expect(find.bySemanticsLabel('Searching'), findsOneWidget);
    expect(
      tester.getTopLeft(_header('Test Source')).dy,
      lessThan(tester.getTopLeft(_header('other')).dy),
    );

    pending.complete(SearchPage(items: [summary('a')], hasMore: false));
    await tester.pump();
    expect(find.text('Song a'), findsOneWidget);
    expect(find.byType(SourceIcon), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Song a')).dy,
      lessThan(tester.getTopLeft(_header('other')).dy),
      reason: 'the first group stays above the second once it arrives',
    );
  });

  testWidgets('a failing source shows a compact error with retry; the other '
      'group is untouched', (tester) async {
    var fail = true;
    final h = ShellHarness(
      onSearch: (_) => fail
          ? throw RateLimited(pluginId: 'fmp-test')
          : SearchPage(items: [summary('a')], hasMore: false),
    );
    final other = _other(
      (_) => SearchPage(items: [_otherTrack('o1')], hasMore: false),
    );
    h.sources.add(other);
    await h.pumpShell(tester);
    await _search(tester, 'song');
    await tester.pumpAndSettle();

    final error = find.byWidgetPredicate(
      (widget) => widget is EmptyState && widget.compact && widget.error,
    );
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.text(
          'Too many requests to Test Source. Try again later.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Other song o1'), findsOneWidget);
    // 畫在組裡，不另外跳提示；仍留下紀錄。
    expect(find.text('Search failed'), findsOneWidget);
    expect(
      h.log.history.where((record) => record.message == 'Search failed'),
      hasLength(1),
    );

    fail = false;
    await tester.tap(find.descendant(of: error, matching: find.text('Retry')));
    await tester.pump();
    await tester.pump();

    expect(h.plugin.searches, hasLength(2));
    expect(
      other.searches,
      hasLength(1),
      reason: 'the other group is not reloaded',
    );
    expect(find.text('Song a'), findsOneWidget);
    expect(error, findsNothing);
  });

  testWidgets('offline, a failed group says so', (tester) async {
    final h = ShellHarness(
      onSearch: (_) => throw NetworkError(pluginId: 'fmp-test'),
    );
    h.sources.add(
      _other((_) => SearchPage(items: [_otherTrack('o1')], hasMore: false)),
    );
    await h.pumpShell(tester);
    await h.setNetwork(tester, NetworkStatus.noInterface);
    await _search(tester, 'song');
    await tester.pumpAndSettle();

    final error = find.byWidgetPredicate(
      (widget) => widget is EmptyState && widget.compact && widget.error,
    );
    expect(
      find.descendant(of: error, matching: find.text('No network connection')),
      findsOneWidget,
    );
    expect(find.text('Other song o1'), findsOneWidget);
    expect(h.plugin.searches, hasLength(1), reason: 'the search is still sent');
  });

  group('next pages', () {
    testWidgets('an earlier group has a Load more button; only the last '
        'group loads by itself', (tester) async {
      final h = ShellHarness(
        onSearch: (query) => SearchPage(
          items: [summary('a${query.page}')],
          hasMore: query.page < 2,
        ),
      );
      final other = _other(
        (query) => SearchPage(
          items: [_otherTrack('o${query.page}')],
          hasMore: query.page < 3,
        ),
      );
      h.sources.add(other);
      await h.pumpShell(tester);
      await _search(tester, 'song');
      await tester.pump();
      await tester.pump();

      // 最後一組（Other）自己載到底（3 頁）；前面的組沒有自動載入。
      expect(other.searches.map((query) => query.page), [1, 2, 3]);
      expect(h.plugin.searches.map((query) => query.page), [1]);
      expect(find.text('Other song o3'), findsOneWidget);
      expect(find.text('All loaded'), findsOneWidget);
      final more = find.widgetWithText(OutlinedButton, 'Load more');
      expect(more, findsOneWidget);

      await tester.tap(more);
      await tester.pump();
      await tester.pump();

      // 第一組只動自己的頁碼，另一組沒有再發請求。
      expect(h.plugin.searches.map((query) => query.page), [1, 2]);
      expect(other.searches, hasLength(3));
      expect(find.text('Song a2'), findsOneWidget);
      expect(more, findsNothing);
    });

    testWidgets('a failed next page keeps the group and offers Load more', (
      tester,
    ) async {
      var fail = false;
      final h = ShellHarness(
        onSearch: (query) => query.page == 2 && fail
            ? throw NetworkError(pluginId: 'fmp-test')
            : SearchPage(items: [summary('a${query.page}')], hasMore: true),
      );
      h.sources.add(
        _other((_) => SearchPage(items: [_otherTrack('o1')], hasMore: false)),
      );
      await h.pumpShell(tester);
      await _search(tester, 'song');
      await tester.pump();

      fail = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Load more'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Song a1'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Load more'), findsOneWidget);
      expect(find.text('Other song o1'), findsOneWidget);
    });
  });

  testWidgets('a stale query is ignored', (tester) async {
    final first = Completer<SearchPage>();
    final h = ShellHarness(
      onSearch: (query) => query.keyword == 'old'
          ? first.future
          : SearchPage(items: [summary('new')], hasMore: false),
    );
    h.sources.add(
      _other((_) => SearchPage(items: [_otherTrack('o1')], hasMore: false)),
    );
    await h.pumpShell(tester);

    await _search(tester, 'old');
    await _search(tester, 'fresh');
    expect(find.text('Song new'), findsOneWidget);

    first.complete(SearchPage(items: [summary('old')], hasMore: false));
    await tester.pump();
    await tester.pump();
    expect(find.text('Song old'), findsNothing);
    expect(find.text('Song new'), findsOneWidget);
    expect(h.container(tester).read(searchProvider).keyword, 'fresh');
  });

  testWidgets('switching to one source and back to all', (tester) async {
    final h = ShellHarness();
    final other = _other(
      (_) => SearchPage(items: [_otherTrack('o1')], hasMore: false),
    );
    h.sources.add(other);
    await h.pumpShell(tester);
    await _search(tester, 'song');
    expect(find.byType(SourceIcon), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Other Source'));
    await tester.pump();
    await tester.pump();
    // 單一音源：沒有組標題。
    expect(find.byType(SourceIcon), findsNothing);
    expect(find.text('Other song o1'), findsOneWidget);
    expect(find.text('Song a'), findsNothing);
    expect(other.searches, hasLength(2));
    expect(h.plugin.searches, hasLength(1));

    await tester.tap(find.widgetWithText(ChoiceChip, 'All sources'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SourceIcon), findsNWidgets(2));
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Other song o1'), findsOneWidget);
    expect(h.plugin.searches, hasLength(2));
  });

  testWidgets('a group with no results says so', (tester) async {
    final h = ShellHarness();
    h.sources.add(_other((_) => const SearchPage(items: [], hasMore: false)));
    await h.pumpShell(tester);
    await _search(tester, 'song');

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('No results from this source'), findsOneWidget);
  });

  testWidgets('every group empty is the usual no-results state', (
    tester,
  ) async {
    final h = ShellHarness(
      onSearch: (_) => const SearchPage(items: [], hasMore: false),
    );
    h.sources.add(_other((_) => const SearchPage(items: [], hasMore: false)));
    await h.pumpShell(tester);
    await _search(tester, 'nothing');

    expect(find.text('No results for “nothing”'), findsOneWidget);
  });

  testWidgets('selecting across groups: select all and add in screen order', (
    tester,
  ) async {
    final h = ShellHarness();
    h.sources.add(
      _other((_) => SearchPage(items: [_otherTrack('o1')], hasMore: false)),
    );
    await h.pumpShell(tester);
    await _search(tester, 'song');

    await tester.longPress(find.text('Other song o1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song c'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('4 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Play next'));
    await tester.pump();
    await tester.pump();
    expect(
      [for (final entry in h.controller.queue.entries) entry.track.sourceId],
      ['a', 'b', 'c', 'o1'],
      reason: 'the first group comes first',
    );
  });

  group('live rooms', () {
    LiveRoom room(String id) => LiveRoom(
      roomId: id,
      title: 'Room $id',
      hostName: 'Host',
      status: LiveRoomStatus.live,
      online: 1,
      artwork: const [],
    );

    testWidgets('are grouped by source too, only for sources with live', (
      tester,
    ) async {
      final h = ShellHarness(live: true);
      h.plugin.onLiveSearch = (_) =>
          LiveSearchPage(items: [room('r1')], hasMore: false);
      final liveOther =
          _other((_) => const SearchPage(items: [], hasMore: false), live: true)
            ..onLiveSearch = ((_) =>
                LiveSearchPage(items: [room('r2')], hasMore: false));
      final noLive = FakeSourcePlugin(
        (_) => const [],
        id: 'plain',
        name: 'Plain Source',
        onSearch: (_) => const SearchPage(items: [], hasMore: false),
      );
      h.sources
        ..add(noLive)
        ..add(liveOther);
      await h.pumpShell(tester);

      await tester.tap(find.text('Live rooms'));
      await tester.pump();
      await _search(tester, 'night');
      await tester.pump();

      expect(find.text('Room r1'), findsOneWidget);
      expect(find.text('Room r2'), findsOneWidget);
      expect(find.byType(SourceIcon), findsNWidgets(2));
      expect(noLive.searches, isEmpty);
      expect(h.container(tester).read(searchProvider).roomGroups, hasLength(2));
    });
  });
}
