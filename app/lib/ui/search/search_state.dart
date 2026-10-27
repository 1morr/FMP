import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/search/all_sources_search.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/search/video_parts.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 可以搜尋的音源：已載入、宣告了 `search`、沒有停用的插件，照插件清單的順序。
final searchSourcesProvider = Provider<AsyncValue<List<SourcePlugin>>>(
  (ref) => ref
      .watch(pluginRegistryProvider)
      .whenData(
        (plugins) => [
          for (final plugin in plugins.values)
            if (plugin.manifest.capabilities.contains(
                  PluginCapability.search,
                ) &&
                plugin.health == PluginHealth.ready)
              plugin,
        ],
      ),
);

/// 搜尋頁在做什麼（只有一個音源時；「全部音源」的進度在各組，見 [SourceGroup]）。
enum SearchPhase {
  /// 還沒搜尋。
  idle,

  /// 第一頁載入中。
  loading,

  /// 有結果（可能是 0 筆）。
  loaded,

  /// 下一頁載入中，已有的結果照樣顯示。
  loadingMore,

  /// 第一頁失敗；錯誤已經以提示顯示過。
  failed,
}

/// 搜尋頁搜的是什麼（ADR 0031 §決定 5）：曲目，或目前的音源宣告 `live` 時的直播間。
enum SearchMode { tracks, rooms }

/// 同時對音源發出的搜尋請求上限（ADR 0035 §決定 9）。
const maxConcurrentSearches = 3;

/// 一筆直播間結果與它所屬的插件（收聽與「加為電台」要用）。
@immutable
final class LiveRoomHit {
  const LiveRoomHit({required this.pluginId, required this.room});

  final String pluginId;
  final LiveRoom room;
}

/// 搜尋頁的狀態。
///
/// 結果一律分組（[SourceGroup]，每個音源一組）：選了單一音源是一組，「全部」是每個
/// 已啟用、有 `search`（直播間模式是 `live`）的音源一組，依音源清單的順序。
@immutable
final class SearchState {
  const SearchState({
    this.sourceId,
    this.keyword = '',
    this.mode = SearchMode.tracks,
    this.roomFilter,
    this.trackGroups = const [],
    this.roomGroups = const [],
    this.epoch = 0,
  });

  /// 使用者選的音源（插件 id）；`null` 或不在清單上時是「全部音源」。
  final String? sourceId;

  /// 送出的關鍵字（去掉前後空白）。
  final String keyword;

  /// 曲目或直播間；只有宣告 `live` 的音源會是 [SearchMode.rooms]。
  final SearchMode mode;

  /// 直播間的「全部｜開播中｜未開播」篩選（舊版 `LiveRoomFilter`）；`null` 是全部。換模式、
  /// 換音源時留著。
  final LiveRoomStatus? roomFilter;

  /// 曲目結果（[SearchMode.tracks]）。
  final List<SourceGroup<TrackSummary>> trackGroups;

  /// 直播間結果（[SearchMode.rooms]）。
  final List<SourceGroup<LiveRoomHit>> roomGroups;

  /// 第幾份結果：每次換條件、重搜加一，載入下一頁、重試一個音源不變。多選的鍵是位置，
  /// 這個數字變了就失效。
  final int epoch;

  /// 目前模式的曲目結果，所有組接在一起。
  List<TrackSummary> get items => [
    for (final group in trackGroups) ...group.items,
  ];

  /// 目前模式的直播間結果，所有組接在一起。
  List<LiveRoomHit> get rooms => [
    for (final group in roomGroups) ...group.items,
  ];

  /// 目前模式的各組進度。
  List<GroupPhase> get _phases => switch (mode) {
    SearchMode.tracks => [for (final group in trackGroups) group.phase],
    SearchMode.rooms => [for (final group in roomGroups) group.phase],
  };

  /// 結果有幾組；0 是還沒搜尋。
  int get groupCount => _phases.length;

  /// 整頁的進度。只有一組時就是那一組的；多組時第一次送出之後一律是 [SearchPhase.loaded]，
  /// 各組的載入、失敗畫在組裡。
  SearchPhase get phase {
    final phases = _phases;
    if (phases.isEmpty) return SearchPhase.idle;
    if (phases.length > 1) return SearchPhase.loaded;
    return switch (phases.single) {
      GroupPhase.loading => SearchPhase.loading,
      GroupPhase.loaded => SearchPhase.loaded,
      GroupPhase.loadingMore => SearchPhase.loadingMore,
      GroupPhase.failed => SearchPhase.failed,
    };
  }

  /// 目前模式的結果是不是空的：每一組都載入完而且沒有東西。
  bool get isEmpty =>
      _phases.every((phase) => phase == GroupPhase.loaded) &&
      switch (mode) {
        SearchMode.tracks => items.isEmpty,
        SearchMode.rooms => rooms.isEmpty,
      };

  /// 同一個音源、關鍵字、模式與篩選，換掉結果。
  SearchState copyWith({
    List<SourceGroup<TrackSummary>>? trackGroups,
    List<SourceGroup<LiveRoomHit>>? roomGroups,
  }) => SearchState(
    sourceId: sourceId,
    keyword: keyword,
    mode: mode,
    roomFilter: roomFilter,
    trackGroups: trackGroups ?? this.trackGroups,
    roomGroups: roomGroups ?? this.roomGroups,
    epoch: epoch,
  );

  /// 換條件（音源、模式、篩選、關鍵字）：結果清空，回到還沒搜尋。
  /// [sourceId]、[roomFilter] 以函式給，才分得出「不改」與「改成全部（`null`）」。
  SearchState restart({
    String? Function()? sourceId,
    String? keyword,
    SearchMode? mode,
    LiveRoomStatus? Function()? roomFilter,
  }) => SearchState(
    sourceId: sourceId == null ? this.sourceId : sourceId(),
    keyword: keyword ?? this.keyword,
    mode: mode ?? this.mode,
    roomFilter: roomFilter == null ? this.roomFilter : roomFilter(),
    epoch: epoch + 1,
  );
}

/// [source] 有沒有直播間可搜（宣告 `live`）。
bool hasLiveRooms(SourcePlugin? source) =>
    source?.manifest.capabilities.contains(PluginCapability.live) ?? false;

/// [sources] 裡使用者選的音源（[SearchState.sourceId]）；`null` 是「全部音源」（沒選過，或選的
/// 那個已經不在清單上）。
SourcePlugin? selectedSourceOf(String? sourceId, List<SourcePlugin> sources) {
  for (final source in sources) {
    if (source.manifest.id == sourceId) return source;
  }
  return null;
}

/// 目前的選擇有沒有直播間可搜：選了單一音源看它，「全部」看有沒有任何一個音源宣告 `live`。
bool searchHasLive(String? sourceId, List<SourcePlugin> sources) {
  final selected = selectedSourceOf(sourceId, sources);
  return selected == null ? sources.any(hasLiveRooms) : hasLiveRooms(selected);
}

/// 輸入框現在的文字（沒有去掉空白），頁面在打字、清除時寫入：換音源、模式、篩選時
/// [SearchNotifier] 以它重新搜尋，還沒送出的字也算；搜尋頁重建時輸入框顯示它。
///
/// 不放進 [SearchState]：每打一個字就換一次搜尋狀態，整個搜尋頁連同結果清單都會重建。
/// 沒有人 watch 它。
final searchInputProvider = NotifierProvider<SearchInput, String>(
  SearchInput.new,
);

/// [searchInputProvider] 的寫入端。
final class SearchInput extends Notifier<String> {
  @override
  String build() => '';

  /// 輸入框的文字變了（打字、清除）。
  void set(String input) => state = input;
}

/// 搜尋頁的狀態；換到設定頁再回來時保留。
final searchProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);

/// 搜尋與「載入更多」。新的搜尋開始後，之前還沒回來的結果丟掉，展開的分 P 收起
/// （[VideoParts.collapseAll]）。
///
/// 預設搜「全部音源」（舊版的預設）：對每個音源各發一個請求，同時最多
/// [maxConcurrentSearches] 個，每個音源一組結果（[AllSourcesSearch]）。只有一組時失敗經
/// [Toaster.error] 提示（使用者按了搜尋，屬於使用者動作的回饋）；多組時第一頁的失敗畫在
/// 那一組裡（只 log），下一頁失敗仍是提示。
/// 網路狀態不擋使用者的搜尋，`noInterface`、`unreachable` 都照常送出（ADR 0016
/// §決定 6「使用者操作照常發請求」、§決定 7 的更正）：系統回報可能是錯的，而狀態
/// 要靠請求拿到回應才回得到 `online`。
///
/// 直播間模式（ADR 0031 §決定 5）只在選的音源宣告 `live` 時（「全部」是有任何一個音源宣告）：
/// 沒有了（使用者換音源，或那個音源停用了）就退回曲目。換音源、模式、篩選時，還沒回來的
/// 結果丟掉。選的音源只留在這個 provider 裡（換頁籤再回來還在，重開 App 回到「全部」）。
final class SearchNotifier extends Notifier<SearchState> {
  final _pool = RequestPool(maxConcurrentSearches);
  AllSourcesSearch<TrackSummary>? _tracks;
  AllSourcesSearch<LiveRoomHit>? _rooms;

  @override
  SearchState build() {
    ref.onDispose(_cancel);
    // 音源清單改了（停用、移除）而目前選的沒有直播間：退回曲目。
    ref.listen(searchSourcesProvider, (_, _) {
      if (state.mode == SearchMode.rooms && !_hasLive()) {
        _cancel();
        state = state.restart(mode: SearchMode.tracks);
        unawaited(_researchInput());
      }
    });
    return const SearchState();
  }

  List<SourcePlugin> get _sources =>
      ref.read(searchSourcesProvider).value ?? const [];

  bool _hasLive() => searchHasLive(state.sourceId, _sources);

  /// 丟掉進行中的搜尋。
  void _cancel() {
    _tracks?.cancel();
    _rooms?.cancel();
    _tracks = null;
    _rooms = null;
  }

  /// 換音源（`null` 是「全部音源」）；以輸入框現在的文字重新搜尋（空的就只清掉結果）。
  /// 點的是目前選的就不動。選的音源沒有直播間時退回曲目。
  Future<void> selectSource(String? sourceId) async {
    if (sourceId == selectedSourceOf(state.sourceId, _sources)?.manifest.id) {
      return;
    }
    _cancel();
    state = state.restart(sourceId: () => sourceId);
    if (state.mode == SearchMode.rooms && !_hasLive()) {
      state = state.restart(mode: SearchMode.tracks);
    }
    await _researchInput();
  }

  /// 換「曲目｜直播間」；以輸入框現在的文字重新搜尋。目前的選擇沒有直播間時
  /// 不能切到直播間。
  Future<void> selectMode(SearchMode mode) async {
    if (mode == state.mode) return;
    if (mode == SearchMode.rooms && !_hasLive()) return;
    _cancel();
    state = state.restart(mode: mode);
    await _researchInput();
  }

  /// 換直播間的篩選（`null` 是全部）；在直播間模式就以輸入框現在的文字重新搜尋。
  Future<void> selectRoomFilter(LiveRoomStatus? filter) async {
    if (filter == state.roomFilter) return;
    _cancel();
    state = state.restart(roomFilter: () => filter);
    if (state.mode == SearchMode.rooms) await _researchInput();
  }

  /// 條件換了之後：輸入框有字（去掉空白）就搜它的第一頁，沒有就停在清空的初始畫面。
  Future<void> _researchInput() => search(ref.read(searchInputProvider));

  /// 搜尋 [keyword] 的第一頁；只有空白就不做。
  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    final rooms = state.mode == SearchMode.rooms;
    final selected = selectedSourceOf(state.sourceId, _sources);
    final plugins = [
      for (final plugin in selected == null ? _sources : [selected])
        if (!rooms || hasLiveRooms(plugin)) plugin,
    ];
    if (trimmed.isEmpty || plugins.isEmpty) return;
    _cancel();
    state = state.restart(keyword: trimmed);
    ref.read(videoPartsProvider.notifier).collapseAll();
    final grouped = plugins.length > 1;
    if (rooms) {
      final filter = state.roomFilter;
      final engine = _rooms = AllSourcesSearch<LiveRoomHit>(
        plugins: plugins,
        fetch: (plugin, page) async {
          final result = await plugin.liveSearch(
            LiveSearchQuery(keyword: trimmed, page: page, status: filter),
          );
          return GroupPage(
            items: [
              for (final room in result.items)
                LiveRoomHit(pluginId: plugin.manifest.id, room: room),
            ],
            hasMore: result.hasMore,
          );
        },
        keyOf: (hit) => hit.room.roomId,
        pool: _pool,
        onChanged: (groups) {
          if (ref.mounted) state = state.copyWith(roomGroups: groups);
        },
        onError: (pluginId, error, page) =>
            _failed(error, page: page, grouped: grouped),
      );
      state = state.copyWith(roomGroups: engine.groups);
      await engine.start();
    } else {
      final engine = _tracks = AllSourcesSearch<TrackSummary>(
        plugins: plugins,
        fetch: (plugin, page) async {
          final result = await plugin.search(
            SearchQuery(keyword: trimmed, page: page),
          );
          return GroupPage(items: result.items, hasMore: result.hasMore);
        },
        keyOf: _keyOf,
        pool: _pool,
        onChanged: (groups) {
          if (ref.mounted) state = state.copyWith(trackGroups: groups);
        },
        onError: (pluginId, error, page) =>
            _failed(error, page: page, grouped: grouped),
      );
      state = state.copyWith(trackGroups: engine.groups);
      await engine.start();
    }
  }

  /// [pluginId] 那一組的下一頁，接在已有的結果之後。
  Future<void> loadMore(String pluginId) async {
    await switch (state.mode) {
      SearchMode.tracks => _tracks?.loadMore(pluginId),
      SearchMode.rooms => _rooms?.loadMore(pluginId),
    };
  }

  /// [pluginId] 那一組的第一頁失敗後重試，其他組不動。
  Future<void> retryGroup(String pluginId) async {
    await switch (state.mode) {
      SearchMode.tracks => _tracks?.retry(pluginId),
      SearchMode.rooms => _rooms?.retry(pluginId),
    };
  }

  void _failed(AppError error, {required int page, required bool grouped}) {
    if (!ref.mounted) return;
    if (grouped && page == 1) {
      // 畫在那一組裡，不另外跳提示。
      ref.read(logProvider).report('Search failed', error, tag: 'search');
    } else {
      ref
          .read(toasterProvider)
          .error(error, operation: 'Search failed', tag: 'search');
    }
  }
}

/// [track] 的曲目鍵（含分 P）：列表去重用。
TrackKeyParts _keyOf(TrackSummary track) => TrackKeyParts(
  sourceTypeId: track.sourceTypeId,
  sourceId: track.sourceId,
  cid: track.cid,
);
