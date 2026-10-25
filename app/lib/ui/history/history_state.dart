import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';

/// 歷史頁一次讀的筆數：往下捲到底才讀下一頁，一萬筆不一次載入（design §9.7）。
const historyPageSize = 50;

/// 歷史頁的篩選與排序（只活在頁面開著的期間）：音源、日期、搜尋文字與排序。
@immutable
final class HistoryFilter {
  const HistoryFilter({
    this.source,
    this.day,
    this.query = '',
    this.sort = HistorySort.newest,
  });

  /// 插件 id；`null` 是全部音源。
  final String? source;

  /// 本地時間的那一天（00:00）；`null` 是不限日期。
  final DateTime? day;

  /// 曲名或作者含這段文字；空字串是不搜尋。
  final String query;
  final HistorySort sort;

  bool get isFiltering => source != null || day != null || query.isNotEmpty;

  HistoryFilter copyWith({
    Object? source = _keep,
    Object? day = _keep,
    String? query,
    HistorySort? sort,
  }) => HistoryFilter(
    source: identical(source, _keep) ? this.source : source as String?,
    day: identical(day, _keep) ? this.day : day as DateTime?,
    query: query ?? this.query,
    sort: sort ?? this.sort,
  );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.source == source &&
      other.day == day &&
      other.query == query &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(source, day, query, sort);
}

final historyFilterProvider =
    NotifierProvider.autoDispose<HistoryFilterNotifier, HistoryFilter>(
      HistoryFilterNotifier.new,
    );

final class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setSource(String? source) => state = state.copyWith(source: source);

  /// [day] 取本地時間的日期部分。
  void setDay(DateTime? day) =>
      state = state.copyWith(day: day == null ? null : dayOf(day));

  void setQuery(String query) => state = state.copyWith(query: query.trim());

  void setSort(HistorySort sort) => state = state.copyWith(sort: sort);
}

/// 歷史頁目前載入的部分：符合篩選的最前面 [entries.length] 筆（依排序）；[hasMore] 為真
/// 表示後面還有。
@immutable
final class HistoryState {
  const HistoryState({required this.entries, required this.hasMore});

  final List<PlayHistoryEntry> entries;
  final bool hasMore;
}

/// 播放歷史的分頁載入：先讀 [historyPageSize] 筆，頁面捲到底時 [HistoryNotifier.loadMore]
/// 再讀下一頁。歷史表有變動（新增、刪除、清除、裁切）時重讀已載入的那麼多筆，所以
/// 捲到深處時刪一筆，位置不跳。篩選（[historyFilterProvider]）一變就從第一頁重讀。
final historyProvider =
    AsyncNotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
      HistoryNotifier.new,
    );

final class HistoryNotifier extends AsyncNotifier<HistoryState> {
  /// 每次重讀或載入換一代：舊的回來時結果已經過時，丟掉。
  var _generation = 0;
  var _loadingMore = false;

  /// 目前這一代讀的篩選；下一頁回來時要還是它才接。
  HistoryFilter? _filter;

  /// 目前篩選下已載入的筆數（重讀時讀回那麼多）。
  var _loaded = historyPageSize;

  @override
  Future<HistoryState> build() async {
    final repository = ref.watch(playHistoryRepositoryProvider);
    final filter = ref.watch(historyFilterProvider);
    // 篩選換了：舊篩選的重讀與載入下一頁都作廢。
    _generation++;
    _loaded = historyPageSize;
    _filter = filter;
    final changes = repository.changes().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    return _read(repository, filter, count: historyPageSize);
  }

  /// 讀失敗：包成 [AppError]、`log.report` 一次（在這裡而不是頁面的 build，重建不會再報），
  /// 頁面看到的是 `AsyncError`。
  Never _fail(Object error, StackTrace stackTrace) {
    final wrapped = AppError.wrap(error, stackTrace);
    ref
        .read(logProvider)
        .report('Failed to load play history', wrapped, tag: 'history');
    throw wrapped;
  }

  Future<HistoryState> _read(
    PlayHistoryRepository repository,
    HistoryFilter filter, {
    required int count,
    int offset = 0,
  }) async {
    try {
      final entries = await repository.page(
        limit: count,
        offset: offset,
        source: filter.source,
        day: filter.day,
        query: filter.query,
        sort: filter.sort,
      );
      return HistoryState(entries: entries, hasMore: entries.length == count);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  /// 讀回已載入的那麼多筆（至少一頁）。
  Future<void> _reload() async {
    final repository = ref.read(playHistoryRepositoryProvider);
    final filter = ref.read(historyFilterProvider);
    final generation = ++_generation;
    final next = await AsyncValue.guard(
      () => _read(repository, filter, count: _loaded),
    );
    if (generation == _generation && ref.mounted) {
      _loaded = next.value?.entries.length ?? _loaded;
      if (_loaded < historyPageSize) _loaded = historyPageSize;
      state = next;
    }
  }

  /// 讀下一頁接在後面；沒有更多或正在讀時什麼都不做。
  Future<void> loadMore() async {
    final current = state.value;
    // 篩選換了、第一頁還在讀時，`state.value` 還是舊篩選的清單：不接在它後面。
    if (current == null ||
        !current.hasMore ||
        _loadingMore ||
        state.isLoading) {
      return;
    }
    final filter = ref.read(historyFilterProvider);
    if (filter != _filter) return;
    _loadingMore = true;
    final generation = _generation;
    try {
      final page = await _read(
        ref.read(playHistoryRepositoryProvider),
        filter,
        count: historyPageSize,
        offset: current.entries.length,
      );
      // 讀的期間歷史變了（重讀已經排了），或開始讀時已經有一次重讀在路上、先回來換掉了
      // 清單：這一頁的位移是照舊清單算的，丟掉（接不上會重複或漏掉列）。最後一列還在畫面
      // 上的話，頁面會再讀一次。
      if (generation != _generation ||
          !ref.mounted ||
          filter != _filter ||
          filter != ref.read(historyFilterProvider) ||
          !identical(state.value, current)) {
        return;
      }
      _loaded = current.entries.length + page.entries.length;
      state = AsyncData(
        HistoryState(
          entries: [...current.entries, ...page.entries],
          hasMore: page.hasMore,
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }
}

/// 歷史裡出現過的音源（篩選列的 chip）。歷史表一變就重讀；讀失敗報一次、不出 chip（清單自己會
/// 顯示失敗）。
final historySourcesProvider =
    AsyncNotifierProvider.autoDispose<HistorySourcesNotifier, List<String>>(
      HistorySourcesNotifier.new,
    );

final class HistorySourcesNotifier extends AsyncNotifier<List<String>> {
  var _generation = 0;

  @override
  Future<List<String>> build() {
    final repository = ref.watch(playHistoryRepositoryProvider);
    final changes = repository.changes().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    return _read(repository);
  }

  Future<List<String>> _read(PlayHistoryRepository repository) async {
    try {
      return await repository.sources();
    } on Object catch (error, stackTrace) {
      final wrapped = AppError.wrap(error, stackTrace);
      ref
          .read(logProvider)
          .report(
            'Failed to load play history sources',
            wrapped,
            tag: 'history',
          );
      throw wrapped;
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(
      () => _read(ref.read(playHistoryRepositoryProvider)),
    );
    if (generation == _generation && ref.mounted) state = next;
  }
}

/// 頁首的統計卡（今天、本週、全部）。歷史表一變就重讀；讀失敗報一次、卡片不出現（清單自己
/// 會顯示失敗），所以這裡不把錯誤丟給畫面以外的人。
final historyStatsProvider =
    AsyncNotifierProvider.autoDispose<HistoryStatsNotifier, HistoryStats>(
      HistoryStatsNotifier.new,
    );

final class HistoryStatsNotifier extends AsyncNotifier<HistoryStats> {
  var _generation = 0;

  @override
  Future<HistoryStats> build() {
    final repository = ref.watch(playHistoryRepositoryProvider);
    final changes = repository.changes().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    return _read(repository);
  }

  Future<HistoryStats> _read(PlayHistoryRepository repository) async {
    try {
      return await repository.stats(clock.now());
    } on Object catch (error, stackTrace) {
      final wrapped = AppError.wrap(error, stackTrace);
      ref
          .read(logProvider)
          .report('Failed to load play history stats', wrapped, tag: 'history');
      throw wrapped;
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final next = await AsyncValue.guard(
      () => _read(ref.read(playHistoryRepositoryProvider)),
    );
    if (generation == _generation && ref.mounted) state = next;
  }
}

/// 一天的開頭（本地時間）；歷史頁以它分組。
DateTime dayOf(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 歷史頁的一列：日期標題，或一筆紀錄。
sealed class HistoryRow {
  const HistoryRow();
}

final class HistoryDay extends HistoryRow {
  const HistoryDay(this.day);

  /// 本地時間的那一天（00:00）。
  final DateTime day;
}

final class HistoryItem extends HistoryRow {
  const HistoryItem(this.entry);

  final PlayHistoryEntry entry;
}

/// 依本地的日界把 [entries]（已倒序）分組：每天前面一個 [HistoryDay]。
List<HistoryRow> groupByDay(List<PlayHistoryEntry> entries) {
  final rows = <HistoryRow>[];
  DateTime? current;
  for (final entry in entries) {
    final day = dayOf(entry.playedAt);
    if (day != current) {
      rows.add(HistoryDay(day));
      current = day;
    }
    rows.add(HistoryItem(entry));
  }
  return rows;
}

/// [day] 相對於現在（[clock]）是今天、昨天或其他；跨年與否由顯示的人看年份。
enum HistoryDayKind { today, yesterday, other }

HistoryDayKind dayKindOf(DateTime day) {
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return HistoryDayKind.today;
  // 用日期運算而不是減 24 小時：夏令時間換日那天不是 24 小時。
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return HistoryDayKind.yesterday;
  }
  return HistoryDayKind.other;
}
