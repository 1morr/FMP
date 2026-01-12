import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/models/download_task.dart';
import '../../data/models/playlist_download_task.dart';
import '../../data/models/track.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../services/download/download_service.dart';
import '../database_provider.dart';
import 'download_state.dart';
import 'download_scanner.dart';

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

  final service = DownloadService(
    downloadRepository: downloadRepo,
    trackRepository: trackRepo,
    settingsRepository: settingsRepo,
    sourceManager: sourceManager,
  );

  // 初始化服务
  service.initialize();

  // 在 provider 被销毁时清理
  ref.onDispose(() {
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

/// 歌单下载任务列表 Provider
final playlistDownloadTasksProvider = StreamProvider<List<PlaylistDownloadTask>>((ref) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.watchPlaylistTasks();
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
  final service = ref.watch(downloadServiceProvider);
  final dirInfo = await service.getDownloadDirInfo();
  final downloadDir = Directory(dirInfo.path);

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
