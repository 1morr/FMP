import 'dart:io';

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
/// 数据库迁移逻辑
///
/// 处理从旧版本升级时的数据兼容性问题
Future<void> _migrateDatabase(Isar isar) async {
  await isar.writeTxn(() async {
    // 1. 确保有默认设置
    var settings = await isar.settings.get(0);
    if (settings == null) {
      // 全新安装，根据平台设置合理默认值
      final newSettings = Settings();
      if (Platform.isAndroid || Platform.isIOS) {
        newSettings.maxCacheSizeMB = 16; // 移动端默认 16MB（桌面端保持 32MB）
      }
      await isar.settings.put(newSettings);
    } else {
      // 旧版本升级，修复可能的异常值
      bool needsUpdate = false;

      // 修复并发下载数（旧版本可能是 0）
      if (settings.maxConcurrentDownloads < 1 || settings.maxConcurrentDownloads > 5) {
        settings.maxConcurrentDownloads = 3;
        needsUpdate = true;
      }

      // 修复缓存大小（旧版本可能是 0）
      if (settings.maxCacheSizeMB < 1) {
        settings.maxCacheSizeMB = 32;
        needsUpdate = true;
      }

      // 修复音质等级索引（确保在有效范围内）
      if (settings.audioQualityLevelIndex < 0 || settings.audioQualityLevelIndex > 2) {
        settings.audioQualityLevelIndex = 0;
        needsUpdate = true;
      }

      // 修复下载图片选项索引
      if (settings.downloadImageOptionIndex < 0 || settings.downloadImageOptionIndex > 2) {
        settings.downloadImageOptionIndex = 1;
        needsUpdate = true;
      }

      // 修复歌词显示模式索引
      if (settings.lyricsDisplayModeIndex < 0 || settings.lyricsDisplayModeIndex > 2) {
        settings.lyricsDisplayModeIndex = 0;
        needsUpdate = true;
      }

      // 修复最大歌词缓存文件数
      if (settings.maxLyricsCacheFiles < 1) {
        settings.maxLyricsCacheFiles = 50;
        needsUpdate = true;
      }

      // 修复空字符串字段（设置默认值）
      if (settings.audioFormatPriority.isEmpty) {
        settings.audioFormatPriority = 'aac,opus';
        needsUpdate = true;
      }
      if (settings.youtubeStreamPriority.isEmpty) {
        settings.youtubeStreamPriority = 'audioOnly,muxed,hls';
        needsUpdate = true;
      }
      if (settings.bilibiliStreamPriority.isEmpty) {
        settings.bilibiliStreamPriority = 'audioOnly,muxed';
        needsUpdate = true;
      }
      if (settings.lyricsSourcePriority.isEmpty) {
        settings.lyricsSourcePriority = 'netease,qqmusic,lrclib';
        needsUpdate = true;
      }
      if (settings.enabledSources.isEmpty) {
        settings.enabledSources = ['bilibili', 'youtube'];
        needsUpdate = true;
      }

      if (needsUpdate) {
        await isar.settings.put(settings);
      }
    }

    // 2. 确保有播放队列
    final queues = await isar.playQueues.where().findAll();
    if (queues.isEmpty) {
      await isar.playQueues.put(PlayQueue());
    }
  });
}

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

  // 数据迁移和初始化
  await _migrateDatabase(isar);

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
