import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/search/search_state.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 搜尋頁的直播間模式（ADR 0031 §決定 5、M3 design §9.5）：只有宣告 `live` 的音源有分段鈕、
// 換到沒宣告的音源退回曲目、篩選傳進 liveSearch、結果列的內容、點一下收聽、「加為電台」。

LiveRoom _room(
  String id, {
  LiveRoomStatus status = LiveRoomStatus.live,
  int? online,
}) => LiveRoom(
  roomId: id,
  title: 'Room $id',
  hostName: 'Host $id',
  status: status,
  online: online,
);

/// 測試插件宣告 `live`，另有一個沒宣告的音源「Other Source」。
ShellHarness _harness({
  FutureOr<LiveSearchPage> Function(LiveSearchQuery query)? onLiveSearch,
}) {
  final h = ShellHarness(live: true);
  h.plugin
    ..onLiveSearch =
        onLiveSearch ??
        ((_) => LiveSearchPage(
          items: [
            _room('r1', online: 12345),
            _room('r2', status: LiveRoomStatus.offline),
          ],
          hasMore: false,
        ))
    ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')]);
  h.sources.add(
    FakeSourcePlugin(
      (_) => const [],
      id: 'other',
      name: 'Other Source',
      onSearch: (_) => const SearchPage(items: [], hasMore: false),
    ),
  );
  return h;
}

FakeSourcePlugin _other(ShellHarness h) =>
    h.sources.whereType<FakeSourcePlugin>().last;

Finder get _modes => find.byType(SegmentedButton<SearchMode>);

Future<void> _search(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

Finder _roomRow(String id) => find.widgetWithText(ListTile, 'Room $id');

Finder _toast(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

/// 測試裡可以換的音源清單（`searchSourcesProvider` 的來源）。
final class _Sources extends Notifier<List<SourcePlugin>> {
  _Sources(this._initial);

  final List<SourcePlugin> _initial;

  @override
  List<SourcePlugin> build() => _initial;

  void set(List<SourcePlugin> sources) => state = sources;
}

void main() {
  group('the mode buttons', () {
    testWidgets('show only for a source that declares live', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      expect(_modes, findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Live rooms'), findsOneWidget);

      await _tapAndSettle(tester, find.text('Other Source'));
      expect(_modes, findsNothing);
    });

    testWidgets('switching to a source without live goes back to songs', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');
      expect(h.plugin.liveSearches.single.keyword, 'night');
      expect(h.container(tester).read(searchProvider).mode, SearchMode.rooms);

      await _tapAndSettle(tester, find.text('Other Source'));
      expect(h.container(tester).read(searchProvider).mode, SearchMode.tracks);
      // 換音源照常以同一個關鍵字搜曲目。
      expect(_other(h).searches.single.keyword, 'night');

      await _tapAndSettle(tester, find.text('Test Source'));
      expect(tester.widget<SegmentedButton<SearchMode>>(_modes).selected, {
        SearchMode.tracks,
      });
      expect(h.plugin.searches.single.keyword, 'night');
      expect(h.plugin.liveSearches, hasLength(1));
    });

    // 選的音源從清單上消失（停用、移除）而剩下的第一個沒有直播間：notifier 自己退回曲目，
    // 之後的搜尋不會對沒宣告 `live` 的插件呼叫 liveSearch。
    test('the live source leaving the list goes back to songs', () async {
      SearchPage noTracks(SearchQuery _) =>
          const SearchPage(items: [], hasMore: false);
      final live = FakeSourcePlugin(
        (_) => const [],
        live: true,
        onSearch: noTracks,
      );
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        onSearch: noTracks,
      );
      final sources = NotifierProvider<_Sources, List<SourcePlugin>>(
        () => _Sources([live, other]),
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
      await search.selectMode(SearchMode.rooms);
      expect(container.read(searchProvider).mode, SearchMode.rooms);

      container.read(sources.notifier).set([other]);
      await container.pump();
      expect(container.read(searchProvider).mode, SearchMode.tracks);

      await search.search('night');
      expect(other.searches.single.keyword, 'night');
      expect(other.liveSearches, isEmpty);
    });

    testWidgets('the room filter goes into liveSearch', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      // 篩選只在直播間模式出現。
      expect(find.widgetWithText(ChoiceChip, 'All'), findsNothing);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');
      expect(h.plugin.liveSearches.last.status, isNull);

      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Live'));
      expect(h.plugin.liveSearches.last.status, LiveRoomStatus.live);
      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Offline'));
      expect(h.plugin.liveSearches.last.status, LiveRoomStatus.offline);
      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'All'));
      expect(h.plugin.liveSearches.last.status, isNull);
      expect(h.plugin.liveSearches, hasLength(4));
      expect(h.plugin.liveSearches.map((query) => query.keyword).toSet(), {
        'night',
      });
    });
  });

  // 重搜用輸入框現在的文字，不是上次送出的關鍵字（#260）。
  group('re-searching uses the text in the field', () {
    testWidgets('clearing the field then switching source sends nothing', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Test Source'));
      await _search(tester, 'night');
      expect(h.plugin.searches.single.keyword, 'night');

      await _tapAndSettle(tester, find.byTooltip('Clear'));
      await _tapAndSettle(tester, find.text('Other Source'));
      expect(_other(h).searches, isEmpty);
      final state = h.container(tester).read(searchProvider);
      expect(state.phase, SearchPhase.idle);
      expect(state.isEmpty, isTrue);
    });

    testWidgets('text typed but not submitted is what the new source gets', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Test Source'));
      await _search(tester, 'night');

      await tester.enterText(find.byType(TextField), 'day');
      await _tapAndSettle(tester, find.text('Other Source'));
      expect(_other(h).searches.single.keyword, 'day');
    });

    testWidgets('switching mode and the room filter use it too', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _search(tester, 'night');

      await tester.enterText(find.byType(TextField), 'day');
      await _tapAndSettle(tester, find.text('Live rooms'));
      expect(h.plugin.liveSearches.single.keyword, 'day');

      await tester.enterText(find.byType(TextField), 'dusk');
      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Live'));
      expect(h.plugin.liveSearches.last.keyword, 'dusk');

      await tester.enterText(find.byType(TextField), '  ');
      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Offline'));
      expect(h.plugin.liveSearches, hasLength(2));
      expect(h.container(tester).read(searchProvider).rooms, isEmpty);
    });

    // 重試送的是上次送出的關鍵字，但不把它寫回輸入框的文字：清除後重試再換條件，仍不發請求。
    testWidgets('retrying after clearing the field does not bring the text '
        'back', (tester) async {
      final h = _harness(
        onLiveSearch: (_) => throw NetworkError(pluginId: 'fmp-test'),
      );
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');
      await tester.pump(const Duration(seconds: 7));

      // 空白的輸入框列出搜尋歷史（剛送出的 night）、蓋住失敗畫面：清掉歷史，重試鈕才看得到。
      await _tapAndSettle(tester, find.byTooltip('Clear'));
      await h.loadSettings(tester);
      await _tapAndSettle(tester, find.widgetWithText(TextButton, 'Clear'));
      await h.loadSettings(tester);
      await _tapAndSettle(tester, find.widgetWithText(FilledButton, 'Retry'));
      expect(h.plugin.liveSearches.map((query) => query.keyword), [
        'night',
        'night',
      ]);

      await _tapAndSettle(tester, find.widgetWithText(ChoiceChip, 'Live'));
      expect(h.plugin.liveSearches, hasLength(2));
      // 重試與換篩選不記進搜尋歷史，只有送出才記。
      final stored = await tester.runAsync(
        () => h.container(tester).read(searchHistoryRepositoryProvider).list(),
      );
      expect(stored, isEmpty);
    });

    testWidgets('typing is stored as the text of the field', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'unsent');
      await tester.pump();
      expect(h.container(tester).read(searchInputProvider), 'unsent');
    });

    test('falling back to songs searches the text in the field', () async {
      SearchPage noTracks(SearchQuery _) =>
          const SearchPage(items: [], hasMore: false);
      final live = FakeSourcePlugin(
        (_) => const [],
        live: true,
        onSearch: noTracks,
      );
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        onSearch: noTracks,
      );
      final sources = NotifierProvider<_Sources, List<SourcePlugin>>(
        () => _Sources([live, other]),
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
      await search.selectMode(SearchMode.rooms);

      // 輸入框是空的：退回曲目但不發請求。
      container.read(sources.notifier).set([other]);
      await container.pump();
      expect(container.read(searchProvider).mode, SearchMode.tracks);
      expect(other.searches, isEmpty);

      // 輸入框有未送出的字：以它搜尋。
      container.read(sources.notifier).set([live, other]);
      await container.pump();
      await search.selectMode(SearchMode.rooms);
      container.read(searchInputProvider.notifier).set('  moon ');
      container.read(sources.notifier).set([other]);
      await container.pump();
      await container.pump();
      expect(container.read(searchProvider).mode, SearchMode.tracks);
      expect(other.searches.single.keyword, 'moon');
    });
  });

  group('room results', () {
    testWidgets('show the title, host, status and viewers', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      expect(
        find.descendant(
          of: _roomRow('r1'),
          matching: find.textContaining('Host r1'),
        ),
        findsOneWidget,
      );
      String tag(String id) => tester
          .widget<StatusTag>(
            find.descendant(of: _roomRow(id), matching: find.byType(StatusTag)),
          )
          .text;
      expect(tag('r1'), 'Live');
      expect(tag('r2'), 'Offline');
      expect(
        find.descendant(
          of: _roomRow('r1'),
          matching: find.text('12.3K watching'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('watching'), findsOneWidget);
    });

    // 未開播的直播間（B-27）：封面灰階、「收聽」停用、點一下提示，不嘗試播放。
    testWidgets('an offline room is grayed out and cannot be listened to', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      Finder grayscale(String id) => find.descendant(
        of: _roomRow(id),
        matching: find.byType(ColorFiltered),
      );
      expect(grayscale('r1'), findsNothing);
      expect(grayscale('r2'), findsOneWidget);

      // 點一下：提示，不播。
      await tester.tap(_roomRow('r2'));
      await tester.pump();
      expect(_toast('Not live yet'), findsOneWidget);
      expect(h.container(tester).read(nowPlayingLiveProvider), isNull);

      // 選單的「收聽」停用，「加為電台」照常。
      await tester.tap(
        find.descendant(
          of: _roomRow('r2'),
          matching: find.byTooltip('More options'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.widgetWithText(MenuItemButton, 'Listen'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<MenuItemButton>(
              find.widgetWithText(MenuItemButton, 'Add to Radio'),
            )
            .onPressed,
        isNotNull,
      );
    });

    // 未開播的直播間不顯示人數，不管插件給了什麼值（#262）。
    testWidgets('an offline room shows no viewers even with a count', (
      tester,
    ) async {
      final h = _harness(
        onLiveSearch: (_) => LiveSearchPage(
          items: [
            _room('r1', online: 321),
            _room('r2', status: LiveRoomStatus.offline, online: 500),
          ],
          hasMore: false,
        ),
      );
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      expect(
        find.descendant(
          of: _roomRow('r1'),
          matching: find.text('321 watching'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _roomRow('r2'),
          matching: find.textContaining('watching'),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping a room listens to it', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      await tester.tap(_roomRow('r1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final target = h.controller.queue.live!.target;
      expect((target.pluginId, target.roomId), ('fmp-test', 'r1'));
      expect(target.title, 'Room r1');
      expect(target.hostName, 'Host r1');
      expect(h.plugin.liveRequests.single.roomId, 'r1');
    });

    testWidgets('"Add to Radio" writes the room and says so; again says it '
        'is already there', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      Future<void> addToRadio() async {
        await tester.tap(
          find.descendant(
            of: _roomRow('r1'),
            matching: find.byTooltip('More options'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Add to Radio'));
        // 寫入是資料庫的交易，監看的串流回來還要一輪。
        for (var i = 0; i < 4; i++) {
          await h.loadSettings(tester);
        }
      }

      await addToRadio();
      expect(_toast('Added to Radio'), findsOneWidget);
      final stations = h.container(tester).read(radioStationsProvider).value!;
      expect(stations.single.roomId, 'r1');
      expect(stations.single.pluginId, 'fmp-test');
      expect(stations.single.title, 'Room r1');

      await addToRadio();
      expect(_toast('Already in your stations'), findsOneWidget);
      expect(
        h.container(tester).read(radioStationsProvider).value,
        hasLength(1),
      );
      // 加為電台不收聽。
      expect(h.controller.queue.live, isNull);
    });

    testWidgets('the next page of rooms loads by itself at the last row', (
      tester,
    ) async {
      final h = _harness(
        onLiveSearch: (query) => LiveSearchPage(
          items: [_room('p${query.page}')],
          hasMore: query.page == 1,
        ),
      );
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');
      await tester.pumpAndSettle();

      expect(h.plugin.liveSearches.map((query) => query.page), [1, 2]);
      expect(_roomRow('p1'), findsOneWidget);
      expect(_roomRow('p2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('All loaded'), findsOneWidget);
    });

    testWidgets('a search that fails offline shows the offline state', (
      tester,
    ) async {
      final h = _harness(
        onLiveSearch: (_) => throw NetworkError(pluginId: 'fmp-test'),
      );
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      expect(find.byType(OfflineMessage), findsOneWidget);
      expect(h.plugin.liveSearches, hasLength(1));
    });

    testWidgets('no rooms found says so', (tester) async {
      final h = _harness(
        onLiveSearch: (_) => const LiveSearchPage(items: [], hasMore: false),
      );
      await h.pumpShell(tester);
      await _tapAndSettle(tester, find.text('Live rooms'));
      await _search(tester, 'night');

      expect(find.text('No results for “night”'), findsOneWidget);
    });
  });
}
