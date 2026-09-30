// 兩個後端共用的規則（ADR 0018 §決定 3）：不含任何引擎型別的純函數。
//
// 翻譯仍在後端：只有後端知道自己面對的是 ExoPlayer 還是 mpv。搬到這裡的是規則
// 本身，兩個真後端在 `flutter test` 裡建不起來（just_audio 要 platform channel，
// media_kit 要 libmpv），規則是純函數，「同一份斷言跑在兩個實作與假後端上」才
// 做得到：`test/playback/backends/backend_rules_test.dart` 測規則，
// `audio_backend_contract.dart` 以同一份行為斷言跑假後端（`flutter test`）與
// 平台的真後端（`integration_test/audio_backend_contract_test.dart`）。
//
// 形狀照舊專案的 `playback_end_reason_rules.dart`、`next_media_plan.dart`。

/// 一個來源為什麼停下來。
enum TrackEndReason {
  /// 播到結尾。
  completed,

  /// 離結尾還遠就停了，或引擎從沒回報過時長：串流中斷、零位元組的回應。
  /// 上層當成傳輸中斷，從停下的位置重試（ADR 0018 §決定 7）。
  endedEarly,
}

/// 「位置離時長還差這麼多以上」就算提前結束。兩個引擎的位置回報都有間隔
/// （ExoPlayer 的事件外推、mpv 的 `time-pos`），1.5 秒容得下，舊專案同值。
const completionTolerance = Duration(milliseconds: 1500);

/// 引擎說目前的來源結束了（播完或接到前瞻）時，判斷是真的播完還是提前結束。
///
/// [position] 是結束前最後的位置，[duration] 是引擎回報的時長；`null` 或 0 是
/// 引擎從沒回報過時長，舊專案實測「連得上但零位元組」的串流就是這個形狀，
/// 所以算提前結束，不當成播完直接接下一首。
TrackEndReason classifyTrackEnd({
  required Duration position,
  required Duration? duration,
}) {
  if (duration == null || duration <= Duration.zero) {
    return TrackEndReason.endedEarly;
  }
  if (duration - position > completionTolerance) {
    return TrackEndReason.endedEarly;
  }
  return TrackEndReason.completed;
}

/// 讓後端的播放清單回到「目前＋最多一個前瞻」要做的修改。
final class LookAheadEdit {
  const LookAheadEdit._({required this.removeIndices, required this.append});

  /// 清單裡有 [itemCount] 個項目、正在播 [currentIndex]；[append] 是要不要接上
  /// 新的前瞻（`false` 是清掉）。
  ///
  /// 目前這個項目以外的全部移掉：之後的是舊的前瞻，之前的是剛播完的那一首
  /// （接上前瞻後由後端自己修剪）。留著的話每個項目都是一條開著的連線，而且
  /// 目前的項目不在 0，「下一個」就不一定是 1。清單是空的就什麼都不做：沒有
  /// 東西在播，也就沒有可以接上去的位置。
  factory LookAheadEdit.of({
    required int itemCount,
    required int currentIndex,
    required bool append,
  }) {
    if (itemCount <= 0 || currentIndex < 0 || currentIndex >= itemCount) {
      return const LookAheadEdit._(removeIndices: [], append: false);
    }
    return LookAheadEdit._(
      removeIndices: [
        for (var index = itemCount - 1; index >= 0; index--)
          if (index != currentIndex) index,
      ],
      append: append,
    );
  }

  /// 要移除的索引，由大到小：照這個順序移，前面的索引不會位移。
  final List<int> removeIndices;

  /// 移完後要不要把新的前瞻接在目前的項目之後（成為索引 1）。
  final bool append;
}
