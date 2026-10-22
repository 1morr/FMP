/// 舊版（Isar）資料庫讀出來的內容，純值，不帶任何 Isar 型別。
///
/// 規則（design §4.1）：
/// - 值照 Isar 讀到的原樣：非空 `int` 缺欄是 `-2^63`（舊版稱 minLong）、`double` 是 NaN、
///   `bool` 是 false、非空 `String` 是 `''`。這裡不清理，之後的轉換器把「不在
///   合法值域」當成「沒設定」。
/// - 推導值（舊版沒標 `@ignore` 而被存下來的 getter）與過期值（`audioUrl`、
///   `audioUrlExpiry`）不讀；`LyricsTitleParseCache` 是每次啟動就清掉的快取，
///   只數筆數。
/// - 曲目、歌單、佇列互相以 `Track.id` 引用；DB 不保證參照完整，懸空 id、同一個
///   曲目鍵的多列都可能出現。
/// - 時間是 Isar 給的本機時間（`DateTime`，非 UTC）。
final class LegacySnapshot {
  const LegacySnapshot({
    required this.tracks,
    required this.playlists,
    required this.playQueues,
    required this.playHistory,
    required this.settings,
    required this.searchHistory,
    required this.downloadTasks,
    required this.radioStations,
    required this.lyricsMatches,
    required this.lyricsTitleParseCacheCount,
    required this.accounts,
    required this.storedSchemaVersion,
  });

  final List<LegacyTrack> tracks;
  final List<LegacyPlaylist> playlists;
  final List<LegacyPlayQueue> playQueues;
  final List<LegacyPlayHistory> playHistory;

  /// 舊版只有一列（`id` 0），舊 App 每次啟動都會寫；讀取器讀到沒有列的庫就拋錯，
  /// 所以從資料庫讀出來的至少一列。已補做 `schemaVersion < 4` 的舊 migration 與
  /// `repairSettingsInvariants`。
  final List<LegacySettings> settings;
  final List<LegacySearchHistory> searchHistory;
  final List<LegacyDownloadTask> downloadTasks;
  final List<LegacyRadioStation> radioStations;
  final List<LegacyLyricsMatch> lyricsMatches;

  /// `LyricsTitleParseCache` 不讀內容，只有筆數。
  final int lyricsTitleParseCacheCount;
  final List<LegacyAccount> accounts;

  /// 補做 migration 之前，第一列設定上存的 `schemaVersion`（缺欄的負數已視為 0）；
  /// 沒有設定列時 `null`（資料庫讀取器不會產生這種 snapshot）。
  final int? storedSchemaVersion;

  /// 每個 collection 的筆數，鍵是舊版的 collection 名稱。
  Map<String, int> get counts => {
    'Track': tracks.length,
    'Playlist': playlists.length,
    'PlayQueue': playQueues.length,
    'PlayHistory': playHistory.length,
    'Settings': settings.length,
    'SearchHistory': searchHistory.length,
    'DownloadTask': downloadTasks.length,
    'RadioStation': radioStations.length,
    'LyricsMatch': lyricsMatches.length,
    'LyricsTitleParseCache': lyricsTitleParseCacheCount,
    'Account': accounts.length,
  };
}

/// `Track.playlistInfo[]` 的一項：歌單歸屬與下載路徑。
final class LegacyPlaylistDownloadInfo {
  const LegacyPlaylistDownloadInfo({
    required this.playlistId,
    required this.playlistName,
    required this.downloadPath,
  });

  /// `Playlist.id`；0 是掃描器發現的、不屬於任何歌單的本機檔案。
  final int playlistId;
  final String playlistName;

  /// 空字串＝未下載；非空是絕對路徑。
  final String downloadPath;
}

final class LegacyTrack {
  const LegacyTrack({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.title,
    required this.artist,
    required this.ownerId,
    required this.channelId,
    required this.durationMs,
    required this.thumbnailUrl,
    required this.isAvailable,
    required this.isVip,
    required this.unavailableReason,
    required this.playlistInfo,
    required this.pageCount,
    required this.cid,
    required this.pageNum,
    required this.parentTitle,
    required this.bilibiliAid,
    required this.originalSongId,
    required this.originalSource,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String sourceId;
  final String sourceType;
  final String title;
  final String? artist;
  final int? ownerId;
  final String? channelId;
  final int? durationMs;
  final String? thumbnailUrl;
  final bool isAvailable;
  final bool isVip;
  final String? unavailableReason;
  final List<LegacyPlaylistDownloadInfo> playlistInfo;

  /// 分 P 總數。
  final int? pageCount;
  final int? cid;
  final int? pageNum;
  final String? parentTitle;
  final int? bilibiliAid;
  final String? originalSongId;
  final String? originalSource;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class LegacyPlaylist {
  const LegacyPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.hasCustomCover,
    required this.sourceUrl,
    required this.importSourceType,
    required this.refreshIntervalHours,
    required this.lastRefreshed,
    required this.notifyOnUpdate,
    required this.ownerName,
    required this.ownerUserId,
    required this.useAuthForRefresh,
    required this.isMix,
    required this.mixPlaylistId,
    required this.mixSeedVideoId,
    required this.trackIds,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final String? description;
  final String? coverUrl;
  final bool hasCustomCover;
  final String? sourceUrl;
  final String? importSourceType;
  final int? refreshIntervalHours;
  final DateTime? lastRefreshed;
  final bool notifyOnUpdate;
  final String? ownerName;
  final String? ownerUserId;
  final bool useAuthForRefresh;
  final bool isMix;
  final String? mixPlaylistId;
  final String? mixSeedVideoId;

  /// 有序的 `Track.id`。
  final List<int> trackIds;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int sortOrder;
}

/// 舊版的循環模式（磁碟上存名稱）。
enum LegacyLoopMode { none, all, one }

final class LegacyPlayQueue {
  const LegacyPlayQueue({
    required this.id,
    required this.trackIds,
    required this.currentIndex,
    required this.lastPositionMs,
    required this.isShuffleEnabled,
    required this.loopMode,
    required this.originalOrder,
    required this.lastVolume,
    required this.lastUpdated,
    required this.isMixMode,
    required this.mixPlaylistId,
    required this.mixSeedVideoId,
    required this.mixTitle,
  });

  final int id;

  /// 有序的 `Track.id`。
  final List<int> trackIds;
  final int currentIndex;
  final int lastPositionMs;
  final bool isShuffleEnabled;
  final LegacyLoopMode loopMode;

  /// 隨機開啟時仍可能是空 list 而不是 null。
  final List<int>? originalOrder;
  final double lastVolume;
  final DateTime? lastUpdated;
  final bool isMixMode;
  final String? mixPlaylistId;
  final String? mixSeedVideoId;
  final String? mixTitle;
}

final class LegacyPlayHistory {
  const LegacyPlayHistory({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.cid,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.thumbnailUrl,
    required this.playedAt,
  });

  final int id;
  final String sourceId;
  final String sourceType;
  final int? cid;
  final String title;
  final String? artist;
  final int? durationMs;
  final String? thumbnailUrl;
  final DateTime playedAt;
}

final class LegacySearchHistory {
  const LegacySearchHistory({
    required this.id,
    required this.query,
    required this.timestamp,
  });

  final int id;
  final String query;
  final DateTime timestamp;
}

/// 舊版的下載狀態（磁碟上存名稱）。
enum LegacyDownloadStatus { pending, downloading, paused, completed, failed }

final class LegacyDownloadTask {
  const LegacyDownloadTask({
    required this.id,
    required this.trackId,
    required this.playlistId,
    required this.playlistName,
    required this.savePath,
    required this.status,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.errorMessage,
    required this.tempFilePath,
    required this.priority,
    required this.createdAt,
    required this.completedAt,
  });

  final int id;
  final int trackId;
  final int? playlistId;
  final String? playlistName;
  final String? savePath;
  final LegacyDownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final String? errorMessage;
  final String? tempFilePath;
  final int priority;
  final DateTime createdAt;
  final DateTime? completedAt;
}

final class LegacyRadioStation {
  const LegacyRadioStation({
    required this.id,
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    required this.hostName,
    required this.hostAvatarUrl,
    required this.hostUid,
    required this.sourceType,
    required this.sourceId,
    required this.sortOrder,
    required this.createdAt,
    required this.lastPlayedAt,
    required this.isFavorite,
  });

  final int id;
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
  final DateTime? lastPlayedAt;
  final bool isFavorite;
}

final class LegacyLyricsMatch {
  const LegacyLyricsMatch({
    required this.id,
    required this.trackUniqueKey,
    required this.lyricsSource,
    required this.externalId,
    required this.offsetMs,
    required this.matchedAt,
  });

  final int id;

  /// 舊版的曲目鍵字串（`sourceType:sourceId[:cid]`）。
  final String trackUniqueKey;
  final String lyricsSource;
  final String externalId;
  final int offsetMs;
  final DateTime matchedAt;
}

final class LegacyAccount {
  const LegacyAccount({
    required this.id,
    required this.platform,
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.isLoggedIn,
    required this.lastRefreshed,
    required this.loginAt,
    required this.isVip,
    required this.sessionExpired,
  });

  final int id;
  final String platform;
  final String? userId;
  final String? userName;
  final String? avatarUrl;
  final bool isLoggedIn;
  final DateTime? lastRefreshed;
  final DateTime? loginAt;
  final bool isVip;
  final bool sessionExpired;
}

/// `Settings.sourceSettings[]` 的一項。
final class LegacySourceSettings {
  const LegacySourceSettings({
    required this.sourceId,
    required this.streamPriority,
    required this.useAuthForPlay,
  });

  final String sourceId;

  /// 逗號分隔（`audioOnly,muxed,hls`）。
  final String streamPriority;
  final bool useAuthForPlay;
}

/// 舊版設定（單列）。欄位名稱與舊版 `Settings` 相同；`*Index` 是整數索引。
///
/// 欄位**可變**：`schemaVersion < 4` 的補做（`legacy_settings_migration.dart`）
/// 就地改這個物件。它只由讀取器在讀完資料庫後建出來，沒有其他持有者。
/// 建構子的預設值是舊版欄位初始值，讓測試只寫出關心的欄位；讀取器一律把磁碟
/// 讀到的值全部帶進來。
final class LegacySettings {
  LegacySettings({
    this.id = 0,
    this.schemaVersion = 0,
    this.themeModeIndex = 0,
    this.primaryColor,
    this.railExpanded = false,
    this.detailPanelExpanded = false,
    this.detailPanelWidth = 412.0,
    this.maxCacheSizeMB = 32,
    this.customDownloadDir,
    this.hotkeyConfig,
    this.autoScrollToCurrentTrack = false,
    this.rememberPlaybackPosition = true,
    this.restartRewindSeconds = 0,
    this.tempPlayRewindSeconds = 10,
    this.playHistoryLimit = 10000,
    this.maxConcurrentDownloads = 3,
    this.downloadImageOptionIndex = 1,
    this.minimizeToTrayOnClose = false,
    this.enableGlobalHotkeys = false,
    this.launchAtStartup = false,
    this.launchMinimized = false,
    this.fontFamily,
    this.locale,
    this.audioQualityLevelIndex = 0,
    this.audioFormatPriority = 'opus,aac',
    List<LegacySourceSettings>? sourceSettings,
    this.youtubeStreamPriority = 'audioOnly,muxed,hls',
    this.bilibiliStreamPriority = 'audioOnly,muxed',
    this.neteaseStreamPriority = 'audioOnly',
    this.preferredAudioDeviceId,
    this.preferredAudioDeviceName,
    this.autoMatchLyrics = false,
    this.maxLyricsCacheFiles = 50,
    this.lyricsDisplayModeIndex = 0,
    this.lyricsSourcePriority = 'netease,qqmusic,lrclib',
    this.disabledLyricsSources = 'lrclib',
    this.lyricsAiTitleParsingModeIndex = 0,
    this.allowPlainLyricsAutoMatch = false,
    this.lyricsAiEndpoint = '',
    this.lyricsAiModel = '',
    this.lyricsAiTimeoutSeconds = 20,
    this.lyricsWindowTextColor,
    this.lyricsWindowSecondaryTextColor,
    this.lyricsWindowInactiveTextOpacity,
    this.lyricsWindowOutlineEnabled,
    this.lyricsWindowOutlineColor,
    this.lyricsWindowOutlineWidth,
    this.lyricsWindowShadowEnabled,
    this.lyricsWindowShadowColor,
    this.lyricsWindowShadowBlurRadius,
    this.lyricsWindowShadowOffsetX,
    this.lyricsWindowShadowOffsetY,
    this.useBilibiliAuthForPlay = false,
    this.useYoutubeAuthForPlay = false,
    this.useNeteaseAuthForPlay = true,
    this.rankingRefreshIntervalMinutes = 60,
    this.homeRankingSourcePriority = 'bilibili,youtube,netease',
    this.disabledHomeRankingSources = '',
    this.radioRefreshIntervalMinutes = 5,
  }) : sourceSettings = sourceSettings ?? [];

  int id;
  int schemaVersion;
  int themeModeIndex;
  int? primaryColor;
  bool railExpanded;
  bool detailPanelExpanded;
  double detailPanelWidth;
  int maxCacheSizeMB;
  String? customDownloadDir;
  String? hotkeyConfig;
  bool autoScrollToCurrentTrack;
  bool rememberPlaybackPosition;
  int restartRewindSeconds;
  int tempPlayRewindSeconds;
  int playHistoryLimit;
  int maxConcurrentDownloads;
  int downloadImageOptionIndex;
  bool minimizeToTrayOnClose;
  bool enableGlobalHotkeys;
  bool launchAtStartup;
  bool launchMinimized;
  String? fontFamily;
  String? locale;
  int audioQualityLevelIndex;
  String audioFormatPriority;
  List<LegacySourceSettings> sourceSettings;

  /// v1→v2 的來源欄位；v2 之後只有 [sourceSettings] 是真相。
  String youtubeStreamPriority;
  String bilibiliStreamPriority;
  String neteaseStreamPriority;
  String? preferredAudioDeviceId;
  String? preferredAudioDeviceName;
  bool autoMatchLyrics;
  int maxLyricsCacheFiles;
  int lyricsDisplayModeIndex;
  String lyricsSourcePriority;
  String disabledLyricsSources;
  int lyricsAiTitleParsingModeIndex;
  bool allowPlainLyricsAutoMatch;
  String lyricsAiEndpoint;
  String lyricsAiModel;
  int lyricsAiTimeoutSeconds;
  int? lyricsWindowTextColor;
  int? lyricsWindowSecondaryTextColor;
  double? lyricsWindowInactiveTextOpacity;
  bool? lyricsWindowOutlineEnabled;
  int? lyricsWindowOutlineColor;
  double? lyricsWindowOutlineWidth;
  bool? lyricsWindowShadowEnabled;
  int? lyricsWindowShadowColor;
  double? lyricsWindowShadowBlurRadius;
  double? lyricsWindowShadowOffsetX;
  double? lyricsWindowShadowOffsetY;

  /// v1→v2 的來源欄位。
  bool useBilibiliAuthForPlay;
  bool useYoutubeAuthForPlay;
  bool useNeteaseAuthForPlay;
  int rankingRefreshIntervalMinutes;
  String homeRankingSourcePriority;
  String disabledHomeRankingSources;
  int radioRefreshIntervalMinutes;
}
