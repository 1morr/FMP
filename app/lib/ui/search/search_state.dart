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

/// 搜尋頁的狀態。
@immutable
final class SearchState {
  const SearchState({
    this.sourceId,
    this.keyword = '',
    this.items = const [],
    this.hasMore = false,
    this.page = 0,
    this.phase = SearchPhase.idle,
  });

  /// 使用者選的音源（插件 id）；`null` 或不在清單上時是清單的第一個。
  final String? sourceId;

  /// 送出的關鍵字（去掉前後空白）。
  final String keyword;
  final List<TrackSummary> items;
  final bool hasMore;

  /// 已載入到第幾頁；還沒載入是 0。
  final int page;
  final SearchPhase phase;

  SearchState copyWith({
    String? sourceId,
    List<TrackSummary>? items,
    bool? hasMore,
    int? page,
    SearchPhase? phase,
  }) => SearchState(
    sourceId: sourceId ?? this.sourceId,
    keyword: keyword,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    phase: phase ?? this.phase,
  );
}

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
final class SearchNotifier extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() => const SearchState();

  /// 換音源；已經搜尋過就以同一個關鍵字重新搜尋。點的是目前選的（包括還沒
  /// 點過時預設的第一個）就不動。
  Future<void> selectSource(String sourceId) async {
    if (sourceId == _source()?.manifest.id) return;
    state = SearchState(sourceId: sourceId, keyword: state.keyword);
    if (state.keyword.isNotEmpty) await search(state.keyword);
  }

  /// 搜尋 [keyword] 的第一頁；只有空白就不做。
  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    final source = _source();
    if (trimmed.isEmpty || source == null) return;
    final generation = ++_generation;
    state = SearchState(
      sourceId: state.sourceId,
      keyword: trimmed,
      phase: SearchPhase.loading,
    );
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
    final SearchPage result;
    try {
      result = await source.search(SearchQuery(keyword: keyword, page: page));
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
    // 兩次請求之間排序變了時，下一頁會有上一頁已經列出的曲目：只留第一次的，
    // 同一首不會在列表裡出現兩次。
    final listed = {if (page > 1) ...state.items.map(_keyOf)};
    state = state.copyWith(
      items: List.unmodifiable([
        if (page > 1) ...state.items,
        ...result.items.where((track) => listed.add(_keyOf(track))),
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
