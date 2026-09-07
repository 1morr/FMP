/// 应用常量定义
class AppConstants {
  AppConstants._();

  // ==================== 应用信息 ====================

  /// 应用名称
  static const String appName = 'FMP';

  /// 应用全称
  static const String appFullName = 'Flutter Music Player';

  // ==================== 窗口 ====================

  /// 默认窗口大小 (Windows)
  static const double defaultWindowWidth = 1280;
  static const double defaultWindowHeight = 800;

  /// 最小窗口大小 (Windows)
  static const double minimumWindowWidth = 400;
  static const double minimumWindowHeight = 500;

  // ==================== 缓存与存储 ====================

  /// 音频 URL 默认过期时间 (小时) - Bilibili 使用
  static const int bilibiliAudioUrlExpiryHours = 2;

  /// 音频 URL 默认过期时间 (小时) - YouTube 使用 (过期较快)
  static const int youtubeAudioUrlExpiryHours = 1;

  /// 搜索历史最大条数
  static const int maxSearchHistoryCount = 100;

  /// 队列最大容量
  static const int maxQueueSize = 10000;

  /// 最大播放历史记录数
  static const int maxPlayHistoryCount = 1000;

  // ==================== 播放控制 ====================

  /// 点击"上一首"时，如果当前播放超过此秒数则重新开始当前歌曲，否则切换到上一首
  static const int previousTrackThresholdSeconds = 3;

  /// 播放速度选项
  static const List<double> playbackSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  /// 位置保存定时器间隔
  static const Duration positionSaveInterval = Duration(seconds: 10);

  /// 播放锁超时
  static const Duration playLockTimeout = Duration(seconds: 5);

  /// 音频服务状态轮询延迟 (media_kit 内部等待)
  static const Duration audioServicePollingDelay = Duration(milliseconds: 50);

  /// 播放器 seek 前等待延迟 (确保播放器就绪)
  static const Duration seekStabilizationDelay = Duration(milliseconds: 500);

  /// seek 后验证延迟 (等待 seek 生效后检查位置)
  static const Duration seekVerificationDelay = Duration(milliseconds: 300);

  /// 基于位置检测的备选切歌检查间隔
  static const Duration positionCheckInterval = Duration(seconds: 1);

  /// 基于位置检测的切歌阈值（距离结尾多近时触发）
  static const Duration positionCheckThreshold = Duration(milliseconds: 500);

  /// 「引擎宣告播完」的容忍窗：位置離時長還差這麼多以上，就判定為提前結束。
  ///
  /// 兩個音訊後端各自在翻譯 `PlaybackEndReason` 時使用同一個值，避免 Android
  /// 與 Windows 對「算不算播完」給出不同答案。
  static final Duration completionTolerance =
      positionCheckInterval + positionCheckThreshold;

  /// 匯入比對搜尋之間的節流延遲——避免觸發音源限流（B7）。
  /// all（搜尋多源）需較長間隔；單源（bilibili/youtube）較短。
  static const Duration importThrottleMultiSourceDelay = Duration(
    milliseconds: 1000,
  );
  static const Duration importThrottleSingleSourceDelay = Duration(
    milliseconds: 800,
  );

  // ==================== Mix 播放列表 ====================

  /// Mix 模式每次加载的最少新歌曲数
  static const int mixMinNewTracksRequired = 10;

  /// Mix 模式剩余多少首时开始预加载更多歌曲
  static const int mixLoadMoreRemainingThreshold = 1;

  /// Mix 模式最大加载尝试次数
  static const int mixMaxLoadAttempts = 10;

  /// Mix 模式使用相同种子视频的重试次数
  static const int mixSameVideoRetries = 3;

  /// Mix 模式加载重试延迟
  static const Duration mixRetryDelay = Duration(seconds: 1);

  // ==================== 下载 ====================

  /// 下载进度更新最小间隔（避免频繁回调）
  static const double downloadProgressUpdateThreshold = 0.05;

  // ==================== 网络超时 ====================

  /// 网络连接超时
  static const Duration networkConnectTimeout = Duration(seconds: 10);

  /// 网络接收超时
  static const Duration networkReceiveTimeout = Duration(seconds: 30);

  /// 更新服务连接超时 (GitHub Releases 可能较慢)
  static const Duration updateConnectTimeout = Duration(seconds: 15);

  /// 下载连接超时
  static const Duration downloadConnectTimeout = Duration(seconds: 30);

  // ==================== 重试与延迟 ====================

  /// 网络请求重试延迟
  static const Duration networkRetryDelay = Duration(milliseconds: 200);

  /// 队列保存重试延迟
  static const Duration queueSaveRetryDelay = Duration(seconds: 1);

  /// 串流解析內層重試前的等待。
  ///
  /// 過去這裡借用 [queueSaveRetryDelay]，兩個不相干的東西共用一個數字 ——
  /// 調整佇列保存的節奏會連帶改到播放解析的重試。
  static const Duration streamResolutionRetryDelay = Duration(seconds: 1);

  // ==================== 后台服务 ====================

  /// 自动刷新检查间隔
  static const Duration autoRefreshCheckInterval = Duration(minutes: 30);

  /// 网络状态轮询间隔
  static const Duration connectivityPollingInterval = Duration(seconds: 15);

  /// DNS 查询超时
  static const Duration dnsTimeout = Duration(seconds: 5);

  // ==================== 显示数量限制 ====================

  /// 首页歌曲预览数量
  static const int homeTrackPreviewCount = 5;

  /// 首页列表预览数量
  static const int homeListPreviewCount = 20;

  /// 即将播放预览数量
  static const int upcomingTracksPreviewCount = 3;

  /// 排行榜预览数量
  static const int rankingPreviewCount = 10;

  /// 评论预览数量
  static const int commentsPreviewCount = 3;

  // ==================== 歌词匹配 ====================

  /// 歌词自动匹配时长容差（秒）
  static const int lyricsDurationToleranceSec = 20;

  /// 歌词自动匹配最低得分阈值（0.0 - 1.0）
  static const double lyricsMatchScoreThreshold = 0.6;

  /// AI 歌词匹配请求默认超时（秒）
  static const int lyricsAiDefaultTimeoutSeconds = 20;
}

/// 播放載入路徑的逾時預算。
///
/// 沒有它的時候，「等多久」完全由音訊引擎內部策略決定，FMP 既不設定也不知道
/// ——實測 YouTube 退到 muxed 要 9.9–20 秒，而一條「連得上但零位元組」的串流
/// 在 Windows 上 6.1 秒就假裝成功、在 Android 上阻塞 37.7 秒才拋。
///
/// 可注入，測試才不必真的等 6 秒。
class PlaybackTimeoutBudget {
  const PlaybackTimeoutBudget({
    this.streamResolution = const Duration(seconds: 25),
    this.mediaOpen = const Duration(seconds: 8),
    this.bufferStarvation = const Duration(seconds: 15),
  });

  /// T1：把 track 解析成一個可播的 URL。
  ///
  /// 實測：YouTube 的 androidVr audio-only 被 bot 檢查擋下之後（那是常態不是
  /// 例外），退到 muxed 在 Android 模擬器上量到 21.3–22.7 秒、在 Windows 主機上
  /// 9.9 秒。這一層是「別無限等下去」的兜底，不是用來逼快的閘門 —— P0-2 要的是
  /// **有界**，不是短。太緊的代價是那些影片一律播不出來，太鬆只是多轉一下才
  /// 誠實失敗，所以取值偏寬。命中 audio-only 的常見路徑只要 1–2 秒。
  final Duration streamResolution;

  /// T2：把那個 URL 交給後端開流。
  final Duration mediaOpen;

  /// T3：播放中連續緩衝多久才算「播不動了」。
  final Duration bufferStarvation;

  /// 一次播放請求從頭到尾的總上限。
  ///
  /// 沒有它的話「原始一輪 + fallback 一輪」各拿一份完整預算，最壞是
  /// (T1+T2)×2 —— 放寬 T1 之後那會變成 56 秒，比原本要修的 Android 37.7 秒
  /// 阻塞還糟。fallback 只能用總預算剩下的時間。
  Duration get total => streamResolution + mediaOpen;
}

/// 网络重试配置（播放失败后的渐进式重试）
class NetworkRetryConfig {
  NetworkRetryConfig._();

  /// 最大重试次数
  static const int maxRetries = 5;

  /// 重试延迟（漸進式：1s, 2s, 4s, 8s, 16s）
  static const List<Duration> retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  /// 获取指定重试次数的延迟
  static Duration getRetryDelay(int attempt) {
    if (attempt < 0) return retryDelays.first;
    if (attempt >= retryDelays.length) return retryDelays.last;
    return retryDelays[attempt];
  }
}

/// 电台重连配置（直播流断开后的渐进式重连）
class RadioReconnectConfig {
  RadioReconnectConfig._();

  /// 最大重连次数
  static const int maxAttempts = 3;

  /// 渐进式重连延迟（1s, 3s, 10s）
  static const List<Duration> delays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];
}
