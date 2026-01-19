import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../services/saf/saf_service.dart';
import '../../services/saf/file_exists_service.dart';
import '../saf_providers.dart';

/// 文件存在检查缓存
///
/// 缓存文件是否存在的检测结果，避免在 UI 渲染时频繁进行同步 IO 操作
/// 支持普通文件路径和 Android SAF content:// URI
class FileExistsCache extends StateNotifier<Map<String, bool>> {
  final FileExistsService _fileExistsService;
  
  FileExistsCache(this._fileExistsService) : super({});

  // ============== 通用方法（新增）==============

  /// 检查指定路径的文件是否存在（使用缓存）
  ///
  /// 如果路径未缓存，返回 false 并安排异步刷新。
  bool exists(String path) {
    if (state.containsKey(path)) {
      return state[path]!;
    }

    // 未缓存时，安排异步刷新并返回 false
    _scheduleRefresh(path);
    return false;
  }

  /// 批量检查路径，返回第一个存在的路径
  ///
  /// 如果有未缓存的路径，会安排异步刷新
  String? getFirstExisting(List<String> paths) {
    bool hasUncached = false;
    for (final path in paths) {
      if (state.containsKey(path)) {
        if (state[path]!) return path;
      } else {
        hasUncached = true;
      }
    }

    // 如果有未缓存的路径，安排刷新
    if (hasUncached) {
      _scheduleRefreshPaths(paths);
    }
    return null;
  }

  // ============== Track 相关方法（保留，向后兼容）==============

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

    return exists(path);
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

  /// 获取第一个存在的下载路径（仅从缓存读取）
  ///
  /// 用于播放时查找有效的本地文件
  /// 如果有未缓存的路径，会安排异步刷新
  String? getFirstExistingPath(Track track) {
    return getFirstExisting(track.downloadPaths);
  }
  
  /// 同步获取第一个存在的下载路径（阻塞式，用于非 build 上下文）
  ///
  /// 此方法会直接执行文件检测，仅在非 build 上下文中使用
  /// 注意：对于 content:// URI，此方法只检查缓存，不会同步检测
  String? getFirstExistingPathSync(Track track) {
    for (final path in track.downloadPaths) {
      bool? fileExists;
      if (state.containsKey(path)) {
        fileExists = state[path]!;
      } else if (!SafService.isContentUri(path)) {
        // 只有普通文件路径可以同步检测
        fileExists = File(path).existsSync();
        // 注意：不在这里更新 state，因为可能在 build 中被间接调用
      }
      // content:// URI 如果未缓存，返回 null
      if (fileExists == true) return path;
    }
    return null;
  }

  // ============== 缓存管理方法 ==============

  /// 安排异步刷新单个路径（避免在 build 期间修改 state）
  void _scheduleRefresh(String path) {
    Future.microtask(() async {
      if (!state.containsKey(path)) {
        final fileExists = await _fileExistsService.exists(path);
        state = {...state, path: fileExists};
      }
    });
  }

  /// 安排异步刷新多个路径
  void _scheduleRefreshPaths(List<String> paths) {
    Future.microtask(() async {
      final updates = <String, bool>{};
      for (final path in paths) {
        if (!state.containsKey(path)) {
          updates[path] = await _fileExistsService.exists(path);
        }
      }
      if (updates.isNotEmpty) {
        state = {...state, ...updates};
      }
    });
  }

  /// 批量刷新缓存（异步）
  ///
  /// 在进入页面时调用，预先加载所有歌曲的下载状态
  Future<void> refreshCache(List<Track> tracks) async {
    final newState = <String, bool>{};

    for (final track in tracks) {
      for (final path in track.downloadPaths) {
        newState[path] = await _fileExistsService.exists(path);
      }
    }

    state = {...state, ...newState};
  }

  /// 批量预加载指定路径的缓存（异步）
  ///
  /// 用于预加载一组图片路径的存在状态
  Future<void> preloadPaths(List<String> paths) async {
    final updates = <String, bool>{};
    for (final path in paths) {
      if (!state.containsKey(path)) {
        updates[path] = await _fileExistsService.exists(path);
      }
    }
    if (updates.isNotEmpty) {
      state = {...state, ...updates};
    }
  }

  /// 刷新单个歌曲在指定歌单中的缓存
  Future<bool> refreshSingle(Track track, int playlistId) async {
    final path = track.getDownloadPath(playlistId);
    if (path == null) return false;

    final fileExists = await _fileExistsService.exists(path);
    state = {...state, path: fileExists};
    return fileExists;
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

  /// 标记路径为已存在
  ///
  /// 下载完成后调用，避免重新检测
  void markAsDownloaded(String path) {
    state = {...state, path: true};
  }

  /// 标记路径为不存在
  ///
  /// 删除文件后调用
  void markAsNotDownloaded(String path) {
    state = {...state, path: false};
  }
}

/// 文件存在检查缓存 Provider
final fileExistsCacheProvider =
    StateNotifierProvider<FileExistsCache, Map<String, bool>>((ref) {
  final fileExistsService = ref.watch(fileExistsServiceProvider);
  return FileExistsCache(fileExistsService);
});

// 向后兼容的别名（标记为 @Deprecated，在迁移完成后可删除）
@Deprecated('Use fileExistsCacheProvider instead')
final downloadStatusCacheProvider = fileExistsCacheProvider;

@Deprecated('Use FileExistsCache instead')
typedef DownloadStatusCache = FileExistsCache;
