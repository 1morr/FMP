import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import '../data/models/video_detail.dart';
import '../data/sources/bilibili_source.dart';
import '../services/audio/audio_provider.dart';

/// Bilibili 数据源 Provider
final bilibiliSourceProvider = Provider<BilibiliSource>((ref) {
  return BilibiliSource();
});

/// 当前播放歌曲详情状态
class TrackDetailState {
  final VideoDetail? detail;
  final bool isLoading;
  final String? error;

  const TrackDetailState({
    this.detail,
    this.isLoading = false,
    this.error,
  });

  TrackDetailState copyWith({
    VideoDetail? detail,
    bool? isLoading,
    String? error,
    bool clearDetail = false,
    bool clearError = false,
  }) {
    return TrackDetailState(
      detail: clearDetail ? null : (detail ?? this.detail),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 歌曲详情 Notifier
class TrackDetailNotifier extends StateNotifier<TrackDetailState> {
  final BilibiliSource _bilibiliSource;
  String? _currentSourceId;

  TrackDetailNotifier(this._bilibiliSource) : super(const TrackDetailState());

  /// 加载歌曲详情
  Future<void> loadDetail(Track? track) async {
    // 如果没有歌曲或不是 Bilibili 源，清空详情
    if (track == null || track.sourceType != SourceType.bilibili) {
      if (state.detail != null) {
        state = const TrackDetailState();
      }
      _currentSourceId = null;
      return;
    }

    // 如果是同一首歌曲，不重复加载
    if (_currentSourceId == track.sourceId && state.detail != null) {
      return;
    }

    _currentSourceId = track.sourceId;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      VideoDetail? detail;

      // 已下载歌曲优先从本地 metadata 加载
      if (track.firstDownloadPath != null) {
        detail = await _loadFromLocalMetadata(track);
      }

      // 如果本地没有或加载失败，从网络获取
      if (detail == null) {
        detail = await _bilibiliSource.getVideoDetail(track.sourceId);
      }

      // 确保加载的还是当前歌曲
      if (_currentSourceId == track.sourceId) {
        state = TrackDetailState(detail: detail);
      }
    } catch (e) {
      if (_currentSourceId == track.sourceId) {
        state = state.copyWith(
          isLoading: false,
          error: e.toString(),
        );
      }
    }
  }

  /// 从本地 metadata.json 加载详情
  Future<VideoDetail?> _loadFromLocalMetadata(Track track) async {
    try {
      final downloadPath = track.firstDownloadPath;
      if (downloadPath == null) return null;

      final dir = Directory(downloadPath).parent;
      final metadataFile = File('${dir.path}/metadata.json');
      if (!await metadataFile.exists()) return null;

      final json = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;

      // 检查是否有完整的元数据
      if (json['viewCount'] == null) return null;

      return VideoDetail.fromMetadata(json, track);
    } catch (e) {
      return null;
    }
  }

  /// 刷新当前歌曲详情
  Future<void> refresh() async {
    if (state.detail == null) return;
    
    final bvid = state.detail!.bvid;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final detail = await _bilibiliSource.getVideoDetail(bvid);
      state = TrackDetailState(detail: detail);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 清空详情
  void clear() {
    _currentSourceId = null;
    state = const TrackDetailState();
  }
}

/// 歌曲详情 Provider
final trackDetailProvider =
    StateNotifierProvider<TrackDetailNotifier, TrackDetailState>((ref) {
  final bilibiliSource = ref.watch(bilibiliSourceProvider);
  final notifier = TrackDetailNotifier(bilibiliSource);

  // 监听当前播放的歌曲变化
  ref.listen<Track?>(currentTrackProvider, (previous, next) {
    if (previous?.sourceId != next?.sourceId) {
      notifier.loadDetail(next);
    }
  });

  // 初始化时加载当前歌曲详情
  final currentTrack = ref.read(currentTrackProvider);
  if (currentTrack != null) {
    notifier.loadDetail(currentTrack);
  }

  return notifier;
});
