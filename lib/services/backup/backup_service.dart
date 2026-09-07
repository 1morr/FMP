import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:isar_community/isar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../core/logger.dart';
import '../../data/models/lyrics_match.dart';
import '../../data/models/hotkey_config.dart';
import '../../data/models/play_history.dart';
import '../../data/models/playlist.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/search_history.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../providers/database/database_migration.dart';
import '../../data/repositories/backup_repository.dart';
import '../../data/repositories/playlist_mutation_repository.dart';
import 'backup_data.dart';

/// 当前备份数据格式版本
/// 備份 JSON 的格式版本。
///
/// v3（Phase 3）：移除 5 個從來沒有讀者的自訂色欄位與 `RadioStation.note`。
/// v4（Phase 3）：6 個每源具名設定欄位收成 `sourceSettings` 清單；補上
/// `railExpanded` / `detailPanelExpanded` / `detailPanelWidth` 三個版面欄位。
///
/// 舊版備份仍然讀得進來 —— `fromJson` 對缺少的鍵一律走預設值，被移除的欄位
/// 在任何既有備份裡都是 null，而 v3 以前的每源設定由 `_readSourceSettings`
/// 折進 `sourceSettings`。
const int kBackupVersion = 4;

/// 备份服务
///
/// 提供数据导出和导入功能
class BackupService with Logging {
  final BackupRepository _repository;

  BackupService(Isar isar, {PlaylistMutationRepository? mutationService})
    : _repository = BackupRepository(isar, mutations: mutationService);

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
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(backupData.toJson());

    // 写入文件
    final file = File(outputPath);
    await file.writeAsString(jsonString, flush: true);

    return outputPath;
  }

  /// 收集所有需要备份的数据
  Future<BackupData> _collectBackupData() async {
    final packageInfo = await PackageInfo.fromPlatform();

    // 获取所有歌单
    final playlists = await _repository.allPlaylists();

    // 获取所有歌曲
    final tracks = await _repository.allTracks();

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

      playlistBackups.add(
        PlaylistBackup(
          name: playlist.name,
          description: playlist.description,
          coverUrl: playlist.coverUrl,
          hasCustomCover: playlist.hasCustomCover,
          sourceUrl: playlist.sourceUrl,
          importSourceType: playlist.importSourceType,
          refreshIntervalHours: playlist.refreshIntervalHours,
          lastRefreshed: playlist.lastRefreshed,
          notifyOnUpdate: playlist.notifyOnUpdate,
          ownerName: playlist.ownerName,
          ownerUserId: playlist.ownerUserId,
          useAuthForRefresh: playlist.useAuthForRefresh,
          isMix: playlist.isMix,
          mixPlaylistId: playlist.mixPlaylistId,
          mixSeedVideoId: playlist.mixSeedVideoId,
          trackKeys: trackKeys,
          createdAt: playlist.createdAt,
          updatedAt: playlist.updatedAt,
          sortOrder: playlist.sortOrder,
        ),
      );
    }

    // 转换歌曲数据
    final trackBackups = tracks
        .map(
          (t) => TrackBackup(
            sourceId: t.sourceId,
            sourceType: t.sourceType,
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
            isAvailable: t.isAvailable,
            isVip: t.isVip,
            unavailableReason: t.unavailableReason,
            bilibiliAid: t.bilibiliAid,
            originalSongId: t.originalSongId,
            originalSource: t.originalSource,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
          ),
        )
        .toList();

    // 获取播放历史
    final playHistory = await _repository.allPlayHistory();
    final playHistoryBackups = playHistory
        .map(
          (h) => PlayHistoryBackup(
            sourceId: h.sourceId,
            sourceType: h.sourceType,
            cid: h.cid,
            title: h.title,
            artist: h.artist,
            durationMs: h.durationMs,
            thumbnailUrl: h.thumbnailUrl,
            playedAt: h.playedAt,
          ),
        )
        .toList();

    // 获取搜索历史
    final searchHistory = await _repository.allSearchHistory();
    final searchHistoryBackups = searchHistory
        .map((s) => SearchHistoryBackup(query: s.query, timestamp: s.timestamp))
        .toList();

    // 获取电台收藏
    final radioStations = await _repository.allRadioStations();
    final radioStationBackups = radioStations
        .map(
          (r) => RadioStationBackup(
            url: r.url,
            title: r.title,
            thumbnailUrl: r.thumbnailUrl,
            hostName: r.hostName,
            hostAvatarUrl: r.hostAvatarUrl,
            hostUid: r.hostUid,
            sourceType: r.sourceType,
            sourceId: r.sourceId,
            sortOrder: r.sortOrder,
            createdAt: r.createdAt,
            lastPlayedAt: r.lastPlayedAt,
            isFavorite: r.isFavorite,
          ),
        )
        .toList();

    // 获取设置
    final settings = await _repository.settings();
    SettingsBackup? settingsBackup;
    if (settings != null) {
      settingsBackup = SettingsBackup(
        themeModeIndex: settings.themeModeIndex,
        primaryColor: settings.primaryColor,
        maxCacheSizeMB: settings.maxCacheSizeMB,
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
        railExpanded: settings.railExpanded,
        detailPanelExpanded: settings.detailPanelExpanded,
        detailPanelWidth: settings.detailPanelWidth,
        fontFamily: settings.fontFamily,
        locale: settings.locale,
        audioQualityLevelIndex: settings.audioQualityLevelIndex,
        audioFormatPriority: settings.audioFormatPriority,
        sourceSettings: [
          for (final entry in settings.sourceSettings)
            SourceSettingsBackup(
              sourceId: entry.sourceId,
              streamPriority: entry.streamPriority,
              useAuthForPlay: entry.useAuthForPlay,
            ),
        ],
        hotkeyConfig: settings.hotkeyConfig,
        autoMatchLyrics: settings.autoMatchLyrics,
        maxLyricsCacheFiles: settings.maxLyricsCacheFiles,
        lyricsDisplayModeIndex: settings.lyricsDisplayModeIndex,
        lyricsSourcePriority: settings.lyricsSourcePriority,
        disabledLyricsSources: settings.disabledLyricsSources,
        lyricsAiTitleParsingModeIndex: settings.lyricsAiTitleParsingModeIndex,
        allowPlainLyricsAutoMatch: settings.allowPlainLyricsAutoMatch,
        lyricsAiEndpoint: settings.lyricsAiEndpoint,
        lyricsAiModel: settings.lyricsAiModel,
        lyricsAiTimeoutSeconds: settings.lyricsAiTimeoutSeconds,
        lyricsWindowTextColor: settings.lyricsWindowTextColor,
        lyricsWindowSecondaryTextColor: settings.lyricsWindowSecondaryTextColor,
        lyricsWindowInactiveTextOpacity:
            settings.lyricsWindowInactiveTextOpacity,
        lyricsWindowOutlineEnabled: settings.lyricsWindowOutlineEnabled,
        lyricsWindowOutlineColor: settings.lyricsWindowOutlineColor,
        lyricsWindowOutlineWidth: settings.lyricsWindowOutlineWidth,
        lyricsWindowShadowEnabled: settings.lyricsWindowShadowEnabled,
        lyricsWindowShadowColor: settings.lyricsWindowShadowColor,
        lyricsWindowShadowBlurRadius: settings.lyricsWindowShadowBlurRadius,
        lyricsWindowShadowOffsetX: settings.lyricsWindowShadowOffsetX,
        lyricsWindowShadowOffsetY: settings.lyricsWindowShadowOffsetY,
        rankingRefreshIntervalMinutes: settings.rankingRefreshIntervalMinutes,
        homeRankingSourcePriority: settings.homeRankingSourcePriorityList.join(
          ',',
        ),
        disabledHomeRankingSources: settings.disabledHomeRankingSourcesSet.join(
          ',',
        ),
        radioRefreshIntervalMinutes: settings.radioRefreshIntervalMinutes,
      );
    }

    // 获取歌词匹配记录
    final lyricsMatches = await _repository.allLyricsMatches();
    final lyricsMatchBackups = lyricsMatches
        .map(
          (m) => LyricsMatchBackup(
            trackUniqueKey: m.trackUniqueKey,
            lyricsSource: m.lyricsSource,
            externalId: m.externalId,
            offsetMs: m.offsetMs,
            matchedAt: m.matchedAt,
          ),
        )
        .toList();

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

  BackupValidationResult validateBackupData(BackupData backupData) {
    if (backupData.version > kBackupVersion) {
      return BackupValidationResult.unsupportedVersion(
        backupVersion: backupData.version,
        supportedVersion: kBackupVersion,
        appVersion: backupData.appVersion,
      );
    }
    final hasImportableData =
        backupData.playlists.isNotEmpty ||
        backupData.tracks.isNotEmpty ||
        backupData.playHistory.isNotEmpty ||
        backupData.searchHistory.isNotEmpty ||
        backupData.radioStations.isNotEmpty ||
        backupData.lyricsMatches.isNotEmpty ||
        backupData.settings != null;
    if (!hasImportableData) {
      return const BackupValidationResult.emptyBackup();
    }
    return const BackupValidationResult.valid();
  }

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
      logWarning('解析备份文件失败: $e');
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

    // 解析階段：把每一筆備份轉成待寫入的物件，跳過與失敗的語意都留在這裡。
    // 資料庫在這個階段完全不動，寫入集中在最後一次 `writeImport`。
    final existingTrackIdsByKey = <String, int>{};
    final plannedTrackKeys = <String>{};
    final preparedTracks = <BackupImportTrack>[];
    final preparedPlaylists = <BackupImportPlaylist>[];
    final preparedPlayHistory = <PlayHistory>[];
    final preparedSearchHistory = <SearchHistory>[];
    final preparedRadioStations = <RadioStation>[];
    final preparedLyricsMatches = <LyricsMatch>[];
    Settings? preparedSettings;

    // 1. 导入歌曲（歌单依赖歌曲，仅在导入歌单时才导入）

    if (importPlaylists) {
      // 先获取现有歌曲的映射
      final existingTracks = await _repository.allTracks();
      for (final track in existingTracks) {
        existingTrackIdsByKey[track.uniqueKey] = track.id;
        plannedTrackKeys.add(track.uniqueKey);
      }

      // 导入新歌曲
      for (final trackBackup in backupData.tracks) {
        if (plannedTrackKeys.contains(trackBackup.uniqueKey)) {
          tracksSkipped++;
          continue;
        }

        try {
          final track = Track()
            ..sourceId = trackBackup.sourceId
            ..sourceType = trackBackup.sourceType
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
            ..isAvailable = trackBackup.isAvailable
            ..isVip = trackBackup.isVip
            ..unavailableReason = trackBackup.unavailableReason
            ..bilibiliAid = trackBackup.bilibiliAid
            ..originalSongId = trackBackup.originalSongId
            ..originalSource = trackBackup.originalSource
            ..createdAt = trackBackup.createdAt
            ..updatedAt = trackBackup.updatedAt;

          preparedTracks.add(
            BackupImportTrack(uniqueKey: trackBackup.uniqueKey, track: track),
          );
          plannedTrackKeys.add(trackBackup.uniqueKey);
          tracksImported++;
        } catch (e) {
          errors.add('导入歌曲失败: ${trackBackup.title} - $e');
        }
      }
    } // end importPlaylists (tracks)

    // 2. 导入歌单
    if (importPlaylists) {
      final existingPlaylistNames = <String>{};
      final existingPlaylists = await _repository.allPlaylists();
      for (final playlist in existingPlaylists) {
        existingPlaylistNames.add(playlist.name);
      }

      for (final playlistBackup in backupData.playlists) {
        if (existingPlaylistNames.contains(playlistBackup.name)) {
          playlistsSkipped++;
          continue;
        }

        try {
          final playlist = Playlist()
            ..name = playlistBackup.name
            ..description = playlistBackup.description
            ..coverUrl = playlistBackup.coverUrl
            ..hasCustomCover = playlistBackup.hasCustomCover
            ..sourceUrl = playlistBackup.sourceUrl
            ..importSourceType = playlistBackup.importSourceType
            ..refreshIntervalHours = playlistBackup.refreshIntervalHours
            ..lastRefreshed = playlistBackup.lastRefreshed
            ..notifyOnUpdate = playlistBackup.notifyOnUpdate
            ..ownerName = playlistBackup.ownerName
            ..ownerUserId = playlistBackup.ownerUserId
            ..useAuthForRefresh = playlistBackup.useAuthForRefresh
            ..isMix = playlistBackup.isMix
            ..mixPlaylistId = playlistBackup.mixPlaylistId
            ..mixSeedVideoId = playlistBackup.mixSeedVideoId
            ..createdAt = playlistBackup.createdAt
            ..updatedAt = playlistBackup.updatedAt
            ..sortOrder = playlistBackup.sortOrder;

          // 成員要等歌曲寫進去才有 id，所以只帶 key；封面與 updatedAt 會被
          // `addTracksInTxn` 依政策改寫，備份裡的原值一併交給寫入階段還原。
          preparedPlaylists.add(
            BackupImportPlaylist(
              playlist: playlist,
              trackKeys: playlistBackup.trackKeys,
              coverUrl: playlistBackup.coverUrl,
              hasCustomCover: playlistBackup.hasCustomCover,
              updatedAt: playlistBackup.updatedAt,
            ),
          );
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
      final existingHistory = await _repository.allPlayHistory();
      for (final history in existingHistory) {
        existingHistoryKeys.add(
          '${history.trackKey}:${history.playedAt.millisecondsSinceEpoch}',
        );
      }

      for (final historyBackup in backupData.playHistory) {
        final key =
            '${historyBackup.trackKey}:${historyBackup.playedAt.millisecondsSinceEpoch}';
        if (existingHistoryKeys.contains(key)) {
          playHistorySkipped++;
          continue;
        }

        try {
          final history = PlayHistory()
            ..sourceId = historyBackup.sourceId
            ..sourceType = historyBackup.sourceType
            ..cid = historyBackup.cid
            ..title = historyBackup.title
            ..artist = historyBackup.artist
            ..durationMs = historyBackup.durationMs
            ..thumbnailUrl = historyBackup.thumbnailUrl
            ..playedAt = historyBackup.playedAt;

          preparedPlayHistory.add(history);
          // 同一份備份裡重複的紀錄以前會重覆插入 —— 這個 set 原本只在迴圈外
          // 填過一次，迴圈內從來沒有再 add。
          existingHistoryKeys.add(key);
          playHistoryImported++;
        } catch (e) {
          errors.add('导入播放历史失败: ${historyBackup.title} - $e');
        }
      }
    } // end importPlayHistory

    // 4. 导入搜索历史
    if (importSearchHistory) {
      final existingSearchQueries = <String>{};
      final existingSearchHistory = await _repository.allSearchHistory();
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

          preparedSearchHistory.add(search);
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
      final existingRadios = await _repository.allRadioStations();
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
            ..sourceType = radioBackup.sourceType
            ..sourceId = radioBackup.sourceId
            ..sortOrder = radioBackup.sortOrder
            ..createdAt = radioBackup.createdAt
            ..lastPlayedAt = radioBackup.lastPlayedAt
            ..isFavorite = radioBackup.isFavorite;

          preparedRadioStations.add(radio);
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
      final existingMatches = await _repository.allLyricsMatches();
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

          preparedLyricsMatches.add(match);
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
        final currentSettings = await _repository.settings();
        final settings = createBootstrapSettings()..id = 0;

        settings
          // 通用设置 - 从备份导入
          ..themeModeIndex = settingsBackup.themeModeIndex
          ..primaryColor = settingsBackup.primaryColor
          ..maxCacheSizeMB = settingsBackup.maxCacheSizeMB
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
          ..sourceSettings = [
            for (final entry in settingsBackup.sourceSettings)
              SourceSettingsEntry()
                ..sourceId = entry.sourceId
                ..streamPriority = entry.streamPriority
                ..useAuthForPlay = entry.useAuthForPlay,
          ]
          ..rankingRefreshIntervalMinutes =
              settingsBackup.rankingRefreshIntervalMinutes
          ..homeRankingSourcePriorityList = settingsBackup
              .homeRankingSourcePriority
              .split(',')
          ..disabledHomeRankingSourcesSet = normalizeDisabledHomeRankingSources(
            settingsBackup.disabledHomeRankingSources,
          )
          ..radioRefreshIntervalMinutes =
              settingsBackup.radioRefreshIntervalMinutes
          // 桌面专属设置 - 仅在桌面平台导入，否则保留当前值
          ..minimizeToTrayOnClose = Platform.isWindows
              ? settingsBackup.minimizeToTrayOnClose
              : (currentSettings?.minimizeToTrayOnClose ??
                    settings.minimizeToTrayOnClose)
          ..enableGlobalHotkeys = Platform.isWindows
              ? settingsBackup.enableGlobalHotkeys
              : (currentSettings?.enableGlobalHotkeys ??
                    settings.enableGlobalHotkeys)
          ..launchAtStartup = Platform.isWindows
              ? settingsBackup.launchAtStartup
              : (currentSettings?.launchAtStartup ?? settings.launchAtStartup)
          ..launchMinimized = Platform.isWindows
              ? settingsBackup.launchMinimized
              : (currentSettings?.launchMinimized ?? settings.launchMinimized)
          ..hotkeyConfig = Platform.isWindows
              ? _sanitizeHotkeyConfig(settingsBackup.hotkeyConfig)
              : currentSettings?.hotkeyConfig
          // 版面狀態 - 無條件還原。這三個欄位不是桌面平台專屬能力，
          // `_ExpandedLayout` 是由螢幕寬度斷點選出來的
          // (`responsive_scaffold.dart`)，Android 平板在寬版面下
          // 同樣會用到側欄與詳情面板。匯入端不必夾寬度：
          // `repairSettingsInvariants` 每次啟動會擋掉垃圾值，而真正的範圍
          // （視窗寬的一個比例）本來就只有渲染期算得出來 —— 從別台機器帶進來
          // 的寬度在這台機器上合不合法，匯入的當下沒有答案。
          ..railExpanded = settingsBackup.railExpanded
          ..detailPanelExpanded = settingsBackup.detailPanelExpanded
          ..detailPanelWidth = settingsBackup.detailPanelWidth
          // 歌词设置 - 从备份导入
          ..autoMatchLyrics = settingsBackup.autoMatchLyrics
          ..maxLyricsCacheFiles = settingsBackup.maxLyricsCacheFiles
          ..lyricsDisplayModeIndex = settingsBackup.lyricsDisplayModeIndex
          ..lyricsSourcePriority = settingsBackup.lyricsSourcePriority
          ..disabledLyricsSources = settingsBackup.disabledLyricsSources
          ..lyricsAiTitleParsingModeIndex =
              settingsBackup.lyricsAiTitleParsingModeIndex
          ..allowPlainLyricsAutoMatch = settingsBackup.allowPlainLyricsAutoMatch
          ..lyricsAiEndpoint = settingsBackup.lyricsAiEndpoint
          ..lyricsAiModel = settingsBackup.lyricsAiModel
          ..lyricsAiTimeoutSeconds = settingsBackup.lyricsAiTimeoutSeconds
          ..lyricsWindowTextColor = settingsBackup.lyricsWindowTextColor
          ..lyricsWindowSecondaryTextColor =
              settingsBackup.lyricsWindowSecondaryTextColor
          ..lyricsWindowInactiveTextOpacity =
              settingsBackup.lyricsWindowInactiveTextOpacity
          ..lyricsWindowOutlineEnabled =
              settingsBackup.lyricsWindowOutlineEnabled
          ..lyricsWindowOutlineColor = settingsBackup.lyricsWindowOutlineColor
          ..lyricsWindowOutlineWidth = settingsBackup.lyricsWindowOutlineWidth
          ..lyricsWindowShadowEnabled = settingsBackup.lyricsWindowShadowEnabled
          ..lyricsWindowShadowColor = settingsBackup.lyricsWindowShadowColor
          ..lyricsWindowShadowBlurRadius =
              settingsBackup.lyricsWindowShadowBlurRadius
          ..lyricsWindowShadowOffsetX = settingsBackup.lyricsWindowShadowOffsetX
          ..lyricsWindowShadowOffsetY = settingsBackup.lyricsWindowShadowOffsetY
          // 设备相关设置 - 保留当前值
          ..customDownloadDir = currentSettings?.customDownloadDir
          ..preferredAudioDeviceId = currentSettings?.preferredAudioDeviceId
          ..preferredAudioDeviceName =
              currentSettings?.preferredAudioDeviceName;

        preparedSettings = settings;
        settingsImportedFlag = true;
      } catch (e) {
        errors.add('导入设置失败: $e');
      }
    }

    // 寫入階段：一筆交易寫完所有倖存者。任何一步失敗都會整批回滾，而且例外
    // 直接往上拋 —— 回一個宣稱匯入了多少筆的結果對話框會是謊話。
    await _repository.writeImport(
      BackupImportBatch(
        existingTrackIdsByKey: existingTrackIdsByKey,
        tracks: preparedTracks,
        playlists: preparedPlaylists,
        playHistory: preparedPlayHistory,
        searchHistory: preparedSearchHistory,
        radioStations: preparedRadioStations,
        lyricsMatches: preparedLyricsMatches,
        settings: preparedSettings,
      ),
    );

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

  String? _sanitizeHotkeyConfig(String? hotkeyConfig) {
    if (hotkeyConfig == null || hotkeyConfig.isEmpty) return hotkeyConfig;
    try {
      final decoded = jsonDecode(hotkeyConfig);
      if (decoded is Map<String, dynamic> && decoded['bindings'] is List) {
        return HotkeyConfig.fromJson(decoded).toJsonString();
      }
    } catch (_) {
      return hotkeyConfig;
    }
    return hotkeyConfig;
  }
}
