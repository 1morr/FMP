/// 应用常量定义
class AppConstants {
  AppConstants._();

  // ==================== 应用信息 ====================

  /// 应用名称
  static const String appName = 'FMP';

  /// 应用全称
  static const String appFullName = 'Flutter Music Player';

  /// 版本号
  static const String version = '1.0.0';

  // ==================== 缓存与存储 ====================

  /// 默认缓存大小上限 (MB)
  static const int defaultMaxCacheSizeMB = 2048;

  /// 音频 URL 默认过期时间 (小时)
  static const int audioUrlExpiryHours = 2;

  /// 默认刷新间隔 (小时)
  static const int defaultRefreshIntervalHours = 24;

  /// 搜索历史最大条数
  static const int maxSearchHistoryCount = 50;

  /// 队列最大容量
  static const int maxQueueSize = 10000;

  // ==================== 播放控制 ====================

  /// 快进/快退时间 (秒)
  static const int seekDurationSeconds = 10;

  /// 临时播放恢复位置偏移（秒）
  static const int temporaryPlayRestoreOffsetSeconds = 10;

  /// 播放速度选项
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// 位置保存定时器间隔
  static const Duration positionSaveInterval = Duration(seconds: 10);

  // ==================== 下载相关 ====================

  /// 最大并发下载数
  static const int maxConcurrentDownloads = 3;

  /// 下载调度器间隔
  static const Duration downloadSchedulerInterval = Duration(milliseconds: 500);

  /// 下载进度更新节流间隔
  static const Duration downloadProgressThrottleInterval = Duration(milliseconds: 500);

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

  /// Toast 默认显示时长
  static const Duration toastDuration = Duration(seconds: 3);

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

  /// 播放锁等待延迟
  static const Duration playLockWaitDelay = Duration(milliseconds: 100);

  /// 播放位置恢复延迟
  static const Duration playPositionRestoreDelay = Duration(milliseconds: 300);

  /// 页面导航延迟
  static const Duration pageNavigationDelay = Duration(milliseconds: 100);

  // ==================== UI 尺寸 ====================

  /// 小圆角
  static const double borderRadiusSmall = 4.0;

  /// 中圆角
  static const double borderRadiusMedium = 8.0;

  /// 大圆角
  static const double borderRadiusLarge = 12.0;

  /// 超大圆角
  static const double borderRadiusXL = 16.0;

  /// 小缩略图尺寸
  static const double thumbnailSizeSmall = 40.0;

  /// 中缩略图尺寸
  static const double thumbnailSizeMedium = 48.0;

  /// 大缩略图尺寸
  static const double thumbnailSizeLarge = 56.0;

  // ==================== 透明度 ====================

  /// 禁用状态透明度
  static const double disabledOpacity = 0.5;

  /// 次要内容透明度
  static const double secondaryOpacity = 0.7;

  /// 占位符背景透明度
  static const double placeholderOpacity = 0.1;
}
