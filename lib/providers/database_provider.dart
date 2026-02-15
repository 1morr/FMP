import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/track.dart';
import '../data/models/playlist.dart';
import '../data/models/play_queue.dart';
import '../data/models/settings.dart';
import '../data/models/search_history.dart';
import '../data/models/download_task.dart';
import '../data/models/play_history.dart';
import '../data/models/radio_station.dart';
import '../data/models/lyrics_match.dart';

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
      PlayHistorySchema,
      RadioStationSchema,
      LyricsMatchSchema,
    ],
    directory: dir.path,
    name: 'fmp_database',
    // 降低 LMDB mmap 大小：默认 1024 MB，音乐播放器不需要这么大
    // LMDB 会 mmap 整个 maxSizeMiB 到虚拟地址空间，已访问页面计入 RSS
    maxSizeMiB: 128,
    // 启动时自动压缩数据库，回收碎片空间
    compactOnLaunch: const CompactCondition(
      minFileSize: 8 * 1024 * 1024,  // 文件 > 8MB 时才考虑压缩
      minRatio: 2.0,                  // 可回收空间 >= 50% 时触发
    ),
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
