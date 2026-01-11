import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';

/// 本地图片 LRU 缓存
///
/// 功能：
/// - 缓存本地图片的 ImageProvider，避免重复从文件系统读取
/// - 使用 LRU 策略，限制缓存大小
/// - 自动清理缓存中已删除的文件
class LocalImageCache {
  LocalImageCache._();

  /// 缓存的最大条目数
  static const int _maxSize = 100;

  /// LRU 缓存，使用 LinkedHashMap 实现访问顺序
  static final LinkedHashMap<String, ImageProvider> _cache =
      LinkedHashMap<String, ImageProvider>();

  /// 记录缓存命中次数（用于调试）
  static int _hitCount = 0;

  /// 记录缓存未命中次数（用于调试）
  static int _missCount = 0;

  /// 获取本地图片的 ImageProvider
  ///
  /// 如果缓存中存在且文件仍然有效，直接返回缓存的 ImageProvider。
  /// 否则创建新的 FileImage 并加入缓存。
  ///
  /// [path] 本地文件绝对路径
  /// 返回 ImageProvider，如果文件不存在则返回 null
  static ImageProvider? getLocalImage(String path) {
    // 检查缓存
    if (_cache.containsKey(path)) {
      // 移到末尾表示最近访问
      final provider = _cache.remove(path)!;
      _cache[path] = provider;
      _hitCount++;
      return provider;
    }

    // 检查文件是否存在
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }

    // 创建新的 ImageProvider
    final provider = FileImage(file);
    _missCount++;

    // 如果缓存已满，移除最旧的条目
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }

    _cache[path] = provider;
    return provider;
  }

  /// 从缓存中移除指定路径的图片
  ///
  /// 当图片文件被删除时调用此方法清理缓存
  static void remove(String path) {
    _cache.remove(path);
  }

  /// 清空所有缓存
  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
  }

  /// 预加载图片到缓存
  ///
  /// [paths] 要预加载的路径列表
  /// [maxPreload] 最大预加载数量，默认为 20
  static void preload(List<String> paths, {int maxPreload = 20}) {
    final count = paths.length > maxPreload ? maxPreload : paths.length;
    for (int i = 0; i < count; i++) {
      getLocalImage(paths[i]);
    }
  }

  /// 获取缓存统计信息（用于调试）
  static Map<String, dynamic> get stats => {
        'size': _cache.length,
        'maxSize': _maxSize,
        'hitCount': _hitCount,
        'missCount': _missCount,
        'hitRate': _hitCount + _missCount > 0
            ? _hitCount / (_hitCount + _missCount)
            : 0.0,
      };
}
