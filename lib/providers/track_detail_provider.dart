import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/auth_headers_utils.dart';
import '../data/models/track.dart';
import '../data/models/video_detail.dart';
import '../data/sources/bilibili_source.dart';
import '../data/sources/netease_source.dart';
import '../data/sources/source_provider.dart';
import '../data/sources/youtube_source.dart';
import '../services/audio/audio_provider.dart';

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
  final YouTubeSource _youtubeSource;
  final NeteaseSource _neteaseSource;
  final Ref _ref;
  Track? _currentTrack;

  TrackDetailNotifier(
      this._bilibiliSource, this._youtubeSource, this._neteaseSource, this._ref)
      : super(const TrackDetailState());

  /// 加载歌曲详情
  Future<void> loadDetail(Track? track) async {
    // 如果没有歌曲，清空详情
    if (track == null) {
      if (state.detail != null) {
        state = const TrackDetailState();
      }
      _currentTrack = null;
      return;
    }

    final trackKey = track.uniqueKey;

    // 如果是同一首歌曲，不重复加载
    if (_currentTrack?.uniqueKey == trackKey && state.detail != null) {
      return;
    }

    _currentTrack = track;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      VideoDetail? detail;

      // 优先从网络获取最新数据
      try {
        if (track.sourceType == SourceType.bilibili) {
          final authHeaders =
              await getAuthHeadersForPlatform(SourceType.bilibili, _ref);
          detail = await _bilibiliSource.getVideoDetail(track.sourceId,
              authHeaders: authHeaders);
        } else if (track.sourceType == SourceType.youtube) {
          final authHeaders =
              await getAuthHeadersForPlatform(SourceType.youtube, _ref);
          detail = await _youtubeSource.getVideoDetail(track.sourceId,
              authHeaders: authHeaders);
        } else if (track.sourceType == SourceType.netease) {
          final authHeaders =
              await getAuthHeadersForPlatform(SourceType.netease, _ref);
          detail = await _neteaseSource.getVideoDetail(track.sourceId,
              authHeaders: authHeaders);
        }
      } catch (_) {
        // 网络获取失败，已下载歌曲回退到本地 metadata（Bilibili/YouTube）
        if (track.hasAnyDownload && track.sourceType != SourceType.netease) {
          detail = await _loadFromLocalMetadata(track);
        }
        // 本地也没有则重新抛出原始异常
        if (detail == null) rethrow;
      }

      // 确保加载的还是当前歌曲
      if (_currentTrack?.uniqueKey == trackKey) {
        state = TrackDetailState(detail: detail);
      }
    } catch (e) {
      if (_currentTrack?.uniqueKey == trackKey) {
        state = state.copyWith(
          isLoading: false,
          error: e.toString(),
        );
      }
    }
  }

  /// 从本地 metadata.json 加载详情（遍历所有下载路径查找）
  Future<VideoDetail?> _loadFromLocalMetadata(Track track) async {
    if (!track.hasAnyDownload) return null;

    // 遍历所有下载路径，查找第一个存在 metadata.json 的路径
    for (final downloadPath in track.allDownloadPaths) {
      try {
        final dir = Directory(downloadPath).parent;
        final metadataFile = File(p.join(dir.path, 'metadata.json'));
        if (!await metadataFile.exists()) continue;

        final json = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;

        // 检查是否有完整的元数据
        if (json['viewCount'] == null) continue;

        return VideoDetail.fromMetadata(json, track);
      } catch (e) {
        // 继续尝试下一个路径
        continue;
      }
    }

    return null;
  }

  /// 刷新当前歌曲详情
  Future<void> refresh() async {
    final track = _currentTrack;
    if (state.detail == null || track == null) return;

    final trackKey = track.uniqueKey;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      VideoDetail detail;
      if (track.sourceType == SourceType.bilibili) {
        final authHeaders =
            await getAuthHeadersForPlatform(SourceType.bilibili, _ref);
        detail = await _bilibiliSource.getVideoDetail(track.sourceId,
            authHeaders: authHeaders);
      } else if (track.sourceType == SourceType.netease) {
        final authHeaders =
            await getAuthHeadersForPlatform(SourceType.netease, _ref);
        detail = await _neteaseSource.getVideoDetail(track.sourceId,
            authHeaders: authHeaders);
      } else {
        final authHeaders =
            await getAuthHeadersForPlatform(SourceType.youtube, _ref);
        detail = await _youtubeSource.getVideoDetail(track.sourceId,
            authHeaders: authHeaders);
      }
      if (_currentTrack?.uniqueKey == trackKey) {
        state = TrackDetailState(detail: detail);
      }
    } catch (e) {
      if (_currentTrack?.uniqueKey == trackKey) {
        state = state.copyWith(
          isLoading: false,
          error: e.toString(),
        );
      }
    }
  }

  /// 清空详情
  void clear() {
    _currentTrack = null;
    state = const TrackDetailState();
  }
}

/// 歌曲详情 Provider
final trackDetailProvider =
    StateNotifierProvider<TrackDetailNotifier, TrackDetailState>((ref) {
  final bilibiliSource = ref.watch(bilibiliSourceProvider);
  final youtubeSource = ref.watch(youtubeSourceProvider);
  final neteaseSource = ref.watch(neteaseAudioSourceProvider);
  final notifier =
      TrackDetailNotifier(bilibiliSource, youtubeSource, neteaseSource, ref);

  // 监听当前播放的歌曲变化
  ref.listen<Track?>(currentTrackProvider, (previous, next) {
    if (previous?.uniqueKey != next?.uniqueKey) {
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
