import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';

/// 音訊後端：宿主自己的播放器介面（brief §6）。Android、iOS、macOS 的實作
/// 用 just_audio，Windows 用 media_kit（`playback/backends/`）；依平台挑哪個
/// 在 `platform/audio_backend.dart`。
///
/// 一次只放一條串流。M0 只有載入、播放、暫停、狀態與錯誤；佇列、seek、
/// 預載下一首在 M1。
///
/// 實作負責把原生播放器的錯誤轉成錯誤分類（[AudioBackendError]），呼叫端
/// 負責寫 log。[state] 與 [states] 從載入起才有意義；實作不寫 log，也不在
/// [AudioBackendError.detail] 以外帶出原生訊息。
abstract interface class AudioBackend {
  /// 目前的狀態。
  AudioBackendState get state;

  /// 狀態每變一次發一次（含位置前進），不重播目前的值，讀 [state] 拿。
  Stream<AudioBackendState> get states;

  /// 開啟 [stream]，請求時帶上它的 header；開好後停在開頭、不自動播放。
  /// 取代原本放的串流。開不了時先把 [state] 改成 failed，再丟
  /// [AudioBackendError]。還沒開好就被下一次 [load] 取代時直接回來，不丟錯，
  /// 狀態歸下一次。
  Future<void> load(AudioStream stream);

  /// 開始或繼續播放。不等播完。
  Future<void> play();

  Future<void> pause();

  /// 停止並釋放原生播放器；之後不能再用。
  Future<void> dispose();
}

/// 後端的處理狀態，照 just_audio 的 `ProcessingState` 加上 [failed]。
enum AudioBackendStatus {
  /// 沒有載入串流。
  idle,

  /// 正在開啟串流。
  loading,

  /// 開好了但資料不夠，等網路。
  buffering,

  /// 可以播（是否在播看 [AudioBackendState.playing]）。
  ready,

  /// 播到結尾。
  completed,

  /// 播放中出錯，原因在 [AudioBackendState.error]。
  failed,
}

class AudioBackendState {
  const AudioBackendState({
    this.status = AudioBackendStatus.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  final AudioBackendStatus status;

  /// 使用者要它播（按了播放、沒按暫停）；[status] 是 [AudioBackendStatus.buffering]
  /// 時也可能是真，這時還沒出聲。
  final bool playing;

  final Duration position;

  /// 串流的長度；還不知道時是 null。後端回報 0 時照實給 0（事實 I4、W4）。
  final Duration? duration;

  /// [status] 是 [AudioBackendStatus.failed] 時的原因。
  final AudioBackendError? error;

  AudioBackendState copyWith({
    AudioBackendStatus? status,
    bool? playing,
    Duration? position,
    Duration? Function()? duration,
    AudioBackendError? Function()? error,
  }) => AudioBackendState(
    status: status ?? this.status,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration == null ? this.duration : duration(),
    error: error == null ? this.error : error(),
  );

  @override
  bool operator ==(Object other) =>
      other is AudioBackendState &&
      other.status == status &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, playing, position, duration, error);

  @override
  String toString() =>
      'AudioBackendState(${status.name}, playing: $playing, '
      '$position / $duration, $error)';
}

/// 原生播放器的錯誤，已轉成錯誤分類。
class AudioBackendError implements Exception {
  const AudioBackendError(this.category, this.detail);

  final AppError category;

  /// 原生播放器的代碼與訊息，只寫進 log（log 門面會遮蔽網址）。
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is AudioBackendError &&
      other.category.toString() == category.toString() &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(category.toString(), detail);

  @override
  String toString() => 'AudioBackendError($category: $detail)';
}
