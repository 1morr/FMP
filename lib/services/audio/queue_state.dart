import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/play_queue.dart';
import '../../data/models/track.dart';

/// 佇列面向 UI 的投影，唯一一份。
///
/// 由 [AudioController] 在每次佇列變動後重算並經 `onQueueStateChanged` 推出來。
/// 佇列的形狀只住在這裡；`PlayerState` 描述的是「正在播的那一首」，兩者沒有
/// 重疊的欄位。分開的理由是位置每秒更新一次而佇列很少變，合併會讓每次位置
/// 更新都重建整個佇列清單。
///
/// **這裡的 12 個欄位曾經在 `PlayerState` 裡各存一份**，靠控制器每次逐欄位抄
/// 過去維持一致，而消費端會因為問了不同的 provider 拿到不同的答案。
/// `audio_queue_state_provider_test.dart` 的
/// `PlayerState declares none of the queue fields` 守著它不要長回來。
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
