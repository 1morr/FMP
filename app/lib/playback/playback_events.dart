import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_info.dart';

// `PlaybackController.events` 的事件（design §7.9）：使用者要知道、但不是播放
// 狀態的事。外殼以 `ref.listen` 轉成提示。輸出裝置失敗在 M2 PR 13 加。

/// 播放控制器發出的一次性事件。
///
/// 事件沒有 `const` 建構子、也不覆寫 `==`：每次都是不同的實例，provider 以
/// `==` 判斷要不要通知時，連續兩次同樣的事件也都會送到。
sealed class PlaybackEvent {
  PlaybackEvent();
}

/// 加入會超過佇列上限（[limit] 首），整批沒有加入（ADR 0018 §決定 4）。
final class QueueFull extends PlaybackEvent {
  QueueFull({required this.limit});

  final int limit;
}

/// [track] 播不了，因為 [error] 跳過了，已經往下一首（臨時播放中是回到佇列；
/// ADR 0018 §決定 7）。
final class TrackSkipped extends PlaybackEvent {
  TrackSkipped({required this.error, required this.track});

  final AppError error;
  final TrackInfo track;
}

/// 播放停在 `Failed`：[track] 因為 [error] 播不了，而且沒有地方可去（佇列到底、
/// 臨時播放而佇列是空的），或連續播不了的達到上限（ADR 0018 §決定 7）。
/// [failedInARow] 是連著播不了的曲目數，含 [track]。
final class PlaybackStopped extends PlaybackEvent {
  PlaybackStopped({
    required this.error,
    required this.track,
    required this.failedInARow,
  });

  final AppError error;
  final TrackInfo track;
  final int failedInARow;
}

/// [track] 只有試聽片段，而「跳過試聽片段」關著：照播並標「試聽」（D4）。
/// 同一首重播（單曲循環、重試）不再發。
final class PreviewPlaying extends PlaybackEvent {
  PreviewPlaying({required this.track});

  final TrackInfo track;
}
