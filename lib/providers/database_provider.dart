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

  // 一次性迁移：将旧的 playlistIds/downloadPaths 并行列表迁移到 playlistInfo
  await isar.writeTxn(() async {
    final tracks = await isar.tracks
        .filter()
        .playlistIdsIsNotEmpty()
        .and()
        .playlistInfoIsEmpty()
        .findAll();

    if (tracks.isNotEmpty) {
      for (final track in tracks) {
        final infos = <PlaylistDownloadInfo>[];
        for (int i = 0; i < track.playlistIds.length; i++) {
          final info = PlaylistDownloadInfo()
            ..playlistId = track.playlistIds[i]
            ..downloadPath =
                (i < track.downloadPaths.length) ? track.downloadPaths[i] : '';
          infos.add(info);
        }
        track.playlistInfo = infos;
        // 清除旧字段
        track.playlistIds = [];
        track.downloadPaths = [];
      }
      await isar.tracks.putAll(tracks);
    }
  });

  return isar;
});

/// 数据库是否已初始化
final isDatabaseReadyProvider = Provider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return db.hasValue;
});
