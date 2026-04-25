import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/play_history.dart';
import '../data/models/track.dart';
import '../data/repositories/play_history_repository.dart';
import 'repository_providers.dart';

/// 共享播放历史快照 Provider
final playHistorySnapshotProvider =
    StreamProvider.autoDispose<List<PlayHistory>>((ref) async* {
  final repo = ref.watch(playHistoryRepositoryProvider);

  yield await repo.loadHistorySnapshot();

  await for (final _ in repo.watchHistory()) {
    yield await repo.loadHistorySnapshot();
  }
});

/// 最近播放历史 Provider（用于首页显示，去重）
/// 默认获取最近 10 首不重复的歌曲
final recentPlayHistoryProvider =
    FutureProvider.autoDispose<List<PlayHistory>>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getRecentHistoryDistinct(limit: 10);
});

/// 播放次数最多的歌曲 Provider
final mostPlayedProvider =
    FutureProvider.autoDispose<List<({PlayHistory history, int count})>>(
        (ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getMostPlayed(limit: 10);
});

/// 所有播放历史 Provider（用于历史页面，支持分页）
final allPlayHistoryProvider = FutureProvider.autoDispose
    .family<List<PlayHistory>, int>((ref, page) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  const pageSize = 50;
  return repo.getAllHistory(offset: page * pageSize, limit: pageSize);
});

/// 播放历史总数 Provider
final playHistoryCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getHistoryCount();
});

/// 播放历史操作 Provider
final playHistoryActionsProvider = Provider<PlayHistoryActions>((ref) {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return PlayHistoryActions(repo);
});

/// 播放历史操作类
class PlayHistoryActions {
  final PlayHistoryRepository _repo;

  PlayHistoryActions(this._repo);

  /// 清空所有历史
  Future<void> clearAll() => _repo.clearAllHistory();

  /// 删除单条记录
  Future<void> delete(int id) => _repo.deleteHistory(id);
}

/// 当前筛选后的播放历史 Provider
final filteredPlayHistoryProvider =
    Provider.autoDispose<AsyncValue<List<PlayHistory>>>((ref) {
  final snapshot = ref.watch(playHistorySnapshotProvider);
  final selectedSource =
      ref.watch(playHistoryPageProvider.select((s) => s.selectedSource));
  final sortOrder =
      ref.watch(playHistoryPageProvider.select((s) => s.sortOrder));
  final searchKeyword =
      ref.watch(playHistoryPageProvider.select((s) => s.searchKeyword));
  final selectedDate =
      ref.watch(playHistoryPageProvider.select((s) => s.selectedDate));

  return snapshot.whenData(
    (records) => _filterAndSortHistory(
      records,
      selectedSource: selectedSource,
      sortOrder: sortOrder,
      searchKeyword: searchKeyword,
      selectedDate: selectedDate,
    ),
  );
});

/// 播放历史统计 Provider
final playHistoryStatsProvider =
    FutureProvider.autoDispose<PlayHistoryStats>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getHistoryStats();
});

List<PlayHistory> _filterAndSortHistory(
  List<PlayHistory> records, {
  SourceType? selectedSource,
  HistorySortOrder sortOrder = HistorySortOrder.timeDesc,
  String? searchKeyword,
  DateTime? selectedDate,
}) {
  var filtered = List<PlayHistory>.from(records);

  if (selectedSource != null) {
    filtered = filtered
        .where((history) => history.sourceType == selectedSource)
        .toList();
  }

  if (selectedDate != null) {
    final start =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final endExclusive = start.add(const Duration(days: 1));
    filtered = filtered
        .where((history) =>
            !history.playedAt.isBefore(start) &&
            history.playedAt.isBefore(endExclusive))
        .toList();
  }

  if (searchKeyword != null && searchKeyword.isNotEmpty) {
    final lower = searchKeyword.toLowerCase();
    filtered = filtered
        .where((history) =>
            history.title.toLowerCase().contains(lower) ||
            (history.artist?.toLowerCase().contains(lower) ?? false))
        .toList();
  }

  switch (sortOrder) {
    case HistorySortOrder.timeDesc:
      filtered.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      break;
    case HistorySortOrder.timeAsc:
      filtered.sort((a, b) => a.playedAt.compareTo(b.playedAt));
      break;
    case HistorySortOrder.playCount:
      final countMap = <String, int>{};
      for (final history in filtered) {
        countMap[history.trackKey] = (countMap[history.trackKey] ?? 0) + 1;
      }
      filtered.sort(
        (a, b) =>
            (countMap[b.trackKey] ?? 0).compareTo(countMap[a.trackKey] ?? 0),
      );
      break;
  }

  return filtered;
}

Map<DateTime, List<PlayHistory>> _groupHistoryByDate(
    List<PlayHistory> records) {
  final grouped = <DateTime, List<PlayHistory>>{};

  for (final history in records) {
    final date = DateTime(
      history.playedAt.year,
      history.playedAt.month,
      history.playedAt.day,
    );
    grouped.putIfAbsent(date, () => []).add(history);
  }

  return grouped;
}

/// 播放历史页面状态
class PlayHistoryPageState {
  final SourceType? selectedSource; // null = 全部
  final HistorySortOrder sortOrder;
  final String? searchKeyword;
  final DateTime? selectedDate;
  final bool isSearching;
  final Set<int> selectedIds; // 多选模式下选中的记录ID
  final bool isMultiSelectMode;

  const PlayHistoryPageState({
    this.selectedSource, // null = 全部
    this.sortOrder = HistorySortOrder.timeDesc,
    this.searchKeyword,
    this.selectedDate,
    this.isSearching = false,
    this.selectedIds = const {},
    this.isMultiSelectMode = false,
  });

  PlayHistoryPageState copyWith({
    SourceType? selectedSource,
    HistorySortOrder? sortOrder,
    String? searchKeyword,
    DateTime? selectedDate,
    bool? isSearching,
    Set<int>? selectedIds,
    bool? isMultiSelectMode,
    bool clearSelectedSource = false,
    bool clearSearchKeyword = false,
    bool clearSelectedDate = false,
  }) {
    return PlayHistoryPageState(
      selectedSource:
          clearSelectedSource ? null : (selectedSource ?? this.selectedSource),
      sortOrder: sortOrder ?? this.sortOrder,
      searchKeyword:
          clearSearchKeyword ? null : (searchKeyword ?? this.searchKeyword),
      selectedDate:
          clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
      isSearching: isSearching ?? this.isSearching,
      selectedIds: selectedIds ?? this.selectedIds,
      isMultiSelectMode: isMultiSelectMode ?? this.isMultiSelectMode,
    );
  }
}

/// 播放历史页面状态管理器
class PlayHistoryPageNotifier extends StateNotifier<PlayHistoryPageState> {
  final PlayHistoryRepository _repo;

  PlayHistoryPageNotifier(this._repo) : super(const PlayHistoryPageState());

  /// 设置音源筛选（null = 全部）
  void setSource(SourceType? sourceType) {
    state = state.copyWith(
      selectedSource: sourceType,
      clearSelectedSource: sourceType == null,
    );
  }

  /// 设置排序方式
  void setSortOrder(HistorySortOrder order) {
    state = state.copyWith(sortOrder: order);
  }

  /// 设置搜索关键词
  void setSearchKeyword(String? keyword) {
    state = state.copyWith(
      searchKeyword: keyword,
      clearSearchKeyword: keyword == null || keyword.isEmpty,
    );
  }

  /// 开始/结束搜索模式
  void setSearching(bool isSearching) {
    state = state.copyWith(
      isSearching: isSearching,
      clearSearchKeyword: !isSearching,
    );
  }

  /// 选择日期
  void setSelectedDate(DateTime? date) {
    state = state.copyWith(
      selectedDate: date,
      clearSelectedDate: date == null,
    );
  }

  /// 进入多选模式
  void enterMultiSelectMode(int initialId) {
    state = state.copyWith(
      isMultiSelectMode: true,
      selectedIds: {initialId},
    );
  }

  /// 退出多选模式
  void exitMultiSelectMode() {
    state = state.copyWith(
      isMultiSelectMode: false,
      selectedIds: {},
    );
  }

  /// 切换选中状态
  void toggleSelection(int id) {
    final selected = Set<int>.from(state.selectedIds);
    if (selected.contains(id)) {
      selected.remove(id);
    } else {
      selected.add(id);
    }
    state = state.copyWith(selectedIds: selected);
  }

  /// 全选
  void selectAll(List<PlayHistory> histories) {
    state = state.copyWith(
      selectedIds: histories.map((h) => h.id).toSet(),
    );
  }

  /// 取消全选
  void deselectAll() {
    state = state.copyWith(selectedIds: {});
  }

  /// 删除选中的记录
  Future<int> deleteSelected() async {
    final ids = state.selectedIds.toList();
    final deletedCount = await _repo.deleteHistories(ids);
    exitMultiSelectMode();
    return deletedCount;
  }

  /// 删除某首歌的所有记录
  Future<int> deleteAllForTrack(String trackKey) async {
    return _repo.deleteAllForTrack(trackKey);
  }
}

/// 播放历史页面状态 Provider
final playHistoryPageProvider = StateNotifierProvider.autoDispose<
    PlayHistoryPageNotifier, PlayHistoryPageState>((ref) {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return PlayHistoryPageNotifier(repo);
});

/// 分组后的播放历史 Provider
/// 注意：只監聽影響數據獲取的字段，不監聽選擇狀態，避免選擇時重新獲取數據導致閃爍
final groupedPlayHistoryProvider =
    Provider.autoDispose<AsyncValue<Map<DateTime, List<PlayHistory>>>>((ref) {
  final filtered = ref.watch(filteredPlayHistoryProvider);
  return filtered.whenData(_groupHistoryByDate);
});

/// 获取某首歌的播放次数 Provider
final trackPlayCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, trackKey) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getPlayCountByKey(trackKey);
});
