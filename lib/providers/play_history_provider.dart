import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/play_history.dart';
import '../data/models/track.dart';
import '../data/repositories/play_history_repository.dart';
import 'repository_providers.dart';

/// 最近播放历史 Provider（用于首页显示，去重）
/// 默认获取最近 10 首不重复的歌曲
final recentPlayHistoryProvider =
    StreamProvider.autoDispose<List<PlayHistory>>((ref) async* {
  final repo = ref.watch(playHistoryRepositoryProvider);

  // 初始加载（去重）
  yield await repo.getRecentHistoryDistinct(limit: 10);

  // 监听变化
  await for (final _ in repo.watchHistory()) {
    yield await repo.getRecentHistoryDistinct(limit: 10);
  }
});

/// 播放次数最多的歌曲 Provider
final mostPlayedProvider =
    FutureProvider.autoDispose<List<({PlayHistory history, int count})>>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getMostPlayed(limit: 10);
});

/// 所有播放历史 Provider（用于历史页面，支持分页）
final allPlayHistoryProvider =
    FutureProvider.autoDispose.family<List<PlayHistory>, int>((ref, page) async {
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

/// 播放历史统计 Provider
final playHistoryStatsProvider =
    StreamProvider.autoDispose<PlayHistoryStats>((ref) async* {
  final repo = ref.watch(playHistoryRepositoryProvider);

  // 初始加载
  yield await repo.getHistoryStats();

  // 监听变化
  await for (final _ in repo.watchHistory()) {
    yield await repo.getHistoryStats();
  }
});

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
      selectedSource: clearSelectedSource ? null : (selectedSource ?? this.selectedSource),
      sortOrder: sortOrder ?? this.sortOrder,
      searchKeyword: clearSearchKeyword ? null : (searchKeyword ?? this.searchKeyword),
      selectedDate: clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
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
    for (final id in ids) {
      await _repo.deleteHistory(id);
    }
    exitMultiSelectMode();
    return ids.length;
  }

  /// 删除某首歌的所有记录
  Future<int> deleteAllForTrack(String trackKey) async {
    return _repo.deleteAllForTrack(trackKey);
  }
}

/// 播放历史页面状态 Provider
final playHistoryPageProvider =
    StateNotifierProvider.autoDispose<PlayHistoryPageNotifier, PlayHistoryPageState>((ref) {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return PlayHistoryPageNotifier(repo);
});

/// 分组后的播放历史 Provider
final groupedPlayHistoryProvider =
    StreamProvider.autoDispose<Map<DateTime, List<PlayHistory>>>((ref) async* {
  final repo = ref.watch(playHistoryRepositoryProvider);
  final pageState = ref.watch(playHistoryPageProvider);

  Future<Map<DateTime, List<PlayHistory>>> fetchData() async {
    // 如果选择了特定日期，只获取该日期的记录
    if (pageState.selectedDate != null) {
      final date = pageState.selectedDate!;
      final start = DateTime(date.year, date.month, date.day);
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      final records = await repo.queryHistory(
        sourceTypes: pageState.selectedSource == null ? null : {pageState.selectedSource!},
        startDate: start,
        endDate: end,
        searchKeyword: pageState.searchKeyword,
        sortOrder: pageState.sortOrder,
        limit: 1000,
      );
      
      return {start: records};
    }

    // 否则获取分组数据
    return repo.getHistoryGroupedByDate(
      sourceTypes: pageState.selectedSource == null ? null : {pageState.selectedSource!},
      searchKeyword: pageState.searchKeyword,
      sortOrder: pageState.sortOrder,
    );
  }

  // 初始加载
  yield await fetchData();

  // 监听变化
  await for (final _ in repo.watchHistory()) {
    yield await fetchData();
  }
});

/// 获取某首歌的播放次数 Provider
final trackPlayCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, trackKey) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getPlayCountByKey(trackKey);
});
