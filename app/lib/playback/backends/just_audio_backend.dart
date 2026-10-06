import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';

/// [AudioBackend] 的 just_audio（ExoPlayer）實作：Android。
///
/// 整個 App 一個 `AudioPlayer`，換來源只換清單（音訊焦點見 [AudioBackend]）。
/// 每個 just_audio 項目的 `tag` 是 [BackendSource.id]，索引以它對回來源。
final class JustAudioBackend implements AudioBackend {
  JustAudioBackend({required this._log})
    : _player = AudioPlayer(
        // 標頭直接交給 ExoPlayer（DataSource 的 request properties），不開
        // just_audio 的本機明文 proxy。
        useProxyForRequestHeaders: false,
        // 第二個項目（前瞻）一接上就預備，交接處才不用等開流。
        useLazyPreparation: false,
      ) {
    _subscriptions
      ..add(_player.playerStateStream.listen(_onPlayerState))
      ..add(_player.playbackEventStream.listen(_onPlaybackEvent))
      ..add(_player.errorStream.listen(_onError))
      ..add(_player.positionStream.listen(_onPosition));
  }

  final Log _log;
  final AudioPlayer _player;
  final _subscriptions = <StreamSubscription<Object?>>[];

  final _status = StreamController<BackendStatus>.broadcast();
  final _progress = StreamController<SourceProgress>.broadcast();
  final _events = StreamController<BackendEvent>.broadcast();

  int? _currentId;
  int? _nextId;

  /// 目前的來源已經載入（有時長或位置）；之前的失敗算 [BackendFailure.open]。
  bool _loaded = false;

  /// 目前的來源已經發過結束或失敗，不再發第二次。
  bool _settled = false;

  /// 目前來源最後一次的事件，用來外推交接時的位置。
  PlaybackEvent? _lastEvent;

  /// ExoPlayer 已經換到前瞻的索引，還不知道它開不開得起來：前瞻沒預備好時，
  /// 換過去那一刻的事件仍是 `ready`、沒有時長，開不起來的錯誤之後才到。有時長
  /// 才發 [SourceAdvanced]；這段期間目前的來源還是上一首。
  ///
  /// 已知限制：ExoPlayer 給不出時長的前瞻（沒有長度資訊的串流）因此一直不算
  /// 接上，上一首不會結束。位置不能代替時長：just_audio 在 `ready` 時以時鐘外推
  /// 位置，開不起來的前瞻也會「前進」。出現這種音源時要另找載入的訊號。
  _PendingHandover? _pendingHandover;

  /// 前瞻在交接時開不起來，目前的來源（上一首）已經結束、ExoPlayer 停在錯誤。
  bool _ended = false;

  /// 使用者要不要出聲：[open] 的 `play`、[play]、[pause] 設定。載入中被暫停時，
  /// 載入完不能再以 [open] 當時的 `play` 開始播。
  bool _wantPlaying = false;

  /// 清單正在修改：事件裡的索引可能還是舊的，改完再核對一次。
  int _editing = 0;
  Future<void> _edits = Future.value();

  @override
  Stream<BackendStatus> get status => _status.stream;

  @override
  Stream<SourceProgress> get progress => _progress.stream;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<void> open(
    BackendSource source, {
    Duration start = Duration.zero,
    bool play = true,
  }) {
    _currentId = source.id;
    _nextId = null;
    _wantPlaying = play;
    _resetCurrent();
    return _edit(() async {
      if (_currentId != source.id) return;
      // just_audio 的 playing 跨來源保留：要停在暫停就先暫停，否則一載入就播。
      if (!_wantPlaying) await _player.pause();
      try {
        await _player.setAudioSources([
          _audioSource(source),
        ], initialPosition: start);
      } on PlayerInterruptedException {
        // 被下一次 open 取代；新的來源自己會回報。
        return;
      } on Object catch (error) {
        // PlayerException，或 asset 找不到之類在交給 ExoPlayer 前就拋的錯誤。
        _fail(source.id, BackendFailure.open, error);
        return;
      }
      if (_wantPlaying && _currentId == source.id) {
        // play() 的 Future 要到暫停才完成，不能 await。
        unawaited(_player.play());
      }
    });
  }

  @override
  Future<void> setNext(BackendSource? next) {
    final owner = _currentId;
    if (owner == null) return Future.value();
    _nextId = next?.id;
    return _edit(() async {
      // 排隊的期間換了來源（open、交接）：這次修改已經過時。
      if (_currentId != owner) return;
      if (_pendingHandover case final handover? when handover.to != next?.id) {
        await _abandonHandover(handover);
        return;
      }
      final edit = LookAheadEdit.of(
        itemCount: _player.sequence.length,
        currentIndex: _player.currentIndex ?? -1,
        append: next != null,
      );
      for (final index in edit.removeIndices) {
        await _player.removeAudioSourceAt(index);
      }
      if (!edit.append || next == null || _nextId != next.id) return;
      try {
        await _player.addAudioSource(_audioSource(next));
      } on PlayerInterruptedException {
        return;
      } on Object catch (error) {
        // asset 找不到之類，交給 ExoPlayer 前就失敗（just_audio 的 Dart 清單裡
        // 留著它，下一次修改會移掉）：目前的來源照常播完。
        if (_currentId != owner || _nextId != next.id) return;
        _nextId = null;
        _add(
          _events,
          SourceFailed(id: next.id, failure: BackendFailure.open, cause: error),
        );
      }
    });
  }

  @override
  Future<void> play() async {
    _wantPlaying = true;
    unawaited(_player.play());
  }

  @override
  Future<void> pause() {
    _wantPlaying = false;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() {
    _currentId = null;
    _nextId = null;
    _wantPlaying = false;
    _resetCurrent();
    return _edit(() async {
      if (_currentId != null) return;
      await _player.stop();
      await _player.clearAudioSources();
    });
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _status.close();
    await _progress.close();
    await _events.close();
  }

  AudioSource _audioSource(BackendSource source) => AudioSource.uri(
    source.url,
    headers: source.headers.isEmpty ? null : source.headers,
    tag: source.id,
  );

  void _resetCurrent() {
    _loaded = false;
    _settled = false;
    _lastEvent = null;
    _pendingHandover = null;
    _ended = false;
  }

  /// 清單的修改一個接一個做：每次都依當下的清單算 [LookAheadEdit]，交接後的
  /// 修剪與 `PlaybackSession` 的下一次 [setNext] 才不會以同一份舊清單各算一次。
  Future<void> _edit(Future<void> Function() change) {
    final done = _edits.then((_) async {
      _editing++;
      try {
        await change();
      } finally {
        _editing--;
        // 修改期間的事件都丟掉了：以最後一個事件補一次。暫停中載入好的來源
        // 之後不會再有事件（播放中還有 play 帶來的那一個），不補就停在緩衝。
        if (_editing == 0) _onPlaybackEvent(_player.playbackEvent);
      }
    });
    _edits = done.catchError(_logEditError);
    return done;
  }

  int? _idAt(int? index) {
    final sequence = _player.sequence;
    if (index == null || index < 0 || index >= sequence.length) return null;
    return switch (sequence[index].tag) {
      final int id => id,
      _ => null,
    };
  }

  void _onPlayerState(PlayerState state) => _emitStatus();

  void _emitStatus() {
    final state = _player.playerState;
    final id = _currentId;
    final phase = switch (state.processingState) {
      _ when id == null => BackendPhase.idle,
      _ when _ended => BackendPhase.ended,
      ProcessingState.idle => BackendPhase.idle,
      ProcessingState.loading ||
      ProcessingState.buffering => BackendPhase.buffering,
      // 狀態可能還是上一個來源的：目前的來源載入前都算緩衝。
      ProcessingState.ready =>
        _loaded ? BackendPhase.ready : BackendPhase.buffering,
      ProcessingState.completed => BackendPhase.ended,
    };
    _add(
      _status,
      BackendStatus(
        sourceId: id,
        playing: state.playing && phase != BackendPhase.ended && id != null,
        phase: phase,
      ),
    );
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    if (_editing > 0) return;
    _checkCurrentSource(event);
    if (_idAt(event.currentIndex) != _currentId) return;
    _lastEvent = event;
    if (!_loaded &&
        event.processingState == ProcessingState.ready &&
        (event.duration != null || event.updatePosition > Duration.zero)) {
      _loaded = true;
      _emitStatus();
    }
    final id = _currentId;
    if (event.processingState == ProcessingState.completed &&
        id != null &&
        !_settled) {
      _settled = true;
      _add(
        _events,
        SourceEnded(
          id: id,
          end: classifyTrackEnd(
            position: event.updatePosition,
            duration: event.duration,
          ),
        ),
      );
    }
  }

  /// ExoPlayer 自己換到前瞻時，事件的索引指到 [_nextId]；事件有時長（前瞻
  /// 預備好了）才算接上。
  void _checkCurrentSource(PlaybackEvent event) {
    final current = _currentId;
    final next = _nextId;
    if (current == null || next == null) return;
    if (_idAt(event.currentIndex) != next) return;
    final handover = _pendingHandover ??= _PendingHandover(
      from: current,
      to: next,
      end: classifyTrackEnd(
        position: _positionAtHandover(),
        duration: _lastEvent?.duration,
      ),
    );
    if (event.duration == null) return;
    final end = handover.end;
    _currentId = next;
    _nextId = null;
    _resetCurrent();
    // 前瞻是預備好才接上的。
    _loaded = true;
    _add(_events, SourceAdvanced(from: current, to: next, end: end));
    _emitStatus();
    // 播完的那一個移掉，清單回到只有目前這一個。
    unawaited(setNext(null).catchError(_logEditError));
  }

  /// 前一個來源交接時的位置：最後一次事件的位置，播放中就外推到現在。
  Duration _positionAtHandover() {
    final event = _lastEvent;
    if (event == null) return Duration.zero;
    var position = event.updatePosition;
    if (_player.playing && event.processingState == ProcessingState.ready) {
      position += DateTime.now().difference(event.updateTime);
    }
    final duration = event.duration;
    return duration != null && position > duration ? duration : position;
  }

  void _onError(PlayerException error) {
    final id = _idAt(error.index) ?? _currentId;
    if (id == null) return;
    if (id == _nextId) {
      _failLookAhead(id, error);
      return;
    }
    if (id != _currentId) return;
    _fail(
      id,
      _loaded ? BackendFailure.interrupted : BackendFailure.open,
      error,
    );
  }

  /// 交給 Dart 的錯誤只有 `Source error` 這類文字，沒有 HTTP 狀態碼（見
  /// `AudioBackend`），所以 [SourceFailed.httpStatus] 一律是 `null`。
  void _fail(int id, BackendFailure failure, Object cause) {
    if (id != _currentId || _settled) return;
    _settled = true;
    _add(_events, SourceFailed(id: id, failure: failure, cause: cause));
  }

  /// 前瞻開不起來（錯誤的索引是前瞻）。ExoPlayer 只在換到前瞻之後才報這種錯誤
  /// （上一首已經播完）：先報前瞻的失敗、再報上一首結束，ExoPlayer 停在錯誤，
  /// 不再說在播。
  void _failLookAhead(int id, PlayerException error) {
    final handover = _pendingHandover;
    _pendingHandover = null;
    _nextId = null;
    _add(
      _events,
      SourceFailed(id: id, failure: BackendFailure.open, cause: error),
    );
    if (handover == null) return;
    if (!_settled) {
      _settled = true;
      _add(_events, SourceEnded(id: handover.from, end: handover.end));
    }
    _ended = true;
    _emitStatus();
  }

  /// 引擎換到前瞻、還沒確定接上時，前瞻被換掉或清掉（佇列改了）：上一首已經
  /// 播完。停下引擎，被換掉的那首不出聲；報上一首結束，`PlaybackSession` 照一般
  /// 的下一首開流。
  Future<void> _abandonHandover(_PendingHandover handover) async {
    _pendingHandover = null;
    _nextId = null;
    _ended = true;
    if (!_settled) {
      _settled = true;
      _add(_events, SourceEnded(id: handover.from, end: handover.end));
    }
    _emitStatus();
    await _player.stop();
  }

  void _onPosition(Duration position) {
    final id = _currentId;
    // 換到前瞻、還沒確定接上時的位置是前瞻的。
    if (id == null || !_loaded || _pendingHandover != null) return;
    _add(
      _progress,
      SourceProgress(
        sourceId: id,
        progress: PlaybackProgress(
          position: position,
          duration: _player.duration,
          buffered: _player.bufferedPosition,
        ),
      ),
    );
  }

  void _logEditError(Object error, StackTrace stackTrace) => _log.warning(
    'Failed to edit the playlist',
    tag: 'playback',
    error: error,
    stackTrace: stackTrace,
  );

  static void _add<T>(StreamController<T> controller, T value) {
    if (!controller.isClosed) controller.add(value);
  }
}

final class _PendingHandover {
  const _PendingHandover({
    required this.from,
    required this.to,
    required this.end,
  });

  final int from;
  final int to;

  /// 上一首怎麼結束的（換過去那一刻算）。
  final TrackEndReason end;
}
