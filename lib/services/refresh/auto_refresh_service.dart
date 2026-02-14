import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../providers/refresh_provider.dart';
import '../../providers/repository_providers.dart';

/// 自动刷新服务
///
/// 负责定期检查需要刷新的歌单并触发刷新操作。
/// - 每小时检查一次
/// - 同时只刷新一个歌单（避免 API 限流）
/// - 按 lastRefreshed 时间排序，优先刷新最久未刷新的
class AutoRefreshService with Logging {
  final Ref _ref;
  final PlaylistRepository _playlistRepository;

  Timer? _checkTimer;
  bool _isRefreshing = false;

  AutoRefreshService({
    required Ref ref,
    required PlaylistRepository playlistRepository,
  })  : _ref = ref,
        _playlistRepository = playlistRepository;

  /// 启动自动刷新服务
  void start() {
    logInfo('Starting auto-refresh service');

    // 立即检查一次
    _checkAndRefresh();

    // 每 30 分钟检查一次
    _checkTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _checkAndRefresh(),
    );
  }

  /// 停止自动刷新服务
  void stop() {
    logInfo('Stopping auto-refresh service');
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 检查并刷新需要更新的歌单
  Future<void> _checkAndRefresh() async {
    // 如果正在刷新，跳过本次检查
    if (_isRefreshing) {
      logDebug('Already refreshing, skipping check');
      return;
    }

    try {
      // 获取所有需要刷新的歌单
      final playlists = await _playlistRepository.getAll();
      final needsRefreshList = playlists
          .where((p) => p.needsRefresh)
          .toList();

      if (needsRefreshList.isEmpty) {
        logDebug('No playlists need refresh');
        return;
      }

      // 按 lastRefreshed 排序，优先刷新最久未刷新的
      needsRefreshList.sort((a, b) {
        if (a.lastRefreshed == null) return -1;
        if (b.lastRefreshed == null) return 1;
        return a.lastRefreshed!.compareTo(b.lastRefreshed!);
      });

      logInfo('Found ${needsRefreshList.length} playlists needing refresh');

      // 逐个刷新（同时只刷新一个）
      for (final playlist in needsRefreshList) {
        // 再次检查是否需要刷新（可能在等待期间已被手动刷新）
        final current = await _playlistRepository.getById(playlist.id);
        if (current == null || !current.needsRefresh) {
          logDebug('Playlist ${playlist.name} no longer needs refresh, skipping');
          continue;
        }

        _isRefreshing = true;
        try {
          logInfo('Auto-refreshing playlist: ${playlist.name}');
          await _ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);

          // 刷新成功后等待一小段时间再继续下一个（避免请求过快）
          await Future.delayed(const Duration(seconds: 5));
        } catch (e) {
          logError('Failed to auto-refresh playlist ${playlist.name}: $e');
          // 继续刷新下一个歌单
        } finally {
          _isRefreshing = false;
        }
      }
    } catch (e) {
      logError('Error in auto-refresh check: $e');
      _isRefreshing = false;
    }
  }

  /// 手动触发检查（用于应用启动时）
  Future<void> checkNow() async {
    logInfo('Manual check triggered');
    await _checkAndRefresh();
  }

  void dispose() {
    stop();
  }
}

/// AutoRefreshService Provider
final autoRefreshServiceProvider = Provider<AutoRefreshService>((ref) {
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  final service = AutoRefreshService(
    ref: ref,
    playlistRepository: playlistRepo,
  );

  // 自动启动服务
  service.start();

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});
