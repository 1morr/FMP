/// 备份数据模型
/// 导出数据的根结构
///
/// 用于数据导出和导入的 JSON 序列化结构
class BackupData {
  /// 数据格式版本（用于向后兼容）
  final int version;

  /// 导出时间
  final DateTime exportedAt;

  /// 应用版本
  final String appVersion;

  /// 歌单数据
  final List<PlaylistBackup> playlists;

  /// 歌曲数据
  final List<TrackBackup> tracks;

  /// 播放历史
  final List<PlayHistoryBackup> playHistory;

  /// 搜索历史
  final List<SearchHistoryBackup> searchHistory;

  /// 电台收藏
  final List<RadioStationBackup> radioStations;

  /// 应用设置
  final SettingsBackup? settings;

  /// 歌词匹配记录
  final List<LyricsMatchBackup> lyricsMatches;

  BackupData({
    required this.version,
    required this.exportedAt,
    required this.appVersion,
    required this.playlists,
    required this.tracks,
    required this.playHistory,
    required this.searchHistory,
    required this.radioStations,
    this.settings,
    this.lyricsMatches = const [],
  });

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'] as int? ?? 1,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      appVersion: json['appVersion'] as String? ?? 'unknown',
      playlists: (json['playlists'] as List<dynamic>?)
              ?.map((e) => PlaylistBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => TrackBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      playHistory: (json['playHistory'] as List<dynamic>?)
              ?.map((e) => PlayHistoryBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      searchHistory: (json['searchHistory'] as List<dynamic>?)
              ?.map(
                  (e) => SearchHistoryBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      radioStations: (json['radioStations'] as List<dynamic>?)
              ?.map(
                  (e) => RadioStationBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      settings: json['settings'] != null
          ? SettingsBackup.fromJson(json['settings'] as Map<String, dynamic>)
          : null,
      lyricsMatches: (json['lyricsMatches'] as List<dynamic>?)
              ?.map((e) =>
                  LyricsMatchBackup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'exportedAt': exportedAt.toIso8601String(),
      'appVersion': appVersion,
      'playlists': playlists.map((e) => e.toJson()).toList(),
      'tracks': tracks.map((e) => e.toJson()).toList(),
      'playHistory': playHistory.map((e) => e.toJson()).toList(),
      'searchHistory': searchHistory.map((e) => e.toJson()).toList(),
      'radioStations': radioStations.map((e) => e.toJson()).toList(),
      if (settings != null) 'settings': settings!.toJson(),
      if (lyricsMatches.isNotEmpty)
        'lyricsMatches': lyricsMatches.map((e) => e.toJson()).toList(),
    };
  }
}

/// 歌单备份数据
class PlaylistBackup {
  final String name;
  final String? description;
  final String? coverUrl;
  final bool hasCustomCover;
  final String? sourceUrl;
  final String? importSourceType;
  final int? refreshIntervalHours;
  final bool notifyOnUpdate;
  final bool isMix;
  final String? mixPlaylistId;
  final String? mixSeedVideoId;
  final List<String> trackKeys; // sourceType:sourceId[:cid] 格式
  final DateTime createdAt;
  final int sortOrder;

  PlaylistBackup({
    required this.name,
    this.description,
    this.coverUrl,
    this.hasCustomCover = false,
    this.sourceUrl,
    this.importSourceType,
    this.refreshIntervalHours,
    this.notifyOnUpdate = true,
    this.isMix = false,
    this.mixPlaylistId,
    this.mixSeedVideoId,
    required this.trackKeys,
    required this.createdAt,
    this.sortOrder = 0,
  });

  factory PlaylistBackup.fromJson(Map<String, dynamic> json) {
    return PlaylistBackup(
      name: json['name'] as String,
      description: json['description'] as String?,
      coverUrl: json['coverUrl'] as String?,
      hasCustomCover: json['hasCustomCover'] as bool? ?? false,
      sourceUrl: json['sourceUrl'] as String?,
      importSourceType: json['importSourceType'] as String?,
      refreshIntervalHours: json['refreshIntervalHours'] as int?,
      notifyOnUpdate: json['notifyOnUpdate'] as bool? ?? true,
      isMix: json['isMix'] as bool? ?? false,
      mixPlaylistId: json['mixPlaylistId'] as String?,
      mixSeedVideoId: json['mixSeedVideoId'] as String?,
      trackKeys: (json['trackKeys'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (coverUrl != null) 'coverUrl': coverUrl,
      'hasCustomCover': hasCustomCover,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      if (importSourceType != null) 'importSourceType': importSourceType,
      if (refreshIntervalHours != null)
        'refreshIntervalHours': refreshIntervalHours,
      'notifyOnUpdate': notifyOnUpdate,
      'isMix': isMix,
      if (mixPlaylistId != null) 'mixPlaylistId': mixPlaylistId,
      if (mixSeedVideoId != null) 'mixSeedVideoId': mixSeedVideoId,
      'trackKeys': trackKeys,
      'createdAt': createdAt.toIso8601String(),
      'sortOrder': sortOrder,
    };
  }
}

/// 歌曲备份数据
class TrackBackup {
  final String sourceId;
  final String sourceType;
  final String title;
  final String? artist;
  final int? ownerId;
  final String? channelId;
  final int? durationMs;
  final String? thumbnailUrl;
  final int? viewCount;
  final int? pageCount;
  final int? cid;
  final int? pageNum;
  final String? parentTitle;
  final String? originalSongId;
  final String? originalSource;
  final DateTime createdAt;

  TrackBackup({
    required this.sourceId,
    required this.sourceType,
    required this.title,
    this.artist,
    this.ownerId,
    this.channelId,
    this.durationMs,
    this.thumbnailUrl,
    this.viewCount,
    this.pageCount,
    this.cid,
    this.pageNum,
    this.parentTitle,
    this.originalSongId,
    this.originalSource,
    required this.createdAt,
  });

  /// 生成唯一键（用于匹配）
  String get uniqueKey => cid != null
      ? '$sourceType:$sourceId:$cid'
      : '$sourceType:$sourceId';

  factory TrackBackup.fromJson(Map<String, dynamic> json) {
    return TrackBackup(
      sourceId: json['sourceId'] as String,
      sourceType: json['sourceType'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      ownerId: json['ownerId'] as int?,
      channelId: json['channelId'] as String?,
      durationMs: json['durationMs'] as int?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      viewCount: json['viewCount'] as int?,
      pageCount: json['pageCount'] as int?,
      cid: json['cid'] as int?,
      pageNum: json['pageNum'] as int?,
      parentTitle: json['parentTitle'] as String?,
      originalSongId: json['originalSongId'] as String?,
      originalSource: json['originalSource'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'sourceType': sourceType,
      'title': title,
      if (artist != null) 'artist': artist,
      if (ownerId != null) 'ownerId': ownerId,
      if (channelId != null) 'channelId': channelId,
      if (durationMs != null) 'durationMs': durationMs,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (viewCount != null) 'viewCount': viewCount,
      if (pageCount != null) 'pageCount': pageCount,
      if (cid != null) 'cid': cid,
      if (pageNum != null) 'pageNum': pageNum,
      if (parentTitle != null) 'parentTitle': parentTitle,
      if (originalSongId != null) 'originalSongId': originalSongId,
      if (originalSource != null) 'originalSource': originalSource,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// 播放历史备份数据
class PlayHistoryBackup {
  final String sourceId;
  final String sourceType;
  final int? cid;
  final String title;
  final String? artist;
  final int? durationMs;
  final String? thumbnailUrl;
  final DateTime playedAt;

  PlayHistoryBackup({
    required this.sourceId,
    required this.sourceType,
    this.cid,
    required this.title,
    this.artist,
    this.durationMs,
    this.thumbnailUrl,
    required this.playedAt,
  });

  /// 生成唯一键（用于去重）
  String get trackKey => cid != null
      ? '$sourceType:$sourceId:$cid'
      : '$sourceType:$sourceId';

  factory PlayHistoryBackup.fromJson(Map<String, dynamic> json) {
    return PlayHistoryBackup(
      sourceId: json['sourceId'] as String,
      sourceType: json['sourceType'] as String,
      cid: json['cid'] as int?,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      durationMs: json['durationMs'] as int?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      playedAt: DateTime.parse(json['playedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'sourceType': sourceType,
      if (cid != null) 'cid': cid,
      'title': title,
      if (artist != null) 'artist': artist,
      if (durationMs != null) 'durationMs': durationMs,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      'playedAt': playedAt.toIso8601String(),
    };
  }
}

/// 搜索历史备份数据
class SearchHistoryBackup {
  final String query;
  final DateTime timestamp;

  SearchHistoryBackup({
    required this.query,
    required this.timestamp,
  });

  factory SearchHistoryBackup.fromJson(Map<String, dynamic> json) {
    return SearchHistoryBackup(
      query: json['query'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// 电台备份数据
class RadioStationBackup {
  final String url;
  final String title;
  final String? thumbnailUrl;
  final String? hostName;
  final String? hostAvatarUrl;
  final int? hostUid;
  final String sourceType;
  final String sourceId;
  final int sortOrder;
  final DateTime createdAt;
  final bool isFavorite;
  final String? note;

  RadioStationBackup({
    required this.url,
    required this.title,
    this.thumbnailUrl,
    this.hostName,
    this.hostAvatarUrl,
    this.hostUid,
    required this.sourceType,
    required this.sourceId,
    this.sortOrder = 0,
    required this.createdAt,
    this.isFavorite = false,
    this.note,
  });

  factory RadioStationBackup.fromJson(Map<String, dynamic> json) {
    return RadioStationBackup(
      url: json['url'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      hostName: json['hostName'] as String?,
      hostAvatarUrl: json['hostAvatarUrl'] as String?,
      hostUid: json['hostUid'] as int?,
      sourceType: json['sourceType'] as String,
      sourceId: json['sourceId'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (hostName != null) 'hostName': hostName,
      if (hostAvatarUrl != null) 'hostAvatarUrl': hostAvatarUrl,
      if (hostUid != null) 'hostUid': hostUid,
      'sourceType': sourceType,
      'sourceId': sourceId,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite,
      if (note != null) 'note': note,
    };
  }
}

/// 设置备份数据
class SettingsBackup {
  final int themeModeIndex;
  final int? primaryColor;
  final int? secondaryColor;
  final int? backgroundColor;
  final int? surfaceColor;
  final int? textColor;
  final int? cardColor;
  final int maxCacheSizeMB;
  final List<String> enabledSources;
  final bool autoScrollToCurrentTrack;
  final bool rememberPlaybackPosition;
  final int restartRewindSeconds;
  final int tempPlayRewindSeconds;
  final int maxConcurrentDownloads;
  final int downloadImageOptionIndex;
  final bool minimizeToTrayOnClose;
  final bool enableGlobalHotkeys;
  final bool launchAtStartup;
  final bool launchMinimized;
  final String? fontFamily;
  final String? locale;
  final int audioQualityLevelIndex;
  final String audioFormatPriority;
  final String youtubeStreamPriority;
  final String bilibiliStreamPriority;
  final String? hotkeyConfig;
  final bool autoMatchLyrics;
  final int maxLyricsCacheFiles;
  final int lyricsDisplayModeIndex;
  final String lyricsSourcePriority;
  final String disabledLyricsSources;

  SettingsBackup({
    this.themeModeIndex = 0,
    this.primaryColor,
    this.secondaryColor,
    this.backgroundColor,
    this.surfaceColor,
    this.textColor,
    this.cardColor,
    this.maxCacheSizeMB = 32,
    this.enabledSources = const ['bilibili', 'youtube'],
    this.autoScrollToCurrentTrack = false,
    this.rememberPlaybackPosition = true,
    this.restartRewindSeconds = 0,
    this.tempPlayRewindSeconds = 10,
    this.maxConcurrentDownloads = 3,
    this.downloadImageOptionIndex = 1,
    this.minimizeToTrayOnClose = true,
    this.enableGlobalHotkeys = true,
    this.launchAtStartup = false,
    this.launchMinimized = false,
    this.fontFamily,
    this.locale,
    this.audioQualityLevelIndex = 0,
    this.audioFormatPriority = 'aac,opus',
    this.youtubeStreamPriority = 'audioOnly,muxed,hls',
    this.bilibiliStreamPriority = 'audioOnly,muxed',
    this.hotkeyConfig,
    this.autoMatchLyrics = true,
    this.maxLyricsCacheFiles = 50,
    this.lyricsDisplayModeIndex = 0,
    this.lyricsSourcePriority = 'netease,qqmusic,lrclib',
    this.disabledLyricsSources = '',
  });

  factory SettingsBackup.fromJson(Map<String, dynamic> json) {
    return SettingsBackup(
      themeModeIndex: json['themeModeIndex'] as int? ?? 0,
      primaryColor: json['primaryColor'] as int?,
      secondaryColor: json['secondaryColor'] as int?,
      backgroundColor: json['backgroundColor'] as int?,
      surfaceColor: json['surfaceColor'] as int?,
      textColor: json['textColor'] as int?,
      cardColor: json['cardColor'] as int?,
      maxCacheSizeMB: json['maxCacheSizeMB'] as int? ?? 32,
      enabledSources: (json['enabledSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['bilibili', 'youtube'],
      autoScrollToCurrentTrack:
          json['autoScrollToCurrentTrack'] as bool? ?? false,
      rememberPlaybackPosition:
          json['rememberPlaybackPosition'] as bool? ?? true,
      restartRewindSeconds: json['restartRewindSeconds'] as int? ?? 0,
      tempPlayRewindSeconds: json['tempPlayRewindSeconds'] as int? ?? 10,
      maxConcurrentDownloads: json['maxConcurrentDownloads'] as int? ?? 3,
      downloadImageOptionIndex: json['downloadImageOptionIndex'] as int? ?? 1,
      minimizeToTrayOnClose: json['minimizeToTrayOnClose'] as bool? ?? true,
      enableGlobalHotkeys: json['enableGlobalHotkeys'] as bool? ?? true,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      launchMinimized: json['launchMinimized'] as bool? ?? false,
      fontFamily: json['fontFamily'] as String?,
      locale: json['locale'] as String?,
      audioQualityLevelIndex: json['audioQualityLevelIndex'] as int? ?? 0,
      audioFormatPriority:
          json['audioFormatPriority'] as String? ?? 'aac,opus',
      youtubeStreamPriority:
          json['youtubeStreamPriority'] as String? ?? 'audioOnly,muxed,hls',
      bilibiliStreamPriority:
          json['bilibiliStreamPriority'] as String? ?? 'audioOnly,muxed',
      hotkeyConfig: json['hotkeyConfig'] as String?,
      autoMatchLyrics: json['autoMatchLyrics'] as bool? ?? true,
      maxLyricsCacheFiles: json['maxLyricsCacheFiles'] as int? ?? 50,
      lyricsDisplayModeIndex: json['lyricsDisplayModeIndex'] as int? ?? 0,
      lyricsSourcePriority:
          json['lyricsSourcePriority'] as String? ?? 'netease,qqmusic,lrclib',
      disabledLyricsSources:
          json['disabledLyricsSources'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeModeIndex': themeModeIndex,
      if (primaryColor != null) 'primaryColor': primaryColor,
      if (secondaryColor != null) 'secondaryColor': secondaryColor,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (surfaceColor != null) 'surfaceColor': surfaceColor,
      if (textColor != null) 'textColor': textColor,
      if (cardColor != null) 'cardColor': cardColor,
      'maxCacheSizeMB': maxCacheSizeMB,
      'enabledSources': enabledSources,
      'autoScrollToCurrentTrack': autoScrollToCurrentTrack,
      'rememberPlaybackPosition': rememberPlaybackPosition,
      'restartRewindSeconds': restartRewindSeconds,
      'tempPlayRewindSeconds': tempPlayRewindSeconds,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'downloadImageOptionIndex': downloadImageOptionIndex,
      'minimizeToTrayOnClose': minimizeToTrayOnClose,
      'enableGlobalHotkeys': enableGlobalHotkeys,
      'launchAtStartup': launchAtStartup,
      'launchMinimized': launchMinimized,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (locale != null) 'locale': locale,
      'audioQualityLevelIndex': audioQualityLevelIndex,
      'audioFormatPriority': audioFormatPriority,
      'youtubeStreamPriority': youtubeStreamPriority,
      'bilibiliStreamPriority': bilibiliStreamPriority,
      if (hotkeyConfig != null) 'hotkeyConfig': hotkeyConfig,
      'autoMatchLyrics': autoMatchLyrics,
      'maxLyricsCacheFiles': maxLyricsCacheFiles,
      'lyricsDisplayModeIndex': lyricsDisplayModeIndex,
      'lyricsSourcePriority': lyricsSourcePriority,
      'disabledLyricsSources': disabledLyricsSources,
    };
  }
}

/// 歌词匹配备份数据
class LyricsMatchBackup {
  final String trackUniqueKey;
  final String lyricsSource;
  final String externalId;
  final int offsetMs;
  final DateTime matchedAt;

  LyricsMatchBackup({
    required this.trackUniqueKey,
    required this.lyricsSource,
    required this.externalId,
    this.offsetMs = 0,
    required this.matchedAt,
  });

  factory LyricsMatchBackup.fromJson(Map<String, dynamic> json) {
    return LyricsMatchBackup(
      trackUniqueKey: json['trackUniqueKey'] as String,
      lyricsSource: json['lyricsSource'] as String,
      externalId: json['externalId'] as String,
      offsetMs: json['offsetMs'] as int? ?? 0,
      matchedAt: DateTime.parse(json['matchedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trackUniqueKey': trackUniqueKey,
      'lyricsSource': lyricsSource,
      'externalId': externalId,
      if (offsetMs != 0) 'offsetMs': offsetMs,
      'matchedAt': matchedAt.toIso8601String(),
    };
  }
}

/// 导入结果统计
class ImportResult {
  final int playlistsImported;
  final int playlistsSkipped;
  final int tracksImported;
  final int tracksSkipped;
  final int playHistoryImported;
  final int playHistorySkipped;
  final int searchHistoryImported;
  final int searchHistorySkipped;
  final int radioStationsImported;
  final int radioStationsSkipped;
  final int lyricsMatchesImported;
  final int lyricsMatchesSkipped;
  final bool settingsImported;
  final List<String> errors;

  ImportResult({
    this.playlistsImported = 0,
    this.playlistsSkipped = 0,
    this.tracksImported = 0,
    this.tracksSkipped = 0,
    this.playHistoryImported = 0,
    this.playHistorySkipped = 0,
    this.searchHistoryImported = 0,
    this.searchHistorySkipped = 0,
    this.radioStationsImported = 0,
    this.radioStationsSkipped = 0,
    this.lyricsMatchesImported = 0,
    this.lyricsMatchesSkipped = 0,
    this.settingsImported = false,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;

  int get totalImported =>
      playlistsImported +
      tracksImported +
      playHistoryImported +
      searchHistoryImported +
      radioStationsImported +
      lyricsMatchesImported;

  int get totalSkipped =>
      playlistsSkipped +
      tracksSkipped +
      playHistorySkipped +
      searchHistorySkipped +
      radioStationsSkipped +
      lyricsMatchesSkipped;
}
