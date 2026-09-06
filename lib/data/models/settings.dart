import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_layout.dart';
import 'track.dart';

part 'settings.g.dart';

/// 下载图片选项枚举
enum DownloadImageOption {
  /// 不下载图片
  none,

  /// 仅封面
  coverOnly,

  /// 封面和头像
  coverAndAvatar,
}

/// 音质等级
enum AudioQualityLevel {
  /// 最高码率
  high,

  /// 中等码率
  medium,

  /// 最低码率（省流量）
  low,
}

/// 音频格式（用户可排序优先级）
enum AudioFormat {
  /// Opus 编码 (WebM 容器，音质好、体积小，兼容性稍差)
  opus,

  /// AAC 编码 (MP4/M4A 容器，兼容性好)
  aac,
}

/// 流类型
enum StreamType {
  /// 纯音频流
  audioOnly,

  /// 混合流 (视频+音频)
  muxed,

  /// HLS 分段流 (仅 YouTube)
  hls,
}

/// 每個內建音源的預設串流優先序。
///
/// 這是**資料**而不是 schema：新增音源只要多一筆，不必再走一輪
/// `build_runner` + migration + 備份格式同步。
const Map<String, String> kDefaultStreamPriorityBySource = {
  SourceIds.bilibili: 'audioOnly,muxed',
  SourceIds.youtube: 'audioOnly,muxed,hls',
  SourceIds.netease: 'audioOnly',
};

/// 沒有專屬預設的音源使用的串流優先序。
///
/// `audioOnly` 放第一位是因為它對所有音源都成立；`hls` 目前只有 YouTube 會回。
const String kFallbackStreamPriority = 'audioOnly,muxed';

/// 預設就啟用播放認證的音源。
///
/// 網易雲不帶登入狀態時大量歌曲只回試聽片段，所以它的預設是 true；
/// 其餘音源預設 false。
const Map<String, bool> kDefaultUseAuthForPlayBySource = {
  SourceIds.netease: true,
};

/// 指定音源的預設串流優先序。
///
/// `Settings` 與 `audio_settings_provider` 的預設值都從這裡來，避免兩邊各寫
/// 一份 literal 然後悄悄漂移。
List<StreamType> defaultStreamPriorityFor(String sourceId) =>
    parseStreamPriority(
      kDefaultStreamPriorityBySource[sourceId] ?? kFallbackStreamPriority,
    );

/// 指定音源是否預設啟用播放認證。
bool defaultUseAuthForPlayFor(String sourceId) =>
    kDefaultUseAuthForPlayBySource[sourceId] ?? false;

/// 解析逗號分隔的串流優先序字串。
///
/// 認不得的 token 直接丟掉。舊版把它當成 audioOnly，那會在清單裡塞出重複項；
/// 丟掉之後若整串都無效，呼叫端會落回該音源的預設。
List<StreamType> parseStreamPriority(String value) {
  final result = <StreamType>[];
  for (final raw in value.split(',')) {
    final type = switch (raw.trim()) {
      'audioOnly' => StreamType.audioOnly,
      'muxed' => StreamType.muxed,
      'hls' => StreamType.hls,
      _ => null,
    };
    if (type != null && !result.contains(type)) result.add(type);
  }
  return result;
}

/// 串流類型在持久化字串裡的名稱。
String streamTypeName(StreamType type) => switch (type) {
      StreamType.audioOnly => 'audioOnly',
      StreamType.muxed => 'muxed',
      StreamType.hls => 'hls',
    };

/// 單一音源的設定。
///
/// 取代原本六個具名欄位（三個 `*StreamPriority` + 三個 `use*AuthForPlay`）。
/// 依 `Track.playlistInfo` 的先例用 `@embedded`，而不是塞成一坨 JSON 字串：
/// 偵錯檢視器能逐欄位列出，備份 DTO 也能結構化對映。
///
/// ⚠️ 跟所有 `@embedded` 物件一樣，**改值必須建新的物件與新的 list**，
/// 否則 Isar 偵測不到變更（同 `track.dart` 的註解）。
@embedded
class SourceSettingsEntry {
  /// 音源 id，對應 [SourceIds]。
  String sourceId = '';

  /// 串流優先序，逗號分隔（語意與舊的 `*StreamPriority` 欄位相同）。
  String streamPriority = '';

  /// 播放時是否帶上該音源的登入狀態。
  bool useAuthForPlay = false;

  SourceSettingsEntry();

  SourceSettingsEntry copy() => SourceSettingsEntry()
    ..sourceId = sourceId
    ..streamPriority = streamPriority
    ..useAuthForPlay = useAuthForPlay;

  @override
  String toString() => 'SourceSettingsEntry($sourceId, '
      'streamPriority: $streamPriority, useAuthForPlay: $useAuthForPlay)';
}

/// 歌词显示模式
enum LyricsDisplayMode {
  /// 只显示原文
  original,

  /// 优先显示翻译（翻译 → 罗马音 → 原文）
  preferTranslated,

  /// 优先显示罗马音（罗马音 → 翻译 → 原文）
  preferRomaji,
}

enum LyricsAiTitleParsingMode {
  off,
  alwaysAi,
  advancedAiSelect,
}

/// 首頁排行榜音源白名單。
///
/// 單一真相衍生自 [SourceIds.values]：新增內建音源後自動同步，
/// 不會因為忘了補 literal 而讓新源 id 被 normalize 靜默丟棄（D4）。
/// 回傳可變副本，因為使用處（含作為狀態預設）皆以可變值形式取用。
List<String> get homeRankingSourceIds =>
    List<String>.of(SourceIds.values);

const String defaultHomeRankingSourcePriority = 'bilibili,youtube,netease';

List<String> normalizeHomeRankingSourcePriority(String value) {
  final seen = <String>{};
  final normalized = <String>[];

  for (final raw in value.split(',')) {
    final source = raw.trim();
    if (!homeRankingSourceIds.contains(source) || !seen.add(source)) {
      continue;
    }
    normalized.add(source);
  }

  for (final source in homeRankingSourceIds) {
    if (seen.add(source)) normalized.add(source);
  }

  return normalized;
}

Set<String> normalizeDisabledHomeRankingSources(String value) {
  if (value.isEmpty) return <String>{};
  final disabled = value
      .split(',')
      .map((s) => s.trim())
      .where(homeRankingSourceIds.contains)
      .toSet();
  if (disabled.length >= homeRankingSourceIds.length) return <String>{};
  return disabled;
}

/// 应用设置实体（单例模式，始终使用 ID 0）
@collection
class Settings {
  Id id = 0;

  /// 持久化 schema 的版本號。
  ///
  /// Isar 對新增的 int 欄位一律補 0，而 0 剛好就是「這是 Phase 3 之前的資料庫」
  /// 的意思，所以不需要另外推斷。遷移步驟表在
  /// `lib/providers/database/database_migration.dart`。
  int schemaVersion = 0;

  /// 主题模式: 0=system, 1=light, 2=dark
  int themeModeIndex = 0;

  /// 自定义颜色 (ARGB int)
  int? primaryColor;
  // ========== 桌面版面（每次啟動要記得上次的樣子）==========

  /// 側欄是否展開。預設收起，與 `_DesktopLayoutState` 的初值一致。
  bool railExpanded = false;

  /// 詳情面板是否展開。
  ///
  /// **業務預設從 true 改成 false**（決策 04-D2）：面板現在從 840dp 就開始
  /// 提供，而在 840–1199dp 上它會吃掉 40% 的主內容，所以讓使用者自己展開。
  /// 這只影響新建的列 —— 既有使用者存下來的值原封不動，而
  /// `database_migration.dart` 的 v0 救援仍然把舊列補成 true，因為那些列在
  /// 這個改動之前確實是展開的。
  bool detailPanelExpanded = false;

  /// 詳情面板寬度（像素）。Isar 對舊列的 double 補 NaN 而不是 0，
  /// 同樣要在不變式修復裡處理。
  double detailPanelWidth = AppLayout.detailPanelDefault;

  /// 缓存设置
  int maxCacheSizeMB = 32; // 默认 32MB

  /// 下载目录
  String? customDownloadDir;

  /// 快捷键配置 (JSON 字符串)
  String? hotkeyConfig;

  /// 切歌时自动跳转到队列页面并定位当前歌曲
  bool autoScrollToCurrentTrack = false;

  /// 记住播放位置（应用重启后从上次位置继续播放）
  bool rememberPlaybackPosition = true;

  /// 应用重启恢复时回退秒数（0 = 从精确位置恢复）
  int restartRewindSeconds = 0;

  /// 临时播放恢复时回退秒数
  int tempPlayRewindSeconds = 10;

  // ========== 下载设置 ==========

  /// 最大并发下载数 (1-5)
  int maxConcurrentDownloads = 3;

  /// 下载图片选项: 0=none, 1=coverOnly, 2=coverAndAvatar
  int downloadImageOptionIndex = 1;

  // ========== 桌面平台设置 ==========

  /// 关闭窗口时最小化到托盘（仅 Windows）
  bool minimizeToTrayOnClose = false;

  /// 启用全局快捷键（仅 Windows）
  bool enableGlobalHotkeys = false;

  /// 开机自启动（仅 Windows）
  bool launchAtStartup = false;

  /// 自启动时最小化到托盘（仅 Windows）
  bool launchMinimized = false;

  /// 自定义字体 (null 或空 = 系统默认)
  String? fontFamily;

  /// 语言设置 (null = 跟随系统, 'zh_CN', 'zh_TW', 'en')
  String? locale;

  // ========== 音频质量设置 ==========

  /// 音质等级: 0=high, 1=medium, 2=low
  int audioQualityLevelIndex = 0;

  /// 格式优先级 (逗号分隔: "opus,aac")
  /// 按顺序尝试，第一个可用的格式被选中
  String audioFormatPriority = 'opus,aac';

  /// 每個音源的設定（串流優先序、播放認證）。
  ///
  /// v2 之後這是唯一的真相來源；下面六個具名欄位只留給 v1→v2 遷移讀。
  List<SourceSettingsEntry> sourceSettings = [];

  /// YouTube 流优先级 (逗号分隔: "audioOnly,muxed,hls")
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  String youtubeStreamPriority = 'audioOnly,muxed,hls';

  /// Bilibili 流优先级 (逗号分隔: "audioOnly,muxed")
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  String bilibiliStreamPriority = 'audioOnly,muxed';

  /// 網易雲流優先級 (逗號分隔: "audioOnly")
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  String neteaseStreamPriority = 'audioOnly';

  /// 首选音频输出设备 ID (null = 自动/跟随系统)
  String? preferredAudioDeviceId;

  /// 首选音频输出设备名称 (用于 UI 显示，设备 ID 可能变化)
  String? preferredAudioDeviceName;

  // ========== 歌词设置 ==========

  /// 自动匹配歌词（播放时自动搜索并匹配）
  bool autoMatchLyrics = false;

  /// 最大歌词缓存文件数
  int maxLyricsCacheFiles = 50;

  /// 歌词显示模式: 0=original, 1=preferTranslated, 2=preferRomaji
  int lyricsDisplayModeIndex = 0;

  /// 歌词匹配源优先级 (逗号分隔: "netease,qqmusic,lrclib")
  /// 按顺序尝试匹配，排在前面的源优先
  String lyricsSourcePriority = 'netease,qqmusic,lrclib';

  /// 禁用的歌词源 (逗号分隔: "lrclib" 或 "netease,lrclib")
  /// 自动匹配和搜索时跳过这些源
  String disabledLyricsSources = 'lrclib';

  /// AI 标题解析模式: 0=off, 2=alwaysAi, 3=advancedAiSelect
  int lyricsAiTitleParsingModeIndex = 0;

  /// Allow auto-matching plain lyrics without timestamps.
  bool allowPlainLyricsAutoMatch = false;

  /// OpenAI-compatible API base URL for AI title parsing.
  String lyricsAiEndpoint = '';

  /// OpenAI-compatible model name for AI title parsing.
  String lyricsAiModel = '';

  /// AI title parsing request timeout in seconds.
  int lyricsAiTimeoutSeconds = AppConstants.lyricsAiDefaultTimeoutSeconds;

  /// Lyrics popup text color. Null uses the default style.
  int? lyricsWindowTextColor;

  /// Lyrics popup secondary line color.
  int? lyricsWindowSecondaryTextColor;

  /// Opacity for inactive lyrics in the popup.
  double? lyricsWindowInactiveTextOpacity;

  /// Whether popup lyrics render an outline.
  bool? lyricsWindowOutlineEnabled;

  /// Outline color for popup lyrics.
  int? lyricsWindowOutlineColor;

  /// Outline width for popup lyrics.
  double? lyricsWindowOutlineWidth;

  /// Whether popup lyrics render a shadow.
  bool? lyricsWindowShadowEnabled;

  /// Shadow color for popup lyrics.
  int? lyricsWindowShadowColor;

  /// Shadow blur radius for popup lyrics.
  double? lyricsWindowShadowBlurRadius;

  /// Shadow horizontal offset for popup lyrics.
  double? lyricsWindowShadowOffsetX;

  /// Shadow vertical offset for popup lyrics.
  double? lyricsWindowShadowOffsetY;

  // ========== 播放認證設置 ==========

  /// Bilibili 播放時使用登入狀態
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  bool useBilibiliAuthForPlay = false;

  /// YouTube 播放時使用登入狀態
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  bool useYoutubeAuthForPlay = false;

  /// 網易雲播放時使用登入狀態
  @Deprecated('read only by the v1 to v2 migration; removed in schema v3')
  bool useNeteaseAuthForPlay = true;

  // ========== 刷新间隔设置 ==========

  /// 排行榜缓存刷新间隔（分钟），默认 60
  int rankingRefreshIntervalMinutes = 60;

  /// Home recent trending ranking source priority.
  String homeRankingSourcePriority = defaultHomeRankingSourcePriority;

  /// Disabled Home recent trending ranking sources.
  String disabledHomeRankingSources = '';

  /// 电台直播状态刷新间隔（分钟），默认 5
  int radioRefreshIntervalMinutes = 5;

  /// 获取 ThemeMode
  @ignore
  ThemeMode get themeMode {
    switch (themeModeIndex) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// 设置 ThemeMode
  set themeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        themeModeIndex = 1;
        break;
      case ThemeMode.dark:
        themeModeIndex = 2;
        break;
      case ThemeMode.system:
        themeModeIndex = 0;
        break;
    }
  }

  /// 获取主色 Color
  @ignore
  Color? get primaryColorValue =>
      primaryColor != null ? Color(primaryColor!) : null;

  /// 设置主色 Color
  set primaryColorValue(Color? color) {
    primaryColor = color?.toARGB32();
  }

  /// 获取下载图片选项
  @ignore
  DownloadImageOption get downloadImageOption {
    switch (downloadImageOptionIndex) {
      case 0:
        return DownloadImageOption.none;
      case 2:
        return DownloadImageOption.coverAndAvatar;
      default:
        return DownloadImageOption.coverOnly;
    }
  }

  /// 设置下载图片选项
  set downloadImageOption(DownloadImageOption option) {
    switch (option) {
      case DownloadImageOption.none:
        downloadImageOptionIndex = 0;
        break;
      case DownloadImageOption.coverOnly:
        downloadImageOptionIndex = 1;
        break;
      case DownloadImageOption.coverAndAvatar:
        downloadImageOptionIndex = 2;
        break;
    }
  }

  /// 获取音质等级
  @ignore
  AudioQualityLevel get audioQualityLevel {
    switch (audioQualityLevelIndex) {
      case 1:
        return AudioQualityLevel.medium;
      case 2:
        return AudioQualityLevel.low;
      default:
        return AudioQualityLevel.high;
    }
  }

  /// 设置音质等级
  set audioQualityLevel(AudioQualityLevel level) {
    switch (level) {
      case AudioQualityLevel.high:
        audioQualityLevelIndex = 0;
        break;
      case AudioQualityLevel.medium:
        audioQualityLevelIndex = 1;
        break;
      case AudioQualityLevel.low:
        audioQualityLevelIndex = 2;
        break;
    }
  }

  /// 获取格式优先级列表
  @ignore
  List<AudioFormat> get audioFormatPriorityList {
    if (audioFormatPriority.isEmpty) {
      return [AudioFormat.opus, AudioFormat.aac];
    }
    return audioFormatPriority.split(',').map((s) {
      switch (s.trim()) {
        case 'opus':
          return AudioFormat.opus;
        default:
          return AudioFormat.aac;
      }
    }).toList();
  }

  /// 设置格式优先级列表
  set audioFormatPriorityList(List<AudioFormat> list) {
    audioFormatPriority = list.map((f) {
      switch (f) {
        case AudioFormat.opus:
          return 'opus';
        case AudioFormat.aac:
          return 'aac';
      }
    }).join(',');
  }

  /// 获取歌词显示模式
  @ignore
  LyricsDisplayMode get lyricsDisplayMode {
    switch (lyricsDisplayModeIndex) {
      case 1:
        return LyricsDisplayMode.preferTranslated;
      case 2:
        return LyricsDisplayMode.preferRomaji;
      default:
        return LyricsDisplayMode.original;
    }
  }

  /// 设置歌词显示模式
  set lyricsDisplayMode(LyricsDisplayMode mode) {
    switch (mode) {
      case LyricsDisplayMode.original:
        lyricsDisplayModeIndex = 0;
        break;
      case LyricsDisplayMode.preferTranslated:
        lyricsDisplayModeIndex = 1;
        break;
      case LyricsDisplayMode.preferRomaji:
        lyricsDisplayModeIndex = 2;
        break;
    }
  }

  /// 获取歌词匹配源优先级列表
  @ignore
  List<String> get lyricsSourcePriorityList {
    if (lyricsSourcePriority.isEmpty) {
      return ['netease', 'qqmusic', 'lrclib'];
    }
    return lyricsSourcePriority
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 设置歌词匹配源优先级列表
  set lyricsSourcePriorityList(List<String> list) {
    lyricsSourcePriority = list.join(',');
  }

  /// 获取禁用的歌词源集合
  @ignore
  Set<String> get disabledLyricsSourcesSet {
    if (disabledLyricsSources.isEmpty) return {};
    return disabledLyricsSources
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// 设置禁用的歌词源集合
  set disabledLyricsSourcesSet(Set<String> set) {
    disabledLyricsSources = set.join(',');
  }

  /// 获取首页排行榜源优先级列表
  @ignore
  List<String> get homeRankingSourcePriorityList {
    return normalizeHomeRankingSourcePriority(homeRankingSourcePriority);
  }

  /// 设置首页排行榜源优先级列表
  set homeRankingSourcePriorityList(List<String> list) {
    homeRankingSourcePriority =
        normalizeHomeRankingSourcePriority(list.join(',')).join(',');
  }

  /// 获取禁用的首页排行榜源集合
  @ignore
  Set<String> get disabledHomeRankingSourcesSet {
    return normalizeDisabledHomeRankingSources(disabledHomeRankingSources);
  }

  /// 设置禁用的首页排行榜源集合
  set disabledHomeRankingSourcesSet(Set<String> set) {
    disabledHomeRankingSources =
        normalizeDisabledHomeRankingSources(set.join(',')).join(',');
  }

  @ignore
  LyricsAiTitleParsingMode get lyricsAiTitleParsingMode {
    switch (lyricsAiTitleParsingModeIndex) {
      case 2:
        return LyricsAiTitleParsingMode.alwaysAi;
      case 3:
        return LyricsAiTitleParsingMode.advancedAiSelect;
      case 0:
      case 1:
      default:
        return LyricsAiTitleParsingMode.off;
    }
  }

  set lyricsAiTitleParsingMode(LyricsAiTitleParsingMode mode) {
    switch (mode) {
      case LyricsAiTitleParsingMode.off:
        lyricsAiTitleParsingModeIndex = 0;
      case LyricsAiTitleParsingMode.alwaysAi:
        lyricsAiTitleParsingModeIndex = 2;
      case LyricsAiTitleParsingMode.advancedAiSelect:
        lyricsAiTitleParsingModeIndex = 3;
    }
  }

  // ========== 每源設定 ==========

  /// 取得指定音源的設定；沒有就依預設建一筆（不寫回）。
  SourceSettingsEntry _entryFor(String sourceId) {
    for (final entry in sourceSettings) {
      if (entry.sourceId == sourceId) return entry;
    }
    return SourceSettingsEntry()
      ..sourceId = sourceId
      ..streamPriority =
          kDefaultStreamPriorityBySource[sourceId] ?? kFallbackStreamPriority
      ..useAuthForPlay = defaultUseAuthForPlayFor(sourceId);
  }

  /// 覆寫指定音源的設定。
  ///
  /// Isar 對 `@embedded` 物件只比較 list 的識別，所以這裡**必須**建新的 list
  /// 與新的 entry，就地改欄位不會被持久化（同 `Track.playlistInfo` 的坑）。
  void _putEntry(SourceSettingsEntry entry) {
    sourceSettings = [
      for (final existing in sourceSettings)
        if (existing.sourceId != entry.sourceId) existing.copy(),
      entry,
    ];
  }

  /// 指定音源的串流優先序。
  List<StreamType> streamPriorityFor(String sourceId) {
    final parsed = parseStreamPriority(_entryFor(sourceId).streamPriority);
    if (parsed.isNotEmpty) return parsed;
    return defaultStreamPriorityFor(sourceId);
  }

  /// 設定指定音源的串流優先序。
  void setStreamPriorityFor(String sourceId, List<StreamType> list) {
    _putEntry(_entryFor(sourceId).copy()
      ..streamPriority = list.map(streamTypeName).join(','));
  }

  /// 指定音源是否在播放時帶上登入狀態。
  bool useAuthForPlay(String sourceId) => _entryFor(sourceId).useAuthForPlay;

  /// 設定指定音源是否在播放時帶上登入狀態。
  void setUseAuthForPlay(String sourceId, bool value) {
    _putEntry(_entryFor(sourceId).copy()..useAuthForPlay = value);
  }


  @override
  String toString() =>
      'Settings(themeMode: $themeMode, maxCacheSizeMB: $maxCacheSizeMB)';
}
