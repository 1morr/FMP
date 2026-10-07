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

/// 歷史頁目前載入的部分：最新的 [entries.length] 筆，依時間倒序；[hasMore] 為真
/// 表示後面還有。
@immutable
final class HistoryState {
  const HistoryState({required this.entries, required this.hasMore});

  final List<PlayHistoryEntry> entries;
  final bool hasMore;
}

/// 播放歷史的分頁載入：先讀 [historyPageSize] 筆，頁面捲到底時 [HistoryNotifier.loadMore]
/// 再讀下一頁。歷史表有變動（新增、刪除、清除、裁切）時重讀已載入的那麼多筆，所以
/// 捲到深處時刪一筆，位置不跳。
final historyProvider = AsyncNotifierProvider<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);

final class HistoryNotifier extends AsyncNotifier<HistoryState> {
  /// 每次重讀或載入換一代：舊的回來時結果已經過時，丟掉。
  var _generation = 0;
  var _loadingMore = false;

  @override
  Future<HistoryState> build() async {
    final repository = ref.watch(playHistoryRepositoryProvider);
    final changes = repository.changes().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    return _read(repository, count: historyPageSize);
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
    PlayHistoryRepository repository, {
    required int count,
    int offset = 0,
  }) async {
    try {
      final entries = await repository.page(limit: count, offset: offset);
      return HistoryState(entries: entries, hasMore: entries.length == count);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  /// 讀回已載入的那麼多筆（至少一頁）。
  Future<void> _reload() async {
    final repository = ref.read(playHistoryRepositoryProvider);
    final loaded = state.value?.entries.length ?? 0;
    final generation = ++_generation;
    final next = await AsyncValue.guard(
      () => _read(
        repository,
        count: loaded < historyPageSize ? historyPageSize : loaded,
      ),
    );
    if (generation == _generation && ref.mounted) state = next;
  }

  /// 讀下一頁接在後面；沒有更多或正在讀時什麼都不做。
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    final generation = _generation;
    try {
      final page = await _read(
        ref.read(playHistoryRepositoryProvider),
        count: historyPageSize,
        offset: current.entries.length,
      );
      // 讀的期間歷史變了（重讀已經排了），或開始讀時已經有一次重讀在路上、先回來換掉了
      // 清單：這一頁的位移是照舊清單算的，丟掉（接不上會重複或漏掉列）。最後一列還在畫面
      // 上的話，頁面會再讀一次。
      if (generation != _generation ||
          !ref.mounted ||
          !identical(state.value, current)) {
        return;
      }
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
