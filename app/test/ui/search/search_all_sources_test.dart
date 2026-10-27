import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/search/all_sources_search.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
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

/// 可以換掉的音源清單（插件更新、停用）。
final class _Sources extends Notifier<List<SourcePlugin>> {
  _Sources(this._initial);

  final List<SourcePlugin> _initial;

  @override
  List<SourcePlugin> build() => _initial;

  void set(List<SourcePlugin> sources) => state = sources;
}

/// 測試決定什麼時候回的音源：每次搜尋以「插件 id／關鍵字／頁碼」記一個 [Completer]。
final class _Held {
  final pending = <String, Completer<SearchPage>>{};

  FakeSourcePlugin plugin(String id) => FakeSourcePlugin(
    (_) => const [],
    id: id,
    name: id,
    onSearch: (query) =>
        (pending['$id/${query.keyword}/${query.page}'] = Completer()).future,
  );

  void answer(String key, SearchPage page) => pending[key]!.complete(page);
}

/// 搜尋的 notifier，音源清單可以換（停用、移除、更新）。
(ProviderContainer, NotifierProvider<_Sources, List<SourcePlugin>>) _container(
  List<SourcePlugin> initial,
) {
  final sources = NotifierProvider<_Sources, List<SourcePlugin>>(
    () => _Sources(initial),
  );
  final container = ProviderContainer(
    overrides: [
      searchSourcesProvider.overrideWith(
        (ref) => AsyncData(ref.watch(sources)),
      ),
      logProvider.overrideWithValue(
        Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(searchProvider, (_, _) {});
  return (container, sources);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

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

  group('the source list changing after a search', () {
    // 停用、移除：那一組當場拿掉，路上的結果丟掉，之後的下一頁與重試不會再到它。
    test(
      'a disabled plugin loses its group and is never asked again',
      () async {
        final held = _Held();
        final more = FakeSourcePlugin(
          (_) => const [],
          id: 'more',
          onSearch: (query) =>
              SearchPage(items: [summary('m${query.page}')], hasMore: true),
        );
        final failing = FakeSourcePlugin(
          (_) => const [],
          id: 'failing',
          onSearch: (_) => throw NetworkError(pluginId: 'failing'),
        );
        final slow = held.plugin('slow');
        final stays = FakeSourcePlugin(
          (_) => const [],
          id: 'stays',
          onSearch: (_) => SearchPage(items: [summary('s')], hasMore: false),
        );
        final (container, sources) = _container([more, failing, slow, stays]);
        final search = container.read(searchProvider.notifier);
        container.read(searchInputProvider.notifier).set('song');
        unawaited(search.search('song'));
        await _settle();
        await _settle();
        expect(container.read(searchProvider).trackGroups.map((g) => g.phase), [
          GroupPhase.loaded,
          GroupPhase.failed,
          GroupPhase.loading,
          GroupPhase.loaded,
        ]);

        container.read(sources.notifier).set([stays]);
        await container.pump();
        expect(
          container.read(searchProvider).trackGroups.map((g) => g.pluginId),
          ['stays'],
        );

        held.answer(
          'slow/song/1',
          SearchPage(items: [summary('late')], hasMore: false),
        );
        await search.loadMore('more');
        await search.retryGroup('failing');
        await _settle();

        expect(more.searches, hasLength(1));
        expect(failing.searches, hasLength(1));
        final state = container.read(searchProvider);
        expect(state.trackGroups.map((g) => g.pluginId), ['stays']);
        expect(state.items.map((track) => track.sourceId), ['s']);
        expect(
          state.phase,
          SearchPhase.loaded,
          reason: 'one group: page states',
        );
      },
    );

    test(
      'the last group leaving goes back to the page before searching',
      () async {
        final only = FakeSourcePlugin(
          (_) => const [],
          id: 'only',
          onSearch: (_) => SearchPage(items: [summary('o')], hasMore: false),
        );
        final other = FakeSourcePlugin(
          (_) => const [],
          id: 'other',
          onSearch: (_) => SearchPage(items: [summary('x')], hasMore: false),
        );
        final (container, sources) = _container([only, other]);
        final search = container.read(searchProvider.notifier);
        container.read(searchInputProvider.notifier).set('song');
        await search.selectSource('only');
        expect(container.read(searchProvider).groupCount, 1);

        container.read(sources.notifier).set([other]);
        await container.pump();
        final state = container.read(searchProvider);
        expect(state.groupCount, 0);
        expect(state.phase, SearchPhase.idle);
        expect(other.searches, isEmpty, reason: 'no search until the next one');
      },
    );

    // 新啟用的音源不補進目前的結果，下一次送出才有它。
    test('a plugin enabled mid-search joins at the next search', () async {
      SearchPage one(SearchQuery query) =>
          SearchPage(items: [summary(query.keyword)], hasMore: false);
      final a = FakeSourcePlugin((_) => const [], id: 'a', onSearch: one);
      final b = FakeSourcePlugin((_) => const [], id: 'b', onSearch: one);
      final late = FakeSourcePlugin((_) => const [], id: 'late', onSearch: one);
      final (container, sources) = _container([a, b]);
      final search = container.read(searchProvider.notifier);
      await search.search('first');

      container.read(sources.notifier).set([a, late, b]);
      await container.pump();
      expect(
        container.read(searchProvider).trackGroups.map((g) => g.pluginId),
        ['a', 'b'],
      );
      expect(late.searches, isEmpty);

      await search.search('second');
      expect(
        container.read(searchProvider).trackGroups.map((g) => g.pluginId),
        ['a', 'late', 'b'],
      );
      expect(late.searches.single.keyword, 'second');
    });

    // 插件更新：同一個 id 換成新的實例、舊的關閉。下一頁發給新的，不是搜尋當時的那一個。
    test('the next page goes to the updated plugin', () async {
      SearchPage page(SearchQuery query) =>
          SearchPage(items: [summary('p${query.page}')], hasMore: true);
      final before = FakeSourcePlugin((_) => const [], onSearch: page);
      final after = FakeSourcePlugin((_) => const [], onSearch: page);
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        onSearch: (_) => const SearchPage(items: [], hasMore: false),
      );
      final sources = NotifierProvider<_Sources, List<SourcePlugin>>(
        () => _Sources([before, other]),
      );
      final container = ProviderContainer(
        overrides: [
          searchSourcesProvider.overrideWith(
            (ref) => AsyncData(ref.watch(sources)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchProvider, (_, _) {});
      final search = container.read(searchProvider.notifier);
      await search.search('song');
      expect(before.searches.map((query) => query.page), [1]);

      container.read(sources.notifier).set([after, other]);
      await container.pump();
      await search.loadMore('fmp-test');

      expect(before.searches, hasLength(1));
      expect(after.searches.single.page, 2);
      expect(
        container.read(searchProvider).items.map((track) => track.sourceId),
        ['p1', 'p2'],
      );
    });

    // 選的音源停用了：chip 列選的是「全部」，結果卻是那個音源的；點「全部」要重搜。
    test('tapping all sources after the chosen one left re-searches', () async {
      SearchPage none(SearchQuery _) =>
          const SearchPage(items: [], hasMore: false);
      final test = FakeSourcePlugin((_) => const [], onSearch: none);
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        onSearch: none,
      );
      final third = FakeSourcePlugin(
        (_) => const [],
        id: 'third',
        onSearch: none,
      );
      final sources = NotifierProvider<_Sources, List<SourcePlugin>>(
        () => _Sources([test, other, third]),
      );
      final container = ProviderContainer(
        overrides: [
          searchSourcesProvider.overrideWith(
            (ref) => AsyncData(ref.watch(sources)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchProvider, (_, _) {});
      final search = container.read(searchProvider.notifier);
      container.read(searchInputProvider.notifier).set('song');
      await search.selectSource('other');
      expect(other.searches, hasLength(1));
      expect(test.searches, isEmpty);

      container.read(sources.notifier).set([test, third]);
      await container.pump();
      await search.selectSource(null);

      expect(container.read(searchProvider).sourceId, isNull);
      expect(test.searches, hasLength(1));
      expect(third.searches, hasLength(1));
      expect(container.read(searchProvider).trackGroups, hasLength(2));

      // 已經是「全部」：再點不動。
      await search.selectSource(null);
      expect(test.searches, hasLength(1));
    });
  });

  testWidgets('group titles are headers and a failed group is announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = ShellHarness(
      onSearch: (_) => throw RateLimited(pluginId: 'fmp-test'),
    );
    h.sources.add(
      _other((_) => SearchPage(items: [_otherTrack('o1')], hasMore: false)),
    );
    await h.pumpShell(tester);
    await _search(tester, 'song');
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_header('Test Source')),
      isSemantics(label: 'Test Source', isHeader: true),
    );
    expect(
      tester.getSemantics(_header('other')),
      isSemantics(label: 'other', isHeader: true),
    );
    expect(
      tester.getSemantics(find.text('Search failed')),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  // 名額每次搜尋各自計算（ADR 0035 §決定 9）：舊搜尋的請求還在路上，新的關鍵字照樣立刻送出；
  // 舊搜尋排隊中的從來不送出。
  test(
    'a new search does not wait for the requests of the one it replaced',
    () async {
      final held = _Held();
      final ids = ['a', 'b', 'c', 'd', 'e'];
      final (container, _) = _container([
        for (final id in ids) held.plugin(id),
      ]);
      final search = container.read(searchProvider.notifier);

      unawaited(search.search('old'));
      await _settle();
      expect(held.pending.keys, ['a/old/1', 'b/old/1', 'c/old/1']);

      unawaited(search.search('new'));
      await _settle();
      expect(held.pending.keys.where((key) => key.endsWith('/new/1')), [
        'a/new/1',
        'b/new/1',
        'c/new/1',
      ], reason: 'sent while the old three are still pending');

      for (final id in ['a', 'b', 'c']) {
        held.answer(
          '$id/old/1',
          SearchPage(items: [summary('old')], hasMore: false),
        );
      }
      await _settle();
      for (final id in ['a', 'b', 'c']) {
        held.answer(
          '$id/new/1',
          SearchPage(items: [summary(id)], hasMore: false),
        );
      }
      await _settle();
      for (final id in ['d', 'e']) {
        held.answer(
          '$id/new/1',
          SearchPage(items: [summary(id)], hasMore: false),
        );
      }
      await _settle();

      expect(held.pending.keys, isNot(contains('d/old/1')));
      expect(held.pending.keys, isNot(contains('e/old/1')));
      final state = container.read(searchProvider);
      expect(state.keyword, 'new');
      expect(state.items.map((track) => track.sourceId), ids);
    },
  );
}
