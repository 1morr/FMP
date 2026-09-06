import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/play_queue.dart';
import '../../data/models/track.dart';

/// 佇列面向 UI 的投影。
///
/// 由 [AudioController] 在每次佇列變動後重算並經 `onQueueStateChanged` 推出來，
/// 與 `PlayerState`（單曲播放狀態）分開：佇列變動遠比播放位置稀疏，兩者合併會讓
/// 每秒一次的位置更新去重建整個佇列清單。
class QueueState {
  final List<Track> queue;
  final List<Track> upcomingTracks;
  final int? currentIndex;
  final Track? queueTrack;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int queueVersion;
  final bool isMixMode;
  final String? mixTitle;
  final bool isLoadingMoreMix;

  const QueueState({
    this.queue = const [],
    this.upcomingTracks = const [],
    this.currentIndex,
    this.queueTrack,
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.none,
    this.queueVersion = 0,
    this.isMixMode = false,
    this.mixTitle,
    this.isLoadingMoreMix = false,
  });

  QueueState copyWith({
    List<Track>? queue,
    List<Track>? upcomingTracks,
    int? currentIndex,
    Track? queueTrack,
    bool? canPlayPrevious,
    bool? canPlayNext,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? queueVersion,
    bool? isMixMode,
    String? mixTitle,
    bool clearMixTitle = false,
    bool? isLoadingMoreMix,
  }) {
    return QueueState(
      queue: queue ?? this.queue,
      upcomingTracks: upcomingTracks ?? this.upcomingTracks,
      currentIndex: currentIndex ?? this.currentIndex,
      queueTrack: queueTrack ?? this.queueTrack,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      queueVersion: queueVersion ?? this.queueVersion,
      isMixMode: isMixMode ?? this.isMixMode,
      mixTitle: clearMixTitle ? null : (mixTitle ?? this.mixTitle),
      isLoadingMoreMix: isLoadingMoreMix ?? this.isLoadingMoreMix,
    );
  }
}

final queueStateProvider =
    StateProvider<QueueState>((ref) => const QueueState());
