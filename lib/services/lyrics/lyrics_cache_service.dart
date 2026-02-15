import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../core/logger.dart';
import 'lrclib_source.dart';

/// 歌词缓存服务
///
/// 使用 LRU (Least Recently Used) 策略管理缓存：
/// - 最多缓存 50 个歌词文件
/// - 总大小限制 5MB
/// - 缓存目录：{cacheDir}/lyrics/
class LyricsCacheService with Logging {
  static const int defaultMaxCacheFiles = 50;
  static const int maxCacheSizeBytes = 5 * 1024 * 1024; // 5MB

  int _maxCacheFiles = defaultMaxCacheFiles;
  int get maxCacheFiles => _maxCacheFiles;

  /// 更新最大缓存文件数
  Future<void> setMaxCacheFiles(int value) async {
    _maxCacheFiles = value;
    // 如果当前缓存超出新限制，执行清理
    if (_cacheDir != null) {
      await _evictIfNeeded();
    }
  }

  Directory? _cacheDir;
  final Map<String, DateTime> _accessTimes = {};

  /// 初始化缓存目录
  Future<void> initialize() async {
    final appCacheDir = await getApplicationCacheDirectory();
    _cacheDir = Directory(path.join(appCacheDir.path, 'lyrics'));

    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
      logInfo('Created lyrics cache directory: ${_cacheDir!.path}');
    }

    // 加载现有缓存的访问时间
    await _loadAccessTimes();
  }

  /// 获取缓存的歌词（如果存在）
  Future<LrclibResult?> get(String trackUniqueKey) async {
    if (_cacheDir == null) await initialize();

    final file = _getCacheFile(trackUniqueKey);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 更新访问时间
      _accessTimes[trackUniqueKey] = DateTime.now();
      await _saveAccessTimes();

      logDebug('Cache hit: $trackUniqueKey');
      return LrclibResult.fromJson(json);
    } catch (e) {
      logError('Failed to read cache for $trackUniqueKey: $e');
      await file.delete();
      return null;
    }
  }

  /// 保存歌词到缓存
  Future<void> put(String trackUniqueKey, LrclibResult result) async {
    if (_cacheDir == null) await initialize();

    try {
      // 检查是否需要清理缓存
      await _evictIfNeeded();

      final file = _getCacheFile(trackUniqueKey);
      final json = {
        'id': result.id,
        'trackName': result.trackName,
        'artistName': result.artistName,
        'albumName': result.albumName,
        'duration': result.duration,
        'instrumental': result.instrumental,
        'plainLyrics': result.plainLyrics,
        'syncedLyrics': result.syncedLyrics,
      };

      await file.writeAsString(jsonEncode(json));

      // 更新访问时间
      _accessTimes[trackUniqueKey] = DateTime.now();
      await _saveAccessTimes();

      logDebug('Cached lyrics: $trackUniqueKey (${await file.length()} bytes)');
    } catch (e) {
      logError('Failed to cache lyrics for $trackUniqueKey: $e');
    }
  }

  /// 清空所有缓存
  Future<void> clear() async {
    if (_cacheDir == null) await initialize();

    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      _accessTimes.clear();
      await _saveAccessTimes();
      logInfo('Cleared all lyrics cache');
    } catch (e) {
      logError('Failed to clear cache: $e');
    }
  }

  /// 获取缓存统计信息
  Future<CacheStats> getStats() async {
    if (_cacheDir == null) await initialize();

    try {
      final files = await _cacheDir!
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();

      int totalSize = 0;
      for (final file in files) {
        totalSize += await file.length();
      }

      return CacheStats(
        fileCount: files.length,
        totalSizeBytes: totalSize,
        maxFiles: maxCacheFiles,
        maxSizeBytes: maxCacheSizeBytes,
      );
    } catch (e) {
      logError('Failed to get cache stats: $e');
      return CacheStats(
        fileCount: 0,
        totalSizeBytes: 0,
        maxFiles: maxCacheFiles,
        maxSizeBytes: maxCacheSizeBytes,
      );
    }
  }

  /// 检查是否需要清理缓存，并执行 LRU 清理
  Future<void> _evictIfNeeded() async {
    final files = await _cacheDir!
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    // 检查文件数量
    if (files.length >= maxCacheFiles) {
      await _evictOldest(files);
      return;
    }

    // 检查总大小
    int totalSize = 0;
    for (final file in files) {
      totalSize += await file.length();
    }

    if (totalSize >= maxCacheSizeBytes) {
      await _evictOldest(files);
    }
  }

  /// 删除最旧的缓存文件（LRU）
  Future<void> _evictOldest(List<File> files) async {
    // 按访问时间排序（最旧的在前）
    final sortedKeys = _accessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sortedKeys.isEmpty) return;

    // 删除最旧的 10% 文件
    final evictCount = (maxCacheFiles * 0.1).ceil();
    for (int i = 0; i < evictCount && i < sortedKeys.length; i++) {
      final key = sortedKeys[i].key;
      final file = _getCacheFile(key);

      if (await file.exists()) {
        await file.delete();
        _accessTimes.remove(key);
        logDebug('Evicted cache: $key');
      }
    }

    await _saveAccessTimes();
  }

  /// 获取缓存文件路径
  File _getCacheFile(String trackUniqueKey) {
    // 使用 base64 编码避免文件名非法字符
    final safeKey = base64Url.encode(utf8.encode(trackUniqueKey));
    return File(path.join(_cacheDir!.path, '$safeKey.json'));
  }

  /// 加载访问时间元数据
  Future<void> _loadAccessTimes() async {
    final metaFile = File(path.join(_cacheDir!.path, '_metadata.json'));
    if (!await metaFile.exists()) return;

    try {
      final content = await metaFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      _accessTimes.clear();
      json.forEach((key, value) {
        _accessTimes[key] = DateTime.parse(value as String);
      });

      logDebug('Loaded ${_accessTimes.length} cache access times');
    } catch (e) {
      logError('Failed to load access times: $e');
    }
  }

  /// 保存访问时间元数据
  Future<void> _saveAccessTimes() async {
    final metaFile = File(path.join(_cacheDir!.path, '_metadata.json'));

    try {
      final json = <String, String>{};
      _accessTimes.forEach((key, value) {
        json[key] = value.toIso8601String();
      });

      await metaFile.writeAsString(jsonEncode(json));
    } catch (e) {
      logError('Failed to save access times: $e');
    }
  }
}

/// 缓存统计信息
class CacheStats {
  final int fileCount;
  final int totalSizeBytes;
  final int maxFiles;
  final int maxSizeBytes;

  const CacheStats({
    required this.fileCount,
    required this.totalSizeBytes,
    required this.maxFiles,
    required this.maxSizeBytes,
  });

  /// 缓存使用率（文件数）
  double get fileUsagePercent => (fileCount / maxFiles * 100).clamp(0, 100);

  /// 缓存使用率（大小）
  double get sizeUsagePercent =>
      (totalSizeBytes / maxSizeBytes * 100).clamp(0, 100);

  /// 格式化大小显示
  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedMaxSize {
    return '${(maxSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
