import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';

/// 播放狀態（ADR 0018 §決定 2）：只有一份，只由 `PlaybackController` 寫。
///
/// 播的是哪一首看 `QueueState`，兩者沒有共同欄位；位置、時長、緩衝這類高頻
/// 資料走 [PlaybackProgress] 的 stream，不在這裡。
@immutable
sealed class PlaybackState {
  const PlaybackState();
}

/// 沒有在播：還沒開始，或佇列播完了。
final class Idle extends PlaybackState {
  const Idle();
}

/// 正在解析串流或開流，還沒出聲。
final class Loading extends PlaybackState {
  const Loading();
}

final class Playing extends PlaybackState {
  const Playing();
}

final class Paused extends PlaybackState {
  const Paused();
}

/// 已經開始播，中途等資料。
final class Buffering extends PlaybackState {
  const Buffering();
}

/// 失敗後等著重試（ADR 0018 §決定 7）。
///
/// - [delay] 不為空：[delay] 後重試，[attempt] 是第幾次（從 1 起算）。
/// - [delay] 為空：等網路（design §5.3），網路狀態回到 `online` 時立刻重試；
///   等網路不算一次重試，[attempt] 為 0。
final class Retrying extends PlaybackState {
  const Retrying({
    required this.error,
    required this.attempt,
    required this.delay,
  });

  final AppError error;
  final int attempt;
  final Duration? delay;

  /// 在等網路，不是倒數重試。
  bool get waitingForNetwork => delay == null;
}

/// 停下來了：連續跳過到上限，或最後一首也播不了（ADR 0018 §決定 7）。
final class Failed extends PlaybackState {
  const Failed(this.error);

  final AppError error;
}

/// 目前這首的位置、時長與已緩衝的位置。
@immutable
final class PlaybackProgress {
  const PlaybackProgress({
    required this.position,
    this.duration,
    this.buffered = Duration.zero,
  });

  final Duration position;

  /// 還不知道時為 `null`。
  final Duration? duration;
  final Duration buffered;
}
