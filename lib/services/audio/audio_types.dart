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
class MediaKitPlayerState {
  final bool playing;
  final FmpAudioProcessingState processingState;

  const MediaKitPlayerState({
    required this.playing,
    required this.processingState,
  });

  @override
  String toString() {
    return 'MediaKitPlayerState(playing: $playing, processingState: $processingState)';
  }
}
