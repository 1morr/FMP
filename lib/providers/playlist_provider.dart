import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../data/models/playlist.dart';
import '../data/models/track.dart';
import '../services/library/playlist_service.dart';
import 'database_provider.dart';
import 'download/file_exists_cache.dart';
import 'repository_providers.dart';

/// PlaylistService Provider
final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  final trackRepo = ref.watch(trackRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return PlaylistService(
    playlistRepository: playlistRepo,
    trackRepository: trackRepo,
    settingsRepository: settingsRepo,
    isar: db,
  );
});

/// 歌单列表状态
class PlaylistListState extends Equatable {
  final List<Playlist> playlists;
  final bool isLoading;
  final String? error;

  const PlaylistListState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  PlaylistListState copyWith({
    List<Playlist>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return PlaylistListState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  List<Object?> get props => [playlists, isLoading, error];
}

/// 歌单列表控制器
class PlaylistListNotifier extends StateNotifier<PlaylistListState> {
  final PlaylistService _service;
  final Ref _ref;

  PlaylistListNotifier(this._service, this._ref) : super(const PlaylistListState()) {
    loadPlaylists();
  }

  /// 加载所有歌单
  Future<void> loadPlaylists() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final playlists = await _service.getAllPlaylists();
      state = state.copyWith(playlists: playlists, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 创建歌单
  Future<Playlist?> createPlaylist({
    required String name,
    String? description,
    String? coverUrl,
  }) async {
    try {
      final playlist = await _service.createPlaylist(
        name: name,
        description: description,
        coverUrl: coverUrl,
      );
      await loadPlaylists();
      return playlist;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// 更新歌单
  Future<bool> updatePlaylist({
    required int playlistId,
    String? name,
    String? description,
    String? coverUrl,
  }) async {
    try {
      await _service.updatePlaylist(
        playlistId: playlistId,
        name: name,
        description: description,
        coverUrl: coverUrl,
      );
      await loadPlaylists();
      // 刷新歌单详情页和封面
      invalidatePlaylistProviders(playlistId);
      // 清除文件存在缓存，强制重新检测
      _ref.read(fileExistsCacheProvider.notifier).clearAll();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 删除歌单
  Future<bool> deletePlaylist(int playlistId) async {
    try {
      await _service.deletePlaylist(playlistId);
      await loadPlaylists();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 复制歌单
  Future<Playlist?> duplicatePlaylist(int playlistId, String newName) async {
    try {
      final playlist = await _service.duplicatePlaylist(playlistId, newName);
      await loadPlaylists();
      return playlist;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 刷新指定歌单的相关 Provider
  /// 
  /// 统一封装 invalidate 逻辑，避免重复代码
  void invalidatePlaylistProviders(int playlistId) {
    _ref.invalidate(playlistDetailProvider(playlistId));
    _ref.invalidate(playlistCoverProvider(playlistId));
  }
}

/// 歌单列表 Provider
final playlistListProvider =
    StateNotifierProvider<PlaylistListNotifier, PlaylistListState>((ref) {
  final service = ref.watch(playlistServiceProvider);
  return PlaylistListNotifier(service, ref);
});

/// 歌单详情状态
class PlaylistDetailState extends Equatable {
  final Playlist? playlist;
  final List<Track> tracks;
  final bool isLoading;
  final String? error;

  const PlaylistDetailState({
    this.playlist,
    this.tracks = const [],
    this.isLoading = false,
    this.error,
  });

  PlaylistDetailState copyWith({
    Playlist? playlist,
    List<Track>? tracks,
    bool? isLoading,
    String? error,
  }) {
    return PlaylistDetailState(
      playlist: playlist ?? this.playlist,
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  Duration get totalDuration {
    int totalMs = 0;
    for (final track in tracks) {
      totalMs += track.durationMs ?? 0;
    }
    return Duration(milliseconds: totalMs);
  }

  @override
  List<Object?> get props => [playlist, tracks, isLoading, error];
}

/// 歌单详情控制器
class PlaylistDetailNotifier extends StateNotifier<PlaylistDetailState> {
  final PlaylistService _service;
  final int playlistId;

  PlaylistDetailNotifier(this._service, this.playlistId)
      : super(const PlaylistDetailState()) {
    loadPlaylist();
  }

  /// 加载歌单详情
  Future<void> loadPlaylist() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.getPlaylistWithTracks(playlistId);
      if (result != null) {
        state = state.copyWith(
          playlist: result.playlist,
          tracks: result.tracks,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: '歌单不存在',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 添加歌曲到歌单
  Future<bool> addTrack(Track track) async {
    try {
      await _service.addTrackToPlaylist(playlistId, track);
      await loadPlaylist();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 移除歌曲
  Future<bool> removeTrack(int trackId) async {
    try {
      await _service.removeTrackFromPlaylist(playlistId, trackId);
      await loadPlaylist();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 重新排序
  Future<bool> reorderTracks(int oldIndex, int newIndex) async {
    try {
      // 乐观更新 UI
      final tracks = List<Track>.from(state.tracks);
      final track = tracks.removeAt(oldIndex);
      final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
      tracks.insert(insertIndex, track);
      state = state.copyWith(tracks: tracks);

      await _service.reorderPlaylistTracks(playlistId, oldIndex, newIndex);
      return true;
    } catch (e) {
      // 回滚
      await loadPlaylist();
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

/// 歌单详情 Provider Family
final playlistDetailProvider = StateNotifierProvider.family<
    PlaylistDetailNotifier, PlaylistDetailState, int>((ref, playlistId) {
  final service = ref.watch(playlistServiceProvider);
  return PlaylistDetailNotifier(service, playlistId);
});

/// 歌单封面 Provider
/// 返回 PlaylistCoverData，包含本地路径和网络 URL
final playlistCoverProvider =
    FutureProvider.family<PlaylistCoverData, int>((ref, playlistId) async {
  final service = ref.watch(playlistServiceProvider);
  return service.getPlaylistCoverData(playlistId);
});

/// 所有歌单列表 Provider (简化版)
final allPlaylistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final service = ref.watch(playlistServiceProvider);
  return service.getAllPlaylists();
});

/// 添加歌曲到歌单的快捷方法
final addTrackToPlaylistProvider =
    FutureProvider.family<bool, ({int playlistId, Track track})>((ref, params) async {
  final service = ref.watch(playlistServiceProvider);
  await service.addTrackToPlaylist(params.playlistId, params.track);
  // 刷新相关的 provider
  ref.invalidate(allPlaylistsProvider);
  ref.invalidate(playlistDetailProvider(params.playlistId));
  return true;
});
