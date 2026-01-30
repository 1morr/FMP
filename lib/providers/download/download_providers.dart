import 'dart:async';
import 'dart:io';

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
import '../download_path_provider.dart';
import '../database_provider.dart';
import '../repository_providers.dart';
import 'download_state.dart';
import 'download_scanner.dart';
import 'file_exists_cache.dart';

// Re-export for convenience
export 'download_state.dart';
export 'download_scanner.dart';
export 'download_extensions.dart';

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
  final pathManager = ref.watch(downloadPathManagerProvider);

  final service = DownloadService(
    downloadRepository: downloadRepo,
    trackRepository: trackRepo,
    settingsRepository: settingsRepo,
    sourceManager: sourceManager,
    pathManager: pathManager,
  );

  // 初始化服务
  service.initialize();

  // 监听下载完成事件，更新缓存和已下载页面
  StreamSubscription<DownloadCompletionEvent>? completionSubscription;
  completionSubscription = service.completionStream.listen((event) {
    // 标记文件已存在，触发 UI 更新
    ref.read(fileExistsCacheProvider.notifier).markAsDownloaded(event.savePath);
    
    // 使用 microtask 延迟刷新，避免循环依赖
    Future.microtask(() {
      // 刷新已下载分类列表和分类详情，使新下载的歌曲显示出来
      ref.invalidate(downloadedCategoriesProvider);
      // 从保存路径中提取分类文件夹路径并刷新对应的分类详情
      // savePath 结构: 下载目录/歌单文件夹/视频文件夹/audio.m4a
      // 需要获取歌单文件夹路径（上两级）
      final categoryFolderPath = p.dirname(p.dirname(event.savePath));
      ref.invalidate(downloadedCategoryTracksProvider(categoryFolderPath));
    });
  });

  // 在 provider 被销毁时清理
  ref.onDispose(() {
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

/// 下载任务状态 Provider (根据状态过滤)
final downloadTasksByStatusProvider = FutureProvider.family<List<DownloadTask>, DownloadStatus>((ref, status) async {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.getTasksByStatus(status);
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

/// 已下载的歌曲列表 Provider
final downloadedTracksProvider = StreamProvider<List<Track>>((ref) {
  final trackRepo = ref.watch(trackRepositoryProvider);
  return trackRepo.watchDownloaded();
});

// ==================== Category Providers ====================

/// 已下载分类列表 Provider
final downloadedCategoriesProvider = FutureProvider<List<DownloadedCategory>>((ref) async {
  // 直接获取下载目录，避免循环依赖 downloadServiceProvider
  final settingsRepo = SettingsRepository(ref.watch(databaseProvider).requireValue);
  final downloadPath = await DownloadPathUtils.getDefaultBaseDir(settingsRepo);
  final downloadDir = Directory(downloadPath);

  if (!await downloadDir.exists()) {
    return [];
  }

  final categories = <DownloadedCategory>[];

  // 扫描所有子文件夹
  await for (final entity in downloadDir.list()) {
    if (entity is Directory) {
      final folderName = p.basename(entity.path);
      final trackCount = await DownloadScanner.countAudioFiles(entity);

      if (trackCount > 0) {
        final coverPath = await DownloadScanner.findFirstCover(entity);
        categories.add(DownloadedCategory(
          folderName: folderName,
          displayName: DownloadScanner.extractDisplayName(folderName),
          trackCount: trackCount,
          coverPath: coverPath,
          folderPath: entity.path,
        ));
      }
    }
  }

  // 按名称排序，但"未分类"放最后
  categories.sort((a, b) {
    if (a.folderName == '未分类') return 1;
    if (b.folderName == '未分类') return -1;
    return a.displayName.compareTo(b.displayName);
  });

  return categories;
});

/// 获取指定分类文件夹中的已下载歌曲（基于本地文件扫描）
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>((ref, folderPath) async {
  return DownloadScanner.scanFolderForTracks(folderPath);
});
