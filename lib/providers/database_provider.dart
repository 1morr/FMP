import 'dart:io';

import 'package:flutter/foundation.dart';
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
import '../data/models/lyrics_title_parse_cache.dart';
import '../data/models/account.dart';

bool _isMobilePlatform() => Platform.isAndroid || Platform.isIOS;

Settings createBootstrapSettings() {
  final settings = Settings();
  if (_isMobilePlatform()) {
    settings.maxCacheSizeMB = 16; // 移动端默认 16MB（桌面端保持 32MB）
  }
  return settings;
}

PlayQueue createBootstrapPlayQueue() => PlayQueue();

bool _hasLegacyPlaybackAndLyricsDefaultsSignature(Settings settings) {
  return settings.neteaseStreamPriority.isEmpty &&
      !settings.useNeteaseAuthForPlay &&
      !settings.enabledSources.contains('netease') &&
      !settings.rememberPlaybackPosition &&
      settings.tempPlayRewindSeconds == 0 &&
      settings.disabledLyricsSources.isEmpty;
}

bool _hasLegacyQueueVolumeSignature(PlayQueue queue) {
  return queue.lastVolume == 0 &&
      queue.trackIds.isEmpty &&
      queue.currentIndex == 0 &&
      queue.lastPositionMs == 0 &&
      !queue.isShuffleEnabled &&
      queue.loopMode == LoopMode.none &&
      queue.originalOrder == null &&
      queue.lastUpdated == null &&
      !queue.isMixMode &&
      queue.mixPlaylistId == null &&
      queue.mixSeedVideoId == null &&
      queue.mixTitle == null;
}

Future<void> _initializeDatabaseDefaultsInTxn(Isar isar) async {
  // 1. 确保有默认设置
  var settings = await isar.settings.get(0);
  if (settings == null) {
    await isar.settings.put(createBootstrapSettings());
  } else {
    // 旧版本升级，修复可能的异常值
    bool needsUpdate = false;

    // 修复并发下载数（旧版本可能是 0）
    if (settings.maxConcurrentDownloads < 1 ||
        settings.maxConcurrentDownloads > 5) {
      settings.maxConcurrentDownloads = 3;
      needsUpdate = true;
    }

    // 修复缓存大小（旧版本可能是 0）
    if (settings.maxCacheSizeMB < 1) {
      settings.maxCacheSizeMB = 32;
      needsUpdate = true;
    }

    // 修复音质等级索引（确保在有效范围内）
    if (settings.audioQualityLevelIndex < 0 ||
        settings.audioQualityLevelIndex > 2) {
      settings.audioQualityLevelIndex = 0;
      needsUpdate = true;
    }

    // 修复下载图片选项索引
    if (settings.downloadImageOptionIndex < 0 ||
        settings.downloadImageOptionIndex > 2) {
      settings.downloadImageOptionIndex = 1;
      needsUpdate = true;
    }

    // 修复歌词显示模式索引
    if (settings.lyricsDisplayModeIndex < 0 ||
        settings.lyricsDisplayModeIndex > 2) {
      settings.lyricsDisplayModeIndex = 0;
      needsUpdate = true;
    }

    // 修复最大歌词缓存文件数
    if (settings.maxLyricsCacheFiles < 1) {
      settings.maxLyricsCacheFiles = 50;
      needsUpdate = true;
    }

    // 修复 AI 标题解析设置（旧版本升级时新增 int 字段会落成 0）
    if (settings.lyricsAiTimeoutSeconds < 1) {
      if (settings.lyricsAiTitleParsingModeIndex == 0 &&
          settings.lyricsAiEndpoint.isEmpty &&
          settings.lyricsAiModel.isEmpty) {
        settings.lyricsAiTitleParsingModeIndex = 1;
      }
      settings.lyricsAiTimeoutSeconds = 10;
      needsUpdate = true;
    }
    if (settings.lyricsAiTitleParsingModeIndex < 0 ||
        settings.lyricsAiTitleParsingModeIndex > 2) {
      settings.lyricsAiTitleParsingModeIndex = 1;
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

    // 修复刷新间隔（旧版本可能是 0）
    if (settings.rankingRefreshIntervalMinutes < 1) {
      settings.rankingRefreshIntervalMinutes = 60;
      needsUpdate = true;
    }
    if (settings.radioRefreshIntervalMinutes < 1) {
      settings.radioRefreshIntervalMinutes = 5;
      needsUpdate = true;
    }

    if (_hasLegacyPlaybackAndLyricsDefaultsSignature(settings)) {
      settings.rememberPlaybackPosition = true;
      settings.tempPlayRewindSeconds = 10;
      settings.disabledLyricsSources = 'lrclib';
      needsUpdate = true;
    }

    // 網易雲相關字段：舊版本升級時，新增字段會落成 Isar 類型默認值
    // 以 neteaseStreamPriority 是否為空判斷是否仍是未遷移的舊數據，避免後續啟動覆蓋用戶當前設置
    if (settings.neteaseStreamPriority.isEmpty) {
      settings.useNeteaseAuthForPlay = true;
      if (!settings.enabledSources.contains('netease')) {
        settings.enabledSources = [...settings.enabledSources, 'netease'];
      }
      settings.neteaseStreamPriority = 'audioOnly';
      needsUpdate = true;
    }

    if (needsUpdate) {
      await isar.settings.put(settings);
    }
  }

  // Note: Track.bilibiliAid (int?) — nullable, defaults to null, populated on-demand
  // by BilibiliFavoritesService. No migration needed.

  // 2. 确保有播放队列
  final queues = await isar.playQueues.where().findAll();
  if (queues.isEmpty) {
    await isar.playQueues.put(createBootstrapPlayQueue());
  } else {
    for (final queue in queues) {
      if (_hasLegacyQueueVolumeSignature(queue)) {
        queue.lastVolume = 1.0;
        await isar.playQueues.put(queue);
      }
    }
  }
}

Future<void> initializeDatabaseDefaults(Isar isar) async {
  await isar.writeTxn(() async {
    await _initializeDatabaseDefaultsInTxn(isar);
  });
}

/// Isar 数据库 Provider
/// 数据库迁移逻辑
///
/// 处理从旧版本升级时的数据兼容性问题
Future<void> _migrateDatabase(Isar isar) async {
  await initializeDatabaseDefaults(isar);
}

@visibleForTesting
Future<void> runDatabaseMigrationForTesting(Isar isar) =>
    _migrateDatabase(isar);

final databaseProvider = FutureProvider<Isar>((ref) async {
  // 尝试复用 _preloadThemeSettings() 已打开的实例
  var isar = Isar.getInstance('fmp_database');

  if (isar == null) {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
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
        LyricsTitleParseCacheSchema,
        AccountSchema,
      ],
      directory: dir.path,
      name: 'fmp_database',
      maxSizeMiB: 64,
      compactOnLaunch: const CompactCondition(
        minFileSize: 8 * 1024 * 1024,
        minRatio: 2.0,
      ),
    );
  }

  // 数据迁移和初始化（包含 PlayQueue 创建）
  await _migrateDatabase(isar);

  return isar;
});

/// 数据库是否已初始化
final isDatabaseReadyProvider = Provider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return db.hasValue;
});
