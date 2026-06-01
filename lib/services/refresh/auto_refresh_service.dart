import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../providers/search/refresh_provider.dart';
import '../../providers/database/repository_providers.dart';

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
  bool _isDisposed = false;
  int _checkGeneration = 0;

  AutoRefreshService({
    required Ref ref,
    required PlaylistRepository playlistRepository,
  })  : _ref = ref,
        _playlistRepository = playlistRepository;

  /// 启动自动刷新服务
  void start() {
    if (_isDisposed) return;
    logInfo('Starting auto-refresh service');
    _checkTimer?.cancel();

    // 立即检查一次
    unawaited(_checkAndRefresh(++_checkGeneration));

    // 每 30 分钟检查一次
    _checkTimer = Timer.periodic(
      AppConstants.autoRefreshCheckInterval,
      (_) => _checkAndRefresh(++_checkGeneration),
    );
  }

  /// 停止自动刷新服务
  void stop() {
    logInfo('Stopping auto-refresh service');
    _checkGeneration++;
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRefreshing = false;
  }

  /// 检查并刷新需要更新的歌单
  Future<void> _checkAndRefresh(int generation) async {
    if (!_isCurrentCheck(generation)) return;
    // 如果正在刷新，跳过本次检查
    if (_isRefreshing) {
      logDebug('Already refreshing, skipping check');
      return;
    }

    try {
      // 获取所有需要刷新的歌单
      final playlists = await _playlistRepository.getAll();
      if (!_isCurrentCheck(generation)) return;
      final needsRefreshList = playlists.where((p) => p.needsRefresh).toList();

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
        if (!_isCurrentCheck(generation)) return;
        if (current == null || !current.needsRefresh) {
          logDebug(
              'Playlist ${playlist.name} no longer needs refresh, skipping');
          continue;
        }

        _isRefreshing = true;
        try {
          logInfo('Auto-refreshing playlist: ${playlist.name}');
          await _ref
              .read(refreshManagerProvider.notifier)
              .refreshPlaylist(playlist);
          if (!_isCurrentCheck(generation)) return;

          // 刷新成功后等待一小段时间再继续下一个（避免请求过快）
          await Future.delayed(const Duration(seconds: 5));
          if (!_isCurrentCheck(generation)) return;
        } catch (e) {
          logError('Failed to auto-refresh playlist ${playlist.name}: $e');
          // 继续刷新下一个歌单
        } finally {
          if (_isCurrentCheck(generation)) {
            _isRefreshing = false;
          }
        }
      }
    } catch (e) {
      logError('Error in auto-refresh check: $e');
      if (_isCurrentCheck(generation)) {
        _isRefreshing = false;
      }
    }
  }

  bool _isCurrentCheck(int generation) {
    return !_isDisposed && generation == _checkGeneration;
  }

  /// 手动触发检查（用于应用启动时）
  Future<void> checkNow() async {
    logInfo('Manual check triggered');
    if (_isDisposed) return;
    await _checkAndRefresh(++_checkGeneration);
  }

  void dispose() {
    _isDisposed = true;
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
