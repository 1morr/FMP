import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/models/download_task.dart';
import '../../data/models/track.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../services/download/download_service.dart';
import '../../services/download/download_path_utils.dart';
import '../database_provider.dart';
import '../repository_providers.dart';
import 'download_scanner.dart';
import 'file_exists_cache.dart';
import '../playlist_provider.dart' show playlistDetailProvider;

// Re-export for convenience
export 'download_scanner.dart';

// ==================== Repository Providers ====================

/// DownloadRepository Provider
final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return DownloadRepository(isar);
});

/// TrackRepository Provider (for downloaded tracks)
final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return TrackRepository(isar);
});

// ==================== Service Providers ====================

/// DownloadService Provider
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final downloadRepo = ref.watch(downloadRepositoryProvider);
  final trackRepo = TrackRepository(ref.watch(databaseProvider).requireValue);
  final settingsRepo = SettingsRepository(ref.watch(databaseProvider).requireValue);
  final sourceManager = ref.watch(sourceManagerProvider);
  final service = DownloadService(
    downloadRepository: downloadRepo,
    trackRepository: trackRepo,
    settingsRepository: settingsRepo,
    sourceManager: sourceManager,
  );

  // 初始化服务
  service.initialize();

  // D1-D3: 监听下载完成事件，使用 debouncing 批量处理
  Timer? debounceTimer;
  final pendingPlaylistIds = <int>{};
  final pendingCategoryPaths = <String>{};
  bool categoriesNeedRefresh = false;

  void flushInvalidations() {
    if (categoriesNeedRefresh) {
      ref.invalidate(downloadedCategoriesProvider);
      categoriesNeedRefresh = false;
    }
    for (final categoryPath in pendingCategoryPaths) {
      ref.invalidate(downloadedCategoryTracksProvider(categoryPath));
    }
    pendingCategoryPaths.clear();
    // 使用静默刷新而不是 invalidate，避免页面闪烁
    for (final playlistId in pendingPlaylistIds) {
      final notifier = ref.read(playlistDetailProvider(playlistId).notifier);
      notifier.refreshTracks();
    }
    pendingPlaylistIds.clear();
  }

  StreamSubscription<DownloadCompletionEvent>? completionSubscription;
  completionSubscription = service.completionStream.listen((event) {
    // 标记文件已存在，触发 UI 更新
    ref.read(fileExistsCacheProvider.notifier).markAsExisting(event.savePath);
    
    // 收集需要刷新的内容
    categoriesNeedRefresh = true;
    final categoryFolderPath = p.dirname(p.dirname(event.savePath));
    pendingCategoryPaths.add(categoryFolderPath);
    if (event.playlistId != null) {
      pendingPlaylistIds.add(event.playlistId!);
    }
    
    // D1-D3: 使用 debouncing，300ms 后批量刷新
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () {
      Future.microtask(flushInvalidations);
    });
  });

  // 在 provider 被销毁时清理
  ref.onDispose(() {
    debounceTimer?.cancel();
    completionSubscription?.cancel();
    service.dispose();
  });

  return service;
});

// ==================== Task Providers ====================

/// 所有下载任务列表 Provider
final downloadTasksProvider = StreamProvider<List<DownloadTask>>((ref) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchAllTasks();
});

/// 进行中的下载任务 Provider
final activeDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.maybeWhen(
    data: (data) => data.where((t) => t.isDownloading || t.isPending).toList(),
    orElse: () => [],
  );
});

/// 已完成的下载任务 Provider
final completedDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.maybeWhen(
    data: (data) => data.where((t) => t.isCompleted).toList(),
    orElse: () => [],
  );
});

// ==================== Progress Providers ====================

/// 下载进度流 Provider
final downloadProgressProvider = StreamProvider<DownloadProgressEvent>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return service.progressStream;
});

/// 下载目录信息 Provider
final downloadDirInfoProvider = FutureProvider<DownloadDirInfo>((ref) async {
  final service = ref.watch(downloadServiceProvider);
  return service.getDownloadDirInfo();
});

/// 下載基礎目錄 Provider
final downloadBaseDirProvider = FutureProvider<String>((ref) async {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return DownloadPathUtils.getDefaultBaseDir(settingsRepo);
});

// ==================== Track Providers ====================

/// 检查歌曲是否正在下载
final isTrackDownloadingProvider = Provider.family<bool, int>((ref, trackId) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.maybeWhen(
    data: (data) => data.any((t) => t.trackId == trackId && (t.isDownloading || t.isPending)),
    orElse: () => false,
  );
});

/// 获取歌曲的下载任务
final trackDownloadTaskProvider = Provider.family<DownloadTask?, int>((ref, trackId) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.maybeWhen(
    data: (data) {
      try {
        return data.firstWhere((t) => t.trackId == trackId);
      } catch (_) {
        return null;
      }
    },
    orElse: () => null,
  );
});

/// 根据 trackId 获取 Track 信息（带缓存）
final trackByIdProvider = FutureProvider.family<Track?, int>((ref, trackId) async {
  final trackRepo = ref.watch(trackRepositoryProvider);
  return trackRepo.getById(trackId);
});

// ==================== Category Providers ====================

/// 已下载分类列表 Provider
/// 
/// 使用 Isolate.run() 在单独的 isolate 中执行文件扫描，
/// 避免阻塞 UI 线程
final downloadedCategoriesProvider = FutureProvider<List<DownloadedCategory>>((ref) async {
  // 直接获取下载目录，避免循环依赖 downloadServiceProvider
  final settingsRepo = SettingsRepository(ref.watch(databaseProvider).requireValue);
  final downloadPath = await DownloadPathUtils.getDefaultBaseDir(settingsRepo);

  // 在单独的 isolate 中执行文件扫描，直接返回 DownloadedCategory 列表
  return Isolate.run(() => scanCategoriesInIsolate(ScanCategoriesParams(downloadPath)));
});

/// 获取指定分类文件夹中的已下载歌曲（基于本地文件扫描）
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>((ref, folderPath) async {
  return DownloadScanner.scanFolderForTracks(folderPath);
});
