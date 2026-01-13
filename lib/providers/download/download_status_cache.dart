import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';

/// 下载状态缓存
///
/// 缓存文件是否存在的检测结果，避免在 UI 渲染时频繁进行同步 IO 操作
class DownloadStatusCache extends StateNotifier<Map<String, bool>> {
  DownloadStatusCache() : super({});

  /// 检查指定歌单中的歌曲是否已下载（使用缓存）
  ///
  /// [track] 要检查的歌曲
  /// [playlistId] 歌单ID
  /// 返回 true 如果缓存显示文件存在，false 如果不存在、路径为空或未缓存
  /// 
  /// 注意：此方法只读取缓存，不会修改 state。
  /// 如果路径未缓存，返回 false 并安排异步刷新。
  bool isDownloadedForPlaylist(Track track, int playlistId) {
    final path = track.getDownloadPath(playlistId);
    if (path == null) return false;

    // 只读取缓存
    if (state.containsKey(path)) {
      return state[path]!;
    }

    // 未缓存时，安排异步刷新并返回 false
    _scheduleRefresh(path);
    return false;
  }
  
  /// 安排异步刷新单个路径（避免在 build 期间修改 state）
  void _scheduleRefresh(String path) {
    Future.microtask(() async {
      if (!state.containsKey(path)) {
        final exists = await File(path).exists();
        state = {...state, path: exists};
      }
    });
  }

  /// 检查歌曲是否有任何已下载的文件
  ///
  /// 遍历所有下载路径，检查缓存中是否有任何一个文件存在
  /// 未缓存的路径会被安排异步刷新
  bool hasAnyDownload(Track track) {
    bool hasUncached = false;
    for (final path in track.downloadPaths) {
      if (state.containsKey(path)) {
        if (state[path]!) return true;
      } else {
        hasUncached = true;
      }
    }
    
    // 如果有未缓存的路径，安排刷新
    if (hasUncached) {
      _scheduleRefreshPaths(track.downloadPaths);
    }
    return false;
  }
  
  /// 安排异步刷新多个路径
  void _scheduleRefreshPaths(List<String> paths) {
    Future.microtask(() async {
      final updates = <String, bool>{};
      for (final path in paths) {
        if (!state.containsKey(path)) {
          updates[path] = await File(path).exists();
        }
      }
      if (updates.isNotEmpty) {
        state = {...state, ...updates};
      }
    });
  }

  /// 获取第一个存在的下载路径（仅从缓存读取）
  ///
  /// 用于播放时查找有效的本地文件
  /// 如果有未缓存的路径，会安排异步刷新
  String? getFirstExistingPath(Track track) {
    bool hasUncached = false;
    for (final path in track.downloadPaths) {
      if (state.containsKey(path)) {
        if (state[path]!) return path;
      } else {
        hasUncached = true;
      }
    }
    
    // 如果有未缓存的路径，安排刷新
    if (hasUncached) {
      _scheduleRefreshPaths(track.downloadPaths);
    }
    return null;
  }
  
  /// 同步获取第一个存在的下载路径（阻塞式，用于非 build 上下文）
  ///
  /// 此方法会直接执行文件检测，仅在非 build 上下文中使用
  String? getFirstExistingPathSync(Track track) {
    for (final path in track.downloadPaths) {
      bool exists;
      if (state.containsKey(path)) {
        exists = state[path]!;
      } else {
        exists = File(path).existsSync();
        // 注意：不在这里更新 state，因为可能在 build 中被间接调用
      }
      if (exists) return path;
    }
    return null;
  }

  /// 批量刷新缓存（异步）
  ///
  /// 在进入页面时调用，预先加载所有歌曲的下载状态
  Future<void> refreshCache(List<Track> tracks) async {
    final newState = <String, bool>{};

    for (final track in tracks) {
      for (final path in track.downloadPaths) {
        newState[path] = await File(path).exists();
      }
    }

    state = {...state, ...newState};
  }

  /// 刷新单个歌曲在指定歌单中的缓存
  Future<bool> refreshSingle(Track track, int playlistId) async {
    final path = track.getDownloadPath(playlistId);
    if (path == null) return false;

    final exists = await File(path).exists();
    state = {...state, path: exists};
    return exists;
  }

  /// 使特定路径的缓存失效
  void invalidate(String? path) {
    if (path == null) return;
    final newState = Map<String, bool>.from(state);
    newState.remove(path);
    state = newState;
  }

  /// 使歌曲所有路径的缓存失效
  void invalidateTrack(Track track) {
    final newState = Map<String, bool>.from(state);
    for (final path in track.downloadPaths) {
      newState.remove(path);
    }
    state = newState;
  }

  /// 清除所有缓存
  void clearAll() {
    state = {};
  }

  /// 标记路径为已下载
  ///
  /// 下载完成后调用，避免重新检测
  void markAsDownloaded(String path) {
    state = {...state, path: true};
  }

  /// 标记路径为未下载
  ///
  /// 删除文件后调用
  void markAsNotDownloaded(String path) {
    state = {...state, path: false};
  }
}

/// 下载状态缓存 Provider
final downloadStatusCacheProvider =
    StateNotifierProvider<DownloadStatusCache, Map<String, bool>>((ref) {
  return DownloadStatusCache();
});
