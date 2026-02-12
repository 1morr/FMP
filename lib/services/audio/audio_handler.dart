import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import 'audio_types.dart';

/// 自定义 AudioHandler，用于 Android 媒体通知控制
/// 提供上一首、下一首、随机播放、循环模式等控制按钮
class FmpAudioHandler extends BaseAudioHandler with SeekHandler, Logging {
  // 回调函数，由 AudioController 设置
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration position)? onSeek;
  Future<void> Function(AudioServiceRepeatMode mode)? onSetRepeatMode;
  Future<void> Function(AudioServiceShuffleMode mode)? onSetShuffleMode;

  FmpAudioHandler() {
    logInfo('FmpAudioHandler created');
  }

  /// 初始化播放状态
  void initPlaybackState({
    bool isPlaying = false,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
    AudioServiceShuffleMode shuffleMode = AudioServiceShuffleMode.none,
  }) {
    playbackState.add(PlaybackState(
      controls: _getControls(isPlaying),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2], // 紧凑视图中显示的按钮索引
      processingState: AudioProcessingState.idle,
      playing: isPlaying,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
      repeatMode: repeatMode,
      shuffleMode: shuffleMode,
    ));
  }

  /// 获取媒体控制按钮列表
  List<MediaControl> _getControls(bool isPlaying) {
    return [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      // MediaControl.stop, // 可选：添加停止按钮
    ];
  }

  /// 更新当前播放的媒体项（从 Track 转换）
  void updateCurrentMediaItem(Track track) {
    final item = MediaItem(
      id: track.uniqueKey,
      title: track.title,
      artist: track.artist ?? t.smtc.unknownArtist,
      artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
    );
    mediaItem.add(item);
    logDebug('Updated media item: ${track.title}');
  }

  /// 更新播放状态
  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required FmpAudioProcessingState processingState,
    Duration? duration,
    double speed = 1.0,
  }) {
    final audioProcessingState = _mapProcessingState(processingState);

    playbackState.add(playbackState.value.copyWith(
      controls: _getControls(isPlaying),
      processingState: audioProcessingState,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: bufferedPosition,
      speed: speed,
    ));
  }

  /// 更新循环模式
  void updateRepeatMode(LoopMode loopMode) {
    final audioRepeatMode = _loopModeToRepeatMode(loopMode);
    playbackState.add(playbackState.value.copyWith(
      repeatMode: audioRepeatMode,
    ));
    logDebug('Updated repeat mode: $audioRepeatMode');
  }

  /// 更新随机播放模式
  void updateShuffleMode(bool isShuffleEnabled) {
    final audioShuffleMode = isShuffleEnabled
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;
    playbackState.add(playbackState.value.copyWith(
      shuffleMode: audioShuffleMode,
    ));
    logDebug('Updated shuffle mode: $audioShuffleMode');
  }

  /// 映射 FmpAudioProcessingState 到 AudioProcessingState
  AudioProcessingState _mapProcessingState(FmpAudioProcessingState state) {
    switch (state) {
      case FmpAudioProcessingState.idle:
        return AudioProcessingState.idle;
      case FmpAudioProcessingState.loading:
        return AudioProcessingState.loading;
      case FmpAudioProcessingState.buffering:
        return AudioProcessingState.buffering;
      case FmpAudioProcessingState.ready:
        return AudioProcessingState.ready;
      case FmpAudioProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 转换 LoopMode 到 AudioServiceRepeatMode
  AudioServiceRepeatMode _loopModeToRepeatMode(LoopMode loopMode) {
    switch (loopMode) {
      case LoopMode.none:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  // ========== AudioHandler 回调方法 ==========

  @override
  Future<void> play() async {
    logDebug('AudioHandler.play() called');
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    logDebug('AudioHandler.pause() called');
    await onPause?.call();
  }

  @override
  Future<void> stop() async {
    logDebug('AudioHandler.stop() called');
    await onStop?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    logDebug('AudioHandler.skipToNext() called');
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    logDebug('AudioHandler.skipToPrevious() called');
    await onSkipToPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    logDebug('AudioHandler.seek() called: $position');
    await onSeek?.call(position);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    logDebug('AudioHandler.setRepeatMode() called: $repeatMode');
    await onSetRepeatMode?.call(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    logDebug('AudioHandler.setShuffleMode() called: $shuffleMode');
    await onSetShuffleMode?.call(shuffleMode);
  }
}
