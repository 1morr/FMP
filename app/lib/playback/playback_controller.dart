import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/recovery_policy.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// 臨時播放回到佇列時要的兩個設定值（「播放」設定組），在回到佇列的當下讀。
typedef TemporaryReturnSettings = ({bool rememberPosition, Duration rewind});

/// UI 唯一的播放入口（ADR 0018 §決定 1），也是 [PlaybackState] 唯一的寫入者。
///
/// 協作者只回報：[QueueModel] 保管佇列；[PlaybackSession] 解析、開流、前瞻，
/// 並把後端的回報過濾成 [SessionEvent]；[routePlaybackEvent] 決定事件要做什麼；
/// [decideRecovery] 決定失敗後怎麼辦。狀態只在這裡依它們的結果改。
///
/// 佇列的每個編輯都重新指定前瞻（[PlaybackSession.retargetLookAhead]），引擎接上
/// 的一定是佇列當下的下一首。臨時播放中不準備佇列的前瞻：臨時曲目播完回到的那
/// 一首要從快照的位置開始，不能由引擎從頭接上（舊版「臨時播放不預取」）。單曲
/// 循環的前瞻是目前這首的同一份解析結果，接上時佇列不動。
///
/// 每個非同步步驟回來時以 [PlaybackSession.generation] 比對，代不同就丟掉結果。
final class PlaybackController {
  /// [session] 由控制器擁有，[dispose] 時一起釋放。[temporaryReturnSettings]
  /// 在臨時播放回到佇列時讀。
  PlaybackController({
    required this._session,
    required this._log,
    required this._temporaryReturnSettings,
  }) {
    _sessionEvents = _session.events.listen(_onSessionEvent);
  }

  static const _tag = 'playback';

  final PlaybackSession _session;
  final Log _log;
  final TemporaryReturnSettings Function() _temporaryReturnSettings;
  late final StreamSubscription<SessionEvent> _sessionEvents;

  final _queue = QueueModel();
  final _states = StreamController<PlaybackState>.broadcast();
  final _queueStates = StreamController<QueueState>.broadcast();
  final _events = StreamController<PlaybackEvent>.broadcast();

  PlaybackState _state = const Idle();

  /// 使用者要不要出聲：暫停中開始的一首載入後停在暫停。
  bool _playWhenReady = true;

  /// 等重試或暫停時，下次從哪裡開始。
  Duration _resumeAt = Duration.zero;
  Timer? _retryTimer;

  /// 臨時播放結束時要不要載入佇列那一首：進入臨時播放時那一首有載入（在播或
  /// 暫停）才載入；原本停著（`Idle`、`Failed`、佇列是空的）就停在 `Idle`。
  bool _returnLoadsQueueTrack = false;

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

  /// 使用者要知道的一次性事件（佇列滿了等，design §7.9）。
  Stream<PlaybackEvent> get events => _events.stream;

  // ---- 佇列 -----------------------------------------------------------------

  /// 臨時播放 [track]（D1）：不放進佇列，播完或按上一首、下一首回到佇列進入
  /// 時的那一首。已經在臨時播放時只換曲目，回到的點不變。
  Future<void> playTemporary(TrackInfo track) {
    if (_queue.state.mode == QueueMode.queue) {
      _returnLoadsQueueTrack = switch (_state) {
        Idle() || Failed() => false,
        Loading() || Playing() || Paused() || Buffering() || Retrying() => true,
      };
    }
    _queue.playTemporary(track, position: _position, playing: _wantsSound);
    _emitQueue();
    _consecutiveSkips = 0;
    _playWhenReady = true;
    return _beginTrack();
  }

  /// 加在佇列最後。會超過佇列上限就整批不加、發 [QueueFull]，回傳 `false`。
  /// 佇列原本是空的時第一首成為目前這首，但不開始播。
  bool addToQueue(List<TrackInfo> tracks) => _add(tracks, _queue.append);

  /// 下一首播放：排在目前這首（臨時播放中是回到的那一首）之後，接在之前連續
  /// 加入的後面。會超過上限就整批不加、發 [QueueFull]，回傳 `false`。
  bool playNext(List<TrackInfo> tracks) => _add(tracks, _queue.playNext);

  /// 從頭播佇列位置 [index] 的歌（在佇列中點選）；臨時播放就此結束。
  Future<void> jumpTo(int index) {
    final prepared = _session.takeLookAhead(index);
    _queue.jumpTo(index);
    _emitQueue();
    _consecutiveSkips = 0;
    _playWhenReady = true;
    return _beginTrack(prepared: prepared);
  }

  /// 移除佇列位置 [index]。移除的是正在播的那一首時換到佇列的下一首，沒有下一
  /// 首就是前一首（`QueueModel.remove`；暫停中就載入後停著）；佇列因此空了就停
  /// 在 `Idle`。
  Future<void> removeAt(int index) {
    final before = _queue.state;
    final removesPlaying =
        before.mode == QueueMode.queue && index == before.currentIndex;
    _queue.remove(index);
    if (!removesPlaying) {
      _queueEdited();
      return Future.value();
    }
    _emitQueue();
    switch (_state) {
      case Idle() || Failed():
        _resumeAt = Duration.zero;
        return _stopWith(const Idle());
      case Loading() || Playing() || Paused() || Buffering() || Retrying():
        if (_queue.state.current == null) {
          _resumeAt = Duration.zero;
          return _stopWith(const Idle());
        }
        _consecutiveSkips = 0;
        return _beginTrack();
    }
  }

  /// 把佇列位置 [from] 的歌拖到 [to]。播的歌不變。
  void move(int from, int to) {
    _queue.move(from, to);
    _queueEdited();
  }

  /// 清空佇列並停在 `Idle`（臨時播放也一起結束）。
  Future<void> clear() {
    _queue.clear();
    _emitQueue();
    _resumeAt = Duration.zero;
    return _stopWith(const Idle());
  }

  void setShuffle(bool enabled) {
    _queue.setShuffle(enabled);
    _queueEdited();
  }

  /// 循環依關閉 → 全部 → 單曲輪轉。
  void cycleLoopMode() {
    _queue.cycleLoopMode();
    _queueEdited();
  }

  // ---- 播放 -----------------------------------------------------------------

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

  /// 下一首（`QueueState.hasNext` 為假就不動）。臨時播放中是回到佇列；佇列
  /// 是空的時就此停在 `Idle`。
  Future<void> next() {
    if (!_queue.state.hasNext) return Future.value();
    _consecutiveSkips = 0;
    return _moveNext();
  }

  /// 上一首：播超過 3 秒（`QueueModel.restartThreshold`）回到這首的開頭，否則
  /// 往前一首；前面沒有歌也回到開頭。臨時播放中是回到佇列。
  Future<void> previous() {
    final step = _queue.movePrevious(position: _position);
    if (step is MovedToTrack || step is ReturnedToQueue) {
      _emitQueue();
      _consecutiveSkips = 0;
    }
    return _follow(step);
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
    await _events.close();
  }

  // ---- 換曲目 ---------------------------------------------------------------

  /// 往下一首（按下一首、播完、被跳過）：佇列的前瞻解析結果沿用。
  Future<void> _moveNext() {
    final next = _queue.next;
    final prepared = next == null ? null : _session.takeLookAhead(next.index);
    final step = _queue.moveNext();
    _emitQueue();
    return _follow(step, prepared: prepared);
  }

  /// 照佇列換曲目的結果開始播。
  Future<void> _follow(QueueStep step, {ResolvedStream? prepared}) =>
      switch (step) {
        MovedToTrack() => _beginTrack(prepared: prepared),
        RestartTrack() => seek(Duration.zero),
        ReturnedToQueue(:final snapshot) => _returnToQueue(snapshot),
        QueueUnchanged() => Future.value(),
      };

  /// 臨時播放結束、回到佇列的那一首（design §7.2）：「記住播放位置」開著時從
  /// 快照的位置倒退設定的秒數，否則從頭；原本在播才自動播。佇列是空的，或進入
  /// 時那一首沒有載入，就停在 `Idle`（播放列顯示那一首）。
  Future<void> _returnToQueue(QueueSnapshot snapshot) {
    final track = _queue.state.current;
    if (track == null || !_returnLoadsQueueTrack) {
      _log.info(
        'Temporary play ended; the queue stays idle',
        tag: _tag,
        fields: {'track': '${track?.key}'},
      );
      _resumeAt = Duration.zero;
      return _stopWith(const Idle());
    }
    final settings = _temporaryReturnSettings();
    final position = snapshot.resumeAt(
      rememberPosition: settings.rememberPosition,
      rewind: settings.rewind,
    );
    _log.info(
      'Temporary play ended; returning to the queue',
      tag: _tag,
      fields: {
        'track': '${track.key}',
        'snapshotPositionMs': snapshot.position.inMilliseconds,
        'resumeAtMs': position.inMilliseconds,
        'play': snapshot.playing,
      },
    );
    _playWhenReady = snapshot.playing;
    return _beginTrack(position: position);
  }

  bool _add(List<TrackInfo> tracks, bool Function(List<TrackInfo>) add) {
    if (!add(tracks)) {
      _log.info(
        'Queue full; nothing added',
        tag: _tag,
        fields: {
          'adding': tracks.length,
          'queueLength': _queue.state.entries.length,
        },
      );
      if (!_events.isClosed) {
        _events.add(QueueFull(limit: QueueModel.maxLength));
      }
      return false;
    }
    _queueEdited();
    return true;
  }

  // ---- 開始一首 -------------------------------------------------------------

  /// 開始目前這首（[QueueState.current]），從 [position] 起：重設這首的恢復
  /// 計數。
  Future<void> _beginTrack({
    ResolvedStream? prepared,
    Duration position = Duration.zero,
  }) {
    _retries = 0;
    _candidateSwitched = false;
    return _load(prepared: prepared, position: position);
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
      fields: {
        'track': '$key',
        'queueIndex': _queue.state.currentIndex,
        if (_queue.state.mode == QueueMode.temporary) 'temporary': true,
      },
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
        hasNext: _queue.state.hasNext,
        repeatsTrack: _queue.state.loopMode == LoopMode.one,
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
        // 單曲循環的前瞻是同一首：佇列不動。佇列的前瞻一定是佇列當下的下一首
        // （每次編輯都重新指定），臨時播放中沒有佇列的前瞻。
        if (!_session.adoptLookAhead(action)) {
          _queue.moveNext();
          _emitQueue();
        }
        _retries = 0;
        _candidateSwitched = false;
        unawaited(_session.prepareLookAhead(_nextTrack));
      case RepeatTrack():
        // 單曲循環而前瞻沒來得及接上：從頭再播，網址從快取拿。
        unawaited(_beginTrack());
      case PlayNextTrack():
        // 前瞻沒來得及接上（例如還在解析）：照一般的下一首開始；臨時播放中是
        // 回到佇列。路由器只在 hasNext 時給這個動作。
        unawaited(_moveNext());
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
        // 臨時播放中是回到佇列（佇列是空的時沒有可去的地方，停下）。
        if (_queue.next == null) return _stopWith(Failed(error));
        await _moveNext();
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

  /// 目前這首播到的位置：來源最後回報的；沒有來源（解析中、等重試）時是下次
  /// 開始的位置。
  Duration get _position => _session.position ?? _resumeAt;

  /// 使用者這時要的是出聲（在播、載入中、等重試，而且沒按暫停）。
  bool get _wantsSound =>
      _playWhenReady &&
      switch (_state) {
        Loading() || Playing() || Buffering() || Retrying() => true,
        Idle() || Paused() || Failed() => false,
      };

  /// 前瞻要接的曲目：單曲循環是目前這首（佇列不動），臨時播放中沒有，否則是
  /// 佇列的下一首。
  NextTrack? _nextTrack() {
    final queue = _queue.state;
    final current = queue.current;
    if (current == null) return null;
    if (queue.loopMode == LoopMode.one) {
      return (index: null, track: current.key);
    }
    if (queue.mode == QueueMode.temporary) return null;
    return switch (_queue.next) {
      (:final index, :final track)? => (index: index, track: track.key),
      null => null,
    };
  }

  /// 佇列編輯過：發出新的佇列，前瞻改指新的下一首。
  void _queueEdited() {
    _emitQueue();
    unawaited(_session.retargetLookAhead(_nextTrack));
  }

  void _emitQueue() {
    if (!_queueStates.isClosed) _queueStates.add(_queue.state);
  }
}
