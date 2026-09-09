/// 系統媒體控制（Android 通知欄、Windows SMTC）在**當前播放模式**下真正支援
/// 哪些命令。
///
/// 這裡講的是「模式」，不是「此刻」。[canSkipNext] 問的是「這種播放有沒有
/// 下一首這個概念」，**不是** `PlayerState.canPlayNext`（佇列裡還有沒有下一首）。
/// 接到佇列邊界上會讓每次切歌都打一次 FFI/IPC，而且系統 UI 的按鈕會閃。
///
/// 這個型別存在的理由是一個真實的 bug：過去能力是兩個 handler 裡寫死的 `const`
/// （`audio_handler.dart` 的 `_getControls`、`windows_smtc_handler.dart` 的
/// `SMTCConfig`），而電台只能把回呼設成 null。系統照樣畫出上／下一首按鈕，
/// 按下去打進 null，靜默無事發生 —— 那就是 issue #40 的症狀一。現在能力一律
/// 由 `NowPlayingPublisher` 從實際綁定的命令推導，宣告與實作不可能再分家。
class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.canSkipNext,
    required this.canSkipPrevious,
    required this.canSeek,
    required this.canShuffle,
    required this.canRepeat,
  });

  /// 一般音樂播放：五項全開。
  static const music = PlaybackCapabilities(
    canSkipNext: true,
    canSkipPrevious: true,
    canSeek: true,
    canShuffle: true,
    canRepeat: true,
  );

  /// 什麼都不宣告。
  ///
  /// 沒有任何擁有者時的降級狀態 —— 系統媒體鍵沒有反應，但也不會出現按下去
  /// 沒事發生的假按鈕。
  static const none = PlaybackCapabilities(
    canSkipNext: false,
    canSkipPrevious: false,
    canSeek: false,
    canShuffle: false,
    canRepeat: false,
  );

  /// 直播電台：沒有下一首、沒有時間軸、沒有佇列，所以與 [none] 同值。
  /// 分開命名是為了讓呼叫端讀得出意圖，不是因為值不同。
  static const liveRadio = none;

  final bool canSkipNext;
  final bool canSkipPrevious;
  final bool canSeek;
  final bool canShuffle;
  final bool canRepeat;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackCapabilities &&
            other.canSkipNext == canSkipNext &&
            other.canSkipPrevious == canSkipPrevious &&
            other.canSeek == canSeek &&
            other.canShuffle == canShuffle &&
            other.canRepeat == canRepeat;
  }

  @override
  int get hashCode =>
      Object.hash(canSkipNext, canSkipPrevious, canSeek, canShuffle, canRepeat);

  @override
  String toString() {
    return 'PlaybackCapabilities(next: $canSkipNext, prev: $canSkipPrevious, '
        'seek: $canSeek, shuffle: $canShuffle, repeat: $canRepeat)';
  }
}
