import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import '../../core/logger.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import 'audio_types.dart';
import 'playback_capabilities.dart';

/// 自定义 AudioHandler，用于 Android 媒体通知控制
///
/// 按钮与 `systemActions` 一律由 [PlaybackCapabilities] 决定，绑定则由
/// [NowPlayingPublisher] 一并设置。过去这里是写死的 `const`，导致电台播放时
/// 通知栏照样画出上／下一首（issue #40 症状一）。
class FmpAudioHandler extends BaseAudioHandler with SeekHandler, Logging {
  // 回调函数，由 NowPlayingPublisher 设置
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration position)? onSeek;
  Future<void> Function(LoopMode mode)? onSetLoopMode;
  Future<void> Function(bool enabled)? onSetShuffleEnabled;

  FmpAudioHandler() {
    logInfo('FmpAudioHandler created');
  }

  PlaybackCapabilities _capabilities = PlaybackCapabilities.none;

  /// 目前对外宣告的能力。
  PlaybackCapabilities get capabilities => _capabilities;

  /// 更新对外宣告的能力，并立刻重发一次 `PlaybackState`。
  void updateCapabilities(PlaybackCapabilities capabilities) {
    _capabilities = capabilities;
    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(playbackState.value.playing),
      systemActions: _systemActionsFor(),
    ));
    logDebug('Updated capabilities: $capabilities');
  }

  /// 获取媒体控制按钮列表
  List<MediaControl> _controlsFor(bool isPlaying) {
    return [
      if (_capabilities.canSkipPrevious) MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (_capabilities.canSkipNext) MediaControl.skipToNext,
    ];
  }

  Set<MediaAction> _systemActionsFor() {
    return {
      if (_capabilities.canSeek) ...{
        MediaAction.seek,
        // 這兩個沒有對應的 override，是刻意的：SeekHandler（見 class 宣告的
        // mixin）已經實作 seekForward / seekBackward / fastForward / rewind，
        // 全部收斂到底下那個 seek()。別以為沒人處理就把它們拿掉。
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      if (_capabilities.canSkipNext) MediaAction.skipToNext,
      if (_capabilities.canSkipPrevious) MediaAction.skipToPrevious,
      if (_capabilities.canRepeat) MediaAction.setRepeatMode,
      if (_capabilities.canShuffle) MediaAction.setShuffleMode,
    };
  }

  /// 更新当前播放的媒体项（从 Track 转换）
  void updateCurrentMediaItem(Track track) {
    final item = MediaItem(
      id: track.uniqueKey,
      title: track.title,
      artist: track.artist ?? t.smtc.unknownArtist,
      artUri:
          track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      duration: track.durationMs != null
          ? Duration(milliseconds: track.durationMs!)
          : null,
    );
    mediaItem.add(item);
    logDebug('Updated media item: ${track.title}');
  }

  /// 更新当前播放的电台
  void updateCurrentRadioStation(RadioStation station) {
    final item = MediaItem(
      id: 'radio_${station.id}',
      title: station.title,
      artist: t.smtc.liveRadio,
      artUri: station.thumbnailUrl != null
          ? Uri.parse(station.thumbnailUrl!)
          : null,
    );
    mediaItem.add(item);
    logDebug('Updated media item for radio: ${station.title}');
  }

  /// 更新播放状态
  ///
  /// `androidCompactActionIndices` 刻意**不设定**：留成 `null` 时 audio_service
  /// 的 Android 端自己算 `[0..min(3, 按钮数))`（`AudioService.java:614-617`），
  /// 所以按钮数缩到 1–2 个时不可能越界。写死 `[0,1,2]` 才会。
  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required FmpAudioProcessingState processingState,
    double speed = 1.0,
  }) {
    final audioProcessingState = _mapProcessingState(processingState);

    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(isPlaying),
      systemActions: _systemActionsFor(),
      processingState: audioProcessingState,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: bufferedPosition,
      speed: speed,
    ));
  }

  /// 更新循环与随机模式
  ///
  /// 两个模式一起发：它们共用同一则 `PlaybackState`，分开发等于白发一次。
  void updatePlayModes({
    required LoopMode loopMode,
    required bool shuffleEnabled,
  }) {
    playbackState.add(playbackState.value.copyWith(
      repeatMode: _loopModeToRepeatMode(loopMode),
      shuffleMode: shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
    logDebug('Updated play modes: loop=$loopMode shuffle=$shuffleEnabled');
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

  /// 转换 AudioServiceRepeatMode 到 LoopMode
  ///
  /// `group` 是 audio_service 的分组循环，FMP 没有这个概念，按「全部循环」处理。
  LoopMode _repeatModeToLoopMode(AudioServiceRepeatMode repeatMode) {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.none;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        return LoopMode.all;
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
    await onSetLoopMode?.call(_repeatModeToLoopMode(repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    logDebug('AudioHandler.setShuffleMode() called: $shuffleMode');
    await onSetShuffleEnabled?.call(shuffleMode != AudioServiceShuffleMode.none);
  }
}
