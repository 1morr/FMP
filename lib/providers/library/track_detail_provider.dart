import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/constants/download_filenames.dart';
import 'package:fmp/core/errors/user_message.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/providers/account/source_auth_context_provider.dart';

/// 当前播放歌曲详情状态
class TrackDetailState {
  final VideoDetail? detail;
  final bool isLoading;
  final String? error;

  const TrackDetailState({this.detail, this.isLoading = false, this.error});

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
///
/// 詳情是**影片層**的資料（`getVideoDetail` 只吃 sourceId，離線 metadata 也優先
/// 讀 `parentTitle`），所以去重看 [Track.groupKey]，不看含 cid 的 `uniqueKey`：
/// 播放途中串流解析會把 cid 從 null 補上，用 `uniqueKey` 的話同一首歌會被當成
/// 換歌，清掉已顯示的詳情再打一次同樣的請求（面板二次閃爍）。換分 P 也一樣不重載。
class TrackDetailNotifier extends Notifier<TrackDetailState> {
  late SourceManager _sourceManager;
  late SourcePlaybackAuthContext _sourceAuthContext;
  Track? _currentTrack;

  @override
  TrackDetailState build() {
    _sourceManager = ref.watch(sourceManagerProvider);
    _sourceAuthContext = ref.watch(sourceAuthContextProvider);

    // 监听当前播放的歌曲变化
    ref.listen<Track?>(currentTrackProvider, (previous, next) {
      if (previous?.groupKey != next?.groupKey) {
        loadDetail(next);
      }
    });

    // 初始化时加载当前歌曲详情
    final currentTrack = ref.read(currentTrackProvider);
    if (currentTrack != null) {
      // `loadDetail` 會同步寫 state，不能在 build() 裡直接呼叫。
      Future.microtask(() => loadDetail(currentTrack));
    }

    return const TrackDetailState();
  }

  /// 加载歌曲详情
  Future<void> loadDetail(Track? track) async {
    // 如果没有歌曲，清空详情
    if (track == null) {
      state = const TrackDetailState();
      _currentTrack = null;
      return;
    }

    final trackKey = track.groupKey;

    // 同一支影片：已經有詳情或正在載入，都不再打一次
    if (_currentTrack?.groupKey == trackKey &&
        (state.detail != null || state.isLoading)) {
      _currentTrack = track;
      return;
    }

    _currentTrack = track;
    state = state.copyWith(
      isLoading: true,
      clearDetail: true,
      clearError: true,
    );

    try {
      VideoDetail? detail;
      final source = _requireTrackDetailSource(track);

      // 优先从网络获取最新数据
      try {
        detail = await _loadNetworkDetail(track, source);
      } catch (_) {
        // 網路取不到時，已下載的歌曲退回下載時存的本地 metadata
        if (track.hasAnyDownload) {
          detail = await _loadFromLocalMetadata(track);
        }
        // 本地也没有则重新抛出原始异常
        if (detail == null) rethrow;
      }

      // 确保加载的还是当前歌曲
      if (_currentTrack?.groupKey == trackKey) {
        state = TrackDetailState(detail: detail);
      }
    } catch (e, stack) {
      if (_currentTrack?.groupKey == trackKey) {
        state = state.copyWith(
          isLoading: false,
          error: failureMessage(
            e,
            stack,
            'Loading the track detail failed',
            tag: 'TrackDetail',
          ),
        );
      }
    }
  }

  /// 從本地 metadata 載入詳情（遍歷所有下載路徑查找）。多頁下載的 metadata
  /// 是 `metadata_P{N}.json`，配對規則與寫入端共用 `DownloadFileNames`。
  Future<VideoDetail?> _loadFromLocalMetadata(Track track) async {
    if (!track.hasAnyDownload) return null;

    for (final downloadPath in track.allDownloadPaths) {
      try {
        final dir = Directory(downloadPath).parent;
        File? metadataFile;
        for (final candidate in DownloadFileNames.metadataCandidatesForAudio(
          downloadPath,
        )) {
          final file = File(p.join(dir.path, candidate));
          if (await file.exists()) {
            metadataFile = file;
            break;
          }
        }
        if (metadataFile == null) continue;

        final json =
            jsonDecode(await metadataFile.readAsString())
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

  TrackDetailSource _requireTrackDetailSource(Track track) {
    final source = _sourceManager.trackDetailSource(track.sourceType);
    if (source == null) {
      throw StateError(
        'Track detail source not registered: ${track.sourceType}',
      );
    }

    return source;
  }

  Future<VideoDetail> _loadNetworkDetail(
    Track track,
    TrackDetailSource source,
  ) async {
    final authHeaders = await _sourceAuthContext.authForPlay(track.sourceType);
    return source.getVideoDetail(track.sourceId, authHeaders: authHeaders);
  }

  /// 刷新当前歌曲详情
  Future<void> refresh() async {
    final track = _currentTrack;
    if (track == null) return;

    final trackKey = track.groupKey;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final source = _requireTrackDetailSource(track);
      final detail = await _loadNetworkDetail(track, source);
      if (_currentTrack?.groupKey == trackKey) {
        state = TrackDetailState(detail: detail);
      }
    } catch (e, stack) {
      if (_currentTrack?.groupKey == trackKey) {
        state = state.copyWith(
          isLoading: false,
          error: failureMessage(
            e,
            stack,
            'Loading the track detail failed',
            tag: 'TrackDetail',
          ),
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
    NotifierProvider<TrackDetailNotifier, TrackDetailState>(
      TrackDetailNotifier.new,
    );
