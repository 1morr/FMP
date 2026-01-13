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
  /// 返回 true 如果文件存在，false 如果不存在或路径为空
  bool isDownloadedInPlaylist(Track track, int playlistId) {
    final path = track.getDownloadedPath(playlistId);
    if (path == null) return false;

    // 使用缓存
    if (state.containsKey(path)) {
      return state[path]!;
    }

    // 同步检查并缓存（首次访问时）
    final exists = File(path).existsSync();
    state = {...state, path: exists};
    return exists;
  }

  /// 检查歌曲是否有任何已下载的文件
  ///
  /// 遍历所有下载路径，检查是否有任何一个文件存在
  bool hasAnyDownload(Track track) {
    for (final path in track.downloadedPaths) {
      if (state.containsKey(path)) {
        if (state[path]!) return true;
      } else {
        final exists = File(path).existsSync();
        state = {...state, path: exists};
        if (exists) return true;
      }
    }
    return false;
  }

  /// 获取第一个存在的下载路径
  ///
  /// 用于播放时查找有效的本地文件
  String? getFirstExistingPath(Track track) {
    for (final path in track.downloadedPaths) {
      bool exists;
      if (state.containsKey(path)) {
        exists = state[path]!;
      } else {
        exists = File(path).existsSync();
        state = {...state, path: exists};
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
      for (final path in track.downloadedPaths) {
        newState[path] = await File(path).exists();
      }
    }

    state = {...state, ...newState};
  }

  /// 刷新单个歌曲在指定歌单中的缓存
  Future<bool> refreshSingle(Track track, int playlistId) async {
    final path = track.getDownloadedPath(playlistId);
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
    for (final path in track.downloadedPaths) {
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
