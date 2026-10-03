// `PlaybackController.events` 的事件（design §7.9）：使用者要知道、但不是播放
// 狀態的事。外殼以 `ref.listen` 轉成提示。M2 PR 10 只有 [QueueFull]；跳過、停止、
// 輸出裝置、試聽在 PR 12、13 加。

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
