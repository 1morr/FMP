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

  /// 排行榜缓存刷新间隔
  static const Duration rankingCacheRefreshInterval = Duration(hours: 1);

  /// 搜索历史最大条数
  static const int maxSearchHistoryCount = 100;

  /// 队列最大容量
  static const int maxQueueSize = 10000;

  /// 最大播放历史记录数
  static const int maxPlayHistoryCount = 1000;

  // ==================== 播放控制 ====================

  /// 快进/快退时间 (秒)
  static const int seekDurationSeconds = 10;

  /// 播放速度选项
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// 位置保存定时器间隔
  static const Duration positionSaveInterval = Duration(seconds: 10);

  /// 播放锁超时
  static const Duration playLockTimeout = Duration(seconds: 5);

  /// 音频服务状态轮询延迟 (media_kit 内部等待)
  static const Duration audioServicePollingDelay = Duration(milliseconds: 50);

  /// 播放器 seek 前等待延迟 (确保播放器就绪)
  static const Duration seekStabilizationDelay = Duration(milliseconds: 500);

  // ==================== 网络超时 ====================

  /// 网络连接超时
  static const Duration networkConnectTimeout = Duration(seconds: 10);

  /// 网络接收超时
  static const Duration networkReceiveTimeout = Duration(seconds: 30);

  /// 下载连接超时
  static const Duration downloadConnectTimeout = Duration(seconds: 30);

  // ==================== 重试与延迟 ====================

  /// 网络请求重试延迟
  static const Duration networkRetryDelay = Duration(milliseconds: 200);

  /// 队列保存重试延迟
  static const Duration queueSaveRetryDelay = Duration(seconds: 1);

  // ==================== 后台服务 ====================

  /// 自动刷新检查间隔
  static const Duration autoRefreshCheckInterval = Duration(minutes: 30);

  /// 电台刷新间隔
  static const Duration radioRefreshInterval = Duration(minutes: 5);

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
}

/// 网络重试配置
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
