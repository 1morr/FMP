import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/play_history.dart';
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
