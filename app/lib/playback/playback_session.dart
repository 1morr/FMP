import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// 佇列裡的下一首：位置與曲目。
typedef NextTrack = ({int index, TrackKeyParts track});

/// 唯一持有 [AudioBackend] 的協作者（ADR 0018 §決定 1）：解析與開流、前瞻、
/// 代與來源 id。只由 `PlaybackController` 呼叫，不寫播放狀態。
///
/// 後端的狀態與事件以來源 id 過濾成目前這個來源的 [SessionEvent]，同步交給
/// [events] 的監聽者（控制器）；後端的 stream 本身是非同步送達的，所以不會在
/// 處理一個事件的途中再收到下一個。位置轉成 [progress]。
///
/// 前瞻（ADR 0018 §決定 3、6）：目前這首載入好之後，解析下一首一次、交給後端
/// 的 [AudioBackend.setNext]；後端自己接上（[LookAheadTookOver]），接上的那首不
/// 再解析。候選有期限時，在過期前（[ResolvedStream.expiryMargin]）重新解析並換掉
/// 前瞻；手動下一首時由控制器以 [isFresh] 檢查。
///
/// 每次開始一首（含重試、換候選、接上前瞻）都換一個「代」：還在進行的解析回來
/// 時代已經不同，結果就丟掉。插件的 `resolveStream` 沒有取消參數，M1 不取消網路
/// 工作（ADR 0018 §決定 6 的取消在插件 API 支援後接上）。
final class PlaybackSession {
  PlaybackSession({
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

  final _events = StreamController<SessionEvent>.broadcast(sync: true);
  final _progress = StreamController<PlaybackProgress>.broadcast();

  int _generation = 0;
  int _lastSourceId = 0;

  /// 交給後端的目前來源；解析中、等重試、停下時為 `null`。
  _Current? _current;
  _LookAhead? _lookAhead;

  /// 已經為哪一代要求過前瞻（每首只解析一次）。
  int? _lookAheadFor;

  // 交接的量測（實機驗證用，見 app/AGENTS.md § 播放）。
  DateTime? _requestedAt;
  _Handover? _handover;
  DateTime? _lastProgressAt;

  /// 目前的代。
  int get generation => _generation;

  /// 目前的來源已經交給後端（不在解析、等重試或停下）。
  bool get hasSource => _current != null;

  /// 目前的來源還有沒開過的候選。
  bool get hasOtherCandidate {
    final current = _current;
    return current != null &&
        current.candidate + 1 < current.stream.candidates.length;
  }

  /// 目前這個來源的事件，同步送達。
  Stream<SessionEvent> get events => _events.stream;

  /// 目前這首的位置、時長與緩衝。
  Stream<PlaybackProgress> get progress => _progress.stream;

  // ---- 代與來源 -------------------------------------------------------------

  /// 換一代並放掉目前的來源與前瞻；回傳新的代。
  int newGeneration() {
    _generation++;
    _current = null;
    _clearLookAhead();
    return _generation;
  }

  /// 開始要求一首：[newGeneration]，並從這裡量到出聲。
  int beginRequest() {
    final generation = newGeneration();
    _handover = null;
    _requestedAt = _now();
    return generation;
  }

  /// 放掉目前的來源與前瞻，不換代（佇列播完）。
  void release() {
    _current = null;
    _clearLookAhead();
  }

  /// [MarkReady]：之後的緩衝是 [Buffering] 而不是 [Loading]。
  void markReady() => _current?.ready = true;

  // ---- 解析與開流 -----------------------------------------------------------

  /// [stream] 現在還能用（沒有期限，或離過期還有餘裕）。
  bool isFresh(ResolvedStream stream) => stream.isFreshAt(_now());

  /// 解析 [track]，丟出 `AppError`。解析期間不讓上一首繼續出聲。
  Future<ResolvedStream> resolve(TrackKeyParts track) {
    unawaited(_backend.stop());
    return _resolver.resolve(track);
  }

  /// 以 [stream] 的第一個候選取代後端的清單，從 [position] 開始；[play] 為假
  /// 時載入後停在暫停。
  Future<void> open(
    ResolvedStream stream, {
    required Duration position,
    required bool play,
  }) => _open(stream, candidate: 0, position: position, play: play);

  /// 換一代，改開目前這首的下一個候選（[hasOtherCandidate] 為真時）。
  Future<void> openNextCandidate({
    required Duration position,
    required bool play,
  }) {
    final current = _current!;
    _generation++;
    return _open(
      current.stream,
      candidate: current.candidate + 1,
      position: position,
      play: play,
    );
  }

  Future<void> _open(
    ResolvedStream stream, {
    required int candidate,
    required Duration position,
    required bool play,
  }) async {
    final chosen = stream.candidates[candidate];
    final source = BackendSource(
      id: ++_lastSourceId,
      url: chosen.url,
      headers: chosen.headers,
    );
    _current = _Current(
      generation: _generation,
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
    await _backend.open(source, start: position, play: play);
  }

  Future<void> play() => _backend.play();

  Future<void> pause() => _backend.pause();

  Future<void> seek(Duration position) => _backend.seek(position);

  Future<void> stop() => _backend.stop();

  // ---- 前瞻 -----------------------------------------------------------------

  /// 為目前這一代解析下一首一次，交給後端。[next] 讀佇列當下的下一首。
  Future<void> prepareLookAhead(NextTrack? Function() next) async {
    final current = _current;
    if (current == null || _lookAheadFor == current.generation) return;
    _lookAheadFor = current.generation;
    final target = next();
    if (target == null) return;
    final ResolvedStream stream;
    try {
      stream = await _resolver.resolve(target.track);
    } on AppError catch (error) {
      // 到那一首時再依錯誤處理（重新解析一次）。
      _log.report('Look-ahead resolution failed', error, tag: _tag);
      return;
    }
    if (_current?.generation != current.generation ||
        next()?.index != target.index) {
      return;
    }
    await _setLookAhead(target.index, stream);
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
  ResolvedStream? takeLookAhead(int queueIndex) {
    final lookAhead = _lookAhead;
    if (lookAhead == null || lookAhead.queueIndex != queueIndex) return null;
    _clearLookAhead();
    return lookAhead.stream;
  }

  /// [AdoptLookAhead]：前瞻成為目前的來源（新的一代，已經載入好）。
  void adoptLookAhead(AdoptLookAhead handover) {
    final current = _current!;
    final lookAhead = _lookAhead!;
    final now = _now();
    final previous = current.progress;
    final lastProgressAt = _lastProgressAt;
    _log.info(
      'Look-ahead handover',
      tag: _tag,
      fields: {
        'from': '${current.stream.track}',
        'to': '${lookAhead.stream.track}',
        'end': handover.end.name,
        'previousPositionMs': ?previous?.position.inMilliseconds,
        'previousDurationMs': ?previous?.duration?.inMilliseconds,
        if (lastProgressAt != null)
          'sinceLastProgressMs': now.difference(lastProgressAt).inMilliseconds,
      },
    );
    if (handover.previousEndedEarly) {
      _log.warning(
        'The previous track ended early at the handover',
        tag: _tag,
        fields: {'track': '${current.stream.track}'},
      );
    }
    _clearLookAhead();
    _handover = _Handover(
      at: now,
      previousEnd: _estimatedEnd(previous, lastProgressAt),
    );
    _current = _Current(
      generation: ++_generation,
      sourceId: lookAhead.sourceId,
      stream: lookAhead.stream,
      candidate: 0,
    )..ready = true;
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
        _emit(
          SourceBuffering(
            generation: current.generation,
            wasReady: current.ready,
          ),
        );
      case BackendPhase.ready:
        _emit(
          SourceReady(
            generation: current.generation,
            playing: status.playing,
            wasReady: current.ready,
          ),
        );
      // 結束由事件回報。
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
    final current = _current;
    if (current == null) return;
    final pluginId = current.stream.track.sourceTypeId;
    switch (event) {
      case SourceAdvanced(:final from, :final to, :final end):
        if (current.sourceId != from || _lookAhead?.sourceId != to) return;
        _emit(LookAheadTookOver(generation: current.generation, end: end));
      case SourceEnded(:final id, :final end):
        if (id != current.sourceId) return;
        _emit(
          SourceFinished(
            generation: current.generation,
            pluginId: pluginId,
            end: end,
            lastPosition: current.progress?.position,
          ),
        );
      case SourceFailed(:final id, :final failure, :final cause):
        if (id != current.sourceId) return;
        // 引擎的錯誤可能帶完整的串流網址：只以 error 交給 log 門面。
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
        _emit(switch (failure) {
          BackendFailure.open => SourceUnopenable(
            generation: current.generation,
            pluginId: pluginId,
          ),
          BackendFailure.interrupted => SourceInterrupted(
            generation: current.generation,
            pluginId: pluginId,
            lastPosition: current.progress?.position,
          ),
        });
    }
  }

  void _emit(SessionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// 從最後一次位置推算上一首播到結尾的時間。
  static DateTime? _estimatedEnd(PlaybackProgress? last, DateTime? at) {
    if (last == null || at == null) return at;
    final duration = last.duration;
    if (duration == null || duration <= last.position) return at;
    return at.add(duration - last.position);
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

  /// 換一代、放掉來源與前瞻，停止收後端的回報。後端由建它的人釋放。
  Future<void> dispose() async {
    newGeneration();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
    await _progress.close();
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
