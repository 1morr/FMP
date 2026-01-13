import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/track.dart';
import '../data/models/playlist.dart';
import '../data/models/play_queue.dart';
import '../data/models/settings.dart';
import '../data/models/search_history.dart';
import '../data/models/download_task.dart';
import '../data/repositories/track_repository.dart';
import '../core/logger.dart';

/// Isar 数据库 Provider
final databaseProvider = FutureProvider<Isar>((ref) async {
  final dir = await getApplicationDocumentsDirectory();

  final isar = await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      PlayQueueSchema,
      SettingsSchema,
      SearchHistorySchema,
      DownloadTaskSchema,
    ],
    directory: dir.path,
    name: 'fmp_database',
  );

  // 确保有默认设置
  await isar.writeTxn(() async {
    final settings = await isar.settings.get(0);
    if (settings == null) {
      await isar.settings.put(Settings());
    }
  });

  // 确保有播放队列
  await isar.writeTxn(() async {
    final queues = await isar.playQueues.where().findAll();
    if (queues.isEmpty) {
      await isar.playQueues.put(PlayQueue());
    }
  });

  return isar;
});

/// 数据库是否已初始化
final isDatabaseReadyProvider = Provider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return db.hasValue;
});

/// 启动时清理孤儿 Track 的 Provider
///
/// 删除不被任何歌单/队列引用且本地文件不存在的 Track
final startupCleanupProvider = FutureProvider<int>((ref) async {
  final isar = await ref.watch(databaseProvider.future);

  // 收集所有被引用的 Track ID
  final referencedIds = <int>{};

  // 1. 从所有歌单收集
  final playlists = await isar.playlists.where().findAll();
  for (final playlist in playlists) {
    referencedIds.addAll(playlist.trackIds);
  }

  // 2. 从播放队列收集
  final queues = await isar.playQueues.where().findAll();
  for (final queue in queues) {
    referencedIds.addAll(queue.trackIds);
  }

  // 3. 执行清理
  final trackRepo = TrackRepository(isar);
  final deletedCount = await trackRepo.cleanupOrphanTracks(referencedIds);

  return deletedCount;
});

/// 下载路径数据迁移 Provider
///
/// 将旧的 downloadedPath 迁移到新的多路径格式
final downloadPathMigrationProvider = FutureProvider<int>((ref) async {
  final isar = await ref.watch(databaseProvider.future);

  // 查找所有有旧 downloadedPath 但 downloadedPaths 为空的 Track
  // ignore: deprecated_member_use_from_same_package
  final tracksToMigrate = await isar.tracks
      .filter()
      .downloadedPathIsNotNull()
      .downloadedPathsIsEmpty()
      .findAll();

  if (tracksToMigrate.isEmpty) {
    return 0;
  }

  AppLogger.debug('Found ${tracksToMigrate.length} tracks to migrate download paths');

  // 获取所有歌单，用于查找 Track 所属的歌单
  final playlists = await isar.playlists.where().findAll();

  // 构建 trackId -> playlistIds 的映射
  final trackPlaylistMap = <int, List<int>>{};
  for (final playlist in playlists) {
    for (final trackId in playlist.trackIds) {
      trackPlaylistMap.putIfAbsent(trackId, () => []).add(playlist.id);
    }
  }

  int migratedCount = 0;

  await isar.writeTxn(() async {
    for (final track in tracksToMigrate) {
      // ignore: deprecated_member_use_from_same_package
      final oldPath = track.downloadedPath;
      if (oldPath == null) continue;

      // 查找这个 Track 所属的歌单
      final playlistIds = trackPlaylistMap[track.id] ?? [];

      if (playlistIds.isNotEmpty) {
        // 将旧路径添加到第一个歌单
        track.setDownloadedPath(playlistIds.first, oldPath);
      } else {
        // 没有找到所属歌单，使用 playlistId = 0 表示未分类
        track.setDownloadedPath(0, oldPath);
      }

      await isar.tracks.put(track);
      migratedCount++;
    }
  });

  AppLogger.debug('Migrated $migratedCount tracks to new download path format');
  return migratedCount;
});
