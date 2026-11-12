import 'dart:async';

import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';

/// 測試用的音訊後端：記下呼叫，狀態由測試用 [emit] 推進。照真的後端的
/// 習慣，[load] 先發 loading 再發 ready（失敗時發 failed 再丟錯），[play]、
/// [pause] 改 `playing`。
class FakeAudioBackend implements AudioBackend {
  final _states = StreamController<AudioBackendState>.broadcast(sync: true);

  /// 依序載入過的串流。
  final loaded = <AudioStream>[];

  /// 依序收到的呼叫：`load`、`play`、`pause`、`dispose`。
  final calls = <String>[];

  /// 設了就讓下一次 [load] 丟它（只丟一次）。
  AudioBackendError? failNextLoad;

  /// 設了就讓 [load] 等它完成才回來，用來測載入途中又點了別首。
  Completer<void>? holdLoad;

  /// 設了就讓下一次 [play] 丟它（只丟一次）。
  AudioBackendError? failNextPlay;

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
    _states.add(next);
  }

  @override
  Future<void> load(AudioStream stream) async {
    calls.add('load');
    loaded.add(stream);
    emit(const AudioBackendState(status: AudioBackendStatus.loading));
    await holdLoad?.future;
    if (failNextLoad case final error?) {
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
  Future<void> play() async {
    calls.add('play');
    if (failNextPlay case final error?) {
      failNextPlay = null;
      throw error;
    }
    emit(state.copyWith(playing: true));
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
