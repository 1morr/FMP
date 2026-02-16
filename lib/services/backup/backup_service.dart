import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../data/models/lyrics_match.dart';
import '../../data/models/play_history.dart';
import '../../data/models/playlist.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/search_history.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import 'backup_data.dart';

/// 当前备份数据格式版本
const int kBackupVersion = 1;

/// 备份服务
///
/// 提供数据导出和导入功能
class BackupService {
  final Isar _isar;

  BackupService(this._isar);

  // ==================== 导出功能 ====================

  /// 导出所有数据到 JSON 文件
  ///
  /// 返回导出的文件路径，如果用户取消则返回 null
  Future<String?> exportData() async {
    // 让用户选择保存位置
    final fileName =
        'fmp_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';

    String? outputPath;

    if (Platform.isAndroid) {
      // Android: 使用 file_picker 选择目录
      final directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) return null;
      outputPath = p.join(directory, fileName);
    } else {
      // Windows/Desktop: 使用保存对话框
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出数据',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    }

    if (outputPath == null) return null;

    // 收集所有数据
    final backupData = await _collectBackupData();

    // 序列化为 JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(backupData.toJson());

    // 写入文件
    final file = File(outputPath);
    await file.writeAsString(jsonString, flush: true);

    return outputPath;
  }

  /// 收集所有需要备份的数据
  Future<BackupData> _collectBackupData() async {
    final packageInfo = await PackageInfo.fromPlatform();

    // 获取所有歌单
    final playlists = await _isar.playlists.where().findAll();

    // 获取所有歌曲
    final tracks = await _isar.tracks.where().findAll();

    // 构建 track ID -> Track 的映射
    final trackMap = <int, Track>{};
    for (final track in tracks) {
      trackMap[track.id] = track;
    }

    // 转换歌单数据
    final playlistBackups = <PlaylistBackup>[];
    for (final playlist in playlists) {
      // 获取歌单中的歌曲 keys
      final trackKeys = <String>[];
      for (final trackId in playlist.trackIds) {
        final track = trackMap[trackId];
        if (track != null) {
          trackKeys.add(track.uniqueKey);
        }
      }

      playlistBackups.add(PlaylistBackup(
        name: playlist.name,
        description: playlist.description,
        coverUrl: playlist.coverUrl,
        hasCustomCover: playlist.hasCustomCover,
        sourceUrl: playlist.sourceUrl,
        importSourceType: playlist.importSourceType?.name,
        refreshIntervalHours: playlist.refreshIntervalHours,
        notifyOnUpdate: playlist.notifyOnUpdate,
        isMix: playlist.isMix,
        mixPlaylistId: playlist.mixPlaylistId,
        mixSeedVideoId: playlist.mixSeedVideoId,
        trackKeys: trackKeys,
        createdAt: playlist.createdAt,
        sortOrder: playlist.sortOrder,
      ));
    }

    // 转换歌曲数据
    final trackBackups = tracks.map((t) => TrackBackup(
          sourceId: t.sourceId,
          sourceType: t.sourceType.name,
          title: t.title,
          artist: t.artist,
          ownerId: t.ownerId,
          channelId: t.channelId,
          durationMs: t.durationMs,
          thumbnailUrl: t.thumbnailUrl,
          viewCount: t.viewCount,
          pageCount: t.pageCount,
          cid: t.cid,
          pageNum: t.pageNum,
          parentTitle: t.parentTitle,
          originalSongId: t.originalSongId,
          originalSource: t.originalSource,
          createdAt: t.createdAt,
        )).toList();

    // 获取播放历史
    final playHistory = await _isar.playHistorys.where().findAll();
    final playHistoryBackups = playHistory.map((h) => PlayHistoryBackup(
          sourceId: h.sourceId,
          sourceType: h.sourceType.name,
          cid: h.cid,
          title: h.title,
          artist: h.artist,
          durationMs: h.durationMs,
          thumbnailUrl: h.thumbnailUrl,
          playedAt: h.playedAt,
        )).toList();

    // 获取搜索历史
    final searchHistory = await _isar.searchHistorys.where().findAll();
    final searchHistoryBackups = searchHistory.map((s) => SearchHistoryBackup(
          query: s.query,
          timestamp: s.timestamp,
        )).toList();

    // 获取电台收藏
    final radioStations = await _isar.radioStations.where().findAll();
    final radioStationBackups = radioStations.map((r) => RadioStationBackup(
          url: r.url,
          title: r.title,
          thumbnailUrl: r.thumbnailUrl,
          hostName: r.hostName,
          hostAvatarUrl: r.hostAvatarUrl,
          hostUid: r.hostUid,
          sourceType: r.sourceType.name,
          sourceId: r.sourceId,
          sortOrder: r.sortOrder,
          createdAt: r.createdAt,
          isFavorite: r.isFavorite,
          note: r.note,
        )).toList();

    // 获取设置
    final settings = await _isar.settings.get(0);
    SettingsBackup? settingsBackup;
    if (settings != null) {
      settingsBackup = SettingsBackup(
        themeModeIndex: settings.themeModeIndex,
        primaryColor: settings.primaryColor,
        secondaryColor: settings.secondaryColor,
        backgroundColor: settings.backgroundColor,
        surfaceColor: settings.surfaceColor,
        textColor: settings.textColor,
        cardColor: settings.cardColor,
        maxCacheSizeMB: settings.maxCacheSizeMB,
        enabledSources: settings.enabledSources,
        autoScrollToCurrentTrack: settings.autoScrollToCurrentTrack,
        rememberPlaybackPosition: settings.rememberPlaybackPosition,
        restartRewindSeconds: settings.restartRewindSeconds,
        tempPlayRewindSeconds: settings.tempPlayRewindSeconds,
        maxConcurrentDownloads: settings.maxConcurrentDownloads,
        downloadImageOptionIndex: settings.downloadImageOptionIndex,
        minimizeToTrayOnClose: settings.minimizeToTrayOnClose,
        enableGlobalHotkeys: settings.enableGlobalHotkeys,
        launchAtStartup: settings.launchAtStartup,
        launchMinimized: settings.launchMinimized,
        fontFamily: settings.fontFamily,
        locale: settings.locale,
        audioQualityLevelIndex: settings.audioQualityLevelIndex,
        audioFormatPriority: settings.audioFormatPriority,
        youtubeStreamPriority: settings.youtubeStreamPriority,
        bilibiliStreamPriority: settings.bilibiliStreamPriority,
        hotkeyConfig: settings.hotkeyConfig,
        autoMatchLyrics: settings.autoMatchLyrics,
        maxLyricsCacheFiles: settings.maxLyricsCacheFiles,
        lyricsDisplayModeIndex: settings.lyricsDisplayModeIndex,
        lyricsSourcePriority: settings.lyricsSourcePriority,
        disabledLyricsSources: settings.disabledLyricsSources,
      );
    }

    // 获取歌词匹配记录
    final lyricsMatches = await _isar.lyricsMatchs.where().findAll();
    final lyricsMatchBackups = lyricsMatches.map((m) => LyricsMatchBackup(
          trackUniqueKey: m.trackUniqueKey,
          lyricsSource: m.lyricsSource,
          externalId: m.externalId,
          offsetMs: m.offsetMs,
          matchedAt: m.matchedAt,
        )).toList();

    return BackupData(
      version: kBackupVersion,
      exportedAt: DateTime.now(),
      appVersion: packageInfo.version,
      playlists: playlistBackups,
      tracks: trackBackups,
      playHistory: playHistoryBackups,
      searchHistory: searchHistoryBackups,
      radioStations: radioStationBackups,
      settings: settingsBackup,
      lyricsMatches: lyricsMatchBackups,
    );
  }

  // ==================== 导入功能 ====================

  /// 选择并解析备份文件
  ///
  /// 返回解析后的备份数据，如果用户取消或文件无效则返回 null
  Future<BackupData?> pickAndParseBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final filePath = result.files.first.path;
    if (filePath == null) return null;

    return parseBackupFile(filePath);
  }

  /// 解析备份文件
  Future<BackupData?> parseBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return BackupData.fromJson(json);
    } catch (e) {
      debugPrint('解析备份文件失败: $e');
      return null;
    }
  }

  /// 执行导入
  ///
  /// [backupData] 要导入的备份数据
  /// [importSettings] 是否导入设置
  Future<ImportResult> importData(
    BackupData backupData, {
    bool importPlaylists = true,
    bool importPlayHistory = true,
    bool importSearchHistory = true,
    bool importRadioStations = true,
    bool importLyricsMatches = true,
    bool importSettings = true,
  }) async {
    int playlistsImported = 0;
    int playlistsSkipped = 0;
    int tracksImported = 0;
    int tracksSkipped = 0;
    int playHistoryImported = 0;
    int playHistorySkipped = 0;
    int searchHistoryImported = 0;
    int searchHistorySkipped = 0;
    int radioStationsImported = 0;
    int radioStationsSkipped = 0;
    int lyricsMatchesImported = 0;
    int lyricsMatchesSkipped = 0;
    bool settingsImportedFlag = false;
    final errors = <String>[];

    // 1. 导入歌曲（歌单依赖歌曲，仅在导入歌单时才导入）
    final trackKeyToId = <String, int>{};

    if (importPlaylists) {
    // 先获取现有歌曲的映射
    final existingTracks = await _isar.tracks.where().findAll();
    for (final track in existingTracks) {
      trackKeyToId[track.uniqueKey] = track.id;
    }

    // 导入新歌曲
    for (final trackBackup in backupData.tracks) {
      if (trackKeyToId.containsKey(trackBackup.uniqueKey)) {
        tracksSkipped++;
        continue;
      }

      try {
        final track = Track()
          ..sourceId = trackBackup.sourceId
          ..sourceType = _parseSourceType(trackBackup.sourceType)
          ..title = trackBackup.title
          ..artist = trackBackup.artist
          ..ownerId = trackBackup.ownerId
          ..channelId = trackBackup.channelId
          ..durationMs = trackBackup.durationMs
          ..thumbnailUrl = trackBackup.thumbnailUrl
          ..viewCount = trackBackup.viewCount
          ..pageCount = trackBackup.pageCount
          ..cid = trackBackup.cid
          ..pageNum = trackBackup.pageNum
          ..parentTitle = trackBackup.parentTitle
          ..originalSongId = trackBackup.originalSongId
          ..originalSource = trackBackup.originalSource
          ..createdAt = trackBackup.createdAt;

        await _isar.writeTxn(() async {
          final id = await _isar.tracks.put(track);
          trackKeyToId[trackBackup.uniqueKey] = id;
        });
        tracksImported++;
      } catch (e) {
        errors.add('导入歌曲失败: ${trackBackup.title} - $e');
      }
    }
    } // end importPlaylists (tracks)

    // 2. 导入歌单
    if (importPlaylists) {
    final existingPlaylistNames = <String>{};
    final existingPlaylists = await _isar.playlists.where().findAll();
    for (final playlist in existingPlaylists) {
      existingPlaylistNames.add(playlist.name);
    }

    for (final playlistBackup in backupData.playlists) {
      if (existingPlaylistNames.contains(playlistBackup.name)) {
        playlistsSkipped++;
        continue;
      }

      try {
        // 解析歌曲 ID 列表
        final trackIds = <int>[];
        for (final trackKey in playlistBackup.trackKeys) {
          final trackId = trackKeyToId[trackKey];
          if (trackId != null) {
            trackIds.add(trackId);
          }
        }

        final playlist = Playlist()
          ..name = playlistBackup.name
          ..description = playlistBackup.description
          ..coverUrl = playlistBackup.coverUrl
          ..hasCustomCover = playlistBackup.hasCustomCover
          ..sourceUrl = playlistBackup.sourceUrl
          ..importSourceType = playlistBackup.importSourceType != null
              ? _parseSourceType(playlistBackup.importSourceType!)
              : null
          ..refreshIntervalHours = playlistBackup.refreshIntervalHours
          ..notifyOnUpdate = playlistBackup.notifyOnUpdate
          ..isMix = playlistBackup.isMix
          ..mixPlaylistId = playlistBackup.mixPlaylistId
          ..mixSeedVideoId = playlistBackup.mixSeedVideoId
          ..trackIds = trackIds
          ..createdAt = playlistBackup.createdAt
          ..sortOrder = playlistBackup.sortOrder;

        await _isar.writeTxn(() async {
          final playlistId = await _isar.playlists.put(playlist);

          // 更新歌曲的歌单关联
          for (final trackId in trackIds) {
            final track = await _isar.tracks.get(trackId);
            if (track != null) {
              track.addToPlaylist(playlistId, playlistName: playlist.name);
              await _isar.tracks.put(track);
            }
          }
        });
        playlistsImported++;
        existingPlaylistNames.add(playlistBackup.name);
      } catch (e) {
        errors.add('导入歌单失败: ${playlistBackup.name} - $e');
      }
    }
    } // end importPlaylists

    // 3. 导入播放历史
    if (importPlayHistory) {
    final existingHistoryKeys = <String>{};
    final existingHistory = await _isar.playHistorys.where().findAll();
    for (final history in existingHistory) {
      existingHistoryKeys.add('${history.trackKey}:${history.playedAt.millisecondsSinceEpoch}');
    }

    for (final historyBackup in backupData.playHistory) {
      final key = '${historyBackup.trackKey}:${historyBackup.playedAt.millisecondsSinceEpoch}';
      if (existingHistoryKeys.contains(key)) {
        playHistorySkipped++;
        continue;
      }

      try {
        final history = PlayHistory()
          ..sourceId = historyBackup.sourceId
          ..sourceType = _parseSourceType(historyBackup.sourceType)
          ..cid = historyBackup.cid
          ..title = historyBackup.title
          ..artist = historyBackup.artist
          ..durationMs = historyBackup.durationMs
          ..thumbnailUrl = historyBackup.thumbnailUrl
          ..playedAt = historyBackup.playedAt;

        await _isar.writeTxn(() async {
          await _isar.playHistorys.put(history);
        });
        playHistoryImported++;
      } catch (e) {
        errors.add('导入播放历史失败: ${historyBackup.title} - $e');
      }
    }
    } // end importPlayHistory

    // 4. 导入搜索历史
    if (importSearchHistory) {
    final existingSearchQueries = <String>{};
    final existingSearchHistory = await _isar.searchHistorys.where().findAll();
    for (final search in existingSearchHistory) {
      existingSearchQueries.add(search.query);
    }

    for (final searchBackup in backupData.searchHistory) {
      if (existingSearchQueries.contains(searchBackup.query)) {
        searchHistorySkipped++;
        continue;
      }

      try {
        final search = SearchHistory()
          ..query = searchBackup.query
          ..timestamp = searchBackup.timestamp;

        await _isar.writeTxn(() async {
          await _isar.searchHistorys.put(search);
        });
        searchHistoryImported++;
        existingSearchQueries.add(searchBackup.query);
      } catch (e) {
        errors.add('导入搜索历史失败: ${searchBackup.query} - $e');
      }
    }
    } // end importSearchHistory

    // 5. 导入电台收藏
    if (importRadioStations) {
    final existingRadioUrls = <String>{};
    final existingRadios = await _isar.radioStations.where().findAll();
    for (final radio in existingRadios) {
      existingRadioUrls.add(radio.url);
    }

    for (final radioBackup in backupData.radioStations) {
      if (existingRadioUrls.contains(radioBackup.url)) {
        radioStationsSkipped++;
        continue;
      }

      try {
        final radio = RadioStation()
          ..url = radioBackup.url
          ..title = radioBackup.title
          ..thumbnailUrl = radioBackup.thumbnailUrl
          ..hostName = radioBackup.hostName
          ..hostAvatarUrl = radioBackup.hostAvatarUrl
          ..hostUid = radioBackup.hostUid
          ..sourceType = _parseSourceType(radioBackup.sourceType)
          ..sourceId = radioBackup.sourceId
          ..sortOrder = radioBackup.sortOrder
          ..createdAt = radioBackup.createdAt
          ..isFavorite = radioBackup.isFavorite
          ..note = radioBackup.note;

        await _isar.writeTxn(() async {
          await _isar.radioStations.put(radio);
        });
        radioStationsImported++;
        existingRadioUrls.add(radioBackup.url);
      } catch (e) {
        errors.add('导入电台失败: ${radioBackup.title} - $e');
      }
    }
    } // end importRadioStations

    // 6. 导入歌词匹配记录
    if (importLyricsMatches) {
    final existingMatchKeys = <String>{};
    final existingMatches = await _isar.lyricsMatchs.where().findAll();
    for (final match in existingMatches) {
      existingMatchKeys.add(match.trackUniqueKey);
    }

    for (final matchBackup in backupData.lyricsMatches) {
      if (existingMatchKeys.contains(matchBackup.trackUniqueKey)) {
        lyricsMatchesSkipped++;
        continue;
      }

      try {
        final match = LyricsMatch()
          ..trackUniqueKey = matchBackup.trackUniqueKey
          ..lyricsSource = matchBackup.lyricsSource
          ..externalId = matchBackup.externalId
          ..offsetMs = matchBackup.offsetMs
          ..matchedAt = matchBackup.matchedAt;

        await _isar.writeTxn(() async {
          await _isar.lyricsMatchs.put(match);
        });
        lyricsMatchesImported++;
        existingMatchKeys.add(matchBackup.trackUniqueKey);
      } catch (e) {
        errors.add('导入歌词匹配失败: ${matchBackup.trackUniqueKey} - $e');
      }
    }
    } // end importLyricsMatches

    // 7. 导入设置（覆盖）
    if (importSettings && backupData.settings != null) {
      try {
        final settingsBackup = backupData.settings!;
        
        // 获取当前设置，用于保留设备相关的配置
        final currentSettings = await _isar.settings.get(0);
        
        final settings = Settings()
          ..id = 0
          // 通用设置 - 从备份导入
          ..themeModeIndex = settingsBackup.themeModeIndex
          ..primaryColor = settingsBackup.primaryColor
          ..secondaryColor = settingsBackup.secondaryColor
          ..backgroundColor = settingsBackup.backgroundColor
          ..surfaceColor = settingsBackup.surfaceColor
          ..textColor = settingsBackup.textColor
          ..cardColor = settingsBackup.cardColor
          ..maxCacheSizeMB = settingsBackup.maxCacheSizeMB
          ..enabledSources = settingsBackup.enabledSources
          ..autoScrollToCurrentTrack = settingsBackup.autoScrollToCurrentTrack
          ..rememberPlaybackPosition = settingsBackup.rememberPlaybackPosition
          ..restartRewindSeconds = settingsBackup.restartRewindSeconds
          ..tempPlayRewindSeconds = settingsBackup.tempPlayRewindSeconds
          ..maxConcurrentDownloads = settingsBackup.maxConcurrentDownloads
          ..downloadImageOptionIndex = settingsBackup.downloadImageOptionIndex
          ..fontFamily = settingsBackup.fontFamily
          ..locale = settingsBackup.locale
          ..audioQualityLevelIndex = settingsBackup.audioQualityLevelIndex
          ..audioFormatPriority = settingsBackup.audioFormatPriority
          ..youtubeStreamPriority = settingsBackup.youtubeStreamPriority
          ..bilibiliStreamPriority = settingsBackup.bilibiliStreamPriority
          // 桌面专属设置 - 仅在桌面平台导入，否则保留当前值
          ..minimizeToTrayOnClose = Platform.isWindows 
              ? settingsBackup.minimizeToTrayOnClose 
              : (currentSettings?.minimizeToTrayOnClose ?? true)
          ..enableGlobalHotkeys = Platform.isWindows 
              ? settingsBackup.enableGlobalHotkeys 
              : (currentSettings?.enableGlobalHotkeys ?? true)
          ..launchAtStartup = Platform.isWindows 
              ? settingsBackup.launchAtStartup 
              : (currentSettings?.launchAtStartup ?? false)
          ..launchMinimized = Platform.isWindows 
              ? settingsBackup.launchMinimized 
              : (currentSettings?.launchMinimized ?? false)
          ..hotkeyConfig = Platform.isWindows 
              ? settingsBackup.hotkeyConfig 
              : currentSettings?.hotkeyConfig
          // 歌词设置 - 从备份导入
          ..autoMatchLyrics = settingsBackup.autoMatchLyrics
          ..maxLyricsCacheFiles = settingsBackup.maxLyricsCacheFiles
          ..lyricsDisplayModeIndex = settingsBackup.lyricsDisplayModeIndex
          ..lyricsSourcePriority = settingsBackup.lyricsSourcePriority
          ..disabledLyricsSources = settingsBackup.disabledLyricsSources
          // 设备相关设置 - 保留当前值
          ..customDownloadDir = currentSettings?.customDownloadDir
          ..preferredAudioDeviceId = currentSettings?.preferredAudioDeviceId
          ..preferredAudioDeviceName = currentSettings?.preferredAudioDeviceName;

        await _isar.writeTxn(() async {
          await _isar.settings.put(settings);
        });
        settingsImportedFlag = true;
      } catch (e) {
        errors.add('导入设置失败: $e');
      }
    }

    return ImportResult(
      playlistsImported: playlistsImported,
      playlistsSkipped: playlistsSkipped,
      tracksImported: tracksImported,
      tracksSkipped: tracksSkipped,
      playHistoryImported: playHistoryImported,
      playHistorySkipped: playHistorySkipped,
      searchHistoryImported: searchHistoryImported,
      searchHistorySkipped: searchHistorySkipped,
      radioStationsImported: radioStationsImported,
      radioStationsSkipped: radioStationsSkipped,
      lyricsMatchesImported: lyricsMatchesImported,
      lyricsMatchesSkipped: lyricsMatchesSkipped,
      settingsImported: settingsImportedFlag,
      errors: errors,
    );
  }

  /// 解析 SourceType 枚举
  SourceType _parseSourceType(String value) {
    switch (value.toLowerCase()) {
      case 'youtube':
        return SourceType.youtube;
      case 'bilibili':
      default:
        return SourceType.bilibili;
    }
  }
}
