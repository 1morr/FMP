import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/recovery_policy.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// UI 唯一的播放入口（ADR 0018 §決定 1），也是 [PlaybackState] 唯一的寫入者。
///
/// 協作者只回報：[QueueModel] 保管佇列；[PlaybackSession] 解析、開流、前瞻，
/// 並把後端的回報過濾成 [SessionEvent]；[routePlaybackEvent] 決定事件要做什麼；
/// [decideRecovery] 決定失敗後怎麼辦。狀態只在這裡依它們的結果改。M1 只有播放
/// 一個清單、播放與暫停、上一首與下一首、seek。
///
/// 每個非同步步驟回來時以 [PlaybackSession.generation] 比對，代不同就丟掉結果。
final class PlaybackController {
  /// [session] 由控制器擁有，[dispose] 時一起釋放。
  PlaybackController({required this._session, required this._log}) {
    _sessionEvents = _session.events.listen(_onSessionEvent);
  }

  static const _tag = 'playback';

  final PlaybackSession _session;
  final Log _log;
  late final StreamSubscription<SessionEvent> _sessionEvents;

  final _queue = QueueModel();
  final _states = StreamController<PlaybackState>.broadcast();
  final _queueStates = StreamController<QueueState>.broadcast();

  PlaybackState _state = const Idle();

  /// 使用者要不要出聲：暫停中開始的一首載入後停在暫停。
  bool _playWhenReady = true;

  /// 等重試或暫停時，下次從哪裡開始。
  Duration _resumeAt = Duration.zero;
  Timer? _retryTimer;

  // RecoveryPolicy 的計數，只在這裡改。
  int _retries = 0;
  bool _candidateSwitched = false;
  int _consecutiveSkips = 0;

  PlaybackState get state => _state;

  /// 狀態的變化（只在改變時發出）。
  Stream<PlaybackState> get states => _states.stream;

  QueueState get queue => _queue.state;

  Stream<QueueState> get queueStates => _queueStates.stream;

  /// 目前這首的位置、時長與緩衝。
  Stream<PlaybackProgress> get progress => _session.progress;

  /// 以 [tracks] 取代佇列，從 [startIndex] 開始播。超過佇列上限時整批不加、
  /// 什麼都不做。
  Future<void> playQueue(List<TrackInfo> tracks, {int startIndex = 0}) {
    if (!_queue.replace(tracks, startIndex: startIndex)) return Future.value();
    _emitQueue();
    _consecutiveSkips = 0;
    _playWhenReady = true;
    if (_queue.state.current == null) return _stopWith(const Idle());
    return _beginTrack();
  }

  Future<void> play() async {
    _playWhenReady = true;
    switch (_state) {
      case Paused() || Loading() || Buffering():
        if (_session.hasSource) {
          await _session.play();
        } else if (_state is Paused) {
          // 等重試時被暫停：重新開始這一首。
          await _load(position: _resumeAt);
        }
      case Idle() || Failed():
        if (_queue.state.current == null) return;
        _consecutiveSkips = 0;
        await _beginTrack();
      case Playing() || Retrying():
        return;
    }
  }

  Future<void> pause() async {
    _playWhenReady = false;
    switch (_state) {
      case Playing() || Buffering() || Loading():
        if (_session.hasSource) await _session.pause();
      case Retrying():
        _cancelRetry();
        _setState(const Paused());
      case Paused() || Idle() || Failed():
        return;
    }
  }

  /// 下一首；已經是最後一首就不動。
  Future<void> next() {
    final next = _queue.next;
    if (next == null) return Future.value();
    final prepared = _session.takeLookAhead(next.index);
    _queue.moveNext();
    _emitQueue();
    _consecutiveSkips = 0;
    return _beginTrack(prepared: prepared);
  }

  /// 上一首；已經是第一首就回到這首的開頭。播放位置還沒接上（傳 0），所以
  /// 「播超過 3 秒回到開頭」不生效。
  Future<void> previous() {
    if (_queue.movePrevious(position: Duration.zero) is! MovedToTrack) {
      return seek(Duration.zero);
    }
    _emitQueue();
    _consecutiveSkips = 0;
    return _beginTrack();
  }

  Future<void> seek(Duration position) async {
    if (!_session.hasSource) {
      _resumeAt = position;
      return;
    }
    await _session.seek(position);
  }

  Future<void> dispose() async {
    _cancelRetry();
    // dispose 的同步部分先換一代：還在進行的解析回來時不再開流或設定前瞻。
    await _session.dispose();
    await _sessionEvents.cancel();
    await _states.close();
    await _queueStates.close();
  }

  // ---- 開始一首 -------------------------------------------------------------

  /// 換到佇列目前這首：重設這首的恢復計數。
  Future<void> _beginTrack({ResolvedStream? prepared}) {
    _retries = 0;
    _candidateSwitched = false;
    return _load(prepared: prepared);
  }

  /// 解析（或用 [prepared]）並交給後端，從 [position] 開始。
  Future<void> _load({
    Duration position = Duration.zero,
    ResolvedStream? prepared,
  }) async {
    final key = _queue.state.current?.key;
    if (key == null) return;
    final generation = _session.beginRequest();
    _cancelRetry();
    _resumeAt = position;
    _setState(const Loading());
    _log.info(
      'Track requested',
      tag: _tag,
      fields: {'track': '$key', 'queueIndex': _queue.state.currentIndex},
    );

    final ResolvedStream stream;
    if (prepared != null && _session.isFresh(prepared)) {
      stream = prepared;
    } else {
      if (prepared != null) {
        _log.info(
          'Look-ahead expired; resolving again',
          tag: _tag,
          fields: {'track': '$key'},
        );
      }
      try {
        stream = await _session.resolve(key);
      } on AppError catch (error) {
        if (generation != _session.generation) return;
        _log.report('Stream resolution failed', error, tag: _tag);
        return _recover(ResolveFailed(error), error, position);
      }
      if (generation != _session.generation) return;
    }
    // 解析期間的 seek 記在 _resumeAt。
    await _session.open(stream, position: _resumeAt, play: _playWhenReady);
  }

  // ---- 後端回報 -------------------------------------------------------------

  void _onSessionEvent(SessionEvent event) {
    final action = routePlaybackEvent(
      event,
      PlaybackSnapshot(
        generation: _session.generation,
        playWhenReady: _playWhenReady,
        hasNext: _queue.next != null,
        resumeAt: _resumeAt,
      ),
    );
    switch (action) {
      case IgnoreEvent():
        return;
      case ShowState(:final state):
        _setState(state);
      case MarkReady(:final playing, :final first):
        _session.markReady();
        _setState(playing ? const Playing() : const Paused());
        if (playing) _consecutiveSkips = 0;
        if (first) unawaited(_session.prepareLookAhead(_nextTrack));
      case AdoptLookAhead():
        _session.adoptLookAhead(action);
        _queue.moveNext();
        _emitQueue();
        _retries = 0;
        _candidateSwitched = false;
        unawaited(_session.prepareLookAhead(_nextTrack));
      case PlayNextTrack():
        // 前瞻沒來得及接上（例如還在解析）：照一般的下一首開始。路由器只在
        // 佇列還有下一首時給這個動作。
        final next = _queue.next!;
        final prepared = _session.takeLookAhead(next.index);
        _queue.moveNext();
        _emitQueue();
        unawaited(_beginTrack(prepared: prepared));
      case FinishQueue():
        _log.info('Queue finished', tag: _tag);
        _session.release();
        _resumeAt = Duration.zero;
        _setState(const Idle());
      case Recover(:final failure, :final error, :final position):
        if (action.endedEarly) {
          _log.report('Stream ended early', error, tag: _tag);
        }
        // 串流本身失敗了：網址不再從快取拿，重試與之後再播都重新解析。
        _session.invalidateCurrentStream();
        unawaited(_recover(failure, error, position));
    }
  }

  // ---- 恢復 -----------------------------------------------------------------

  Future<void> _recover(
    PlaybackFailure failure,
    AppError error,
    Duration position,
  ) async {
    final action = decideRecovery(
      failure,
      retries: _retries,
      candidateSwitched: _candidateSwitched,
      hasOtherCandidate: _session.hasOtherCandidate,
      consecutiveSkips: _consecutiveSkips,
      queueLength: _queue.state.entries.length,
    );
    _log.info(
      'Playback recovery',
      tag: _tag,
      fields: {
        'track': '${_queue.state.current?.key}',
        'error': error.typeName,
        'action': switch (action) {
          RetryAfter() => 'retry',
          TryNextCandidate() => 'nextCandidate',
          SkipTrack() => 'skip',
          StopPlayback() => 'stop',
        },
      },
    );
    switch (action) {
      case RetryAfter(:final delay, :final attempt):
        _retries++;
        final generation = _session.newGeneration();
        _resumeAt = position;
        _setState(Retrying(error: error, attempt: attempt, delay: delay));
        _retryTimer = Timer(delay, () {
          _retryTimer = null;
          if (generation == _session.generation) {
            // 等待期間的 seek 記在 _resumeAt。
            unawaited(_load(position: _resumeAt));
          }
        });
      case TryNextCandidate():
        _candidateSwitched = true;
        await _session.openNextCandidate(
          position: position,
          play: _playWhenReady,
        );
      case SkipTrack():
        _consecutiveSkips++;
        final next = _queue.next;
        if (next == null) return _stopWith(Failed(error));
        final prepared = _session.takeLookAhead(next.index);
        _queue.moveNext();
        _emitQueue();
        await _beginTrack(prepared: prepared);
      case StopPlayback():
        await _stopWith(Failed(error));
    }
  }

  Future<void> _stopWith(PlaybackState state) async {
    _session.newGeneration();
    _cancelRetry();
    _setState(state);
    await _session.stop();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ---- 輸出 -----------------------------------------------------------------

  void _setState(PlaybackState state) {
    // 沒有欄位的狀態是 const 單例；Retrying、Failed 每次都是新的。
    if (identical(state, _state)) return;
    _state = state;
    _log.debug(
      'Playback state',
      tag: _tag,
      fields: {
        'state': switch (state) {
          Idle() => 'idle',
          Loading() => 'loading',
          Playing() => 'playing',
          Paused() => 'paused',
          Buffering() => 'buffering',
          Retrying() => 'retrying',
          Failed() => 'failed',
        },
      },
    );
    if (!_states.isClosed) _states.add(state);
  }

  /// 佇列的下一首，給前瞻用。
  NextTrack? _nextTrack() => switch (_queue.next) {
    (:final index, :final track)? => (index: index, track: track.key),
    null => null,
  };

  void _emitQueue() {
    if (!_queueStates.isClosed) _queueStates.add(_queue.state);
  }
}
