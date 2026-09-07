import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/services/toast_service.dart';
import '../../data/models/track.dart';
import '../../i18n/strings.g.dart';
import 'audio_playback_types.dart';
import 'mix_playlist_types.dart';
import 'queue_manager.dart';
import 'queue_persistence_manager.dart';

/// 一次 Mix 工作階段。
///
/// 身分靠物件同一性（`identical`）判定，不靠 ID —— 換一個 Mix 就是換一個物件，
/// 舊工作階段上還在飛的抓取因此可以自己發現「我已經不是現任了」而放棄。
class MixPlaylistSession {
  MixPlaylistSession({
    required this.playlistId,
    required this.seedVideoId,
    required this.title,
    Set<String>? seenVideoIds,
  }) : seenVideoIds = seenVideoIds ?? {};

  final String playlistId;
  final String seedVideoId;
  final String title;
  final Set<String> seenVideoIds;

  bool isLoadingMore = false;

  void addSeenVideoIds(Iterable<String> ids) {
    seenVideoIds.addAll(ids);
  }
}

/// 擁有 YouTube Mix（`RD` 開頭的無限播放列表）的工作階段與它的預取。
///
/// **預取不阻塞播放**：[onTrackStarted] 只是排一個 future 就回來。唯一會等它的
/// 是「最後一首播完，而預取剛好還在飛」這個邊界 —— `AudioController` 用
/// [pendingLoad] 去 await 它，然後接進新抓回來的歌。這是刻意的，不是疏漏。
///
/// **它不碰 `PlayerState`**：載入中與佇列變動經由建構子的 `onLoadingChanged` /
/// `onQueueChanged` 回報，投影留在 `AudioController` —— 與 `QueueCommands` 同一
/// 條規矩。
///
/// **它不啟動播放**：起播 Mix（`startMixFromPlaylist` / `playMixPlaylist`）留在
/// `AudioController`，理由與 `playAt` 留在那裡一樣 —— 那是 transport 命令。
class MixSessionCoordinator with Logging {
  MixSessionCoordinator({
    required QueueManager queueManager,
    required ToastService toastService,
    required void Function(bool isLoading) onLoadingChanged,
    required void Function() onQueueChanged,
    MixTracksFetcher? fetcher,
  }) : _queueManager = queueManager,
       _toastService = toastService,
       _onLoadingChanged = onLoadingChanged,
       _onQueueChanged = onQueueChanged,
       _fetcher = fetcher;

  final QueueManager _queueManager;
  final ToastService _toastService;
  final void Function(bool isLoading) _onLoadingChanged;
  final void Function() _onQueueChanged;
  final MixTracksFetcher? _fetcher;

  MixPlaylistSession? _current;
  Future<void>? _loadMoreFuture;

  MixPlaylistSession? get current => _current;

  /// 進行中的預取，沒有就是 null。供播到隊尾時等待。
  Future<void>? get pendingLoad => _loadMoreFuture;

  bool isCurrent(MixPlaylistSession session) => identical(_current, session);

  /// 有沒有辦法抓 Mix 歌曲。YouTube 音源不在時就沒有。
  bool get canFetch => _fetcher != null;

  /// 抓一批 Mix 歌曲。
  ///
  /// 起播時用來取第一批。去重、重試與排程都不在這裡 —— 那是 [onTrackStarted]
  /// 排出來的預取要處理的事。呼叫端必須先問過 [canFetch]。
  Future<MixFetchResult> fetch({
    required String playlistId,
    required String currentVideoId,
  }) {
    return _fetcher!(playlistId: playlistId, currentVideoId: currentVideoId);
  }

  /// 開一個新的 Mix 工作階段，取代舊的（如果有）。
  MixPlaylistSession start({
    required String playlistId,
    required String seedVideoId,
    required String title,
  }) {
    _current = MixPlaylistSession(
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: title,
    );
    // 舊工作階段的抓取可能還在飛。放掉它的 future，讓新工作階段可以立刻預取；
    // 那個抓取自己會在下一個 isCurrent 檢查點放棄。
    _loadMoreFuture = null;
    return _current!;
  }

  /// 從持久化的佇列狀態接回上一次的 Mix 工作階段。
  ///
  /// 回傳 null 代表「上一次不是 Mix，或 metadata 不完整」，呼叫端據此決定要不要
  /// 把模式切成 Mix。三個欄位少一個都不算數 —— 只有 title 沒有 playlistId 的話
  /// 之後的預取會抓不到任何東西，寧可退回一般佇列，也不要一個永遠加載不出下一
  /// 批的假 Mix。
  ///
  /// 這是 `mixPlaylistId` / `mixSeedVideoId` / `mixTitle` 三個持久化欄位在這個
  /// 類別之外的最後一個讀取點，收進來之後 Mix 身分只有一個來源。
  MixPlaylistSession? restoreFrom(QueueRestoreState? restored) {
    if (restored == null || !restored.queue.isMixMode) return null;

    final playlistId = restored.mixPlaylistId;
    final seedVideoId = restored.mixSeedVideoId;
    final title = restored.mixTitle;
    if (playlistId == null || seedVideoId == null || title == null) return null;

    logDebug('Restoring Mix mode: $title');
    final session = start(
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: title,
    );
    // 佇列裡已經有的歌不要再抓一次。
    session.addSeenVideoIds(_queueManager.tracks.map((t) => t.sourceId));
    return session;
  }

  /// 離開 Mix 模式。工作階段與進行中的預取一起清掉 —— 這兩者過去是分開的欄位，
  /// 每個離開路徑都得記得清兩次。
  void exit() {
    _current = null;
    _loadMoreFuture = null;
  }

  /// 一首歌開始播之後呼叫。接近隊尾時排入預取。
  void onTrackStarted(PlayMode mode) {
    if (!_shouldLoadMore(mode)) return;

    final remaining =
        _queueManager.tracks.length - 1 - _queueManager.currentIndex;
    logDebug(
      'Mix mode: $remaining tracks remaining, loading more before queue end...',
    );
    _scheduleLoadMore();
  }

  bool _shouldLoadMore(PlayMode mode) {
    if (mode != PlayMode.mix) return false;
    if (_loadMoreFuture != null) return false;

    final queueLength = _queueManager.tracks.length;
    if (queueLength == 0) return false;

    final remaining = queueLength - 1 - _queueManager.currentIndex;
    final threshold =
        queueLength > AppConstants.mixLoadMoreRemainingThreshold + 1
        ? AppConstants.mixLoadMoreRemainingThreshold
        : 0;
    return remaining <= threshold;
  }

  void _scheduleLoadMore() {
    if (_loadMoreFuture != null) return;

    final future = _loadMore();
    _loadMoreFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_loadMoreFuture, future)) {
          _loadMoreFuture = null;
        }
      }),
    );
  }

  /// 加載更多 Mix 播放列表歌曲
  ///
  /// 使用重試機制確保每次至少獲取 10 首新歌曲：
  /// 1. 先用最後一首歌曲作為種子重試 3 次
  /// 2. 如果仍不足，嘗試用隊列中其他歌曲作為種子
  /// 3. 最多嘗試 10 次，每次間隔 1 秒
  /// 4. 收集所有新歌曲後一次性添加到隊列
  Future<void> _loadMore() async {
    final mixState = _current;
    if (mixState == null || !_markLoading(mixState)) {
      return;
    }

    final queue = _queueManager.tracks;
    if (queue.isEmpty) {
      _finishLoading(mixState);
      return;
    }

    _onLoadingChanged(true);
    logInfo('Loading more Mix tracks...');

    const minNewTracksRequired = AppConstants.mixMinNewTracksRequired;
    const maxAttempts = AppConstants.mixMaxLoadAttempts;
    const sameVideoRetries = AppConstants.mixSameVideoRetries;
    const retryDelay = AppConstants.mixRetryDelay;

    // 收集所有新歌曲，最後一次性添加
    final collectedTracks = <Track>[];
    final collectedVideoIds = <String>{};
    int attempt = 0;
    final fetcher = _fetcher;
    if (fetcher == null) {
      logWarning('Mix load failed: YouTube source unavailable');
      _toastService.showInfo(t.audio.mixLoadMoreError);
      _finishLoading(mixState);
      if (isCurrent(mixState)) {
        _onLoadingChanged(false);
      }
      return;
    }

    try {
      while (collectedTracks.length < minNewTracksRequired &&
          attempt < maxAttempts) {
        if (!isCurrent(mixState)) {
          logDebug('Mix mode exited during load-more, aborting');
          return;
        }

        attempt++;

        // 選擇種子視頻：前 3 次用最後一首，之後用不同的視頻
        String seedVideoId;
        if (attempt <= sameVideoRetries) {
          seedVideoId = queue.last.sourceId;
          logDebug(
            'Attempt $attempt/$maxAttempts: using last track as seed ($seedVideoId)',
          );
        } else {
          // 從隊列倒數第 2 ~ 倒數第 10 首中選擇一個不同的種子
          final seedIndex = queue.length - 1 - (attempt - sameVideoRetries);
          if (seedIndex >= 0) {
            seedVideoId = queue[seedIndex].sourceId;
            logDebug(
              'Attempt $attempt/$maxAttempts: using track at index $seedIndex as seed ($seedVideoId)',
            );
          } else {
            seedVideoId = queue.last.sourceId;
            logDebug(
              'Attempt $attempt/$maxAttempts: fallback to last track as seed ($seedVideoId)',
            );
          }
        }

        try {
          final result = await fetcher(
            playlistId: mixState.playlistId,
            currentVideoId: seedVideoId,
          );

          if (!isCurrent(mixState)) {
            logDebug('Mix mode exited after load-more fetch, aborting');
            return;
          }

          // 過濾已存在的歌曲（包括已在隊列中的和本輪已收集的）
          final newTracks = result.tracks
              .where(
                (t) =>
                    !mixState.seenVideoIds.contains(t.sourceId) &&
                    !collectedVideoIds.contains(t.sourceId),
              )
              .toList();

          if (newTracks.isNotEmpty) {
            logDebug(
              'Attempt $attempt: got ${newTracks.length} new tracks (total: ${collectedTracks.length + newTracks.length})',
            );
            collectedTracks.addAll(newTracks);
            collectedVideoIds.addAll(newTracks.map((t) => t.sourceId));
          } else {
            logDebug('Attempt $attempt: no new tracks (all duplicates)');
          }

          // 如果還沒達到目標且還有重試次數，等待後繼續
          if (collectedTracks.length < minNewTracksRequired &&
              attempt < maxAttempts) {
            await Future.delayed(retryDelay);
          }
        } catch (e) {
          logWarning('Attempt $attempt failed: $e');
          // 單次請求失敗，等待後繼續嘗試
          if (attempt < maxAttempts) {
            await Future.delayed(retryDelay);
          }
        }
      }

      if (!isCurrent(mixState)) {
        logDebug('Mix mode exited before applying load-more results, aborting');
        return;
      }

      // 一次性添加所有收集到的新歌曲
      if (collectedTracks.isNotEmpty) {
        logInfo(
          'Mix load complete: adding ${collectedTracks.length} new tracks in $attempt attempts',
        );
        mixState.addSeenVideoIds(collectedTracks.map((t) => t.sourceId));
        await _queueManager.addAll(collectedTracks);
        _onQueueChanged();
      } else {
        logWarning('Mix load failed: no new tracks after $attempt attempts');
        _toastService.showInfo(t.audio.mixLoadMoreFailed);
      }
    } catch (e, stack) {
      logError('Failed to load more Mix tracks', e, stack);
      _toastService.showInfo(t.audio.mixLoadMoreError);
    } finally {
      _finishLoading(mixState);
      if (isCurrent(mixState)) {
        _onLoadingChanged(false);
      }
    }
  }

  bool _markLoading(MixPlaylistSession session) {
    if (!isCurrent(session) || session.isLoadingMore) {
      return false;
    }
    session.isLoadingMore = true;
    return true;
  }

  void _finishLoading(MixPlaylistSession session) {
    if (isCurrent(session)) {
      session.isLoadingMore = false;
    }
  }
}
