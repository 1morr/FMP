import 'dart:async';

import 'package:clock/clock.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// 前瞻要接的曲目：佇列裡的位置與曲目；位置為 `null` 是重播目前這首（單曲
/// 循環，佇列不動）。
typedef NextTrack = ({int? index, TrackKeyParts track});

/// 唯一持有 [AudioBackend] 的協作者（ADR 0018 §決定 1）：解析與開流、前瞻、
/// 代與來源 id。只由 `PlaybackController` 呼叫，不寫播放狀態。
///
/// 後端的狀態與事件以來源 id 過濾成目前這個來源的 [SourceEvent]，同步交給
/// [events] 的監聽者（控制器）；不屬於來源的輸出事件（音訊中斷、拔耳機、輸出
/// 裝置失敗）不過濾，照樣轉成 [SessionEvent]。後端的 stream 本身是非同步送達
/// 的，所以不會在處理一個事件的途中再收到下一個。位置轉成 [progress]。
///
/// [progress] 一直是目前這首的：開始要求一首（[beginRequest]）與交給後端
/// （[open]、[openNextCandidate]）時先發出起點，不等後端。後端只保證播放中與
/// seek 後回報（[AudioBackend.progress]），暫停中開的來源可能到按播放前都不
/// 回報（ExoPlayer），不先發的話 stream 留著上一首的位置與時長。同一首重開
/// （重試、換候選）時沿用已知的時長，其他是 `null`（還不知道）。
///
/// 前瞻（ADR 0018 §決定 3、6）：目前這首載入好之後，解析下一首一次、交給後端
/// 的 [AudioBackend.setNext]；後端自己接上（[LookAheadTookOver]），接上的那首不
/// 再解析。佇列改了（[retargetLookAhead]）就改指新的下一首。單曲循環時前瞻是
/// 目前這首的同一份解析結果與同一個候選（換過候選就是換過的那個），引擎無縫
/// 重播。只有試聽片段的（[ResolvedStream.previewOnly]）不當前瞻：到那首時由
/// 控制器依「跳過試聽片段」決定跳過或照播。候選有期限時，在過期前
/// （[ResolvedStream.expiryMargin]）作廢快取、重新解析並換掉前瞻；手動下一首時
/// 由控制器以 [isFresh] 檢查。解析都經 [StreamResolver] 的網址快取，所以前瞻解析
/// 過的那首之後再播（或前瞻還在解析時就要播）不會再問插件。
///
/// 每次開始一首（含重試、換候選、接上前瞻）都換一個「代」：還在進行的解析回來
/// 時代已經不同，結果就丟掉。插件的 `resolveStream` 沒有取消參數，M1 不取消網路
/// 工作（ADR 0018 §決定 6 的取消在插件 API 支援後接上）。
final class PlaybackSession {
  PlaybackSession({
    required this._backend,
    required this._resolver,
    required this._log,
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

  /// 前瞻的要求編號：較新的要求（佇列改了）蓋掉還在解析的舊要求。
  int _lookAheadRequest = 0;

  /// [progress] 最後發出的是哪一首與它的時長：同一首重開時沿用時長。
  ({TrackKeyParts track, Duration? duration})? _progressOf;

  // 交接的量測（實機驗證用，見 app/AGENTS.md § 播放）。
  DateTime? _requestedAt;
  _Handover? _handover;
  DateTime? _lastProgressAt;

  /// 目前的代。
  int get generation => _generation;

  /// 目前的來源已經交給後端（不在解析、等重試或停下）。
  bool get hasSource => _current != null;

  /// 目前來源最後回報的位置；沒有來源或還沒回報過時為 `null`。
  Duration? get position => _current?.progress?.position;

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

  /// 開始要求 [track]、從 [position] 開始：[newGeneration]，[progress] 先發出
  /// 這個起點，並從這裡量到出聲。
  int beginRequest(TrackKeyParts track, {required Duration position}) {
    final generation = newGeneration();
    _handover = null;
    _requestedAt = clock.now();
    _startProgress(track, position);
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
  bool isFresh(ResolvedStream stream) => stream.isFreshAt(clock.now());

  /// 目前的來源播放失敗（開不起來、中斷、提前結束）：從網址快取作廢它，重試
  /// 與之後再播這首時重新解析。來源還留著，換候選照樣用。
  void invalidateCurrentStream() {
    final current = _current;
    if (current != null) _resolver.invalidate(current.stream);
  }

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
    // 解析期間的 seek 改了起點；暫停中開的來源後端可能不回報（見類別說明）。
    _startProgress(stream.track, position);
    _log.info(
      'Opening stream',
      tag: _tag,
      fields: {
        'track': '${stream.track}',
        'candidate': candidate,
        'container': ?chosen.container,
        'codec': ?chosen.codec,
        'bitrate': ?chosen.bitrate,
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

  // ---- 音量、速度、輸出裝置 ------------------------------------------------

  /// 交給後端的音量（0–1）；換來源、交接後後端自己維持。
  Future<void> setVolume(double volume) => _backend.setVolume(volume);

  /// 交給後端的速度（後端夾到 0.5–2.0）。
  Future<void> setSpeed(double speed) => _backend.setSpeed(speed);

  /// 能選輸出裝置（只有 Windows）。
  bool get selectsOutputDevice => _backend.outputDevices != null;

  /// 可選的輸出裝置（不含系統預設）：先給目前的清單，之後每次插拔；不能選的
  /// 平台為 `null`。
  Stream<List<OutputDevice>>? get outputDeviceLists =>
      _backend.outputDevices?.available;

  /// 選 [device]；`null` 是系統預設。不能選的平台什麼都不做。
  Future<void> selectOutputDevice(OutputDevice? device) async =>
      _backend.outputDevices?.select(device);

  // ---- 前瞻 -----------------------------------------------------------------

  /// 為目前這一代解析下一首一次，交給後端。[next] 讀佇列當下的下一首。
  Future<void> prepareLookAhead(NextTrack? Function() next) async {
    final current = _current;
    if (current == null || _lookAheadFor == current.generation) return;
    _lookAheadFor = current.generation;
    await _prepareLookAhead(current, next());
  }

  /// 佇列改了（拖曳、插入、移除、隨機、循環）：前瞻改指 [next] 當下的下一首。
  /// 還是同一首（位置可能變了）就留著、只改位置；不同就清掉後端的前瞻再重新
  /// 解析。目前這首還沒載入好時不動：載入好時 [prepareLookAhead] 照當下的佇列
  /// 準備。
  Future<void> retargetLookAhead(NextTrack? Function() next) async {
    final current = _current;
    if (current == null || _lookAheadFor != current.generation) return;
    final target = next();
    final lookAhead = _lookAhead;
    if (lookAhead != null &&
        target != null &&
        (lookAhead.index == null) == (target.index == null) &&
        lookAhead.stream.track == target.track) {
      lookAhead.index = target.index;
      return;
    }
    await _prepareLookAhead(current, target);
  }

  Future<void> _prepareLookAhead(_Current current, NextTrack? target) async {
    final request = ++_lookAheadRequest;
    if (_lookAhead != null) {
      _clearLookAhead();
      await _backend.setNext(null);
    }
    if (target == null) return;
    // 重播目前這首（單曲循環）：網址還能用就照用目前開著的那個候選，不再問
    // 快取（換候選時快取裡的那一筆已經作廢，再解析會拿回開不起來的第一個）。
    if (target.index == null &&
        target.track == current.stream.track &&
        isFresh(current.stream)) {
      // 清前瞻的修改排隊期間可能換了歌：和下面解析回來時同樣比對。
      if (request != _lookAheadRequest ||
          _current?.generation != current.generation) {
        return;
      }
      return _setLookAhead(null, current.stream, candidate: current.candidate);
    }
    final ResolvedStream stream;
    try {
      stream = await _resolver.resolve(target.track);
    } on AppError catch (error) {
      // 到那一首時再依錯誤處理（重新解析一次）。
      _log.report('Look-ahead resolution failed', error, tag: _tag);
      return;
    }
    if (request != _lookAheadRequest ||
        _current?.generation != current.generation) {
      return;
    }
    await _setLookAhead(target.index, stream);
  }

  /// 以 [stream] 的第 [candidate] 個候選當前瞻。只有試聽片段的不當前瞻（見
  /// 類別說明），回傳前清掉舊的前瞻。
  Future<void> _setLookAhead(
    int? index,
    ResolvedStream stream, {
    int candidate = 0,
  }) async {
    if (stream.previewOnly) {
      if (_lookAhead != null) {
        _clearLookAhead();
        await _backend.setNext(null);
      }
      _log.info(
        'Look-ahead skipped: preview only',
        tag: _tag,
        fields: {'track': '${stream.track}'},
      );
      return;
    }
    _clearLookAhead();
    final chosen = stream.candidates[candidate];
    final source = BackendSource(
      id: ++_lastSourceId,
      url: chosen.url,
      headers: chosen.headers,
    );
    final lookAhead = _lookAhead = _LookAhead(
      index: index,
      stream: stream,
      candidate: candidate,
      sourceId: source.id,
    );
    final refreshAt = stream.refreshAt;
    if (refreshAt != null) {
      final delay = refreshAt.difference(clock.now());
      // 一解析出來就快過期的不排：手動下一首時會再檢查。
      if (delay > Duration.zero) {
        lookAhead.refresh = Timer(delay, () => _refreshLookAhead(lookAhead));
      }
    }
    _log.info(
      'Look-ahead prepared',
      tag: _tag,
      fields: {
        'track': '${stream.track}',
        if (index == null) 'repeat': true,
        if (candidate != 0) 'candidate': candidate,
      },
    );
    await _backend.setNext(source);
  }

  /// 前瞻的網址快過期了：重新解析並換掉。先作廢快取裡的那一筆，計時器早一點
  /// 觸發時也不會拿回同一個網址。
  Future<void> _refreshLookAhead(_LookAhead lookAhead) async {
    if (!identical(_lookAhead, lookAhead)) return;
    _resolver.invalidate(lookAhead.stream);
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
    await _setLookAhead(lookAhead.index, stream);
  }

  /// 取走位置 [queueIndex] 的前瞻解析結果（手動下一首、跳過時沿用）。單曲
  /// 循環的前瞻（重播目前這首）不算佇列的位置，不會被取走。
  ResolvedStream? takeLookAhead(int queueIndex) {
    final lookAhead = _lookAhead;
    if (lookAhead == null || lookAhead.index != queueIndex) return null;
    _clearLookAhead();
    return lookAhead.stream;
  }

  /// [AdoptLookAhead]：前瞻成為目前的來源（新的一代，已經載入好）。回傳接上的
  /// 是不是重播目前這首（單曲循環）：是的話佇列不動。
  bool adoptLookAhead(AdoptLookAhead handover) {
    final current = _current!;
    final lookAhead = _lookAhead!;
    final now = clock.now();
    final previous = current.progress;
    final lastProgressAt = _lastProgressAt;
    _log.info(
      'Look-ahead handover',
      tag: _tag,
      fields: {
        'from': '${current.stream.track}',
        'to': '${lookAhead.stream.track}',
        if (lookAhead.index == null) 'repeat': true,
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
      candidate: lookAhead.candidate,
    )..ready = true;
    return lookAhead.index == null;
  }

  /// [progress] 發出 [track] 從 [position] 開始；時長只在同一首時沿用。不是
  /// 後端的回報，所以不設 [position]、不算出聲。
  void _startProgress(TrackKeyParts track, Duration position) {
    final previous = _progressOf;
    final duration = previous != null && previous.track == track
        ? previous.duration
        : null;
    _progressOf = (track: track, duration: duration);
    if (!_progress.isClosed) {
      _progress.add(PlaybackProgress(position: position, duration: duration));
    }
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
    _progressOf = (track: current.stream.track, duration: progress.duration);
    final now = clock.now();
    _lastProgressAt = now;
    if (!current.audible && progress.position > Duration.zero) {
      current.audible = true;
      _logAudible(current, now);
    }
    if (!_progress.isClosed) _progress.add(progress);
  }

  void _onEvent(BackendEvent event) {
    // 輸出事件不屬於來源：沒有來源（停下、等重試）時也交給控制器。
    switch (event) {
      case Interrupted(:final transient):
        return _emit(AudioInterrupted(transient: transient));
      case InterruptionEnded(:final resume):
        return _emit(AudioInterruptionEnded(resume: resume));
      case BecameNoisy():
        return _emit(const HeadphonesUnplugged());
      case OutputDeviceFailed(:final cause):
        // 引擎的那一行只以 error 交給 log 門面。
        _log.warning('Output device failed', tag: _tag, error: cause);
        return _emit(const OutputDeviceLost());
      case SourceAdvanced() || SourceEnded() || SourceFailed():
        break;
    }
    final current = _current;
    if (current == null) return;
    final pluginId = current.stream.track.sourceTypeId;
    switch (event) {
      case SourceAdvanced(:final from, :final to, :final end):
        if (current.sourceId != from) return;
        if (_lookAhead?.sourceId == to) {
          _emit(LookAheadTookOver(generation: current.generation, end: end));
          return;
        }
        // 引擎接上的是剛被換掉的前瞻（佇列改了，清掉前瞻的修改還在排隊）：
        // 先讓引擎停下，再當成目前這首播完、沒有前瞻，控制器照一般的下一首
        // 重新開流。不停的話，佇列沒有下一首（停在 Idle）或等重試時，被換掉
        // 的那首會一直出聲。
        _log.info(
          'The engine took over a replaced look-ahead; stopping it',
          tag: _tag,
          fields: {'track': '${current.stream.track}'},
        );
        unawaited(_backend.stop());
        _emit(
          SourceFinished(
            generation: current.generation,
            pluginId: pluginId,
            end: end,
            lastPosition: current.progress?.position,
          ),
        );
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
      case SourceFailed(:final id, :final cause, :final httpStatus)
          when id == _lookAhead?.sourceId:
        _lookAheadFailed(_lookAhead!, cause, httpStatus);
      case SourceFailed(
        :final id,
        :final failure,
        :final cause,
        :final httpStatus,
      ):
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
            'httpStatus': ?httpStatus,
          },
        );
        _emit(switch (failure) {
          BackendFailure.open => SourceUnopenable(
            generation: current.generation,
            pluginId: pluginId,
            httpStatus: httpStatus,
          ),
          BackendFailure.interrupted => SourceInterrupted(
            generation: current.generation,
            pluginId: pluginId,
            lastPosition: current.progress?.position,
          ),
        });
      // 上面已經轉出去了。
      case Interrupted() ||
          InterruptionEnded() ||
          BecameNoisy() ||
          OutputDeviceFailed():
        return;
    }
  }

  /// 前瞻開不起來（後端不接上它，目前這首照常播完）：當成那一首的開流失敗，
  /// 作廢網址快取裡的那一筆、放掉前瞻；到那首時控制器照一般的下一首重新解析，
  /// 再失敗就走恢復。目前這首不受影響。
  void _lookAheadFailed(_LookAhead lookAhead, Object? cause, int? httpStatus) {
    _log.warning(
      'Look-ahead failed to open',
      tag: _tag,
      error: cause,
      fields: {
        'track': '${lookAhead.stream.track}',
        if (lookAhead.index == null) 'repeat': true,
        'httpStatus': ?httpStatus,
      },
    );
    _resolver.invalidate(lookAhead.stream);
    _clearLookAhead();
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
    required this.index,
    required this.stream,
    required this.candidate,
    required this.sourceId,
  });

  /// 佇列裡的位置；`null` 是重播目前這首。佇列改了而曲目沒變時跟著改。
  int? index;
  final ResolvedStream stream;

  /// 交給後端的是第幾個候選（重播目前這首時同目前開著的那個）。
  final int candidate;
  final int sourceId;
  Timer? refresh;
}

final class _Handover {
  _Handover({required this.at, required this.previousEnd});

  final DateTime at;

  /// 從上一首最後的位置推算的結束時間；沒有位置時為 `null`。
  final DateTime? previousEnd;
}
