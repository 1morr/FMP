import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../data/models/playlist.dart';
import '../services/import/import_service.dart';
import '../core/services/toast_service.dart';
import '../data/sources/source_provider.dart';
import 'account_provider.dart';
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
  final Set<int> _refreshingPlaylistIds = {};
  final Map<int, StreamSubscription<ImportProgress>> _subscriptions = {};
  final Map<int, ImportService> _activeImportServices = {};
  final Map<int, int> _refreshGenerations = {};
  int _refreshOperationId = 0;

  RefreshManagerNotifier(this._ref) : super(const RefreshManagerState());

  /// 刷新单个歌单
  Future<ImportResult?> refreshPlaylist(Playlist playlist) async {
    final playlistId = playlist.id;

    if (_refreshingPlaylistIds.contains(playlistId) ||
        state.isRefreshing(playlistId)) {
      return null;
    }
    _refreshingPlaylistIds.add(playlistId);
    final generation = _nextRefreshGeneration(playlistId);

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
      bilibiliAccountService: _ref.read(bilibiliAccountServiceProvider),
      youtubeAccountService: _ref.read(youtubeAccountServiceProvider),
      neteaseAccountService: _ref.read(neteaseAccountServiceProvider),
    );
    _activeImportServices[playlistId] = importService;

    // 初始化刷新状态
    _updatePlaylistState(
      playlistId,
      PlaylistRefreshState(
        playlistId: playlistId,
        playlistName: playlist.name,
        status: ImportStatus.parsing,
        currentItem: t.refreshProvider.parsing,
      ),
    );

    // 监听进度
    _subscriptions[playlistId]?.cancel();
    final subscription = importService.progressStream.listen((progress) {
      if (!_isRefreshGenerationCurrent(playlistId, generation)) return;
      final refreshState = state.getRefreshState(playlistId);
      if (refreshState == null) return;
      _updatePlaylistState(
        playlistId,
        refreshState.copyWith(
          status: progress.status,
          current: progress.current,
          total: progress.total,
          currentItem: progress.currentItem,
          error: progress.error,
        ),
      );
    });
    _subscriptions[playlistId] = subscription;

    try {
      final result = await importService.refreshPlaylist(playlistId);

      if (!_isRefreshGenerationCurrent(playlistId, generation)) return result;

      // 刷新成功
      final refreshState = state.getRefreshState(playlistId);
      if (refreshState == null) return result;
      _updatePlaylistState(
        playlistId,
        refreshState.copyWith(
          status: ImportStatus.completed,
        ),
      );

      // watch 自动更新歌单列表，只需刷新详情和封面
      _ref.invalidate(playlistDetailProvider(playlistId));
      _ref.invalidate(playlistCoverProvider(playlistId));
      _ref.invalidate(allPlaylistsProvider);

      // 使用 ToastService 显示成功提示（不依赖 context）
      final toastService = _ref.read(toastServiceProvider);
      final parts = <String>[];
      if (result.addedCount > 0) {
        parts.add(t.refreshProvider.added(count: result.addedCount));
      }
      if (result.removedCount > 0) {
        parts.add(t.refreshProvider.removed(count: result.removedCount));
      }
      if (result.skippedCount > 0) {
        parts.add(t.refreshProvider.unchanged(count: result.skippedCount));
      }
      final message = t.refreshProvider.completed(name: playlist.name) +
          (parts.isEmpty ? t.refreshProvider.noChanges : parts.join('，'));
      toastService.showSuccess(message);

      _schedulePlaylistStateRemoval(
        playlistId,
        generation,
        const Duration(seconds: 3),
      );

      return result;
    } catch (e) {
      if (!_isRefreshGenerationCurrent(playlistId, generation)) return null;
      final refreshState = state.getRefreshState(playlistId);
      if (refreshState == null) return null;
      _updatePlaylistState(
        playlistId,
        refreshState.copyWith(
          status: ImportStatus.failed,
          error: e.toString(),
        ),
      );

      // 使用 ToastService 显示错误提示
      final toastService = _ref.read(toastServiceProvider);
      toastService.showError(
          t.refreshProvider.failed(name: playlist.name, error: e.toString()));

      _schedulePlaylistStateRemoval(
        playlistId,
        generation,
        const Duration(seconds: 5),
      );

      rethrow;
    } finally {
      await subscription.cancel();
      if (identical(_subscriptions[playlistId], subscription)) {
        _subscriptions.remove(playlistId);
      }
      if (identical(_activeImportServices[playlistId], importService)) {
        _activeImportServices.remove(playlistId);
      }
      _refreshingPlaylistIds.remove(playlistId);
      importService.dispose();
    }
  }

  /// 取消刷新（如果需要）
  void cancelRefresh(int playlistId) {
    _nextRefreshGeneration(playlistId);
    _activeImportServices[playlistId]?.cancelImport();
    _subscriptions[playlistId]?.cancel();
    _subscriptions.remove(playlistId);
    _refreshingPlaylistIds.remove(playlistId);
    _removePlaylistState(playlistId);
  }

  /// 清除已完成或失败的状态
  void clearCompletedStates() {
    final newMap =
        Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap.removeWhere((_, s) =>
        s.status == ImportStatus.completed || s.status == ImportStatus.failed);
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  int _nextRefreshGeneration(int playlistId) {
    final generation = ++_refreshOperationId;
    _refreshGenerations[playlistId] = generation;
    return generation;
  }

  bool _isRefreshGenerationCurrent(int playlistId, int generation) {
    return mounted && _refreshGenerations[playlistId] == generation;
  }

  void _updatePlaylistState(int playlistId, PlaylistRefreshState refreshState) {
    final newMap =
        Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap[playlistId] = refreshState;
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  void _schedulePlaylistStateRemoval(
    int playlistId,
    int generation,
    Duration delay,
  ) {
    Future.delayed(delay, () {
      _removePlaylistStateIfCurrent(playlistId, generation);
    });
  }

  void _removePlaylistStateIfCurrent(int playlistId, int generation) {
    if (_isRefreshGenerationCurrent(playlistId, generation)) {
      _removePlaylistState(playlistId);
    }
  }

  void _removePlaylistState(int playlistId) {
    if (!mounted) return;
    final newMap =
        Map<int, PlaylistRefreshState>.from(state.refreshingPlaylists);
    newMap.remove(playlistId);
    _refreshGenerations.remove(playlistId);
    state = state.copyWith(refreshingPlaylists: newMap);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _refreshingPlaylistIds.clear();
    _refreshGenerations.clear();
    super.dispose();
  }
}

/// 刷新管理器 Provider
final refreshManagerProvider =
    StateNotifierProvider<RefreshManagerNotifier, RefreshManagerState>((ref) {
  return RefreshManagerNotifier(ref);
});

/// 检查特定歌单是否正在刷新
final isPlaylistRefreshingProvider =
    Provider.family<bool, int>((ref, playlistId) {
  final state = ref.watch(refreshManagerProvider);
  return state.isRefreshing(playlistId);
});

/// 获取特定歌单的刷新状态
final playlistRefreshStateProvider =
    Provider.family<PlaylistRefreshState?, int>((ref, playlistId) {
  final state = ref.watch(refreshManagerProvider);
  return state.getRefreshState(playlistId);
});
