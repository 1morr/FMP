import 'dart:async';

import 'package:fmp/domain/audio_stream.dart';
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

  /// 自己接到預載那條之後，原生還可能報上一條的位置（AVPlayer 2026-11-18
  /// 實測：接過去後還報了一次上一條結尾再往後的位置）：大於或等於這個值的
  /// 不收，直到報出比它小的（新那條從頭播）。
  Duration? _staleFrom;

  /// 原生報的播放位置。
  void position(Duration position) {
    if (_staleFrom case final stale?) {
      if (position >= stale) return;
      _staleFrom = null;
    }
    update((s) => s.copyWith(position: position));
  }

  /// 開始載入 [stream]（或換到預載的它）：清掉上一條的位置、長度與錯誤。
  void reset(AudioStream stream) {
    _staleFrom = null;
    _set(AudioBackendState(stream: stream, status: AudioBackendStatus.loading));
  }

  /// 原生播放器自己接到預載的 [next]：先為目前這條報一次播完，再從 [next]
  /// 的開頭報起，照舊在播（介面 [AudioBackend.preload] 的約定）。之後的狀態
  /// 由原生接著更新。
  void advancedTo(AudioStream next) {
    final playing = current.playing;
    _staleFrom = current.position;
    _set(current.copyWith(status: AudioBackendStatus.completed));
    _set(
      AudioBackendState(
        stream: next,
        status: AudioBackendStatus.buffering,
        playing: playing,
      ),
    );
  }

  void _set(AudioBackendState next) {
    if (next == current) return;
    current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> close() => _controller.close();
}
