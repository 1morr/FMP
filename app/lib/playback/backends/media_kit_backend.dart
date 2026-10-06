import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';

/// [AudioBackend] 的 media_kit（libmpv）實作：Windows。libmpv 由
/// `media_kit_libs_windows_audio` 在建置時下載、放在執行檔旁。
///
/// 播放清單裡的 `Media` 是這裡建的實例（media_kit 的清單保留原物件），以
/// [Expando] 對回 [BackendSource.id]；不用網址對，因為不同來源可以是同一個網址。
final class MediaKitBackend implements AudioBackend {
  MediaKitBackend._(this._log, this._player) {
    _ready = _configure();
    final stream = _player.stream;
    _subscriptions
      ..add(stream.playlist.listen(_onPlaylist))
      ..add(stream.playing.listen((_) => _emitStatus()))
      ..add(stream.buffering.listen((_) => _emitStatus()))
      ..add(stream.completed.listen(_onCompleted))
      ..add(stream.duration.listen(_onDuration))
      ..add(stream.position.listen(_onPosition))
      ..add(stream.error.listen(_onError))
      ..add(stream.log.listen(_onLog));
  }

  /// 第一次建立時載入 libmpv（`MediaKit.ensureInitialized`）；找不到就拋錯。
  factory MediaKitBackend.create({required Log log}) {
    MediaKit.ensureInitialized();
    return MediaKitBackend._(
      log,
      Player(
        configuration: const PlayerConfiguration(
          // Windows 音量混合器裡顯示的名稱。
          title: 'FMP',
          // HTTP 狀態碼只在 ffmpeg 的 warn log（`HTTP error 403 Forbidden`），
          // 預設的 error 收不到。
          logLevel: MPVLogLevel.warn,
        ),
      ),
    );
  }

  final Log _log;
  final Player _player;
  late final Future<void> _ready;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _sourceIds = Expando<int>('BackendSource.id');

  final _status = StreamController<BackendStatus>.broadcast();
  final _progress = StreamController<SourceProgress>.broadcast();
  final _events = StreamController<BackendEvent>.broadcast();

  int? _currentId;
  int? _nextId;

  /// 目前的來源已經載入（有時長或位置）；之前的錯誤算 [BackendFailure.open]。
  bool _loaded = false;
  bool _settled = false;

  /// 目前的來源是接上的前瞻：mpv 已經預先開好，載入前不必回報緩衝。
  bool _handedOver = false;

  /// mpv 已經換到前瞻（`playlist-playing-pos`），還不知道它開不開得起來：等它
  /// 回報位置或時長才發 [SourceAdvanced]，先收到錯誤就是前瞻開不起來。這段期間
  /// 目前的來源還是上一首。
  _PendingHandover? _pendingHandover;

  /// 前瞻在交接時開不起來，目前的來源（上一首）已經結束、mpv 停在清單結尾。
  bool _ended = false;

  /// ffmpeg 最近一次回報的 HTTP 錯誤狀態碼，交給下一個開流失敗。log 不帶項目，
  /// 所以每次開流、換前瞻時清掉，不讓上一個網址的狀態碼算到別的來源上。
  int? _httpStatus;

  /// [open] 之後、`Player.open` 回來之前。這段期間收到的位置、時長、結束與
  /// 錯誤還是上一個檔案的：media_kit 的事件不帶項目，`Player.open` 內的 mpv
  /// 指令是非同步的，等待時會先處理已經排著的舊事件。
  bool _opening = false;

  /// 目前來源回報過的最大位置與時長。用最大值：mpv 換檔時可能先回報新檔的
  /// `time-pos`，才換 `playlist-playing-pos`。
  Duration _position = Duration.zero;
  Duration? _duration;

  Future<void> _edits = Future.value();

  /// 使用者要不要出聲：[open] 的 `play`、[play]、[pause] 設定。
  bool _wantPlaying = false;

  @override
  Stream<BackendStatus> get status => _status.stream;

  @override
  Stream<SourceProgress> get progress => _progress.stream;

  @override
  Stream<BackendEvent> get events => _events.stream;

  /// mpv 的選項：預設是影片播放器，關掉影像；清單的第二個項目提早開流
  /// （預設 `no`），交接處才不用等。mpv 手冊說 `prefetch-playlist` 在用了
  /// per-file 選項時可能不準，media_kit 的標頭正是 per-file（`on_load` hook）；
  /// 舊專案以只認正確 Referer 的本機伺服器實測過，前瞻開流帶的標頭是對的。
  Future<void> _configure() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('vid', 'no');
    await platform.setProperty('prefetch-playlist', 'yes');
  }

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
    _opening = true;
    _httpStatus = null;
    return _edit(() async {
      if (_currentId != source.id) return;
      try {
        // 排隊期間的 pause／play 以當下的意願為準。
        await _player.open(_media(source, start: start), play: _wantPlaying);
      } on Object catch (error) {
        _fail(source.id, BackendFailure.open, error);
      } finally {
        if (_currentId == source.id) _opening = false;
      }
    });
  }

  @override
  Future<void> setNext(BackendSource? next) {
    final owner = _currentId;
    if (owner == null) return Future.value();
    _nextId = next?.id;
    _httpStatus = null;
    return _edit(() async {
      if (_currentId != owner) return;
      if (_pendingHandover case final handover? when handover.to != next?.id) {
        await _abandonHandover(handover);
        return;
      }
      final playlist = _player.state.playlist;
      final edit = LookAheadEdit.of(
        itemCount: playlist.medias.length,
        currentIndex: playlist.index,
        append: next != null,
      );
      for (final index in edit.removeIndices) {
        await _player.remove(index);
      }
      if (!edit.append || next == null || _nextId != next.id) return;
      final Media media;
      try {
        media = _media(next);
      } on Object catch (error) {
        // asset 找不到之類，交給 mpv 前就失敗：目前的來源照常播完。
        _nextId = null;
        _add(
          _events,
          SourceFailed(id: next.id, failure: BackendFailure.open, cause: error),
        );
        return;
      }
      await _player.add(media);
    });
  }

  @override
  Future<void> play() async {
    _wantPlaying = true;
    await _ready;
    await _player.play();
    _emitStatus();
  }

  @override
  Future<void> pause() async {
    _wantPlaying = false;
    await _ready;
    await _player.pause();
    _emitStatus();
  }

  @override
  Future<void> seek(Duration position) async {
    await _ready;
    _position = position;
    await _player.seek(position);
  }

  @override
  Future<void> stop() {
    _currentId = null;
    _nextId = null;
    _wantPlaying = false;
    _resetCurrent();
    return _edit(() async {
      if (_currentId != null) return;
      await _player.stop();
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

  Media _media(BackendSource source, {Duration start = Duration.zero}) {
    final media = Media(
      source.url.toString(),
      httpHeaders: source.headers.isEmpty ? null : source.headers,
      start: start > Duration.zero ? start : null,
    );
    _sourceIds[media] = source.id;
    return media;
  }

  void _resetCurrent() {
    _loaded = false;
    _settled = false;
    _handedOver = false;
    _pendingHandover = null;
    _ended = false;
    _position = Duration.zero;
    _duration = null;
  }

  /// 清單的修改一個接一個做，每次依當下的清單算 [LookAheadEdit]。
  Future<void> _edit(Future<void> Function() change) {
    final done = _edits.then((_) async {
      await _ready;
      await change();
    });
    _edits = done.catchError(_logEditError);
    return done;
  }

  void _onPlaylist(Playlist playlist) {
    final index = playlist.index;
    if (index < 0 || index >= playlist.medias.length) return;
    final id = _sourceIds[playlist.medias[index]];
    final current = _currentId;
    if (id == null || current == null || id == current || id != _nextId) {
      return;
    }
    if (_pendingHandover != null) return;
    _pendingHandover = _PendingHandover(
      from: current,
      to: id,
      end: classifyTrackEnd(position: _position, duration: _duration),
    );
  }

  /// 換過去的前瞻回報了位置或時長：它開起來了，這時才算接上。
  void _completeHandover() {
    final handover = _pendingHandover!;
    _currentId = handover.to;
    _nextId = null;
    _resetCurrent();
    _handedOver = true;
    // mpv 的屬性只在值改變時發事件：兩個檔案一樣長時，接上後不會再收到
    // duration，所以先沿用引擎現在的值，不一樣時事件會再更新。
    final duration = _player.state.duration;
    if (duration > Duration.zero) _duration = duration;
    _add(
      _events,
      SourceAdvanced(from: handover.from, to: handover.to, end: handover.end),
    );
    _emitStatus();
    // 播完的那一個移掉，清單回到只有目前這一個。
    unawaited(setNext(null).catchError(_logEditError));
  }

  /// mpv 換檔的瞬間，`playing`、`buffering` 會閃一下（檔尾的 eof、下一個檔的
  /// START_FILE），而且那時目前的來源可能還是舊的。所以 `playing` 報的是使用者
  /// 要不要出聲（[_wantPlaying]，與 just_audio 的 `playing` 同義）；檔尾
  /// [completionTolerance] 之內、以及接上的前瞻回報位置之前，不報緩衝。
  void _emitStatus() {
    final state = _player.state;
    final id = _currentId;
    final duration = _duration;
    final nearEnd =
        state.completed ||
        (duration != null && duration - _position <= completionTolerance);
    final settling = _handedOver && !_loaded;
    final phase = switch (id) {
      null => BackendPhase.idle,
      _ when _ended => BackendPhase.ended,
      _ when _opening => BackendPhase.buffering,
      _ when state.completed && _nextId == null => BackendPhase.ended,
      // open 之後、檔案載入前，mpv 的旗標還沒反映新檔：載入前都算緩衝。
      _ when !_loaded && !_handedOver => BackendPhase.buffering,
      _ when state.buffering && !nearEnd && !settling => BackendPhase.buffering,
      _ => BackendPhase.ready,
    };
    _add(
      _status,
      BackendStatus(
        sourceId: id,
        playing: _wantPlaying && phase != BackendPhase.ended,
        phase: phase,
      ),
    );
  }

  void _onCompleted(bool completed) {
    _emitStatus();
    if (_opening) return;
    final id = _currentId;
    // 有前瞻時 mpv 會接著播下一個（接上時由 _onPlaylist 回報），這裡的
    // completed 只是換檔的瞬間。
    if (!completed || id == null || _nextId != null || _settled) return;
    _settled = true;
    _add(
      _events,
      SourceEnded(
        id: id,
        end: classifyTrackEnd(position: _position, duration: _duration),
      ),
    );
  }

  void _onDuration(Duration duration) {
    if (_currentId == null || _opening || duration <= Duration.zero) return;
    if (_pendingHandover != null) _completeHandover();
    _duration = duration;
    _markLoaded();
  }

  void _onPosition(Duration position) {
    if (_currentId == null || _opening) return;
    // 換過去後的第一個位置（接上的前瞻一開始會報 0 與負值的預捲）。開不起來的
    // 前瞻不會報位置。
    if (_pendingHandover != null) _completeHandover();
    final id = _currentId!;
    if (position > _position) _position = position;
    if (position > Duration.zero) _markLoaded();
    if (!_loaded) return;
    _add(
      _progress,
      SourceProgress(
        sourceId: id,
        progress: PlaybackProgress(
          position: position,
          duration: _duration,
          buffered: _player.state.buffer,
        ),
      ),
    );
  }

  void _markLoaded() {
    if (_loaded) return;
    _loaded = true;
    _emitStatus();
  }

  /// mpv 的錯誤只是一行 log，不帶項目：還沒載入就算開不起來；已經在播的
  /// 錯誤不在這裡處理，mpv 停下時由 [_onCompleted] 依位置判斷是否提前結束。
  ///
  /// 這行字可能帶完整的簽名網址（例如 `ffmpeg: Opening '…/videoplayback?…'`）：
  /// 只以 `error` 交給 log 門面（經 `Redactor` 遮蔽），不自己印、不放進訊息。
  void _onError(String message) {
    final id = _currentId;
    if (id == null || _opening) return;
    if (_pendingHandover case final handover?) {
      _failHandover(handover, message);
      return;
    }
    if (_loaded) {
      _log.warning(
        'Audio engine reported an error',
        tag: 'playback',
        error: message,
      );
      return;
    }
    _fail(id, BackendFailure.open, message);
  }

  void _fail(int id, BackendFailure failure, Object cause) {
    if (id != _currentId || _settled) return;
    _settled = true;
    _add(
      _events,
      SourceFailed(
        id: id,
        failure: failure,
        cause: cause,
        httpStatus: failure == BackendFailure.open ? _takeHttpStatus() : null,
      ),
    );
  }

  /// 換過去的前瞻在載入前出錯：它開不起來。上一首已經播完（mpv 是播完才換
  /// 過去的），先報前瞻的失敗、再報上一首結束；mpv 停在清單結尾，不再說在播。
  void _failHandover(_PendingHandover handover, String message) {
    _pendingHandover = null;
    _nextId = null;
    _add(
      _events,
      SourceFailed(
        id: handover.to,
        failure: BackendFailure.open,
        cause: message,
        httpStatus: _takeHttpStatus(),
      ),
    );
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

  int? _takeHttpStatus() {
    final status = _httpStatus;
    _httpStatus = null;
    return status;
  }

  void _onLog(PlayerLog log) {
    if (log.prefix != 'ffmpeg') return;
    if (httpStatusFromLogLine(log.text) case final status?) {
      _httpStatus = status;
    }
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
