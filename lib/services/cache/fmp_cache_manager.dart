import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// FMP 自定义图片缓存管理器
///
/// 特性：
/// - 限制最大缓存数量（默认 500 张）
/// - 设置过期时间（默认 7 天）
/// - 支持动态调整缓存策略
class FmpCacheManager {
  static const String key = 'fmpImageCache';

  // 默认配置
  static const int defaultMaxObjects = 500;
  static const Duration defaultStalePeriod = Duration(days: 7);

  static CacheManager? _instance;
  static int _maxObjects = defaultMaxObjects;
  static Duration _stalePeriod = defaultStalePeriod;

  /// 获取缓存管理器实例
  static CacheManager get instance {
    _instance ??= _createManager();
    return _instance!;
  }

  /// 创建缓存管理器
  static CacheManager _createManager() {
    return CacheManager(
      Config(
        key,
        stalePeriod: _stalePeriod,
        maxNrOfCacheObjects: _maxObjects,
        repo: JsonCacheInfoRepository(databaseName: key),
        fileService: HttpFileService(),
      ),
    );
  }

  /// 更新缓存配置
  ///
  /// 注意：更新配置后需要重启应用才能完全生效
  static Future<void> updateConfig({
    int? maxObjects,
    Duration? stalePeriod,
  }) async {
    if (maxObjects != null) _maxObjects = maxObjects;
    if (stalePeriod != null) _stalePeriod = stalePeriod;

    // 重新创建实例以应用新配置
    await _instance?.emptyCache();
    _instance = _createManager();
  }

  /// 清除所有图片缓存
  static Future<void> clearCache() async {
    await instance.emptyCache();
  }

  /// 获取缓存文件路径
  static Future<String> get cachePath async {
    final fileInfo = await instance.getFileFromCache('');
    if (fileInfo != null) {
      return fileInfo.file.parent.path;
    }
    // 返回默认路径
    return '';
  }

  /// 从缓存中移除指定 URL 的图片
  static Future<void> removeFile(String url) async {
    await instance.removeFile(url);
  }

  /// 预下载图片到缓存
  static Future<void> downloadFile(String url) async {
    await instance.downloadFile(url);
  }
}
