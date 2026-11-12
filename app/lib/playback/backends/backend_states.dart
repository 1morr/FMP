import 'dart:async';

import 'package:fmp/playback/audio_backend.dart';

/// 兩個音訊後端共用的狀態保管：合併原生播放器零散的事件、只在變了時發出，
/// 失敗後黏住 [AudioBackendStatus.failed]，直到下一次載入（[reset]）。
class BackendStates {
  final _controller = StreamController<AudioBackendState>.broadcast();

  AudioBackendState current = const AudioBackendState();

  Stream<AudioBackendState> get stream => _controller.stream;

  /// 套用原生播放器的一個事件。失敗後什麼都不接受：原生播放器出錯後常
  /// 再報 idle 或 ready，不能蓋掉失敗。
  void update(AudioBackendState Function(AudioBackendState) change) {
    if (current.status == AudioBackendStatus.failed) return;
    _set(change(current));
  }

  /// 播放中出錯。
  void fail(AudioBackendError error) {
    if (current.status == AudioBackendStatus.failed) return;
    _set(
      current.copyWith(
        status: AudioBackendStatus.failed,
        playing: false,
        error: () => error,
      ),
    );
  }

  /// 開始載入新串流：清掉上一條的位置、長度與錯誤。
  void reset() =>
      _set(const AudioBackendState(status: AudioBackendStatus.loading));

  void _set(AudioBackendState next) {
    if (next == current) return;
    current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> close() => _controller.close();
}
