import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/recovery_policy.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// UI 唯一的播放入口（ADR 0018 §決定 1），也是 [PlaybackState] 唯一的寫入者。
///
/// 協作者只回報：[QueueModel] 保管佇列、[StreamResolver] 解析、
/// [decideRecovery] 決定失敗後怎麼辦、[AudioBackend] 播放並回報事件；狀態只在
/// 這裡依它們的結果改。M1 只有播放一個清單、播放與暫停、上一首與下一首、seek。
///
/// 前瞻（ADR 0018 §決定 3、6）：目前這首載入好之後，解析下一首一次、交給後端
/// 的 [AudioBackend.setNext]；後端自己接上（[SourceAdvanced]），接上的那首不再
/// 解析。候選有期限時，在過期前（[ResolvedStream.expiryMargin]）重新解析並換掉
/// 前瞻；手動下一首時也先檢查。
///
/// 每次開始一首（含重試、換候選、接上前瞻）都換一個「代」：還在進行的解析
/// 回來時代已經不同，結果就丟掉。插件的 `resolveStream` 沒有取消參數，M1 不
/// 取消網路工作（ADR 0018 §決定 6 的取消在插件 API 支援後接上）。
final class PlaybackController {
  PlaybackController({
    required this._backend,
    required this._resolver,
    required this._log,
    this._now = DateTime.now,
  }) {
    _subscriptions
      ..add(_backend.status.listen(_onStatus))
      ..add(_backend.progress.listen(_onProgress))
      ..add(_backend.events.listen(_onEvent));
  }

  static const _tag = 'playback';

  final AudioBackend _backend;
  final StreamResolver _resolver;
  final Log _log;
  final DateTime Function() _now;
  final _subscriptions = <StreamSubscription<Object?>>[];

  final _queue = QueueModel();
  final _states = StreamController<PlaybackState>.broadcast();
  final _queueStates = StreamController<QueueState>.broadcast();
  final _progress = StreamController<PlaybackProgress>.broadcast();

  PlaybackState _state = const Idle();

  int _generation = 0;
  int _lastSourceId = 0;

  /// 交給後端的目前來源；解析中、等重試、停下時為 `null`。
  _Current? _current;
  _LookAhead? _lookAhead;

  /// 已經為哪一代要求過前瞻（每首只解析一次）。
  int? _lookAheadFor;

  /// 使用者要不要出聲：暫停中開始的一首載入後停在暫停。
  bool _playWhenReady = true;

  /// 等重試或暫停時，下次從哪裡開始。
  Duration _resumeAt = Duration.zero;
  Timer? _retryTimer;

  // RecoveryPolicy 的計數，只在這裡改。
  int _retries = 0;
  bool _candidateSwitched = false;
  int _consecutiveSkips = 0;

  // 交接的量測（實機驗證用，見 app/AGENTS.md § 播放）。
  DateTime? _requestedAt;
  _Handover? _handover;
  DateTime? _lastProgressAt;

  PlaybackState get state => _state;

  /// 狀態的變化（只在改變時發出）。
  Stream<PlaybackState> get states => _states.stream;

  QueueState get queue => _queue.state;

  Stream<QueueState> get queueStates => _queueStates.stream;

  /// 目前這首的位置、時長與緩衝。
  Stream<PlaybackProgress> get progress => _progress.stream;

  /// 以 [tracks] 取代佇列，從 [startIndex] 開始播。
  Future<void> playQueue(List<TrackKeyParts> tracks, {int startIndex = 0}) {
    _queue.replace(tracks, startIndex: startIndex);
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
        if (_current != null) {
          await _backend.play();
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
        if (_current != null) await _backend.pause();
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
    final prepared = _takeLookAhead(next.index);
    _queue.moveNext();
    _emitQueue();
    _consecutiveSkips = 0;
    return _beginTrack(prepared: prepared);
  }

  /// 上一首；已經是第一首就回到這首的開頭。
  Future<void> previous() {
    if (!_queue.movePrevious()) return seek(Duration.zero);
    _emitQueue();
    _consecutiveSkips = 0;
    return _beginTrack();
  }

  Future<void> seek(Duration position) async {
    if (_current == null) {
      _resumeAt = position;
      return;
    }
    await _backend.seek(position);
  }

  Future<void> dispose() async {
    // 換一代：還在進行的解析回來時不再開流或設定前瞻。
    _generation++;
    _current = null;
    _cancelRetry();
    _clearLookAhead();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _states.close();
    await _queueStates.close();
    await _progress.close();
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
    final track = _queue.state.current;
    if (track == null) return;
    final generation = ++_generation;
    _cancelRetry();
    _clearLookAhead();
    _current = null;
    _handover = null;
    _resumeAt = position;
    _requestedAt = _now();
    _setState(const Loading());
    _log.info(
      'Track requested',
      tag: _tag,
      fields: {'track': '$track', 'queueIndex': _queue.state.currentIndex},
    );

    final ResolvedStream stream;
    if (prepared != null && prepared.isFreshAt(_now())) {
      stream = prepared;
    } else {
      if (prepared != null) {
        _log.info(
          'Look-ahead expired; resolving again',
          tag: _tag,
          fields: {'track': '$track'},
        );
      }
      // 解析期間不讓上一首繼續出聲。
      unawaited(_backend.stop());
      try {
        stream = await _resolver.resolve(track);
      } on AppError catch (error) {
        if (generation != _generation) return;
        _log.report('Stream resolution failed', error, tag: _tag);
        return _recover(ResolveFailed(error), error, position);
      }
      if (generation != _generation) return;
    }
    // 解析期間的 seek 記在 _resumeAt。
    await _open(stream, candidate: 0, position: _resumeAt);
  }

  Future<void> _open(
    ResolvedStream stream, {
    required int candidate,
    required Duration position,
  }) async {
    final generation = _generation;
    final chosen = stream.candidates[candidate];
    final source = BackendSource(
      id: ++_lastSourceId,
      url: chosen.url,
      headers: chosen.headers,
    );
    _current = _Current(
      generation: generation,
      sourceId: source.id,
      stream: stream,
      candidate: candidate,
    );
    _log.info(
      'Opening stream',
      tag: _tag,
      fields: {
        'track': '${stream.track}',
        'candidate': candidate,
        'container': ?chosen.container,
        'codec': ?chosen.codec,
        // 只記名稱：值可能是 User-Agent 以外的識別資訊。
        'headers': source.headers.keys.toList(),
      },
    );
    await _backend.open(source, start: position, play: _playWhenReady);
  }

  // ---- 前瞻 -----------------------------------------------------------------

  /// 為目前這一代解析下一首一次，交給後端。
  Future<void> _prepareLookAhead() async {
    final current = _current;
    if (current == null || _lookAheadFor == current.generation) return;
    _lookAheadFor = current.generation;
    final next = _queue.next;
    if (next == null) return;
    final ResolvedStream stream;
    try {
      stream = await _resolver.resolve(next.track);
    } on AppError catch (error) {
      // 到那一首時再依錯誤處理（重新解析一次）。
      _log.report('Look-ahead resolution failed', error, tag: _tag);
      return;
    }
    if (_current?.generation != current.generation ||
        _queue.next?.index != next.index) {
      return;
    }
    await _setLookAhead(next.index, stream);
  }

  Future<void> _setLookAhead(int queueIndex, ResolvedStream stream) async {
    _clearLookAhead();
    final chosen = stream.candidates.first;
    final source = BackendSource(
      id: ++_lastSourceId,
      url: chosen.url,
      headers: chosen.headers,
    );
    final lookAhead = _lookAhead = _LookAhead(
      queueIndex: queueIndex,
      stream: stream,
      sourceId: source.id,
    );
    final refreshAt = stream.refreshAt;
    if (refreshAt != null) {
      final delay = refreshAt.difference(_now());
      // 一解析出來就快過期的不排：手動下一首時會再檢查。
      if (delay > Duration.zero) {
        lookAhead.refresh = Timer(delay, () => _refreshLookAhead(lookAhead));
      }
    }
    _log.info(
      'Look-ahead prepared',
      tag: _tag,
      fields: {'track': '${stream.track}'},
    );
    await _backend.setNext(source);
  }

  /// 前瞻的網址快過期了：重新解析並換掉。
  Future<void> _refreshLookAhead(_LookAhead lookAhead) async {
    if (!identical(_lookAhead, lookAhead)) return;
    final ResolvedStream stream;
    try {
      stream = await _resolver.resolve(lookAhead.stream.track);
    } on AppError catch (error) {
      _log.report('Look-ahead refresh failed', error, tag: _tag);
      return;
    }
    if (!identical(_lookAhead, lookAhead)) return;
    _log.info(
      'Look-ahead refreshed before expiry',
      tag: _tag,
      fields: {'track': '${stream.track}'},
    );
    await _setLookAhead(lookAhead.queueIndex, stream);
  }

  /// 取走位置 [queueIndex] 的前瞻解析結果（手動下一首、跳過時沿用）。
  ResolvedStream? _takeLookAhead(int queueIndex) {
    final lookAhead = _lookAhead;
    if (lookAhead == null || lookAhead.queueIndex != queueIndex) return null;
    _clearLookAhead();
    return lookAhead.stream;
  }

  void _clearLookAhead() {
    _lookAhead?.refresh?.cancel();
    _lookAhead = null;
  }

  // ---- 後端回報 -------------------------------------------------------------

  void _onStatus(BackendStatus status) {
    final current = _current;
    if (current == null || status.sourceId != current.sourceId) return;
    switch (status.phase) {
      case BackendPhase.buffering:
        _setState(current.ready ? const Buffering() : const Loading());
      case BackendPhase.ready:
        final firstReady = !current.ready;
        if (!status.playing && firstReady && _playWhenReady) {
          // 載入好了，play 還在路上。
          return;
        }
        current.ready = true;
        _setState(status.playing ? const Playing() : const Paused());
        if (status.playing) _consecutiveSkips = 0;
        if (firstReady) unawaited(_prepareLookAhead());
      case BackendPhase.idle || BackendPhase.ended:
        return;
    }
  }

  void _onProgress(SourceProgress sourceProgress) {
    final current = _current;
    if (current == null || sourceProgress.sourceId != current.sourceId) return;
    final progress = sourceProgress.progress;
    current.progress = progress;
    final now = _now();
    _lastProgressAt = now;
    if (!current.audible && progress.position > Duration.zero) {
      current.audible = true;
      _logAudible(current, now);
    }
    if (!_progress.isClosed) _progress.add(progress);
  }

  void _onEvent(BackendEvent event) {
    switch (event) {
      case SourceAdvanced(:final from, :final to, :final end):
        _onAdvanced(from, to, end);
      case SourceEnded(:final id, :final end):
        final current = _current;
        if (current == null || id != current.sourceId) return;
        _onEnded(current, end);
      case SourceFailed(:final id, :final failure, :final cause):
        final current = _current;
        if (current == null || id != current.sourceId) return;
        _onFailed(current, failure, cause);
    }
  }

  void _onAdvanced(int from, int to, TrackEndReason end) {
    final current = _current;
    final lookAhead = _lookAhead;
    if (current == null ||
        current.sourceId != from ||
        lookAhead == null ||
        lookAhead.sourceId != to) {
      return;
    }
    final now = _now();
    final previous = current.progress;
    final lastProgressAt = _lastProgressAt;
    _log.info(
      'Look-ahead handover',
      tag: _tag,
      fields: {
        'from': '${current.stream.track}',
        'to': '${lookAhead.stream.track}',
        'end': end.name,
        'previousPositionMs': ?previous?.position.inMilliseconds,
        'previousDurationMs': ?previous?.duration?.inMilliseconds,
        if (lastProgressAt != null)
          'sinceLastProgressMs': now.difference(lastProgressAt).inMilliseconds,
      },
    );
    if (end == TrackEndReason.endedEarly) {
      // M1 不回頭重試已經交接掉的那一首，只記下來。
      _log.warning(
        'The previous track ended early at the handover',
        tag: _tag,
        fields: {'track': '${current.stream.track}'},
      );
    }
    _clearLookAhead();
    _queue.moveNext();
    _emitQueue();
    _retries = 0;
    _candidateSwitched = false;
    _handover = _Handover(
      at: now,
      previousEnd: _estimatedEnd(previous, lastProgressAt),
    );
    _current = _Current(
      generation: ++_generation,
      sourceId: to,
      stream: lookAhead.stream,
      candidate: 0,
    )..ready = true;
    unawaited(_prepareLookAhead());
  }

  void _onEnded(_Current current, TrackEndReason end) {
    switch (end) {
      case TrackEndReason.completed:
        final next = _queue.next;
        if (next == null) {
          _log.info('Queue finished', tag: _tag);
          _current = null;
          _clearLookAhead();
          _resumeAt = Duration.zero;
          _setState(const Idle());
          return;
        }
        // 前瞻沒來得及接上（例如還在解析）：照一般的下一首開始。
        final prepared = _takeLookAhead(next.index);
        _queue.moveNext();
        _emitQueue();
        unawaited(_beginTrack(prepared: prepared));
      case TrackEndReason.endedEarly:
        final error = NetworkError(pluginId: current.stream.track.sourceTypeId);
        _log.report('Stream ended early', error, tag: _tag);
        unawaited(
          _recover(const StreamInterrupted(), error, _positionOf(current)),
        );
    }
  }

  void _onFailed(_Current current, BackendFailure failure, Object? cause) {
    final pluginId = current.stream.track.sourceTypeId;
    _log.warning(
      'Stream failed',
      tag: _tag,
      error: cause,
      fields: {
        'track': '${current.stream.track}',
        'failure': failure.name,
        'candidate': current.candidate,
      },
    );
    switch (failure) {
      case BackendFailure.open:
        // 開不起來、解不了：對使用者是「播不了」，不是網路問題。
        unawaited(
          _recover(
            const StreamUnopenable(),
            Unsupported(pluginId: pluginId),
            _resumeAt,
          ),
        );
      case BackendFailure.interrupted:
        unawaited(
          _recover(
            const StreamInterrupted(),
            NetworkError(pluginId: pluginId),
            _positionOf(current),
          ),
        );
    }
  }

  /// 從最後一次位置推算上一首播到結尾的時間。
  static DateTime? _estimatedEnd(PlaybackProgress? last, DateTime? at) {
    if (last == null || at == null) return at;
    final duration = last.duration;
    if (duration == null || duration <= last.position) return at;
    return at.add(duration - last.position);
  }

  Duration _positionOf(_Current current) =>
      current.progress?.position ?? _resumeAt;

  // ---- 恢復 -----------------------------------------------------------------

  Future<void> _recover(
    PlaybackFailure failure,
    AppError error,
    Duration position,
  ) async {
    final current = _current;
    final action = decideRecovery(
      failure,
      retries: _retries,
      candidateSwitched: _candidateSwitched,
      hasOtherCandidate:
          current != null &&
          current.candidate + 1 < current.stream.candidates.length,
      consecutiveSkips: _consecutiveSkips,
      queueLength: _queue.state.tracks.length,
    );
    _log.info(
      'Playback recovery',
      tag: _tag,
      fields: {
        'track': '${_queue.state.current}',
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
        final generation = ++_generation;
        _current = null;
        _clearLookAhead();
        _resumeAt = position;
        _setState(Retrying(error: error, attempt: attempt, delay: delay));
        _retryTimer = Timer(delay, () {
          _retryTimer = null;
          if (generation == _generation) {
            // 等待期間的 seek 記在 _resumeAt。
            unawaited(_load(position: _resumeAt));
          }
        });
      case TryNextCandidate():
        _candidateSwitched = true;
        _generation++;
        await _open(
          current!.stream,
          candidate: current.candidate + 1,
          position: position,
        );
      case SkipTrack():
        _consecutiveSkips++;
        final next = _queue.next;
        if (next == null) return _stopWith(Failed(error));
        final prepared = _takeLookAhead(next.index);
        _queue.moveNext();
        _emitQueue();
        await _beginTrack(prepared: prepared);
      case StopPlayback():
        await _stopWith(Failed(error));
    }
  }

  Future<void> _stopWith(PlaybackState state) async {
    _generation++;
    _cancelRetry();
    _clearLookAhead();
    _current = null;
    _setState(state);
    await _backend.stop();
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

  void _emitQueue() {
    if (!_queueStates.isClosed) _queueStates.add(_queue.state);
  }

  /// 一首開始出聲時記一筆：接上前瞻的記「估計的間隔」（上一首推算的結束時間
  /// 到這首第一次回報位置），其他記從要求到出聲的時間。
  void _logAudible(_Current current, DateTime now) {
    final handover = _handover;
    final previousEnd = handover?.previousEnd;
    final requestedAt = _requestedAt;
    _log.info(
      'Track audible',
      tag: _tag,
      fields: {
        'track': '${current.stream.track}',
        if (handover != null) ...{
          'sinceHandoverMs': now.difference(handover.at).inMilliseconds,
          if (previousEnd != null)
            'estimatedGapMs': now.difference(previousEnd).inMilliseconds,
        } else if (requestedAt != null)
          'sinceRequestMs': now.difference(requestedAt).inMilliseconds,
      },
    );
    _handover = null;
  }
}

final class _Current {
  _Current({
    required this.generation,
    required this.sourceId,
    required this.stream,
    required this.candidate,
  });

  final int generation;
  final int sourceId;
  final ResolvedStream stream;

  /// 開的是第幾個候選。
  final int candidate;

  /// 後端回報過載入好（之後的緩衝是 [Buffering] 而不是 [Loading]）。
  bool ready = false;

  /// 回報過大於 0 的位置。
  bool audible = false;
  PlaybackProgress? progress;
}

final class _LookAhead {
  _LookAhead({
    required this.queueIndex,
    required this.stream,
    required this.sourceId,
  });

  final int queueIndex;
  final ResolvedStream stream;
  final int sourceId;
  Timer? refresh;
}

final class _Handover {
  _Handover({required this.at, required this.previousEnd});

  final DateTime at;

  /// 從上一首最後的位置推算的結束時間；沒有位置時為 `null`。
  final DateTime? previousEnd;
}
