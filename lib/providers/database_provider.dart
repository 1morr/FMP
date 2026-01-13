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
