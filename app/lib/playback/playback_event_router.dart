import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/recovery_policy.dart';

// 後端事件變成控制器的哪個動作（ADR 0018 §決定 1）：純函數，不碰後端、計時器
// 與 log。
//
// `PlaybackSession` 把後端的狀態與事件過濾成目前這個來源的 [SourceEvent]
// （帶它屬於哪一代），加上不屬於來源的輸出事件（音訊中斷、拔耳機、輸出裝置），
// 控制器連同自己的 [PlaybackSnapshot] 交給
// [routePlaybackEvent]，照回傳的 [EventAction] 改狀態。事件型別放在這裡而不是
// `PlaybackSession`：結束原因 [TrackEndReason] 只准後端與這裡 import
// （`fmp_layer_imports` 的 `restrictedImports`）。

/// `PlaybackSession` 交給控制器的事件：關於目前這個來源的 [SourceEvent]，與
/// 不屬於任何來源的輸出事件（音訊中斷、拔耳機、輸出裝置失敗）。
@immutable
sealed class SessionEvent {
  const SessionEvent();
}

/// 關於目前這個來源的事件。
sealed class SourceEvent extends SessionEvent {
  const SourceEvent({required this.generation});

  /// 來源屬於哪一代（`PlaybackSession.generation`）。
  final int generation;
}

/// 開流中，或中途等資料。[wasReady]：之前回報過載入好。
final class SourceBuffering extends SourceEvent {
  const SourceBuffering({required super.generation, required this.wasReady});

  final bool wasReady;
}

/// 載入好了。[playing]：引擎有沒有在出聲；[wasReady]：之前回報過載入好。
final class SourceReady extends SourceEvent {
  const SourceReady({
    required super.generation,
    required this.playing,
    required this.wasReady,
  });

  final bool playing;
  final bool wasReady;
}

/// 引擎接上了前瞻：目前的來源結束（[end]），前瞻成為目前的來源。
final class LookAheadTookOver extends SourceEvent {
  const LookAheadTookOver({required super.generation, required this.end});

  final TrackEndReason end;
}

/// 播到結尾或提前結束（[end]），沒有前瞻可接。
final class SourceFinished extends SourceEvent {
  const SourceFinished({
    required super.generation,
    required this.pluginId,
    required this.end,
    required this.lastPosition,
  });

  final String pluginId;
  final TrackEndReason end;

  /// 最後回報的位置；沒回報過時為 `null`。
  final Duration? lastPosition;
}

/// 還沒載入就失敗：開不起來、格式解不了。[httpStatus] 是開流被 HTTP 拒絕時的
/// 狀態碼（只有 mpv 拿得到）。
final class SourceUnopenable extends SourceEvent {
  const SourceUnopenable({
    required super.generation,
    required this.pluginId,
    this.httpStatus,
  });

  final String pluginId;
  final int? httpStatus;
}

/// 已經在播之後中斷。
final class SourceInterrupted extends SourceEvent {
  const SourceInterrupted({
    required super.generation,
    required this.pluginId,
    required this.lastPosition,
  });

  final String pluginId;

  /// 最後回報的位置；沒回報過時為 `null`。
  final Duration? lastPosition;
}

/// 別的 App 拿走音訊焦點（Android 的來電、別的播放器；後端的 `Interrupted`）。
final class AudioInterrupted extends SessionEvent {
  const AudioInterrupted();
}

/// 音訊中斷結束（後端的 `InterruptionEnded`）。[resume]：暫停類的中斷結束、
/// 拿回了焦點。
final class AudioInterruptionEnded extends SessionEvent {
  const AudioInterruptionEnded({required this.resume});

  final bool resume;
}

/// 拔耳機、藍牙斷線（後端的 `BecameNoisy`）。
final class HeadphonesUnplugged extends SessionEvent {
  const HeadphonesUnplugged();
}

/// 音訊輸出裝置開不起來（後端的 `OutputDeviceFailed`）。
final class OutputDeviceLost extends SessionEvent {
  const OutputDeviceLost();
}

/// 收到事件當下，控制器的狀態裡路由要看的部分。
@immutable
final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.generation,
    required this.playWhenReady,
    required this.hasNext,
    required this.repeatsTrack,
    required this.resumeAt,
    required this.wantsSound,
    required this.pausedByInterruption,
  });

  /// 目前的代（`PlaybackSession.generation`）。
  final int generation;

  /// 使用者要不要出聲。
  final bool playWhenReady;

  /// 往下一首會換曲目（`QueueState.hasNext`；臨時播放中一律是：回到佇列）。
  final bool hasNext;

  /// 單曲循環：播完重播目前這首。
  final bool repeatsTrack;

  /// 沒有位置回報時，從哪裡重新開始。
  final Duration resumeAt;

  /// 使用者這時要的是出聲：在播、載入中、緩衝、等重試，而且沒按暫停。
  /// `Idle`、`Failed`、`Paused` 都不是。
  final bool wantsSound;

  /// 目前的暫停是音訊中斷造成的，中斷結束時續播。
  final bool pausedByInterruption;
}

/// [routePlaybackEvent] 的結論。
@immutable
sealed class EventAction {
  const EventAction();
}

/// 不處理：上一代的事件，或載入好了但 `play` 還在路上（之後會再回報）。
final class IgnoreEvent extends EventAction {
  const IgnoreEvent();
}

/// 改成 [state]（[Loading] 或 [Buffering]）。
final class ShowState extends EventAction {
  const ShowState(this.state);

  final PlaybackState state;
}

/// 記下來源載入好了，改成播放或暫停；[first] 時為下一首準備前瞻。
final class MarkReady extends EventAction {
  const MarkReady({required this.playing, required this.first});

  final bool playing;
  final bool first;
}

/// 接上前瞻：佇列往下，接上的那首不再解析。M1 不回頭重試交接時提前結束的
/// 上一首（[previousEndedEarly]），只記下來。
final class AdoptLookAhead extends EventAction {
  const AdoptLookAhead({required this.end});

  /// 上一首怎麼結束的。
  final TrackEndReason end;

  bool get previousEndedEarly => end == TrackEndReason.endedEarly;
}

/// 播完了，往下一首（前瞻沒來得及接上時照一般的下一首開始）。
final class PlayNextTrack extends EventAction {
  const PlayNextTrack();
}

/// 單曲循環的這首播完了，前瞻沒來得及接上：從頭再播一次（網址從快取拿）。
final class RepeatTrack extends EventAction {
  const RepeatTrack();
}

/// 播完了，佇列也到底：停在 [Idle]。
final class FinishQueue extends EventAction {
  const FinishQueue();
}

/// 交給 `decideRecovery`：[failure]、對使用者的 [error]、從 [position] 重來。
final class Recover extends EventAction {
  const Recover({
    required this.failure,
    required this.error,
    required this.position,
    this.endedEarly = false,
  });

  final PlaybackFailure failure;
  final AppError error;
  final Duration position;

  /// 提前結束：控制器先以 `log.report` 記下 [error]（後端沒有回報錯誤）。
  final bool endedEarly;
}

/// 因為音訊中斷暫停，中斷結束時續播。
final class PauseForInterruption extends EventAction {
  const PauseForInterruption();
}

/// 音訊中斷結束，而暫停是它造成的：續播。
final class ResumeAfterInterruption extends EventAction {
  const ResumeAfterInterruption();
}

/// 暫停，之後不自己續播：拔耳機（不從喇叭大聲播出來），以及不會續播的中斷
/// 結束。原本因中斷而暫停的也不再續播。
final class PauseWithoutResuming extends EventAction {
  const PauseWithoutResuming();
}

/// 輸出裝置開不起來：暫停並提示，不跳過（ADR 0018 §決定 7）。
final class PauseForOutputFailure extends EventAction {
  const PauseForOutputFailure();
}

/// [event] 在 [snapshot] 下該做什麼。
EventAction routePlaybackEvent(SessionEvent event, PlaybackSnapshot snapshot) =>
    switch (event) {
      SourceEvent() => _routeSourceEvent(event, snapshot),
      // 輸出事件不屬於任何來源，不比對代。只有原本在出聲才因中斷暫停：
      // 停著（`Idle`）的話續播會從頭開始一首沒在播的歌。
      AudioInterrupted() when snapshot.wantsSound =>
        const PauseForInterruption(),
      AudioInterrupted() => const IgnoreEvent(),
      // 使用者在中斷期間自己按了播放或暫停，暫停就不再是中斷造成的。
      AudioInterruptionEnded() when !snapshot.pausedByInterruption =>
        const IgnoreEvent(),
      AudioInterruptionEnded(resume: true) => const ResumeAfterInterruption(),
      AudioInterruptionEnded(resume: false) => const PauseWithoutResuming(),
      // 中斷期間拔掉耳機：中斷結束時也不續播。
      HeadphonesUnplugged()
          when snapshot.wantsSound || snapshot.pausedByInterruption =>
        const PauseWithoutResuming(),
      HeadphonesUnplugged() => const IgnoreEvent(),
      OutputDeviceLost() => const PauseForOutputFailure(),
    };

EventAction _routeSourceEvent(SourceEvent event, PlaybackSnapshot snapshot) {
  if (event.generation != snapshot.generation) return const IgnoreEvent();
  return switch (event) {
    SourceBuffering(:final wasReady) => ShowState(
      wasReady ? const Buffering() : const Loading(),
    ),
    // 第一次載入好卻沒在出聲，而使用者要出聲：play 還在路上。
    SourceReady(:final playing, :final wasReady)
        when !playing && !wasReady && snapshot.playWhenReady =>
      const IgnoreEvent(),
    SourceReady(:final playing, :final wasReady) => MarkReady(
      playing: playing,
      first: !wasReady,
    ),
    LookAheadTookOver(:final end) => AdoptLookAhead(end: end),
    SourceFinished(end: TrackEndReason.completed) when snapshot.repeatsTrack =>
      const RepeatTrack(),
    SourceFinished(end: TrackEndReason.completed) =>
      snapshot.hasNext ? const PlayNextTrack() : const FinishQueue(),
    SourceFinished(
      end: TrackEndReason.endedEarly,
      :final pluginId,
      :final lastPosition,
    ) =>
      Recover(
        failure: const StreamInterrupted(),
        error: NetworkError(pluginId: pluginId),
        position: lastPosition ?? snapshot.resumeAt,
        endedEarly: true,
      ),
    SourceUnopenable(:final pluginId, :final httpStatus) => Recover(
      failure: StreamUnopenable(httpStatus: httpStatus),
      error: openFailureError(pluginId, httpStatus),
      position: snapshot.resumeAt,
    ),
    SourceInterrupted(:final pluginId, :final lastPosition) => Recover(
      failure: const StreamInterrupted(),
      error: NetworkError(pluginId: pluginId),
      position: lastPosition ?? snapshot.resumeAt,
    ),
  };
}

/// 開流失敗最後跳過時給使用者的錯誤（design §7.5）：被 HTTP 404、410 拒絕是
/// 找不到；403 是取不到、原因不明（重新解析後仍被拒）；其他（解碼失敗、沒有
/// 狀態碼）對使用者是「播不了」，不是網路問題。
AppError openFailureError(String pluginId, int? httpStatus) =>
    switch (httpStatus) {
      404 || 410 => NotFound(pluginId: pluginId),
      403 => Unavailable(pluginId: pluginId),
      _ => Unsupported(pluginId: pluginId),
    };
