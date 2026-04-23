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
  FileExistsCache({required void Function(int epoch) onEpochChanged})
      : _onEpochChanged = onEpochChanged,
        super({});

  final void Function(int epoch) _onEpochChanged;
  final Set<String> _pendingRefreshPaths = <String>{};
  int _cacheEpoch = 0;

  int get pendingRefreshCount => _pendingRefreshPaths.length;
  int get cacheEpoch => _cacheEpoch;

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
  Future<void> preloadPaths(List<String> paths, {int batchSize = 64}) async {
    final uncached = paths.toSet().difference(state).toList();
    if (uncached.isEmpty) return;

    final existing = <String>{};
    for (var i = 0; i < uncached.length; i += batchSize) {
      final batch = uncached.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((path) async {
          try {
            return (path: path, exists: await File(path).exists());
          } catch (_) {
            return (path: path, exists: false);
          }
        }),
      );

      for (final result in results) {
        if (result.exists) {
          existing.add(result.path);
        }
      }
    }

    if (existing.isNotEmpty) {
      _updateState({...state, ...existing});
    }
  }

  /// 标记路径为已存在
  ///
  /// 下载完成后调用，避免重新检测
  void markAsExisting(String path) {
    if (state.contains(path)) return;
    _updateState({...state, path});
  }

  /// 移除路径缓存
  void remove(String path) {
    if (!state.contains(path)) return;
    final newState = Set<String>.from(state)..remove(path);
    _updateState(newState);
  }

  /// 清除所有缓存
  void clearAll() {
    if (state.isEmpty) return;
    _updateState(<String>{});
  }

  // ============== 内部方法 ==============

  Set<String> _trimToMaxSize(Set<String> paths) {
    if (paths.length <= _maxCacheSize) {
      return paths;
    }

    final trimmed = Set<String>.from(paths);
    final toRemove = trimmed.length - _maxCacheSize;
    final keysToRemove = trimmed.take(toRemove).toList();
    trimmed.removeAll(keysToRemove);
    return trimmed;
  }

  void _updateState(Set<String> newState) {
    _cacheEpoch++;
    _onEpochChanged(_cacheEpoch);
    state = _trimToMaxSize(newState);
  }

  /// 异步检查并缓存单个路径
  void _checkAndCache(String path) {
    Future.microtask(() async {
      try {
        if (await File(path).exists()) {
          _updateState({...state, path});
        }
      } catch (_) {}
    });
  }

  /// 安排异步刷新多个路径
  /// 自动应用大小限制
  void _scheduleRefreshPaths(List<String> paths) {
    final uncached = paths.where((path) => !state.contains(path)).toSet();
    if (uncached.isEmpty) return;

    final pending = uncached.difference(_pendingRefreshPaths);
    if (pending.isEmpty) return;

    _pendingRefreshPaths.addAll(pending);

    Future.microtask(() async {
      final existing = <String>{};
      try {
        for (final path in pending) {
          try {
            if (await File(path).exists()) {
              existing.add(path);
            }
          } catch (_) {}
        }
        if (existing.isNotEmpty) {
          _updateState({...state, ...existing});
        }
      } finally {
        _pendingRefreshPaths.removeAll(pending);
      }
    });
  }
}

/// 文件存在检查缓存 Provider
final fileExistsCacheEpochProvider = StateProvider<int>((ref) => 0);

final fileExistsCacheProvider =
    StateNotifierProvider<FileExistsCache, Set<String>>((ref) {
  return FileExistsCache(
    onEpochChanged: (epoch) {
      ref.read(fileExistsCacheEpochProvider.notifier).state = epoch;
    },
  );
});

final filePathExistsProvider = Provider.family<bool, String>((ref, path) {
  return ref.watch(fileExistsCacheProvider.select((paths) => paths.contains(path)));
});
