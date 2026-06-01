import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../constants/ui_constants.dart';

/// 缓存文件信息（用于 Isolate 通信和测试）
class NetworkImageCacheFileInfo {
  final String path;
  final int size;
  final DateTime lastModified;

  const NetworkImageCacheFileInfo({
    required this.path,
    required this.size,
    required this.lastModified,
  });
}

/// Isolate 中执行的缓存扫描结果。
class NetworkImageCacheScanResult {
  final int totalSize;
  final List<NetworkImageCacheFileInfo> files;

  const NetworkImageCacheScanResult({
    required this.totalSize,
    required this.files,
  });
}

class NetworkImageCacheFileStore {
  final Directory cacheDir;

  NetworkImageCacheFileStore._(this.cacheDir);

  factory NetworkImageCacheFileStore.forTesting(Directory cacheDir) {
    return NetworkImageCacheFileStore._(cacheDir);
  }

  Future<bool> exists() => cacheDir.exists();

  Future<NetworkImageCacheScanResult> scan() async {
    if (!await cacheDir.exists()) {
      return const NetworkImageCacheScanResult(totalSize: 0, files: []);
    }
    return compute(NetworkImageCacheService._scanCacheDirectory, cacheDir.path);
  }

  Future<int> calculateSize() async {
    if (!await cacheDir.exists()) return 0;
    return compute(
      NetworkImageCacheService._calculateDirectorySize,
      cacheDir.path,
    );
  }

  Future<int> deleteOldestToFit(int maxSizeBytes) async {
    final scanResult = await scan();
    if (scanResult.totalSize <= maxSizeBytes) return scanResult.totalSize;

    final filesToDelete = <String>[];
    var deletedSize = 0;
    final targetDeleteSize = scanResult.totalSize - maxSizeBytes;

    for (final fileInfo in scanResult.files) {
      if (deletedSize >= targetDeleteSize) break;
      filesToDelete.add(fileInfo.path);
      deletedSize += fileInfo.size;
    }

    if (filesToDelete.isNotEmpty) {
      await compute(NetworkImageCacheService._deleteFiles, filesToDelete);
    }
    return scanResult.totalSize - deletedSize;
  }

  Future<void> clear() async {
    if (!await cacheDir.exists()) return;
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
}

enum _TrimTiming {
  none,
  debounced,
  immediate,
}

/// 网络图片缓存服务
///
/// 功能：
/// - 管理网络图片的磁盘缓存
/// - 支持用户配置缓存大小
/// - 提供缓存清理功能
/// - 使用 Isolate 在后台执行文件操作，避免阻塞 UI
///
/// `flutter_cache_manager` 负责常规过期和文件数限制；本服务只额外执行用户
/// 配置的磁盘大小上限检查。手动删除缓存文件后会重建 CacheManager，避免
/// metadata 长期指向已删除文件。
class NetworkImageCacheService {
  NetworkImageCacheService._();

  static CacheManager? _cacheManager;

  /// 缓存 key（也是缓存目录名）
  static const String _cacheKey = 'fmp_network_image_cache';

  /// 默认缓存有效期（天）
  static const int _stalePeriodDays = 7;

  /// 根据缓存大小动态计算最大缓存文件数
  /// 使用保守估算（100KB/image），确保文件数限制与大小限制一致
  static int get _maxNrOfCacheObjects =>
      (_maxCacheSizeMB * 1024 ~/ 100).clamp(100, 3000);

  /// 当前设置的最大缓存大小（MB）
  /// 移动端默认 16MB，桌面端默认 32MB
  static int _maxCacheSizeMB = _defaultMaxCacheSizeMB;

  /// 平台默认缓存大小
  static int get _defaultMaxCacheSizeMB =>
      Platform.isAndroid || Platform.isIOS ? 16 : 32;

  /// 图片加载计数器
  static int _loadCounter = 0;

  /// 每加载多少张图片后检查一次缓存
  static const int _checkInterval = 30;

  /// 是否正在执行清理
  static bool _isTrimming = false;

  /// 防抖定时器
  static Timer? _debounceTimer;

  /// 缓存大小估算值（字节），用于快速判断是否需要清理
  static int _estimatedCacheSizeBytes = -1;

  /// 预防性清理阈值（90%）
  static const double _preemptiveThreshold = 0.9;

  static int get _maxCacheSizeBytes => _maxCacheSizeMB * 1024 * 1024;

  static int get _preemptiveThresholdBytes =>
      (_maxCacheSizeBytes * _preemptiveThreshold).toInt();

  /// 设置最大缓存大小（MB）
  ///
  /// 应该在应用启动时或用户修改设置时调用
  static void setMaxCacheSizeMB(int value) {
    if (_maxCacheSizeMB == value) return;
    _maxCacheSizeMB = value;
    _resetCacheManager();
  }

  /// 获取当前设置的最大缓存大小（MB）
  static int get maxCacheSizeMB => _maxCacheSizeMB;

  /// 获取缓存管理器（单例）
  static CacheManager get cacheManager {
    _cacheManager ??= _FmpImageCacheManager();
    return _cacheManager!;
  }

  /// 获取默认缓存管理器（兼容旧代码）
  static CacheManager get defaultCacheManager => cacheManager;

  /// 通知图片已加载
  ///
  /// [estimatedFileSize] 可选的文件大小估算值（字节），用于快速判断是否需要清理
  /// 每次图片加载完成时调用此方法，会定期触发缓存清理检查
  static void onImageLoaded({int estimatedFileSize = 100000}) {
    final trimTiming = _recordLoadedImage(estimatedFileSize);
    switch (trimTiming) {
      case _TrimTiming.none:
        return;
      case _TrimTiming.debounced:
        _scheduleTrimmingCheck();
      case _TrimTiming.immediate:
        _scheduleTrimmingCheck(immediate: true);
    }
  }

  static _TrimTiming _recordLoadedImage(int estimatedFileSize) {
    _loadCounter++;

    if (_estimatedCacheSizeBytes >= 0) {
      _estimatedCacheSizeBytes += estimatedFileSize;

      if (_estimatedCacheSizeBytes >= _preemptiveThresholdBytes) {
        _loadCounter = 0;
        return _TrimTiming.immediate;
      }
    }

    if (_loadCounter >= _checkInterval) {
      _loadCounter = 0;
      return _TrimTiming.debounced;
    }
    return _TrimTiming.none;
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
      _debounceTimer = Timer(DebounceDurations.long, () {
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
    await _deleteCacheDirectoryFiles();

    _resetCacheManager();
    _estimatedCacheSizeBytes = 0;
  }

  static Future<void> _deleteCacheDirectoryFiles() async {
    try {
      await (await _getFileStore()).clear();
    } catch (_) {
      // 忽略目录访问错误
    }
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

  static Future<NetworkImageCacheFileStore> _getFileStore() async {
    return NetworkImageCacheFileStore._(await _getCacheDirectory());
  }

  /// 获取当前缓存大小（字节）
  /// 使用 compute 在后台执行，避免阻塞 UI
  static Future<int> getCacheSizeBytes() async {
    try {
      return await (await _getFileStore()).calculateSize();
    } catch (_) {
      return 0;
    }
  }

  /// 在 Isolate 中计算目录大小
  static Future<int> _calculateDirectorySize(String dirPath) async {
    int totalSize = 0;
    try {
      final dir = Directory(dirPath);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {
            // 忽略单个文件读取错误
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
  /// 使用 compute 在后台 Isolate 中执行，避免阻塞 UI
  static Future<void> trimCacheIfNeeded(int maxSizeMB) async {
    final store = await _getFileStore();
    if (!await store.exists()) return;

    final maxSizeBytes = _megabytesToBytes(maxSizeMB);
    final beforeSize = (await store.scan()).totalSize;

    if (beforeSize <= maxSizeBytes) return;

    final remainingSize = await store.deleteOldestToFit(maxSizeBytes);
    if (remainingSize < beforeSize) {
      _markTrimmed(remainingSize);
    }
  }

  static int _megabytesToBytes(int megabytes) => megabytes * 1024 * 1024;

  static void _markTrimmed(int estimatedSizeBytes) {
    _resetCacheManager();
    _estimatedCacheSizeBytes = estimatedSizeBytes;
  }

  static void _resetCacheManager() {
    _cacheManager = null;
  }

  /// 在 Isolate 中扫描缓存目录（一次遍历获取所有信息）
  static Future<NetworkImageCacheScanResult> _scanCacheDirectory(
    String dirPath,
  ) async {
    final dir = Directory(dirPath);
    final files = <NetworkImageCacheFileInfo>[];
    int totalSize = 0;

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            final size = stat.size;
            totalSize += size;
            files.add(NetworkImageCacheFileInfo(
              path: entity.path,
              size: size,
              lastModified: stat.modified,
            ));
          } catch (_) {
            // 忽略单个文件错误
          }
        }
      }

      // 按修改时间排序（最旧的在前）
      files.sort((a, b) => a.lastModified.compareTo(b.lastModified));
    } catch (_) {
      // 忽略目录访问错误
    }

    return NetworkImageCacheScanResult(totalSize: totalSize, files: files);
  }

  /// 在 Isolate 中删除文件
  static Future<void> _deleteFiles(List<String> filePaths) async {
    for (final path in filePaths) {
      try {
        await File(path).delete();
      } catch (_) {
        // 忽略单个文件删除失败
      }
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

/// 支援磁碟圖片縮放的快取管理器
///
/// 整合 [ImageCacheManager] 以啟用 maxWidthDiskCache / maxHeightDiskCache 功能，
/// 在存入磁碟前將圖片縮放到顯示尺寸，節省磁碟空間。
class _FmpImageCacheManager extends CacheManager with ImageCacheManager {
  _FmpImageCacheManager()
      : super(
          Config(
            NetworkImageCacheService._cacheKey,
            stalePeriod:
                const Duration(days: NetworkImageCacheService._stalePeriodDays),
            maxNrOfCacheObjects: NetworkImageCacheService._maxNrOfCacheObjects,
            repo: JsonCacheInfoRepository(
                databaseName: NetworkImageCacheService._cacheKey),
            fileService: HttpFileService(),
          ),
        );
}
