import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/settings_repository.dart';
import 'fmp_cache_manager.dart';

/// 缓存服务
///
/// 管理应用的各类缓存：
/// - 图片缓存（CachedNetworkImage）
/// - 临时文件缓存
class CacheService with Logging {
  final SettingsRepository _settingsRepository;

  CacheService({required SettingsRepository settingsRepository})
      : _settingsRepository = settingsRepository;

  /// 初始化缓存服务
  Future<void> initialize() async {
    final settings = await _settingsRepository.get();
    await _applyCacheSettings(settings);
    logInfo('CacheService initialized');
  }

  /// 应用缓存设置
  Future<void> _applyCacheSettings(Settings settings) async {
    // 根据缓存上限计算最大图片数量
    // 假设每张图片平均 200KB，计算大致数量
    final maxSizeMB = settings.maxCacheSizeMB;
    int maxObjects;

    if (maxSizeMB <= 0) {
      // 无限制
      maxObjects = 10000;
    } else {
      // 假设每张图片 200KB
      maxObjects = (maxSizeMB * 1024 / 200).round().clamp(100, 10000);
    }

    await FmpCacheManager.updateConfig(maxObjects: maxObjects);
    logDebug('Cache config updated: maxObjects=$maxObjects');
  }

  /// 获取图片缓存大小（字节）
  Future<int> getImageCacheSize() async {
    int totalSize = 0;
    try {
      final cacheDirs = await _getImageCacheDirectories();
      for (final dir in cacheDirs) {
        totalSize += await _calculateDirectorySize(dir);
      }
    } catch (e) {
      logError('Failed to get image cache size', e);
    }
    return totalSize;
  }

  /// 获取临时缓存大小（字节）
  Future<int> getTempCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      return await _calculateDirectorySize(tempDir);
    } catch (e) {
      logError('Failed to get temp cache size', e);
      return 0;
    }
  }

  /// 获取总缓存大小（字节）
  Future<int> getTotalCacheSize() async {
    final imageSize = await getImageCacheSize();
    // 临时目录可能包含其他应用的缓存，不计入
    return imageSize;
  }

  /// 获取格式化的缓存大小字符串
  Future<String> getFormattedCacheSize() async {
    final bytes = await getTotalCacheSize();
    return _formatBytes(bytes);
  }

  /// 清除图片缓存
  Future<void> clearImageCache() async {
    try {
      await FmpCacheManager.clearCache();
      logInfo('Image cache cleared');
    } catch (e) {
      logError('Failed to clear image cache', e);
      rethrow;
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    try {
      // 清除图片缓存
      await clearImageCache();

      // 清除临时目录中的 FMP 相关文件
      await _clearFmpTempFiles();

      logInfo('All cache cleared');
    } catch (e) {
      logError('Failed to clear all cache', e);
      rethrow;
    }
  }

  /// 更新缓存上限设置
  Future<void> updateMaxCacheSize(int maxSizeMB) async {
    final settings = await _settingsRepository.get();
    settings.maxCacheSizeMB = maxSizeMB;
    await _settingsRepository.save(settings);
    await _applyCacheSettings(settings);
    logInfo('Cache limit updated to $maxSizeMB MB');
  }

  /// 获取当前缓存上限（MB）
  Future<int> getMaxCacheSize() async {
    final settings = await _settingsRepository.get();
    return settings.maxCacheSizeMB;
  }

  /// 获取所有图片缓存目录
  Future<List<Directory>> _getImageCacheDirectories() async {
    final directories = <Directory>[];
    try {
      final tempDir = await getTemporaryDirectory();
      
      // 旧缓存目录 (libCachedImageData)
      final oldCacheDir = Directory('${tempDir.path}/libCachedImageData');
      if (await oldCacheDir.exists()) {
        directories.add(oldCacheDir);
      }

      // 新缓存目录 (fmpImageCache)
      final newCacheDir = Directory('${tempDir.path}/${FmpCacheManager.key}');
      if (await newCacheDir.exists()) {
        directories.add(newCacheDir);
      }
    } catch (e) {
      logError('Failed to get image cache directories', e);
    }
    return directories;
  }

  /// 清除 FMP 临时文件
  Future<void> _clearFmpTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final entities = await tempDir.list().toList();

      for (final entity in entities) {
        if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          // 清除 libCachedImageData 和 fmpImageCache 目录
          if (name == 'libCachedImageData' || name == FmpCacheManager.key) {
            await entity.delete(recursive: true);
            logDebug('Deleted cache directory: $name');
          }
        }
      }
    } catch (e) {
      logError('Failed to clear FMP temp files', e);
    }
  }

  /// 计算目录大小
  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      // 忽略权限错误
    }
    return size;
  }

  /// 格式化字节数
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    final imageSize = await getImageCacheSize();
    final maxSize = await getMaxCacheSize();

    int imageCount = 0;
    try {
      final cacheDirs = await _getImageCacheDirectories();
      for (final dir in cacheDirs) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            imageCount++;
          }
        }
      }
    } catch (e) {
      // 忽略
    }

    return CacheStats(
      imageCacheBytes: imageSize,
      imageCacheCount: imageCount,
      maxCacheMB: maxSize,
    );
  }
}

/// 缓存统计信息
class CacheStats {
  final int imageCacheBytes;
  final int imageCacheCount;
  final int maxCacheMB;

  const CacheStats({
    required this.imageCacheBytes,
    required this.imageCacheCount,
    required this.maxCacheMB,
  });

  /// 格式化的图片缓存大小
  String get formattedImageCacheSize {
    final bytes = imageCacheBytes;
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 格式化的缓存上限
  String get formattedMaxCache {
    if (maxCacheMB <= 0) {
      return '无限制';
    } else if (maxCacheMB >= 1024) {
      return '${(maxCacheMB / 1024).toStringAsFixed(1)} GB';
    } else {
      return '$maxCacheMB MB';
    }
  }

  /// 缓存使用百分比
  double get usagePercent {
    if (maxCacheMB <= 0) return 0;
    final maxBytes = maxCacheMB * 1024 * 1024;
    return (imageCacheBytes / maxBytes * 100).clamp(0, 100);
  }
}
