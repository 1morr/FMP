import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 一個音源在一次搜尋裡的進度。
enum GroupPhase {
  /// 第一頁載入中。
  loading,

  /// 有結果（可能是 0 筆）。
  loaded,

  /// 下一頁載入中，已有的結果照樣顯示。
  loadingMore,

  /// 第一頁失敗；[SourceGroup.error] 是原因。
  failed,
}

/// 一個音源回的一頁。
@immutable
final class GroupPage<T> {
  const GroupPage({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

/// 「全部音源」搜尋裡一個音源的結果與進度（ADR 0035 §決定 9）：各自的頁碼、下一頁與錯誤。
@immutable
final class SourceGroup<T> {
  const SourceGroup({
    required this.pluginId,
    this.items = const [],
    this.hasMore = false,
    this.page = 0,
    this.phase = GroupPhase.loading,
    this.error,
    this.loadMoreFailed = false,
    this.autoLoadPaused = false,
  });

  final String pluginId;
  final List<T> items;
  final bool hasMore;

  /// 已載入到第幾頁；還沒載入是 0。
  final int page;
  final GroupPhase phase;

  /// [GroupPhase.failed] 的原因。
  final AppError? error;

  /// 下一頁載入失敗（已有的結果留著）：不再自動載入，改顯示「載入更多」讓使用者重試。
  final bool loadMoreFailed;

  /// 上一頁沒有帶來新的結果（空頁，或全是重複）但插件說還有下一頁：停止自動載入，改顯示
  /// 「載入更多」，免得最後一列一直重建、一直載入。
  final bool autoLoadPaused;

  SourceGroup<T> copyWith({
    List<T>? items,
    bool? hasMore,
    int? page,
    GroupPhase? phase,
    AppError? Function()? error,
    bool? loadMoreFailed,
    bool? autoLoadPaused,
  }) => SourceGroup(
    pluginId: pluginId,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    phase: phase ?? this.phase,
    error: error == null ? this.error : error(),
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    autoLoadPaused: autoLoadPaused ?? this.autoLoadPaused,
  );
}

/// 同時進行的請求上限：超過的排隊，先到先做。
///
/// 一次「全部音源」搜尋對每個音源各發一個請求，音源多的時候不一次全部送出（ADR 0035 §決定 9
/// 的上限 3）。每次搜尋一個（[AllSourcesSearch.pool]）：換了搜尋之後，舊搜尋還在路上的請求
/// 不佔新搜尋的名額，新的關鍵字、換 chip 立刻送出。同一個音源前後兩次搜尋重疊時，由插件那一層
/// 的限流（manifest 的 `rateLimitPolicy`）保護音源。
final class RequestPool {
  RequestPool(this.limit) : assert(limit > 0);

  final int limit;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// 目前在跑的請求數。
  int get running => _running;

  /// 等一個名額後執行 [task]；[task] 完成（或丟出例外）就放掉名額。
  Future<R> run<R>(Future<R> Function() task) async {
    if (_running >= limit) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      // 名額直接交給下一個等的，不先減再加：中間不會有別的請求插進來。
      if (_waiting.isEmpty) {
        _running--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

/// 一次搜尋，同時搜多個音源（ADR 0035 §決定 9）：每個音源一組（[SourceGroup]），依 [plugins]
/// 的順序，不依誰先回來。各組有自己的頁碼與錯誤，一個音源失敗不影響其他的。
///
/// 請求經 [RequestPool] 限制同時數量；每個請求是 [fetch] 對一個插件發的一次呼叫，限流、
/// 重試與錯誤轉換都在插件那一層，這裡不繞過。[cancel] 之後（新的搜尋、離開模式）還沒回來的
/// 結果丟掉，排隊中還沒送出的不再送出；[retain] 拿掉的音源（停用、移除）也一樣，只限那一組。
///
/// 只有一個音源時也是這個類別（一組）；畫面決定要不要顯示分組標題。
final class AllSourcesSearch<T> {
  AllSourcesSearch({
    required List<SourcePlugin> plugins,
    required this.fetch,
    required this.keyOf,
    required this.pool,
    required this.onChanged,
    required this.onError,
  }) : _plugins = {for (final plugin in plugins) plugin.manifest.id: plugin},
       _groups = [
         for (final plugin in plugins)
           SourceGroup<T>(pluginId: plugin.manifest.id),
       ];

  /// 對 [plugin] 要第 [page] 頁（從 1 起）。
  final Future<GroupPage<T>> Function(SourcePlugin plugin, int page) fetch;

  /// 同一個音源的結果去重用的鍵（兩次請求之間排序變了，下一頁可能有上一頁已經列出的）。
  final Object Function(T item) keyOf;

  /// 這次搜尋的名額（第一頁、下一頁、重試共用）；不和別次搜尋共用。
  final RequestPool pool;

  /// 任何一組變了（結果、進度、錯誤）。
  final void Function(List<SourceGroup<T>> groups) onChanged;

  /// 一個請求失敗；[page] 是失敗的那一頁。
  final void Function(String pluginId, AppError error, int page) onError;

  final Map<String, SourcePlugin> _plugins;
  List<SourceGroup<T>> _groups;
  bool _cancelled = false;

  /// 目前各組的狀態，依音源順序。
  List<SourceGroup<T>> get groups => _groups;

  /// 丟掉還沒回來的結果。
  void cancel() => _cancelled = true;

  /// 音源清單變了（停用、移除）：不在 [pluginIds] 裡的音源整組拿掉，它還沒回來的結果丟掉、
  /// 排隊中的不再送出，之後的下一頁與重試也不會再到它。新加入的音源不補，等下一次搜尋。
  void retain(Set<String> pluginIds) {
    final gone = [
      for (final id in _plugins.keys)
        if (!pluginIds.contains(id)) id,
    ];
    if (gone.isEmpty) return;
    gone.forEach(_plugins.remove);
    _groups = [
      for (final group in _groups)
        if (_plugins.containsKey(group.pluginId)) group,
    ];
    if (!_cancelled) onChanged(_groups);
  }

  /// 每個音源發第一頁；全部完成（成功或失敗）才完成。
  Future<void> start() =>
      Future.wait([for (final group in _groups) _load(group.pluginId, 1)]);

  /// [pluginId] 的下一頁，接在已有的結果之後。
  Future<void> loadMore(String pluginId) {
    final group = _find(pluginId);
    if (group == null || group.phase != GroupPhase.loaded || !group.hasMore) {
      return Future.value();
    }
    _set(group.copyWith(phase: GroupPhase.loadingMore, loadMoreFailed: false));
    return _load(pluginId, group.page + 1);
  }

  /// [pluginId] 的第一頁失敗後重來；其他組不動。
  Future<void> retry(String pluginId) {
    final group = _find(pluginId);
    if (group == null || group.phase != GroupPhase.failed) {
      return Future.value();
    }
    _set(
      group.copyWith(
        phase: GroupPhase.loading,
        error: () => null,
        loadMoreFailed: false,
      ),
    );
    return _load(pluginId, 1);
  }

  SourceGroup<T>? _find(String pluginId) {
    for (final group in _groups) {
      if (group.pluginId == pluginId) return group;
    }
    return null;
  }

  void _set(SourceGroup<T> next) {
    _groups = [
      for (final group in _groups)
        if (group.pluginId == next.pluginId) next else group,
    ];
    onChanged(_groups);
  }

  Future<void> _load(String pluginId, int page) async {
    try {
      final result = await pool.run(() async {
        // 排隊期間搜尋就換了，或這個音源被拿掉了：不送出。
        final plugin = _plugins[pluginId];
        if (_cancelled || plugin == null) return null;
        return fetch(plugin, page);
      });
      if (result == null || _cancelled) return;
      // 請求在路上時這個音源被拿掉了（[retain]）：結果丟掉。
      final group = _find(pluginId);
      if (group == null) return;
      final listed = {if (page > 1) ...group.items.map(keyOf)};
      // toList：where 的副作用（listed.add）只能跑一次。
      final added = result.items
          .where((item) => listed.add(keyOf(item)))
          .toList();
      _set(
        group.copyWith(
          items: List.unmodifiable([if (page > 1) ...group.items, ...added]),
          hasMore: result.hasMore,
          page: page,
          phase: GroupPhase.loaded,
          error: () => null,
          loadMoreFailed: false,
          autoLoadPaused: added.isEmpty,
        ),
      );
    } on AppError catch (error) {
      if (_cancelled) return;
      final group = _find(pluginId);
      if (group == null) return;
      // 下一頁失敗時留著已有的結果，可以再按一次「載入更多」。
      _set(
        page == 1
            ? group.copyWith(phase: GroupPhase.failed, error: () => error)
            : group.copyWith(phase: GroupPhase.loaded, loadMoreFailed: true),
      );
      onError(pluginId, error, page);
    }
  }
}
