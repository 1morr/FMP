import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../core/constants/app_constants.dart';
import '../data/models/playlist.dart';
import '../services/import/import_service.dart';
import '../core/services/toast_service.dart';
import '../data/sources/source_provider.dart';
import 'database_provider.dart';
import 'repository_providers.dart';
import 'playlist_provider.dart';

/// 单个歌单刷新状态
class PlaylistRefreshState extends Equatable {
  final int playlistId;
  final String playlistName;
  final ImportStatus status;
  final int current;
  final int total;
  final String? currentItem;
  final String? error;

  const PlaylistRefreshState({
    required this.playlistId,
    required this.playlistName,
    this.status = ImportStatus.idle,
    this.current = 0,
    this.total = 0,
    this.currentItem,
    this.error,
  });

  double get progress => total > 0 ? current / total : 0;

  bool get isRefreshing =>
      status == ImportStatus.parsing || status == ImportStatus.importing;

  PlaylistRefreshState copyWith({
    ImportStatus? status,
    int? current,
    int? total,
    String? currentItem,
    String? error,
  }) {
    return PlaylistRefreshState(
      playlistId: playlistId,
      playlistName: playlistName,
      status: status ?? this.status,
      current: current ?? this.current,
      total: total ?? this.total,
      currentItem: currentItem ?? this.currentItem,
      error: error,
    );
  }

  @override
  List<Object?> get props =>
      [playlistId, playlistName, status, current, total, currentItem, error];
}

/// 全局刷新管理状态
class RefreshManagerState extends Equatable {
  final Map<int, PlaylistRefreshState> refreshingPlaylists;

  const RefreshManagerState({
    this.refreshingPlaylists = const {},
  });

  /// 是否有任何正在刷新的歌单
  bool get hasActiveRefresh =>
      refreshingPlaylists.values.any((s) => s.isRefreshing);

  /// 获取所有正在刷新的歌单状态列表
  List<PlaylistRefreshState> get activeRefreshList =>
      refreshingPlaylists.values.where((s) => s.isRefreshing).toList();

  /// 获取特定歌单的刷新状态
  PlaylistRefreshState? getRefreshState(int playlistId) =>
      refreshingPlaylists[playlistId];

  /// 检查特定歌单是否正在刷新
  bool isRefreshing(int playlistId) =>
      refreshingPlaylists[playlistId]?.isRefreshing ?? false;

  RefreshManagerState copyWith({
    Map<int, PlaylistRefreshState>? refreshingPlaylists,
  }) {
    return RefreshManagerState(
      refreshingPlaylists: refreshingPlaylists ?? this.refreshingPlaylists,
    );
  }

  @override
  List<Object?> get props => [refreshingPlaylists];
}

/// 刷新管理器控制器
class RefreshManagerNotifier extends StateNotifier<RefreshManagerState> {
  final Ref _ref;
  final Map<int, StreamSubscription<ImportProgress>> _subscriptions = {};

  RefreshManagerNotifier(this._ref) : super(const RefreshManagerState());

  /// 刷新单个歌单
  Future<ImportResult?> refreshPlaylist(Playlist playlist) async {
    final playlistId = playlist.id;

    // 如果已经在刷新，直接返回
    if (state.isRefreshing(playlistId)) {
      return null;
    }

    // 创建新的 ImportService 实例（每个刷新任务独立）
    final sourceManager = _ref.read(sourceManagerProvider);
    final playlistRepo = _ref.read(playlistRepositoryProvider);
    final trackRepo = _ref.read(trackRepositoryProvider);

    final isar = await _ref.read(databaseProvider.future);
    
    final importService = ImportService(
      sourceManager: sourceManager,
      playlistRepository: playlistRepo,
      trackRepository: trackRepo,
      isar: isar,
    );

    // 初始化刷新状态
    _updatePlaylistState(
      playlistId,
      PlaylistRefreshState(
        playlistId: playlistId,
        playlistName: playlist.name,
        status: ImportStatus.parsing,
        currentItem: '正在解析...',
      ),
    );

    // 监听进度
    _subscriptions[playlistId]?.cancel();
    _subscriptions[playlistId] =
        importService.progressStream.listen((progress) {
      _updatePlaylistState(
        playlistId,
        state.getRefreshState(playlistId)!.copyWith(
              status: progress.status,
              current: progress.current,
              total: progress.total,
              currentItem: progress.currentItem,
              error: progress.error,
            ),
      );
    });

    try {
      final result = await importService.refreshPlaylist(playlistId);

      // 刷新成功
      _updatePlaylistState(
        playlistId,
        state.getRefreshState(playlistId)!.copyWith(
              status: ImportStatus.completed,
            ),
      );

      // 刷新歌单列表、详情和封面
      _ref.read(playlistListProvider.notifier).loadPlaylists();
      _ref.invalidate(playlistDetailProvider(playlistId));
      _ref.invalidate(playlistCoverProvider(playlistId));
      _ref.invalidate(allPlaylistsProvider);

      // 使用 ToastService 显示成功提示（不依赖 context）
      final toastService = _ref.read(toastServiceProvider);
      final parts = <String>[];
      if (result.addedCount > 0) parts.add('新增 ${result.addedCount} 首');
      if (result.removedCount > 0) parts.add('移除 ${result.removedCount} 首');
      if (result.skippedCount > 0) parts.add('${result.skippedCount} 首无变化');
      final message = '${playlist.name} 刷新完成！'
          '${parts.isEmpty ? '无变化' : parts.join('，')}';
      toastService.showSuccess(message);

      // 延迟移除已完成的状态
      Future.delayed(AppConstants.refreshCompleteDelay, () {
        _removePlaylistState(playlistId);
      });

      return result;
    } catch (e) {
      _updatePlaylistState(
        playlistId,
        state.getRefreshState(playlistId)!.copyWith(
              status: ImportStatus.failed,
              error: e.toString(),
            ),
      );

      // 使用 ToastService 显示错误提示
      final toastService = _ref.read(toastServiceProvider);
      toastService.showError('${playlist.name} 刷新失败: $e');

      // 延迟移除失败的状态
      Future.delayed(AppConstants.refreshErrorDelay, () {
        _removePlaylistState(playlistId);
      });

      rethrow;
    } finally {
      _subscriptions[playlistId]?.cancel();
      _subscriptions.remove(playlistId);
      importService.dispose();
    }
  }

  /// 取消刷新（如果需要）
  void cancelRefresh(int playlistId) {
    _subscriptions[playlistId]?.cancel();
    _subscriptions.remove(playlistId);
    _removePlaylistState(playlistId);
  }

  /// 清除已完成或失败的状态
  void clearCompletedStates() {
    final newMap = Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap.removeWhere(
        (_, s) => s.status == ImportStatus.completed || s.status == ImportStatus.failed);
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  void _updatePlaylistState(int playlistId, PlaylistRefreshState refreshState) {
    final newMap = Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap[playlistId] = refreshState;
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  void _removePlaylistState(int playlistId) {
    if (!mounted) return;
    final newMap = Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap.remove(playlistId);
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}

/// 刷新管理器 Provider
final refreshManagerProvider =
    StateNotifierProvider<RefreshManagerNotifier, RefreshManagerState>((ref) {
  return RefreshManagerNotifier(ref);
});

/// 检查特定歌单是否正在刷新
final isPlaylistRefreshingProvider = Provider.family<bool, int>((ref, playlistId) {
  final state = ref.watch(refreshManagerProvider);
  return state.isRefreshing(playlistId);
});

/// 获取特定歌单的刷新状态
final playlistRefreshStateProvider =
    Provider.family<PlaylistRefreshState?, int>((ref, playlistId) {
  final state = ref.watch(refreshManagerProvider);
  return state.getRefreshState(playlistId);
});
