import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文件存在检查缓存（简化版）
///
/// 主要用于 UI 层的图片加载优化，避免重复检查
/// 
/// 简化设计：
/// - 只缓存存在的文件路径（`Set<String>`）
/// - 移除 Track 相关方法，使用 TrackExtensions 代替
/// - 保留核心缓存功能
/// - 添加大小限制防止内存泄漏（最多 5000 条）
class FileExistsCache extends StateNotifier<Set<String>> {
  FileExistsCache() : super({});

  /// 最大缓存条目数
  static const int _maxCacheSize = 5000;

  /// 检查路径是否存在（带缓存）
  ///
  /// 如果路径已缓存，返回 true
  /// 如果路径未缓存，安排异步检查并返回 false
  bool exists(String path) {
    if (state.contains(path)) return true;

    // 异步检查并缓存
    _checkAndCache(path);
    return false;
  }

  /// 批量检查路径，返回第一个存在的路径
  ///
  /// 如果有未缓存的路径，会安排异步刷新
  String? getFirstExisting(List<String> paths) {
    // 检查已缓存的路径
    for (final path in paths) {
      if (state.contains(path)) return path;
    }

    // 如果有未缓存的路径，安排刷新
    _scheduleRefreshPaths(paths);
    return null;
  }

  /// 批量预加载路径
  ///
  /// 检查哪些路径实际存在，并加入缓存
  /// 自动应用大小限制
  Future<void> preloadPaths(List<String> paths) async {
    final existing = <String>{};
    for (final path in paths) {
      try {
        if (await File(path).exists()) {
          existing.add(path);
        }
      } catch (_) {}
    }
    if (existing.isNotEmpty) {
      final newState = {...state, ...existing};
      
      // 如果超过最大大小，移除最早添加的条目
      if (newState.length > _maxCacheSize) {
        final toRemove = newState.length - _maxCacheSize;
        final list = newState.toList();
        for (var i = 0; i < toRemove; i++) {
          newState.remove(list[i]);
        }
      }
      
      state = newState;
    }
  }

  /// 标记路径为已存在
  ///
  /// 下载完成后调用，避免重新检测
  void markAsExisting(String path) {
    final newState = Set<String>.from(state);
    newState.add(path);
    
    // 如果超过最大大小，移除最早添加的条目
    if (newState.length > _maxCacheSize) {
      final toRemove = newState.length - _maxCacheSize;
      final iterator = newState.iterator;
      for (var i = 0; i < toRemove && iterator.moveNext(); i++) {
        newState.remove(iterator.current);
      }
    }
    
    state = newState;
  }

  /// 移除路径缓存
  void remove(String path) {
    final newState = Set<String>.from(state);
    newState.remove(path);
    state = newState;
  }

  /// 清除所有缓存
  void clearAll() {
    state = {};
  }

  // ============== 内部方法 ==============

  /// 异步检查并缓存单个路径
  void _checkAndCache(String path) {
    Future.microtask(() async {
      try {
        if (await File(path).exists()) {
          final newState = Set<String>.from(state);
          newState.add(path);
          
          // 如果超过最大大小，移除最早添加的条目
          if (newState.length > _maxCacheSize) {
            final toRemove = newState.length - _maxCacheSize;
            final iterator = newState.iterator;
            for (var i = 0; i < toRemove && iterator.moveNext(); i++) {
              newState.remove(iterator.current);
            }
          }
          
          state = newState;
        }
      } catch (_) {}
    });
  }

  /// 安排异步刷新多个路径
  /// 自动应用大小限制
  void _scheduleRefreshPaths(List<String> paths) {
    Future.microtask(() async {
      final existing = <String>{};
      for (final path in paths) {
        if (!state.contains(path)) {
          try {
            if (await File(path).exists()) {
              existing.add(path);
            }
          } catch (_) {}
        }
      }
      if (existing.isNotEmpty) {
        final newState = {...state, ...existing};
        
        // 如果超过最大大小，移除最早添加的条目
        if (newState.length > _maxCacheSize) {
          final toRemove = newState.length - _maxCacheSize;
          final list = newState.toList();
          for (var i = 0; i < toRemove; i++) {
            newState.remove(list[i]);
          }
        }
        
        state = newState;
      }
    });
  }
}

/// 文件存在检查缓存 Provider
final fileExistsCacheProvider =
    StateNotifierProvider<FileExistsCache, Set<String>>((ref) {
  return FileExistsCache();
});
