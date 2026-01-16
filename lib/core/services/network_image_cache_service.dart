import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 网络图片缓存服务
///
/// 功能：
/// - 管理网络图片的磁盘缓存
/// - 支持用户配置缓存大小
/// - 提供缓存清理功能
/// - 定期检查并清理超出限制的缓存
class NetworkImageCacheService {
  NetworkImageCacheService._();

  static CacheManager? _cacheManager;

  /// 缓存 key（也是缓存目录名）
  static const String _cacheKey = 'fmp_network_image_cache';

  /// 默认缓存有效期（天）
  static const int _stalePeriodDays = 7;

  /// 默认最大缓存文件数
  static const int _maxNrOfCacheObjects = 1000;

  /// 当前设置的最大缓存大小（MB）
  static int _maxCacheSizeMB = 128;

  /// 图片加载计数器
  static int _loadCounter = 0;

  /// 每加载多少张图片后检查一次缓存
  static const int _checkInterval = 5;

  /// 是否正在执行清理
  static bool _isTrimming = false;

  /// 防抖定时器
  static Timer? _debounceTimer;

  /// 缓存大小估算值（字节），用于快速判断是否需要清理
  static int _estimatedCacheSizeBytes = -1;

  /// 预防性清理阈值（90%）
  static const double _preemptiveThreshold = 0.9;

  /// 设置最大缓存大小（MB）
  ///
  /// 应该在应用启动时或用户修改设置时调用
  static void setMaxCacheSizeMB(int value) {
    _maxCacheSizeMB = value;
  }

  /// 获取当前设置的最大缓存大小（MB）
  static int get maxCacheSizeMB => _maxCacheSizeMB;

  /// 获取缓存管理器（单例）
  static CacheManager get cacheManager {
    _cacheManager ??= CacheManager(
      Config(
        _cacheKey,
        stalePeriod: const Duration(days: _stalePeriodDays),
        maxNrOfCacheObjects: _maxNrOfCacheObjects,
        repo: JsonCacheInfoRepository(databaseName: _cacheKey),
        fileService: HttpFileService(),
      ),
    );
    return _cacheManager!;
  }

  /// 获取默认缓存管理器（兼容旧代码）
  static CacheManager get defaultCacheManager => cacheManager;

  /// 通知图片已加载
  ///
  /// [estimatedFileSize] 可选的文件大小估算值（字节），用于快速判断是否需要清理
  /// 每次图片加载完成时调用此方法，会定期触发缓存清理检查
  static void onImageLoaded({int estimatedFileSize = 50000}) {
    _loadCounter++;

    // 更新缓存大小估算值
    if (_estimatedCacheSizeBytes >= 0) {
      _estimatedCacheSizeBytes += estimatedFileSize;

      // 检查是否接近限制，需要预防性清理
      final maxSizeBytes = _maxCacheSizeMB * 1024 * 1024;
      final threshold = (maxSizeBytes * _preemptiveThreshold).toInt();

      if (_estimatedCacheSizeBytes >= threshold) {
        // 接近限制，立即触发清理
        _loadCounter = 0;
        _scheduleTrimmingCheck(immediate: true);
        return;
      }
    }

    // 每加载 _checkInterval 张图片后检查一次
    if (_loadCounter >= _checkInterval) {
      _loadCounter = 0;
      _scheduleTrimmingCheck();
    }
  }

  /// 调度缓存清理检查（带防抖）
  static void _scheduleTrimmingCheck({bool immediate = false}) {
    // 取消之前的定时器
    _debounceTimer?.cancel();

    if (immediate) {
      // 立即执行（用于预防性清理）
      _performTrimmingCheck();
    } else {
      // 使用防抖，避免短时间内多次触发
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _performTrimmingCheck();
      });
    }
  }

  /// 执行缓存清理检查
  static Future<void> _performTrimmingCheck() async {
    if (_isTrimming) return;

    _isTrimming = true;
    try {
      await trimCacheIfNeeded(_maxCacheSizeMB);
      // 更新估算值为实际值
      _estimatedCacheSizeBytes = await getCacheSizeBytes();
    } finally {
      _isTrimming = false;
    }
  }

  /// 初始化缓存大小估算值
  ///
  /// 应该在应用启动时调用，以便后续能够进行预防性清理
  static Future<void> initializeCacheSizeEstimate() async {
    _estimatedCacheSizeBytes = await getCacheSizeBytes();
  }

  /// 清空所有缓存
  static Future<void> clearCache() async {
    // 先尝试使用 CacheManager 的 emptyCache
    await cacheManager.emptyCache();

    // 然后手动删除缓存目录中的所有文件（确保彻底清除）
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        // 删除目录中的所有文件
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {
              // 忽略单个文件删除失败
            }
          }
        }
      }
    } catch (_) {
      // 忽略目录访问错误
    }

    // 重置缓存管理器，让它重新初始化
    _cacheManager = null;

    // 重置估算值
    _estimatedCacheSizeBytes = 0;
  }

  /// 删除指定 URL 的缓存
  static Future<void> removeFile(String url) async {
    await cacheManager.removeFile(url);
  }

  /// 获取缓存目录
  static Future<Directory> _getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return Directory(p.join(tempDir.path, _cacheKey));
  }

  /// 获取当前缓存大小（字节）
  static Future<int> getCacheSizeBytes() async {
    int totalSize = 0;
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            try {
              totalSize += await entity.length();
            } catch (_) {
              // 忽略单个文件读取错误
            }
          }
        }
      }
    } catch (_) {
      // 忽略目录访问错误
    }
    return totalSize;
  }

  /// 获取当前缓存大小（MB）
  static Future<double> getCacheSizeMB() async {
    final bytes = await getCacheSizeBytes();
    return bytes / (1024 * 1024);
  }

  /// 检查并清理超出大小限制的缓存
  ///
  /// 当缓存超过 [maxSizeMB] 时，删除最旧的文件直到缓存小于限制
  static Future<void> trimCacheIfNeeded(int maxSizeMB) async {
    final maxSizeBytes = maxSizeMB * 1024 * 1024;
    final currentSize = await getCacheSizeBytes();

    if (currentSize <= maxSizeBytes) {
      return; // 缓存未超限
    }

    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return;

      // 获取所有缓存文件，按修改时间排序（最旧的在前）
      final files = <File>[];
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          files.add(entity);
        }
      }

      // 按修改时间排序（最旧的在前）
      files.sort((a, b) {
        try {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      // 删除最旧的文件，直到缓存小于限制
      int deletedSize = 0;
      final targetDeleteSize = currentSize - maxSizeBytes;

      for (final file in files) {
        if (deletedSize >= targetDeleteSize) break;

        try {
          final fileSize = await file.length();
          await file.delete();
          deletedSize += fileSize;
        } catch (_) {
          // 忽略单个文件删除失败
        }
      }
    } catch (_) {
      // 忽略错误
    }
  }

  /// 获取缓存统计信息
  static Future<Map<String, dynamic>> getCacheStats() async {
    final sizeMB = await getCacheSizeMB();
    return {
      'sizeMB': sizeMB.toStringAsFixed(2),
      'maxSizeMB': _maxCacheSizeMB,
      'stalePeriodDays': _stalePeriodDays,
      'maxNrOfCacheObjects': _maxNrOfCacheObjects,
    };
  }
}
