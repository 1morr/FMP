/// 应用常量定义
class AppConstants {
  AppConstants._();

  // ==================== 应用信息 ====================

  /// 应用名称
  static const String appName = 'FMP';

  /// 应用全称
  static const String appFullName = 'Flutter Music Player';

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

  // ==================== 播放控制 ====================

  /// 快进/快退时间 (秒)
  static const int seekDurationSeconds = 10;

  /// 播放速度选项
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// 位置保存定时器间隔
  static const Duration positionSaveInterval = Duration(seconds: 10);

  // ==================== 下载相关 ====================

  /// 下载调度器周期检查间隔（作为事件驱动的备份机制）
  static const Duration downloadSchedulerInterval = Duration(seconds: 5);

  /// 下载进度更新节流间隔（避免 Windows PostMessage 队列溢出）
  static const Duration downloadProgressThrottleInterval = Duration(milliseconds: 1000);

  // ==================== 网络超时 ====================

  /// 网络连接超时
  static const Duration networkConnectTimeout = Duration(seconds: 10);

  /// 网络接收超时
  static const Duration networkReceiveTimeout = Duration(seconds: 30);

  /// 下载连接超时
  static const Duration downloadConnectTimeout = Duration(seconds: 30);

  // ==================== UI 动画 ====================

  /// 默认淡入动画时长
  static const Duration defaultFadeInDuration = Duration(milliseconds: 150);

  /// 导航动画时长
  static const Duration navigationAnimationDuration = Duration(milliseconds: 200);

  /// 进度指示器动画时长
  static const Duration progressIndicatorDuration = Duration(milliseconds: 200);

  /// 评论自动滚动间隔
  static const Duration commentScrollInterval = Duration(seconds: 10);

  // ==================== Toast 与通知 ====================

  /// Toast 默认显示时长（成功、信息）
  static const Duration toastDuration = Duration(milliseconds: 1500);

  /// Toast 错误/警告显示时长
  static const Duration toastErrorDuration = Duration(milliseconds: 3000);

  /// 刷新进度 Toast 时长
  static const Duration refreshToastDuration = Duration(seconds: 4);

  /// 操作反馈延迟
  static const Duration operationFeedbackDelay = Duration(milliseconds: 100);

  // ==================== 播放指示器 ====================

  /// 播放动画时长
  static const Duration playingIndicatorDuration = Duration(milliseconds: 1600);

  // ==================== 重试与延迟 ====================

  /// 网络请求重试延迟
  static const Duration networkRetryDelay = Duration(milliseconds: 200);

  /// 刷新完成提示延迟
  static const Duration refreshCompleteDelay = Duration(seconds: 3);

  /// 刷新错误提示延迟
  static const Duration refreshErrorDelay = Duration(seconds: 5);

  /// 队列保存重试延迟
  static const Duration queueSaveRetryDelay = Duration(seconds: 1);

  // ==================== UI 尺寸 ====================

  /// 小缩略图尺寸
  static const double thumbnailSizeSmall = 40.0;

  /// 中缩略图尺寸
  static const double thumbnailSizeMedium = 48.0;

  /// 大缩略图尺寸
  static const double thumbnailSizeLarge = 56.0;
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
