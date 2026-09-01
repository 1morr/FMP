/// 音频处理状态枚举（替代 just_audio.ProcessingState）
enum FmpAudioProcessingState {
  /// 没有加载音频
  idle,

  /// 正在加载音频源
  loading,

  /// 播放过程中缓冲
  buffering,

  /// 准备好播放
  ready,

  /// 播放完成
  completed,
}

/// 播放器状态（从 media_kit 事件合成）
class FmpPlayerState {
  final bool playing;
  final FmpAudioProcessingState processingState;

  const FmpPlayerState({
    required this.playing,
    required this.processingState,
  });

  @override
  String toString() {
    return 'FmpPlayerState(playing: $playing, processingState: $processingState)';
  }
}

/// 平台无关的音频设备类型
/// Windows/Linux 使用 media_kit 的 AudioDevice 转换而来
/// Android/iOS 不支持设备切换，使用空列表
class FmpAudioDevice {
  /// 设备标识名（对应 media_kit AudioDevice.name）
  final String name;

  /// 设备描述（对应 media_kit AudioDevice.description）
  final String description;

  const FmpAudioDevice({
    required this.name,
    this.description = '',
  });

  /// 自动选择设备（系统默认）
  static const auto = FmpAudioDevice(name: 'auto');
}

/// 播放為什麼停下來。
///
/// **翻譯責任在後端。** `JustAudioService` / `MediaKitAudioService` 各自把引擎
/// 的原生訊息翻成這些型別，`AudioController` 只做 switch，不再比對字串。
///
/// 這樣做的直接原因是實測：同一個網路條件下兩個後端連「哪個事件通道會響」都
/// 不一致（一邊 completed、一邊 error），而 mpv 的音訊輸出失敗訊息
/// （`Could not open/initialize audio device`）剛好落進「媒體開啟失敗」的關鍵
/// 字表裡，被誤判成歌曲本身壞掉（issue #41）。字串比對治不好這件事，因為同一
/// 個子字串在兩種語意上都成立。
sealed class PlaybackEndReason {
  const PlaybackEndReason();
}

/// 正常播完。
final class EndedNaturally extends PlaybackEndReason {
  const EndedNaturally();

  @override
  String toString() => 'EndedNaturally()';
}

/// 引擎宣告結束，但明顯還沒播完。
///
/// [expected] 為 null 代表引擎從未回報過時長 —— 「開了流但一個位元組都沒有」
/// 就是這個形狀，而它過去會被當成正常播完而直接跳下一首。
final class EndedPrematurely extends PlaybackEndReason {
  const EndedPrematurely({required this.at, this.expected});

  final Duration at;
  final Duration? expected;

  @override
  String toString() => 'EndedPrematurely(at: $at, expected: $expected)';
}

/// 傳輸層失敗的細分類別。
enum TransportFailureKind { reset, timeout, dns, tls, refused, unknown }

/// 傳輸層失敗：連線中斷、逾時、DNS、TLS。
///
/// [raw] 只保留供日誌與診斷，**不再是判斷依據**。
final class TransportFailed extends PlaybackEndReason {
  const TransportFailed({required this.kind, required this.raw});

  final TransportFailureKind kind;
  final String raw;

  @override
  String toString() => 'TransportFailed(kind: $kind, raw: $raw)';
}

/// 音訊**輸出裝置**失敗 —— 與媒體本身無關。這一條就是 issue #41。
final class OutputDeviceFailed extends PlaybackEndReason {
  const OutputDeviceFailed({required this.raw});

  final String raw;

  @override
  String toString() => 'OutputDeviceFailed(raw: $raw)';
}

/// 媒體本身打不開：URL 過期、404、容器/編碼不支援。
final class MediaUnopenable extends PlaybackEndReason {
  const MediaUnopenable({required this.raw});

  final String raw;

  @override
  String toString() => 'MediaUnopenable(raw: $raw)';
}

/// 解碼器失敗（媒體開得起來但解不出來）。
final class DecoderFailed extends PlaybackEndReason {
  const DecoderFailed({required this.raw});

  final String raw;

  @override
  String toString() => 'DecoderFailed(raw: $raw)';
}

/// 後端回報了一個無法歸類的失敗。
///
/// 行為上等同於過去的「靜默丟棄」，但至少是**顯性**的：它會被記錄下來，
/// 而不是消失在一串 `if (contains(...))` 之後。
final class UnclassifiedFailure extends PlaybackEndReason {
  const UnclassifiedFailure({required this.raw});

  final String raw;

  @override
  String toString() => 'UnclassifiedFailure(raw: $raw)';
}

/// media_kit 后端在媒体打开后仍长时间停留在 idle（加载失败）时抛出。
///
/// `RadioController` 以型别判断是否要以重新取得串流网址的方式重试，
/// 取代过去对错误消息子字符串（'Stream failed to open'）的比对——
/// 跨平台一致且对消息文字变动免疫。
class StreamOpenFailedException implements Exception {
  final String? message;
  const StreamOpenFailedException([this.message]);

  @override
  String toString() => message != null
      ? 'StreamOpenFailedException: $message'
      : 'StreamOpenFailedException';
}
