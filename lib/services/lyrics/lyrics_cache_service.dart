import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../core/logger.dart';
import 'lyrics_result.dart';

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
      await _evictIfNeeded(reserveOne: false);
    }
  }

  Directory? _cacheDir;
  final Map<String, DateTime> _accessTimes = {};

  /// 防抖：延迟写入 _metadata.json，避免快速切歌时频繁 I/O
  Timer? _saveDebounceTimer;
  bool _accessTimesDirty = false;
  static const Duration _saveDebounceDuration = Duration(seconds: 2);

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
  Future<LyricsResult?> get(String trackUniqueKey) async {
    if (_cacheDir == null) await initialize();

    final file = _getCacheFile(trackUniqueKey);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 更新访问时间（防抖写入）
      _accessTimes[trackUniqueKey] = DateTime.now();
      _scheduleSaveAccessTimes();

      logDebug('Cache hit: $trackUniqueKey');
      return LyricsResult.fromJson(json);
    } catch (e) {
      logError('Failed to read cache for $trackUniqueKey: $e');
      await file.delete();
      return null;
    }
  }

  /// 保存歌词到缓存
  Future<void> put(String trackUniqueKey, LyricsResult result) async {
    if (_cacheDir == null) await initialize();

    try {
      final file = _getCacheFile(trackUniqueKey);
      final isUpdate = await file.exists();

      // 只有写入新文件时才需要检查缓存限制（覆盖更新不增加文件数）
      if (!isUpdate) {
        await _evictIfNeeded(reserveOne: true);
      }
      await file.writeAsString(jsonEncode(result.toJson()));

      // 更新访问时间（防抖写入）
      _accessTimes[trackUniqueKey] = DateTime.now();
      _scheduleSaveAccessTimes();

      logDebug('Cached lyrics: $trackUniqueKey (${await file.length()} bytes)');
    } catch (e) {
      logError('Failed to cache lyrics for $trackUniqueKey: $e');
    }
  }

  /// 删除指定 key 的缓存
  Future<void> remove(String trackUniqueKey) async {
    if (_cacheDir == null) await initialize();

    try {
      final file = _getCacheFile(trackUniqueKey);
      if (await file.exists()) {
        await file.delete();
      }
      _accessTimes.remove(trackUniqueKey);
      _scheduleSaveAccessTimes();
      logDebug('Removed cache: $trackUniqueKey');
    } catch (e) {
      logError('Failed to remove cache for $trackUniqueKey: $e');
    }
  }

  /// 清空所有缓存
  Future<void> clear() async {
    if (_cacheDir == null) await initialize();

    try {
      _saveDebounceTimer?.cancel();
      _accessTimesDirty = false;

      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      _accessTimes.clear();
      await _saveAccessTimesNow();
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
          .where((entity) => entity is File &&
              entity.path.endsWith('.json') &&
              !entity.path.endsWith('_metadata.json'))
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
  ///
  /// [reserveOne] 为 true 时（put 调用），需要为即将写入的新文件预留 1 个位置，
  /// 使用 >= 判断；为 false 时（setMaxCacheFiles 调用），只需清理到不超过限制，
  /// 使用 > 判断。
  Future<void> _evictIfNeeded({required bool reserveOne}) async {
    // 循环清理直到文件数和大小都低于限制
    while (true) {
      final files = await _cacheDir!
          .list()
          .where((entity) => entity is File &&
              entity.path.endsWith('.json') &&
              !entity.path.endsWith('_metadata.json'))
          .cast<File>()
          .toList();

      // 检查文件数量
      final overFileLimit = reserveOne
          ? files.length >= maxCacheFiles
          : files.length > maxCacheFiles;
      if (overFileLimit) {
        if (!await _evictOldest(1)) break; // 无法再清理，退出防止死循环
        continue;
      }

      // 检查总大小
      int totalSize = 0;
      for (final file in files) {
        totalSize += await file.length();
      }

      if (totalSize >= maxCacheSizeBytes) {
        if (!await _evictOldest(1)) break; // 无法再清理，退出防止死循环
        continue;
      }

      break; // 都在限制内，退出
    }
  }

  /// 删除最旧的 N 个缓存文件（LRU）
  ///
  /// 返回 true 表示成功删除了至少一个文件，false 表示无法删除（accessTimes 为空）
  Future<bool> _evictOldest(int count) async {
    // 按访问时间排序（最旧的在前）
    final sortedKeys = _accessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sortedKeys.isEmpty) return false;

    final evictCount = count.clamp(1, sortedKeys.length);
    for (int i = 0; i < evictCount; i++) {
      final key = sortedKeys[i].key;
      final file = _getCacheFile(key);

      if (await file.exists()) {
        await file.delete();
        logDebug('Evicted cache: $key');
      }
      _accessTimes.remove(key);
    }

    await _saveAccessTimesNow();
    return true;
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

      // 清理磁盘上已不存在的幽灵条目
      final keysToRemove = <String>[];
      for (final key in _accessTimes.keys) {
        if (!await _getCacheFile(key).exists()) {
          keysToRemove.add(key);
        }
      }
      if (keysToRemove.isNotEmpty) {
        for (final key in keysToRemove) {
          _accessTimes.remove(key);
        }
        await _saveAccessTimesNow();
        logDebug('Cleaned ${keysToRemove.length} ghost entries from access times');
      }

      logDebug('Loaded ${_accessTimes.length} cache access times');
    } catch (e) {
      logError('Failed to load access times: $e');
    }
  }

  /// 调度防抖保存访问时间（快速切歌时合并多次写入）
  void _scheduleSaveAccessTimes() {
    _accessTimesDirty = true;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(_saveDebounceDuration, () async {
      if (_accessTimesDirty) {
        await _saveAccessTimesNow();
      }
    });
  }

  /// 立即保存访问时间元数据（用于 evict、clear 等需要即时持久化的场景）
  Future<void> _saveAccessTimesNow() async {
    _saveDebounceTimer?.cancel();
    _accessTimesDirty = false;

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
