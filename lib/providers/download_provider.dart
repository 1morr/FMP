import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/models/download_task.dart';
import '../data/models/playlist_download_task.dart';
import '../data/models/track.dart';
import '../data/models/playlist.dart';
import '../data/repositories/download_repository.dart';
import '../data/repositories/track_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sources/source_provider.dart';
import '../services/download/download_service.dart';
import 'database_provider.dart';

/// DownloadRepository Provider
final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return DownloadRepository(isar);
});

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

/// TrackRepository Provider (for downloaded tracks)
final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return TrackRepository(isar);
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

/// 扩展方法：为 Track 添加下载功能
extension TrackDownloadExtension on Track {
  /// 下载此歌曲
  Future<DownloadTask?> download(DownloadService service, {Playlist? fromPlaylist}) async {
    return service.addTrackDownload(this, fromPlaylist: fromPlaylist);
  }
}

/// 扩展方法：为 Playlist 添加下载功能
extension PlaylistDownloadExtension on Playlist {
  /// 下载整个歌单
  Future<PlaylistDownloadTask?> download(DownloadService service) async {
    return service.addPlaylistDownload(this);
  }
}

// ==================== 已下载分类相关 ====================

/// 已下载分类（文件夹）数据模型
class DownloadedCategory {
  final String folderName;     // 原始文件夹名
  final String displayName;    // 显示名称（去掉 _id 后缀）
  final int trackCount;        // 歌曲数量
  final String? coverPath;     // 第一首歌的封面路径
  final String folderPath;     // 完整文件夹路径

  const DownloadedCategory({
    required this.folderName,
    required this.displayName,
    required this.trackCount,
    this.coverPath,
    required this.folderPath,
  });
}

/// 从文件夹名中提取显示名称（移除 _playlistId 后缀）
String _extractDisplayName(String folderName) {
  // 格式: "歌单名_123456" -> "歌单名"
  final lastUnderscoreIndex = folderName.lastIndexOf('_');
  if (lastUnderscoreIndex > 0) {
    final suffix = folderName.substring(lastUnderscoreIndex + 1);
    // 检查后缀是否为纯数字
    if (RegExp(r'^\d+$').hasMatch(suffix)) {
      return folderName.substring(0, lastUnderscoreIndex);
    }
  }
  return folderName;
}

/// 查找文件夹中的封面（优先歌单封面，其次第一首歌的封面）
Future<String?> _findFirstCover(Directory folder) async {
  try {
    // 1. 优先检查歌单封面
    final playlistCoverFile = File(p.join(folder.path, 'playlist_cover.jpg'));
    if (await playlistCoverFile.exists()) {
      return playlistCoverFile.path;
    }

    // 2. 遍历子文件夹（视频文件夹）查找第一首歌的封面
    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final coverFile = File(p.join(entity.path, 'cover.jpg'));
        if (await coverFile.exists()) {
          return coverFile.path;
        }
      }
    }
  } catch (_) {}
  return null;
}

/// 统计文件夹中的音频文件数量
Future<int> _countAudioFiles(Directory folder) async {
  int count = 0;
  try {
    await for (final entity in folder.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.m4a')) {
        count++;
      }
    }
  } catch (_) {}
  return count;
}

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
      final trackCount = await _countAudioFiles(entity);

      if (trackCount > 0) {
        final coverPath = await _findFirstCover(entity);
        categories.add(DownloadedCategory(
          folderName: folderName,
          displayName: _extractDisplayName(folderName),
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

/// 从 metadata.json 创建 Track 对象
Track? _trackFromMetadata(Map<String, dynamic> json, String audioPath) {
  try {
    final sourceTypeStr = json['sourceType'] as String?;
    if (sourceTypeStr == null) return null;

    final sourceType = SourceType.values.firstWhere(
      (e) => e.name == sourceTypeStr,
      orElse: () => SourceType.bilibili,
    );

    return Track()
      ..sourceId = json['sourceId'] as String? ?? ''
      ..sourceType = sourceType
      ..title = json['title'] as String? ?? p.basenameWithoutExtension(audioPath)
      ..artist = json['artist'] as String?
      ..durationMs = json['durationMs'] as int?
      ..thumbnailUrl = json['thumbnailUrl'] as String?
      ..cid = json['cid'] as int?
      ..pageNum = json['pageNum'] as int?
      ..parentTitle = json['parentTitle'] as String?
      ..downloadedPath = audioPath
      ..order = json['order'] as int?
      ..createdAt = DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now();
  } catch (_) {
    return null;
  }
}

/// 扫描文件夹获取已下载的 Track 列表（基于本地文件）
Future<List<Track>> _scanFolderForTracks(String folderPath) async {
  final folder = Directory(folderPath);
  if (!await folder.exists()) return [];

  final tracks = <Track>[];

  // 遍历视频文件夹（每个视频一个子文件夹）
  await for (final entity in folder.list()) {
    if (entity is Directory) {
      final metadataFile = File(p.join(entity.path, 'metadata.json'));
      Map<String, dynamic>? metadata;

      // 读取 metadata.json
      if (await metadataFile.exists()) {
        try {
          final content = await metadataFile.readAsString();
          metadata = jsonDecode(content) as Map<String, dynamic>;
        } catch (_) {}
      }

      // 扫描该视频文件夹下的所有 .m4a 文件
      await for (final audioEntity in entity.list()) {
        if (audioEntity is File && audioEntity.path.endsWith('.m4a')) {
          Track? track;

          if (metadata != null) {
            // 检查是否是多P视频（有多个 .m4a 文件）
            // 多P视频的文件名格式: P01 - xxx.m4a, P02 - yyy.m4a
            final fileName = p.basenameWithoutExtension(audioEntity.path);
            final pageMatch = RegExp(r'^P(\d+)').firstMatch(fileName);

            if (pageMatch != null) {
              // 多P视频：从文件名提取 pageNum，使用 metadata 的基础信息
              final pageNum = int.tryParse(pageMatch.group(1)!);
              track = _trackFromMetadata(metadata, audioEntity.path);
              if (track != null) {
                track.pageNum = pageNum;
                // 多P视频的 title 使用文件名（去掉 P01 - 前缀）
                final titleMatch = RegExp(r'^P\d+\s*-\s*(.+)$').firstMatch(fileName);
                if (titleMatch != null) {
                  track.title = titleMatch.group(1)!;
                }
              }
            } else {
              // 单P视频
              track = _trackFromMetadata(metadata, audioEntity.path);
            }
          }

          // 如果没有 metadata 或解析失败，创建基本 Track
          if (track == null) {
            track = Track()
              ..sourceId = p.basename(entity.path)
              ..sourceType = SourceType.bilibili
              ..title = p.basenameWithoutExtension(audioEntity.path)
              ..downloadedPath = audioEntity.path
              ..createdAt = DateTime.now();
          }

          tracks.add(track);
        }
      }
    }
  }

  // 按 order 排序，如果没有 order 则按 parentTitle + pageNum 排序（向后兼容）
  tracks.sort((a, b) {
    // 优先使用 order 排序
    if (a.order != null && b.order != null) {
      return a.order!.compareTo(b.order!);
    }
    // 如果只有一个有 order，有 order 的排前面
    if (a.order != null) return -1;
    if (b.order != null) return 1;
    // 都没有 order，按原来的方式排序（向后兼容）
    final groupCompare = (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
    if (groupCompare != 0) return groupCompare;
    return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
  });

  return tracks;
}

/// 获取指定分类文件夹中的已下载歌曲（基于本地文件扫描）
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>((ref, folderPath) async {
  return _scanFolderForTracks(folderPath);
});
