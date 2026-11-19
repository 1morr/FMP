import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search_history.dart';

/// 一個音源的搜尋結果（`docs/design/search.html`〈錯誤與空結果〉）：音源各自
/// 搜尋、各自失敗、各自重試。
class SourceResults {
  const SourceResults({
    required this.manifest,
    this.pages = const [],
    this.loading = false,
    this.error,
    this.isEnd = false,
  });

  /// 這個音源的插件；畫面用它的名稱、音源標識與支援的排序。
  final PluginManifest manifest;

  /// 已載入的每一頁，依頁碼。
  final List<List<Track>> pages;

  /// 正在載入第一頁或下一頁。
  final bool loading;

  /// 最近一次載入失敗的原因；重試或重新搜尋時清掉。
  final AppError? error;

  /// 插件說沒有下一頁了。
  final bool isEnd;

  List<Track> get tracks => [for (final page in pages) ...page];

  /// 還能載入下一頁：沒在載入、沒出錯、還沒到最後一頁。
  bool get canLoadMore => !loading && error == null && !isEnd;

  SourceResults _copyWith({
    List<List<Track>>? pages,
    bool? loading,
    AppError? Function()? error,
    bool? isEnd,
  }) => SourceResults(
    manifest: manifest,
    pages: pages ?? this.pages,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
    isEnd: isEnd ?? this.isEnd,
  );
}

/// 一次搜尋：查詢字串、使用者選的排序、每個能搜尋的音源的結果。
class SearchState {
  const SearchState({
    required this.query,
    this.sort,
    this.sources = const [],
    this.starting = false,
  });

  final String query;

  /// 插件還沒載入完，還不知道有哪些音源（畫面照載入中畫）。
  final bool starting;

  /// 使用者選的排序；沒選過是 null，每個插件用自己的預設。
  final SearchSort? sort;

  /// 宣告了 `search` 的每個插件，依插件的順序。
  final List<SourceResults> sources;

  /// 合在一起的結果：一頁一輪，每輪依音源輪流排，下一頁接在後面，已經在
  /// 畫面上的列不會因為載入下一頁而換位置。
  List<Track> get tracks => interleave(sources);

  SearchState _replace(
    String pluginId,
    SourceResults Function(SourceResults) f,
  ) => SearchState(
    query: query,
    sort: sort,
    starting: starting,
    sources: [for (final s in sources) s.manifest.id == pluginId ? f(s) : s],
  );
}

/// 「找不到」：[sources] 每個都回來了、都沒出錯、都沒有結果；只要有一個
/// 出錯就不說找不到（設計稿〈待確認〉4）。畫面傳篩選後看得到的音源。
bool nothingFoundIn(List<SourceResults> sources) =>
    sources.isNotEmpty &&
    sources.every((s) => !s.loading && s.error == null && s.pages.isNotEmpty) &&
    sources.every((s) => s.tracks.isEmpty);

/// [sources] 的結果一頁一輪、每輪依音源輪流排。
/// 同一首（同一個曲目身分）出現在兩頁時只留先出現的那個。
List<Track> interleave(Iterable<SourceResults> sources) {
  final list = sources.toList();
  final seen = <TrackRef>{};
  final rounds = list.fold(
    0,
    (n, s) => s.pages.length > n ? s.pages.length : n,
  );
  return [
    for (var round = 0; round < rounds; round++)
      ..._alternate([
        for (final s in list)
          if (round < s.pages.length) s.pages[round],
      ]),
  ].where((t) => seen.add(t.ref)).toList();
}

List<Track> _alternate(List<List<Track>> lists) {
  final longest = lists.fold(0, (n, l) => l.length > n ? l.length : n);
  return [
    for (var i = 0; i < longest; i++)
      for (final l in lists)
        if (i < l.length) l[i],
  ];
}

/// [manifests] 支援的排序，照宿主定的順序（ADR 0039）；畫面只列這些。
List<SearchSort> sortsOf(Iterable<PluginManifest> manifests) {
  final declared = {for (final m in manifests) ...m.searchSorts};
  return [
    for (final sort in SearchSort.values)
      if (declared.contains(sort)) sort,
  ];
}

/// 目前的搜尋；還沒搜過是 null。
final searchProvider = NotifierProvider<Search, SearchState?>(Search.new);

class Search extends Notifier<SearchState?> {
  /// 每次重新搜尋加一；舊搜尋慢慢回來時不蓋掉新的。
  int _generation = 0;

  /// 這次搜尋的插件，依 id。
  Map<String, Plugin> _plugins = const {};

  @override
  SearchState? build() => null;

  /// 用 [query] 搜尋每個宣告了 `search` 的插件，記進搜尋紀錄。排序沿用上一次
  /// 選的。
  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).record(q);
    await _start(q, state?.sort);
  }

  /// 換排序：用同一個查詢重新搜尋。
  Future<void> sortBy(SearchSort sort) async {
    final current = state;
    if (current == null || current.sort == sort) return;
    await _start(current.query, sort);
  }

  /// 每個還有下一頁的音源載入下一頁（捲到底時）；[only] 給了時只載它
  /// （篩選到一個音源時，不替看不到的音源多打請求）。
  void loadMore({String? only}) {
    for (final source in state?.sources ?? const <SourceResults>[]) {
      if (only != null && source.manifest.id != only) continue;
      if (source.canLoadMore) _load(source.manifest.id, _generation);
    }
  }

  /// 只重查 [pluginId] 這個音源：第一頁失敗就重搜第一頁，下一頁失敗就重載
  /// 那一頁。
  void retry(String pluginId) {
    final source = state?.sources
        .where((s) => s.manifest.id == pluginId)
        .firstOrNull;
    if (source == null || source.loading) return;
    _load(pluginId, _generation);
  }

  Future<void> _start(String query, SearchSort? sort) async {
    final generation = ++_generation;
    state = SearchState(query: query, sort: sort, starting: true);
    final PluginHost host;
    try {
      host = await ref.read(pluginHostProvider.future);
    } catch (error, stackTrace) {
      ref
          .read(logProvider)
          .error('Plugins unavailable', error: error, stackTrace: stackTrace);
      if (ref.mounted && generation == _generation) {
        state = SearchState(query: query, sort: sort);
      }
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    final plugins = [
      for (final plugin in host.plugins)
        if (plugin.manifest.capabilities.contains(PluginCapability.search))
          plugin,
    ];
    _plugins = {for (final p in plugins) p.manifest.id: p};
    state = SearchState(
      query: query,
      sort: sort,
      sources: [for (final p in plugins) SourceResults(manifest: p.manifest)],
    );
    await Future.wait([
      for (final p in plugins) _load(p.manifest.id, generation),
    ]);
  }

  Future<void> _load(String pluginId, int generation) async {
    final current = state;
    final plugin = _plugins[pluginId];
    if (current == null || plugin == null) return;
    final page =
        current.sources
            .firstWhere((s) => s.manifest.id == pluginId)
            .pages
            .length +
        1;
    state = current._replace(
      pluginId,
      (s) => s._copyWith(loading: true, error: () => null),
    );
    try {
      final results = await plugin.search(
        current.query,
        sort: current.sort,
        page: page,
      );
      if (!ref.mounted || generation != _generation) return;
      state = state!._replace(
        pluginId,
        (s) => s._copyWith(
          pages: [...s.pages, results.tracks],
          loading: false,
          isEnd: results.isEnd,
        ),
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _generation) return;
      final AppError reason;
      if (error is AppError) {
        reason = error;
      } else {
        // 錯誤分類以外的例外是程式錯誤，畫面說搜尋失敗，細節留在 log。
        ref
            .read(logProvider)
            .error('Search failed', error: error, stackTrace: stackTrace);
        reason = const ParseFailure();
      }
      state = state!._replace(
        pluginId,
        (s) => s._copyWith(loading: false, error: () => reason),
      );
    }
  }
}
