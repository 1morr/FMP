import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
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

/// 搜尋頁在做什麼。
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

/// 一筆直播間結果與它所屬的插件（收聽與「加為電台」要用）。
@immutable
final class LiveRoomHit {
  const LiveRoomHit({required this.pluginId, required this.room});

  final String pluginId;
  final LiveRoom room;
}

/// 搜尋頁的狀態。
@immutable
final class SearchState {
  const SearchState({
    this.sourceId,
    this.keyword = '',
    this.mode = SearchMode.tracks,
    this.roomFilter,
    this.items = const [],
    this.rooms = const [],
    this.hasMore = false,
    this.page = 0,
    this.phase = SearchPhase.idle,
  });

  /// 使用者選的音源（插件 id）；`null` 或不在清單上時是清單的第一個。
  final String? sourceId;

  /// 送出的關鍵字（去掉前後空白）。
  final String keyword;

  /// 曲目或直播間；只有宣告 `live` 的音源會是 [SearchMode.rooms]。
  final SearchMode mode;

  /// 直播間的「全部｜開播中｜未開播」篩選（舊版 `LiveRoomFilter`）；`null` 是全部。換模式、
  /// 換音源時留著。
  final LiveRoomStatus? roomFilter;

  /// 曲目結果（[SearchMode.tracks]）。
  final List<TrackSummary> items;

  /// 直播間結果（[SearchMode.rooms]）。
  final List<LiveRoomHit> rooms;
  final bool hasMore;

  /// 已載入到第幾頁；還沒載入是 0。
  final int page;
  final SearchPhase phase;

  /// 目前模式的結果是不是空的。
  bool get isEmpty => switch (mode) {
    SearchMode.tracks => items.isEmpty,
    SearchMode.rooms => rooms.isEmpty,
  };

  /// 同一個音源、關鍵字、模式與篩選，換掉結果與進度。
  SearchState copyWith({
    List<TrackSummary>? items,
    List<LiveRoomHit>? rooms,
    bool? hasMore,
    int? page,
    SearchPhase? phase,
  }) => SearchState(
    sourceId: sourceId,
    keyword: keyword,
    mode: mode,
    roomFilter: roomFilter,
    items: items ?? this.items,
    rooms: rooms ?? this.rooms,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    phase: phase ?? this.phase,
  );

  /// 換條件（音源、模式、篩選、關鍵字）：結果清空，[phase] 預設回到還沒搜尋。
  /// [roomFilter] 以函式給，才分得出「不改」與「改成全部（`null`）」。
  SearchState restart({
    String? sourceId,
    String? keyword,
    SearchMode? mode,
    LiveRoomStatus? Function()? roomFilter,
    SearchPhase phase = SearchPhase.idle,
  }) => SearchState(
    sourceId: sourceId ?? this.sourceId,
    keyword: keyword ?? this.keyword,
    mode: mode ?? this.mode,
    roomFilter: roomFilter == null ? this.roomFilter : roomFilter(),
    phase: phase,
  );
}

/// [source] 有沒有直播間可搜（宣告 `live`）。
bool hasLiveRooms(SourcePlugin? source) =>
    source?.manifest.capabilities.contains(PluginCapability.live) ?? false;

/// [sources] 裡目前選的音源（[SearchState.sourceId]，不在清單上就是第一個）。
SourcePlugin? selectedSourceOf(String? sourceId, List<SourcePlugin> sources) {
  for (final source in sources) {
    if (source.manifest.id == sourceId) return source;
  }
  return sources.firstOrNull;
}

/// 搜尋頁的狀態；換到設定頁再回來時保留。
final searchProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);

/// 搜尋與「載入更多」。新的搜尋開始後，之前還沒回來的結果丟掉。
///
/// 失敗經 [Toaster.error] 提示（使用者按了搜尋，屬於使用者動作的回饋）。
/// 網路狀態不擋使用者的搜尋，`noInterface`、`unreachable` 都照常送出（ADR 0016
/// §決定 6「使用者操作照常發請求」、§決定 7 的更正）：系統回報可能是錯的，而狀態
/// 要靠請求拿到回應才回得到 `online`。
///
/// 直播間模式（ADR 0031 §決定 5）只在目前的音源宣告 `live` 時：換到沒宣告的音源（使用者
/// 換的，或那個音源停用了）就退回曲目。換音源、模式、篩選時，還沒回來的結果丟掉。
final class SearchNotifier extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() {
    // 音源清單改了（停用、移除）而目前選的那個沒有直播間：退回曲目。
    ref.listen(searchSourcesProvider, (_, _) {
      if (state.mode == SearchMode.rooms && !hasLiveRooms(_source())) {
        ++_generation;
        state = state.restart(mode: SearchMode.tracks);
      }
    });
    return const SearchState();
  }

  /// 換音源；已經搜尋過就以同一個關鍵字重新搜尋。點的是目前選的（包括還沒
  /// 點過時預設的第一個）就不動。新的音源沒有直播間時退回曲目。
  Future<void> selectSource(String sourceId) async {
    if (sourceId == _source()?.manifest.id) return;
    ++_generation;
    state = state.restart(sourceId: sourceId);
    if (state.mode == SearchMode.rooms && !hasLiveRooms(_source())) {
      state = state.restart(mode: SearchMode.tracks);
    }
    if (state.keyword.isNotEmpty) await search(state.keyword);
  }

  /// 換「曲目｜直播間」；已經搜尋過就以同一個關鍵字重新搜尋。目前的音源沒有直播間時
  /// 不能切到直播間。
  Future<void> selectMode(SearchMode mode) async {
    if (mode == state.mode) return;
    if (mode == SearchMode.rooms && !hasLiveRooms(_source())) return;
    ++_generation;
    state = state.restart(mode: mode);
    if (state.keyword.isNotEmpty) await search(state.keyword);
  }

  /// 換直播間的篩選（`null` 是全部）；在直播間模式而且搜尋過就重新搜尋。
  Future<void> selectRoomFilter(LiveRoomStatus? filter) async {
    if (filter == state.roomFilter) return;
    ++_generation;
    state = state.restart(roomFilter: () => filter);
    if (state.mode == SearchMode.rooms && state.keyword.isNotEmpty) {
      await search(state.keyword);
    }
  }

  /// 搜尋 [keyword] 的第一頁；只有空白就不做。
  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    final source = _source();
    if (trimmed.isEmpty || source == null) return;
    final generation = ++_generation;
    state = state.restart(keyword: trimmed, phase: SearchPhase.loading);
    await _load(source, trimmed, page: 1, generation: generation);
  }

  /// 下一頁，接在已有的結果之後。
  Future<void> loadMore() async {
    final source = _source();
    if (state.phase != SearchPhase.loaded || !state.hasMore || source == null) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: SearchPhase.loadingMore);
    await _load(
      source,
      state.keyword,
      page: state.page + 1,
      generation: generation,
    );
  }

  SourcePlugin? _source() => selectedSourceOf(
    state.sourceId,
    ref.read(searchSourcesProvider).value ?? const [],
  );

  Future<void> _load(
    SourcePlugin source,
    String keyword, {
    required int page,
    required int generation,
  }) async {
    final SearchState next;
    try {
      next = switch (state.mode) {
        SearchMode.tracks => _withTracks(
          await source.search(SearchQuery(keyword: keyword, page: page)),
          page,
        ),
        SearchMode.rooms => _withRooms(
          source.manifest.id,
          await source.liveSearch(
            LiveSearchQuery(
              keyword: keyword,
              page: page,
              status: state.roomFilter,
            ),
          ),
          page,
        ),
      };
    } on AppError catch (error) {
      if (!ref.mounted || generation != _generation) return;
      ref
          .read(toasterProvider)
          .error(error, operation: 'Search failed', tag: 'search');
      // 下一頁失敗時留著已有的結果，可以再按一次「載入更多」。
      state = state.copyWith(
        phase: page == 1 ? SearchPhase.failed : SearchPhase.loaded,
      );
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    state = next;
  }

  /// 兩次請求之間排序變了時，下一頁會有上一頁已經列出的曲目：只留第一次的，
  /// 同一首不會在列表裡出現兩次。在請求回來之後才讀 [state]：代沒變，就是開始時的那份。
  SearchState _withTracks(SearchPage result, int page) {
    final listed = {if (page > 1) ...state.items.map(_keyOf)};
    return state.copyWith(
      items: List.unmodifiable([
        if (page > 1) ...state.items,
        ...result.items.where((track) => listed.add(_keyOf(track))),
      ]),
      hasMore: result.hasMore,
      page: page,
      phase: SearchPhase.loaded,
    );
  }

  /// 同 [_withTracks]，以直播間 id 去重。
  SearchState _withRooms(String pluginId, LiveSearchPage result, int page) {
    final listed = {if (page > 1) ...state.rooms.map((hit) => hit.room.roomId)};
    return state.copyWith(
      rooms: List.unmodifiable([
        if (page > 1) ...state.rooms,
        for (final room in result.items)
          if (listed.add(room.roomId))
            LiveRoomHit(pluginId: pluginId, room: room),
      ]),
      hasMore: result.hasMore,
      page: page,
      phase: SearchPhase.loaded,
    );
  }
}

/// [track] 的曲目鍵（含分 P）：列表去重用。
TrackKeyParts _keyOf(TrackSummary track) => TrackKeyParts(
  sourceTypeId: track.sourceTypeId,
  sourceId: track.sourceId,
  cid: track.cid,
);
