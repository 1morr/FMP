import 'package:isar_community/isar.dart';

part 'settings.g.dart';

/// 單一音源的設定（嵌入物件）。`sourceId` 是舊版的音源 id 字串。
@embedded
class SourceSettingsEntry {
  String sourceId = '';

  /// 串流優先序，逗號分隔（`audioOnly,muxed,hls`）。
  String streamPriority = '';

  bool useAuthForPlay = false;

  SourceSettingsEntry();
}

/// 舊版設定（單列，`id` 恆為 0）。
///
/// 欄位照舊版逐一保留；`*Index` 是整數索引，不是 enum 名稱。標「v1→v2 專用」的
/// 六個欄位舊版標了 `@Deprecated`，只有遷移讀它們；這裡的 `schemaVersion < 4`
/// 補做（`legacy_settings_migration.dart`）同樣要讀。
@collection
class Settings {
  Id id = 0;

  int schemaVersion = 0;
  int themeModeIndex = 0;
  int? primaryColor;
  bool railExpanded = false;
  bool detailPanelExpanded = false;
  double detailPanelWidth = 412.0;
  int maxCacheSizeMB = 32;
  String? customDownloadDir;
  String? hotkeyConfig;
  bool autoScrollToCurrentTrack = false;
  bool rememberPlaybackPosition = true;
  int restartRewindSeconds = 0;
  int tempPlayRewindSeconds = 10;
  int playHistoryLimit = 10000;
  int maxConcurrentDownloads = 3;
  int downloadImageOptionIndex = 1;
  bool minimizeToTrayOnClose = false;
  bool enableGlobalHotkeys = false;
  bool launchAtStartup = false;
  bool launchMinimized = false;
  String? fontFamily;
  String? locale;
  int audioQualityLevelIndex = 0;
  String audioFormatPriority = 'opus,aac';
  List<SourceSettingsEntry> sourceSettings = [];

  /// v1→v2 專用。
  String youtubeStreamPriority = 'audioOnly,muxed,hls';

  /// v1→v2 專用。
  String bilibiliStreamPriority = 'audioOnly,muxed';

  /// v1→v2 專用。
  String neteaseStreamPriority = 'audioOnly';

  String? preferredAudioDeviceId;
  String? preferredAudioDeviceName;
  bool autoMatchLyrics = false;
  int maxLyricsCacheFiles = 50;
  int lyricsDisplayModeIndex = 0;
  String lyricsSourcePriority = 'netease,qqmusic,lrclib';
  String disabledLyricsSources = 'lrclib';
  int lyricsAiTitleParsingModeIndex = 0;
  bool allowPlainLyricsAutoMatch = false;
  String lyricsAiEndpoint = '';
  String lyricsAiModel = '';
  int lyricsAiTimeoutSeconds = 20;
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

  /// v1→v2 專用。
  bool useBilibiliAuthForPlay = false;

  /// v1→v2 專用。
  bool useYoutubeAuthForPlay = false;

  /// v1→v2 專用。
  bool useNeteaseAuthForPlay = true;

  int rankingRefreshIntervalMinutes = 60;
  String homeRankingSourcePriority = 'bilibili,youtube,netease';
  String disabledHomeRankingSources = '';
  int radioRefreshIntervalMinutes = 5;
}
