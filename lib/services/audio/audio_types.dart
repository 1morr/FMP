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
