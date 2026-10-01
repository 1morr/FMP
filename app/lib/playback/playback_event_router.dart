import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/recovery_policy.dart';

// 後端事件變成控制器的哪個動作（ADR 0018 §決定 1）：純函數，不碰後端、計時器
// 與 log。
//
// `PlaybackSession` 把後端的狀態與事件過濾成目前這個來源的 [SessionEvent]
// （帶它屬於哪一代），控制器連同自己的 [PlaybackSnapshot] 交給
// [routePlaybackEvent]，照回傳的 [EventAction] 改狀態。事件型別放在這裡而不是
// `PlaybackSession`：結束原因 [TrackEndReason] 只准後端與這裡 import
// （`fmp_layer_imports` 的 `restrictedImports`）。

/// `PlaybackSession` 交給控制器的事件，都是關於目前這個來源的。
@immutable
sealed class SessionEvent {
  const SessionEvent({required this.generation});

  /// 來源屬於哪一代（`PlaybackSession.generation`）。
  final int generation;
}

/// 開流中，或中途等資料。[wasReady]：之前回報過載入好。
final class SourceBuffering extends SessionEvent {
  const SourceBuffering({required super.generation, required this.wasReady});

  final bool wasReady;
}

/// 載入好了。[playing]：引擎有沒有在出聲；[wasReady]：之前回報過載入好。
final class SourceReady extends SessionEvent {
  const SourceReady({
    required super.generation,
    required this.playing,
    required this.wasReady,
  });

  final bool playing;
  final bool wasReady;
}

/// 引擎接上了前瞻：目前的來源結束（[end]），前瞻成為目前的來源。
final class LookAheadTookOver extends SessionEvent {
  const LookAheadTookOver({required super.generation, required this.end});

  final TrackEndReason end;
}

/// 播到結尾或提前結束（[end]），沒有前瞻可接。
final class SourceFinished extends SessionEvent {
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

/// 還沒載入就失敗：開不起來、格式解不了。
final class SourceUnopenable extends SessionEvent {
  const SourceUnopenable({required super.generation, required this.pluginId});

  final String pluginId;
}

/// 已經在播之後中斷。
final class SourceInterrupted extends SessionEvent {
  const SourceInterrupted({
    required super.generation,
    required this.pluginId,
    required this.lastPosition,
  });

  final String pluginId;

  /// 最後回報的位置；沒回報過時為 `null`。
  final Duration? lastPosition;
}

/// 收到事件當下，控制器的狀態裡路由要看的部分。
@immutable
final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.generation,
    required this.playWhenReady,
    required this.hasNext,
    required this.resumeAt,
  });

  /// 目前的代（`PlaybackSession.generation`）。
  final int generation;

  /// 使用者要不要出聲。
  final bool playWhenReady;

  /// 佇列裡還有下一首。
  final bool hasNext;

  /// 沒有位置回報時，從哪裡重新開始。
  final Duration resumeAt;
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

/// [event] 在 [snapshot] 下該做什麼。
EventAction routePlaybackEvent(SessionEvent event, PlaybackSnapshot snapshot) {
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
    // 開不起來、解不了：對使用者是「播不了」，不是網路問題。
    SourceUnopenable(:final pluginId) => Recover(
      failure: const StreamUnopenable(),
      error: Unsupported(pluginId: pluginId),
      position: snapshot.resumeAt,
    ),
    SourceInterrupted(:final pluginId, :final lastPosition) => Recover(
      failure: const StreamInterrupted(),
      error: NetworkError(pluginId: pluginId),
      position: lastPosition ?? snapshot.resumeAt,
    ),
  };
}
