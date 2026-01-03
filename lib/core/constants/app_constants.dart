/// 应用常量定义
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'FMP';

  /// 应用全称
  static const String appFullName = 'Flutter Music Player';

  /// 版本号
  static const String version = '1.0.0';

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

  /// 快进/快退时间 (秒)
  static const int seekDurationSeconds = 10;

  /// 播放速度选项
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
}
