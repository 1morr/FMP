import 'dart:async';

import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';

/// 測試用的音訊後端：記下呼叫，狀態由測試用 [emit] 推進。照真的後端的
/// 習慣，[load] 先發 loading 再發 ready（失敗時發 failed 再丟錯），[play]、
/// [pause] 改 `playing`；載入預載的那條是換過去（`switch`），正在放的那條
/// 什麼都不做（`load current`）。[advance] 模擬原生自己接到預載的那條。
class FakeAudioBackend implements AudioBackend {
  final _states = StreamController<AudioBackendState>.broadcast(sync: true);

  /// 依序載入過的串流。
  final loaded = <AudioStream>[];

  /// 依序收到的呼叫：`load`、`switch`、`load current`、`preload`、
  /// `preload null`、`play`、`pause`、`seek <毫秒>`、`dispose`。
  final calls = <String>[];

  /// 依序收到的 [preload]（含 null）。
  final preloads = <AudioStream?>[];

  /// 目前排在後面的那條。
  AudioStream? preloaded;

  /// 正在放的那條（照真的後端：自己接到預載的那條時，先記帳再發狀態）。
  AudioStream? _current;

  /// 設了就讓下一次 [load] 丟它（只丟一次）。
  AudioBackendError? failNextLoad;

  /// 設了就讓它回傳錯誤的串流都開不了（例如某一首的 CDN 一直回 403）。
  AudioBackendError? Function(AudioStream stream)? failLoadOf;

  /// 設了就讓 [load] 等它完成才回來，用來測載入途中又點了別首。
  Completer<void>? holdLoad;

  /// 設了就讓下一次 [play] 丟它（只丟一次）。
  AudioBackendError? failNextPlay;

  /// 設了就讓下一次 [seek] 丟它（只丟一次）。
  AudioBackendError? failNextSeek;

  /// [load] 開好時回報的長度。
  Duration? loadedDuration = const Duration(minutes: 3);

  bool disposed = false;

  @override
  AudioBackendState state = const AudioBackendState();

  @override
  Stream<AudioBackendState> get states => _states.stream;

  /// 把狀態改成 [next] 並發出去，像原生播放器回報的一樣。
  void emit(AudioBackendState next) {
    state = next;
    if (!_emitting) {
      _emitting = true;
      try {
        _states.add(next);
      } finally {
        _emitting = false;
      }
      return;
    }
    // 聽眾在收這一個時又叫後端做事（例如播完接著換到預載的那條）：同步的
    // broadcast 不能重入，排到後面發，順序不變。
    _deferred.add(next);
    if (_deferred.length == 1) scheduleMicrotask(_flush);
  }

  bool _emitting = false;
  final _deferred = <AudioBackendState>[];

  void _flush() {
    final pending = [..._deferred];
    _deferred.clear();
    pending.forEach(emit);
  }

  @override
  Future<void> load(AudioStream stream) async {
    loaded.add(stream);
    if (identical(stream, _current)) {
      calls.add('load current');
      return;
    }
    final switching = identical(stream, preloaded);
    calls.add(switching ? 'switch' : 'load');
    preloaded = null;
    _current = stream;
    emit(AudioBackendState(stream: stream, status: AudioBackendStatus.loading));
    await holdLoad?.future;
    if (failNextLoad ?? failLoadOf?.call(stream) case final error?) {
      failNextLoad = null;
      // 照真的後端：先發 failed 再丟錯。
      emit(
        state.copyWith(status: AudioBackendStatus.failed, error: () => error),
      );
      throw error;
    }
    emit(
      state.copyWith(
        status: AudioBackendStatus.ready,
        duration: () => loadedDuration,
      ),
    );
  }

  @override
  Future<void> preload(AudioStream? stream) async {
    calls.add(stream == null ? 'preload null' : 'preload');
    preloads.add(stream);
    if (_current == null) return;
    preloaded = stream;
  }

  /// 模擬原生播放器播完目前這條、自己接到預載的那條：先為目前這條發
  /// completed，再發預載那條的 ready、照舊在播。沒有預載時只發 completed。
  void advance() {
    final next = preloaded;
    preloaded = null;
    if (next != null) _current = next;
    emit(state.copyWith(status: AudioBackendStatus.completed));
    if (next == null) return;
    emit(
      AudioBackendState(
        stream: next,
        status: AudioBackendStatus.ready,
        playing: state.playing,
        duration: loadedDuration,
      ),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (failNextPlay case final error?) {
      failNextPlay = null;
      throw error;
    }
    emit(state.copyWith(playing: true));
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
    if (failNextSeek case final error?) {
      failNextSeek = null;
      throw error;
    }
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(state.copyWith(playing: false));
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
    await _states.close();
  }
}
