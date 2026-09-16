/// 後端事件的**路由決定**，與執行那些決定的副作用分開。
///
/// `AudioController` 過去把兩件事寫在同一個處理函式裡：從一堆私有欄位讀出當下
/// 的情況、然後就地做事。於是「裝置失敗之後不重試 premature end」這種規則沒有
/// 任何單獨的斷言方式 —— 要驗它就得架一整個控制器、一個假後端、一個 Isar，再
/// 從 toast 與日誌反推路由走了哪一條。
///
/// 這裡的做法照 `PlaybackRecoveryCoordinator` 的先例：決定變成純函數，回傳一個
/// [PlaybackAction]，控制器只負責把它套用出去。規則因此可以逐條斷言，而控制器
/// 的 `switch` 是窮盡的 —— 新增一種結束原因時編譯器會指出漏掉的那一格。
///
/// **新增一條決定就新增一個 [PlaybackAction] 變體與一條路由測試，不要在套用端
/// 寫 `if`。** 套用端一旦開始分支，這個檔案就只剩下一半的規則，而另一半又回到
/// 沒有人測得到的地方。
library;

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/effective_playback_state.dart';

/// 一次後端事件抵達時，控制器看得到的全部事實。
///
/// 控制器在路由之前拍下這張快照，路由只讀它。刻意**不放協作者**：拿得到
/// `QueueManager` 的話，「有沒有下一首」就會變成 `moveToNext()` 這種一問就改
/// 狀態的問法，而那正是決定與副作用混在一起的形狀。
final class PlaybackEventContext {
  const PlaybackEventContext({
    required this.isDisposed,
    required this.radioOwnsPlayback,
    required this.isLoadingPlayback,
    required this.isRetrying,
    required this.isNetworkError,
    required this.playingTrackKey,
    required this.hasError,
    required this.terminalMediaOpenErrorTrackKey,
    required this.generationMark,
    required this.outputDeviceFailureMark,
    required this.prematureEndRetryMark,
    required this.lastOutputDeviceFailureAt,
    required this.now,
    required this.loopMode,
    required this.isPlayingOutOfQueue,
    required this.hasNextInQueue,
    required this.mixLoadMorePending,
    required this.armedNextTrackKey,
    required this.armedEndTicks,
    required this.bufferStarvationTrackKey,
    required this.backendIsPlaying,
    required this.position,
    required this.duration,
  });

  /// 控制器已經釋放。
  ///
  /// 呼叫端在讀後端之前通常已經擋掉一次，但這個欄位不是多餘的：完成事件會排到
  /// 一個 microtask 上、串流飢餓救援中間有一個 `await`，兩條路都可能在釋放**之
  /// 後**才走到路由。
  final bool isDisposed;

  /// 電台正占用共用的後端。
  final bool radioOwnsPlayback;

  /// 控制器自己正在跑一次播放請求的交接。
  final bool isLoadingPlayback;

  final bool isRetrying;
  final bool isNetworkError;

  /// 正在播的那一首的 `Track.uniqueKey`；沒有在播就是 null。
  final String? playingTrackKey;

  /// `PlayerState.error` 非空。
  final bool hasError;

  /// 已經判定「這首歌開不起來」的那一首。
  final String? terminalMediaOpenErrorTrackKey;

  /// 現在的請求世代與播放中歌曲。
  final ({int generation, String? trackKey}) generationMark;

  /// 輸出裝置失敗當下是哪一次請求、哪一首歌。
  final ({int generation, String? trackKey})? outputDeviceFailureMark;

  /// 已排定、還沒起跑的 premature-end 重試是哪一次請求、哪一首歌。
  final ({int generation, String? trackKey})? prematureEndRetryMark;

  /// 上一次輸出裝置失敗的時刻。
  final DateTime? lastOutputDeviceFailureAt;

  /// 拍下這張快照的時刻。時間比較一律用它，路由本身不讀時鐘。
  final DateTime now;

  final LoopMode loopMode;
  final bool isPlayingOutOfQueue;

  /// 佇列裡還有下一首（已經照 shuffle 與 loop 模式算過）。
  final bool hasNextInQueue;

  /// Mix 還在補歌。
  final bool mixLoadMorePending;

  /// 已經交給後端的下一首；非 null 代表推進權在後端手上。
  final String? armedNextTrackKey;

  /// arm 期間輪詢備援連續看到「已經到結尾」的次數。
  final int armedEndTicks;

  /// 已經為哪一首歌出手救過一次串流飢餓。
  final String? bufferStarvationTrackKey;

  final bool backendIsPlaying;
  final Duration position;
  final Duration? duration;

  /// 裝置失敗之後的保護窗還開著。
  ///
  /// 失敗訊息會在播放 handoff **完成之前**抵達（實測：錯誤 48.68，
  /// `_ensurePlayback` 49.81 才把 playing 設回 true），所以不能用定時暫停去賭
  /// 順序 —— 改成看到 playing 翻真就收回。
  bool get isWithinOutputDeviceFailureGuard {
    final last = lastOutputDeviceFailureAt;
    return last != null &&
        now.difference(last) <
            PlaybackEventRouter.outputDeviceFailureGuardWindow;
  }

  /// 載入中／重試中／網路錯誤狀態下一律不處理播放結束。
  bool get isPlaybackEndIgnored =>
      isLoadingPlayback || isRetrying || isNetworkError;
}

/// 路由決定的結果：控制器該做的那**一**件事。
///
/// 一個變體一種副作用。不要用布林把一個變體變成兩種行為 —— 那等於把決定搬回
/// 套用端，而套用端沒有測試。
sealed class PlaybackAction {
  const PlaybackAction();
}

/// 什麼都不做，但留下一行說明為什麼。
///
/// [reason] 是給日誌看的英文短句；靜默丟棄是這個檔案唯一禁止的結果。
final class IgnoreEvent extends PlaybackAction {
  const IgnoreEvent(this.reason);

  final String reason;
}

/// 收掉正在計時的緩衝看門狗。
///
/// 進電台時如果計時器正在跑，之後就再也收不到事件來取消它了。
final class CancelBufferWatchdog extends PlaybackAction {
  const CancelBufferWatchdog();
}

/// 把後端的播放收回來。
final class PauseBackend extends PlaybackAction {
  const PauseBackend(this.reason);

  final String reason;
}

/// 把後端狀態投影到 `PlayerState`、看門狗與系統媒體控制。
final class ProjectPlayerState extends PlaybackAction {
  const ProjectPlayerState(
    this.backend,
    this.effective, {
    required this.suppressWatchdog,
  });

  /// 後端的原始值，只給日誌用 —— 投影一律用 [effective]。
  final FmpPlayerState backend;

  final EffectivePlaybackState effective;

  /// 重新緩衝這時候不該升級成失敗。
  final bool suppressWatchdog;
}

/// 進入完成處理（單曲迴圈／推進佇列／等 Mix／到底暫停由 [PlaybackEventRouter.routeCompletion] 再決定）。
final class HandleTrackCompletion extends PlaybackAction {
  const HandleTrackCompletion();
}

/// 單曲迴圈：重播現在這一首。
final class ReplayCurrentTrack extends PlaybackAction {
  const ReplayCurrentTrack();
}

/// 脫離佇列播放的那一首播完了，回到佇列。
final class ReturnToQueue extends PlaybackAction {
  const ReturnToQueue();
}

/// 推進到佇列的下一首。
final class AdvanceQueue extends PlaybackAction {
  const AdvanceQueue();
}

/// 佇列尾端遇上 Mix 還在補歌：等補完再推進。
///
/// 這是整個播放路徑唯一一處「等一個副作用」。
final class WaitForMixLoadMore extends PlaybackAction {
  const WaitForMixLoadMore();
}

/// 佇列真的播完了：暫停後端。
///
/// 不暫停的話後端仍會回報 playing（位置停在結尾），位置檢查計時器每秒都會再
/// 判定一次「播完」—— Android 實測會無限重複觸發。
final class PauseAtQueueEnd extends PlaybackAction {
  const PauseAtQueueEnd();
}

/// 提前結束：從 [at] 重試這一首。
final class RetryPrematureEnd extends PlaybackAction {
  const RetryPrematureEnd({required this.at, required this.expected});

  final Duration at;
  final Duration? expected;
}

/// 提前結束，但輸出裝置在同一個世代已經掛了 —— 不重試。
///
/// 重開串流換不回一個壞掉的輸出裝置，而重試會留下一行誤導人的
/// `Retry playback succeeded`（issue #106）。
final class SkipPrematureEndRetry extends PlaybackAction {
  const SkipPrematureEndRetry(this.at);

  final Duration at;
}

/// 傳輸層失敗：停掉後端再進重試階梯。
final class RecoverTransportFailure extends PlaybackAction {
  const RecoverTransportFailure(this.failure);

  final TransportFailed failure;
}

/// 音訊輸出裝置失敗。
///
/// 三個動作在一個變體裡，因為它們是同一次失敗的同一段處理：記下世代標記、
/// 視情況收回已排定的 premature-end 重試、視情況出 toast。
final class ReportOutputDeviceFailure extends PlaybackAction {
  const ReportOutputDeviceFailure({
    required this.raw,
    required this.at,
    required this.cancelScheduledRetry,
    required this.showToast,
  });

  final String raw;

  /// 這次失敗的時刻，會被記成下一次抑制窗與保護窗的起點。
  final DateTime at;

  /// 已經排好的 premature-end 重試要收回來。
  ///
  /// 實測（Windows）mpv 是先宣告 completed、4ms 後才吐 ao 錯誤，所以到這裡重試
  /// 已經排好了。
  final bool cancelScheduledRetry;

  /// 一次裝置失敗會連續產生多則訊息（實測 mpv 一次吐三條），只有第一條出 toast。
  final bool showToast;
}

/// 媒體開啟／解碼失敗：作廢解析結果，交給播放請求決定要不要延遲自癒。
final class ReopenAfterMediaFailure extends PlaybackAction {
  const ReopenAfterMediaFailure(this.raw);

  final String raw;
}

/// 後端給了一個歸不了類的失敗。顯性地丟棄 —— 至少留下一行看得見的紀錄。
final class ReportUnclassifiedFailure extends PlaybackAction {
  const ReportUnclassifiedFailure(this.raw);

  final String raw;
}

/// 串流飢餓第一次：換一次串流再試。
final class RetryStalledStream extends PlaybackAction {
  const RetryStalledStream();
}

/// 串流飢餓第二次：同一首只救一次，停下並通知。
final class FailStalledPlayback extends PlaybackAction {
  const FailStalledPlayback();
}

/// 離結尾還遠：把 arm 期間的計數歸零。
final class ResetArmedEndTicks extends PlaybackAction {
  const ResetArmedEndTicks();
}

/// 推進權還在後端手上，再讓一格。
final class IncrementArmedEndTicks extends PlaybackAction {
  const IncrementArmedEndTicks();
}

/// 後端一直沒有接上去：收回推進權，並且自己合成一次「播完」。
final class TakeBackAdvanceAndComplete extends PlaybackAction {
  const TakeBackAdvanceAndComplete({
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;
}

/// 後端把完成事件弄丟了（Android 背景播放實測），由位置檢查補一次。
final class SynthesizeCompletion extends PlaybackAction {
  const SynthesizeCompletion({required this.position, required this.duration});

  final Duration position;
  final Duration duration;
}

/// 後端事件 → [PlaybackAction]。全部是純函數，沒有 Riverpod、沒有後端、沒有時鐘。
abstract final class PlaybackEventRouter {
  /// 同一次裝置失敗的連續訊息在這個窗內只出一次 toast（實測 mpv 一次吐三條：
  /// `ao` 的兩條加上 `cplayer` 的一條）。
  static const outputDeviceFailureSuppressWindow = Duration(seconds: 3);

  /// 裝置失敗之後，這段時間內任何「開始播放」都要立刻收回。
  static const outputDeviceFailureGuardWindow = Duration(seconds: 5);

  /// 讓給後端幾格之後就收回推進權。1 秒一格，所以是 3 秒。
  static const armedAdvanceGraceTicks = 3;

  /// 後端回報播放器狀態改變。
  static PlaybackAction routePlayerState(
    FmpPlayerState backend,
    PlaybackEventContext context,
  ) {
    if (context.isDisposed) {
      return const IgnoreEvent('the controller is disposed');
    }
    // 電台播放中的狀態變化由 RadioController 處理，AudioController 不更新自身狀態。
    if (context.radioOwnsPlayback) return const CancelBufferWatchdog();

    if (context.terminalMediaOpenErrorTrackKey != null &&
        context.playingTrackKey == context.terminalMediaOpenErrorTrackKey &&
        context.hasError) {
      return const IgnoreEvent(
        'backend state after a terminal media open error',
      );
    }

    // 音訊裝置剛失敗：引擎可能仍宣稱在播（mpv 沒有輸出裝置也會把 playing
    // 翻真），把它收回，否則 UI 會停在「正在播放」卻完全沒有聲音。
    if (backend.playing && context.isWithinOutputDeviceFailureGuard) {
      return const PauseBackend('audio output device failed moments ago');
    }

    return ProjectPlayerState(
      backend,
      EffectivePlaybackState.from(
        backend: backend,
        controllerIsLoading: context.isLoadingPlayback,
        backendPosition: context.position,
      ),
      // 重新緩衝屬於 playing 的子狀態：這裡只餵資料，升不升級成失敗由 watchdog
      // 判斷 —— 但載入、重試、網路錯誤與裝置失敗保護窗裡的緩衝不算數。
      suppressWatchdog:
          context.isPlaybackEndIgnored ||
          context.isWithinOutputDeviceFailureGuard,
    );
  }

  /// 後端回報「播放停下來了」。
  ///
  /// **判斷是哪一種結束是後端的責任**，因為只有後端知道自己面對的是 mpv 還是
  /// ExoPlayer；這裡只決定每一種結束該做什麼。
  static PlaybackAction routeEnd(
    PlaybackEndReason reason,
    PlaybackEventContext context,
  ) {
    if (context.isDisposed) {
      return const IgnoreEvent('the controller is disposed');
    }

    // 電台的結束與失敗由 RadioController 自行處理（重連等），這裡不介入 ——
    // **輸出裝置失效除外**。裝置壞掉與現在播的是歌還是電台無關，而
    // RadioController 從來沒有訂閱過 endReasons，所以過去電台播放中拔掉音效
    // 裝置是零回饋（issue #41 症狀二）。輸出裝置失敗只發 toast、不動任何播放
    // 狀態，在電台情境下安全。
    if (context.radioOwnsPlayback) {
      if (reason case OutputDeviceFailed(:final raw)) {
        return routeOutputDeviceFailure(raw, context);
      }
      return IgnoreEvent('radio owns playback ($reason)');
    }

    switch (reason) {
      case EndedNaturally():
        // 進不進得了完成處理由 [routeCompletion] 決定：那條路還要再等一個
        // microtask，而載入／重試狀態在那之前可能已經變了。
        return const HandleTrackCompletion();
      case EndedPrematurely(:final at, :final expected):
        if (context.isPlaybackEndIgnored) {
          return const IgnoreEvent(_endIgnoredReason);
        }
        // 重開串流換不回一個壞掉的輸出裝置。連「排重試」那一行都不能印 ——
        // 跟在它後面的是誤導人的「Retry playback succeeded」（issue #106）。
        if (context.outputDeviceFailureMark == context.generationMark) {
          return SkipPrematureEndRetry(at);
        }
        return RetryPrematureEnd(at: at, expected: expected);
      case TransportFailed():
        if (context.playingTrackKey == null) {
          return const IgnoreEvent('transport failure with no playing track');
        }
        return RecoverTransportFailure(reason);
      case OutputDeviceFailed(:final raw):
        return routeOutputDeviceFailure(raw, context);
      case MediaUnopenable(:final raw):
      case DecoderFailed(:final raw):
        if (context.playingTrackKey == null) {
          return IgnoreEvent('media open failure with no playing track ($raw)');
        }
        return ReopenAfterMediaFailure(raw);
      case UnclassifiedFailure(:final raw):
        return ReportUnclassifiedFailure(raw);
    }
  }

  /// 正常播完之後往哪裡去。
  ///
  /// 順序是有意義的：單曲迴圈**優先於**脫離佇列，臨時播放中按下單曲迴圈仍然
  /// 迴圈同一首。
  static PlaybackAction routeCompletion(PlaybackEventContext context) {
    if (context.isDisposed) {
      return const IgnoreEvent('the controller is disposed');
    }
    if (context.isPlaybackEndIgnored) {
      return const IgnoreEvent(_endIgnoredReason);
    }
    if (context.loopMode == LoopMode.one) return const ReplayCurrentTrack();
    if (context.isPlayingOutOfQueue) return const ReturnToQueue();
    if (context.hasNextInQueue) return const AdvanceQueue();
    if (context.mixLoadMorePending) return const WaitForMixLoadMore();
    return const PauseAtQueueEnd();
  }

  /// 一秒一格的位置檢查備援（Android 背景播放會把 completed 事件弄丟）。
  static PlaybackAction routePositionCheck(PlaybackEventContext context) {
    if (context.isDisposed) {
      return const IgnoreEvent('the controller is disposed');
    }
    if (!context.backendIsPlaying) {
      return const IgnoreEvent('the backend is not playing');
    }

    final duration = context.duration;
    if (duration == null || duration.inMilliseconds <= 0) {
      return const IgnoreEvent('no usable duration to compare against');
    }
    if (duration - context.position > AppConstants.positionCheckThreshold) {
      return const ResetArmedEndTicks();
    }

    if (context.armedNextTrackKey != null) {
      // 推進權在後端手上，這裡再合成一次「播完」就是二次前進。但這個備援本來
      // 就是為了「後台 completed 事件丟失」而存在的，所以不是無限期讓路：
      // 連續三格還停在結尾就當後端沒接上去，把推進權收回來。
      if (context.armedEndTicks + 1 < armedAdvanceGraceTicks) {
        return const IncrementArmedEndTicks();
      }
      return TakeBackAdvanceAndComplete(
        position: context.position,
        duration: duration,
      );
    }

    // 走到這裡代表 remaining 已在容忍窗內，是真的播完。
    return SynthesizeCompletion(position: context.position, duration: duration);
  }

  /// T3：連續緩衝超過預算 —— 引擎還沒喊失敗，但已經播不動了。
  ///
  /// 一首歌只救一次，否則就變成無限重載。
  static PlaybackAction routeBufferStarvation(PlaybackEventContext context) {
    if (context.isDisposed) {
      return const IgnoreEvent('the controller is disposed');
    }
    final trackKey = context.playingTrackKey;
    if (trackKey == null) {
      return const IgnoreEvent('buffer starvation with no playing track');
    }
    if (context.isPlaybackEndIgnored) {
      return const IgnoreEvent(_endIgnoredReason);
    }
    if (context.bufferStarvationTrackKey == trackKey) {
      return const FailStalledPlayback();
    }
    return const RetryStalledStream();
  }

  /// 音訊「輸出裝置」失敗 —— 與這首歌無關，所以不能報「播放失敗: <歌名>」。
  ///
  /// 兩個布林各自獨立於抑制窗：即使這是同一次失敗的第二、第三條訊息（不出
  /// toast），世代標記照記、已排定的重試照收。
  static PlaybackAction routeOutputDeviceFailure(
    String raw,
    PlaybackEventContext context,
  ) {
    final last = context.lastOutputDeviceFailureAt;
    final suppressed =
        last != null &&
        context.now.difference(last) < outputDeviceFailureSuppressWindow;
    return ReportOutputDeviceFailure(
      raw: raw,
      at: context.now,
      cancelScheduledRetry:
          context.prematureEndRetryMark == context.generationMark,
      showToast: !suppressed,
    );
  }

  static const _endIgnoredReason = 'loading, retrying or in a network error';
}
