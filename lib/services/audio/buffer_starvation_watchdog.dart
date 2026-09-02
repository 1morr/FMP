import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import 'playback_recovery_coordinator.dart';

/// 「一直在緩衝，但沒有任何人喊失敗」的看門狗。
///
/// 重新緩衝是 playing 的**子狀態**：網路抖一下就 teardown 再完整重新解析一次，
/// 正是使用者體感到的「一卡一卡」。所以這裡不停播、不重解析、不動狀態機 ——
/// 只有**連續**緩衝超過預算才升級成一次失敗。
///
/// 它是「引擎什麼都不說」時的兜底。實測 Windows 上一條零位元組的串流會讓
/// `playUrl` 宣稱成功、`duration` 為 null，然後就一直 buffering 下去，
/// `errorStream` 全程沒有任何輸出 —— 沒有這隻狗，就永遠沒有人會出手。
class BufferStarvationWatchdog with Logging {
  BufferStarvationWatchdog({
    required void Function() onStarved,
    PlaybackTimeoutBudget budget = const PlaybackTimeoutBudget(),
    PlaybackRecoveryTimerFactory timerFactory =
        defaultPlaybackRecoveryTimerFactory,
  })  : _onStarved = onStarved,
        _timeout = budget.bufferStarvation,
        _timerFactory = timerFactory;

  final void Function() _onStarved;
  final Duration _timeout;
  final PlaybackRecoveryTimerFactory _timerFactory;

  PlaybackRecoveryTimer? _timer;

  /// 餵進**與 UI 看到的同一組**播放狀態，看門狗才不可能跟 `state.isBuffering`
  /// 各說各話。
  ///
  /// [isSuppressed] 涵蓋所有「緩衝是預期中的」情況：控制器自己的載入階段、
  /// 重試中、已經在網路錯誤狀態裡。
  void onPlayerStateChanged({
    required bool isBuffering,
    required bool isPlaying,
    required bool isSuppressed,
  }) {
    if (isSuppressed || !isPlaying || !isBuffering) {
      cancel();
      return;
    }

    // 已經在計時就不要重新開始。「連續 15 秒」是從進入 buffering 那一刻起算 ——
    // 每收到一次 buffering 事件就重置的話，這隻狗永遠不會叫。
    if (_timer != null) return;

    _timer = _timerFactory(_timeout, () {
      _timer = null;
      logWarning('Playback has been buffering for ${_timeout.inSeconds}s');
      _onStarved();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
