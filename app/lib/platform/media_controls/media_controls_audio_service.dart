import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

/// 推給 `audio_service` 的曲目資訊。`file://` 的 [NowPlaying.artworkFile] 由
/// `audio_service` 直接交給平台（Android 與 macOS 都是；darwin 端讀它設的
/// `extras['artCacheFile']`），不再自己下載，所以不傳 `cacheManager`。
audio.MediaItem audioServiceMediaItemOf(NowPlaying nowPlaying) =>
    audio.MediaItem(
      id: nowPlaying.id,
      title: nowPlaying.title,
      artist: nowPlaying.uploader,
      duration: nowPlaying.duration,
      artUri: nowPlaying.artworkFile,
    );

/// 把 [errors]（`AudioService.asyncError`）的每一筆記進 [log]，不提示使用者。
/// `audio_service` 的 stream 是私有的，測試只能注入假的 [errors]。
StreamSubscription<Object> reportAsyncErrors(Stream<Object> errors, Log log) =>
    errors.listen(
      (error) => log.report(
        'The system media session reported an error',
        AppError.wrap(error, StackTrace.current),
        tag: 'media-controls',
      ),
    );

/// 推給 `audio_service` 的播放狀態（Android 與 macOS 共用）。[MediaPhase.interrupted] 對成「在播放、
/// 緩衝中」：系統不依速度推算進度，`audio_service` 也不放掉前景服務。
audio.PlaybackState audioServicePlaybackStateOf(NowPlaying nowPlaying) =>
    audio.PlaybackState(
      controls: [
        for (final control in nowPlaying.controls)
          switch (control) {
            MediaControl.previous => audio.MediaControl.skipToPrevious,
            MediaControl.play => audio.MediaControl.play,
            MediaControl.pause => audio.MediaControl.pause,
            MediaControl.next => audio.MediaControl.skipToNext,
          },
      ],
      // seek 讓 Android 13 起的通知有進度條；不放快轉、倒轉。直播沒有時長與可 seek
      // 的位置，不給 seek。
      systemActions: {
        if (nowPlaying.seekable) audio.MediaAction.seek,
        audio.MediaAction.stop,
      },
      processingState: switch (nowPlaying.phase) {
        MediaPhase.idle => audio.AudioProcessingState.idle,
        MediaPhase.loading => audio.AudioProcessingState.loading,
        MediaPhase.buffering ||
        MediaPhase.interrupted => audio.AudioProcessingState.buffering,
        MediaPhase.ready => audio.AudioProcessingState.ready,
      },
      playing: nowPlaying.playing,
      updatePosition: nowPlaying.position,
      speed: nowPlaying.speed,
    );

/// `audio_service` 的 handler：只把系統的呼叫轉成 [MediaCommand]，不改任何
/// 狀態（控制器是唯一的寫入者）。
final class AudioServiceCommandHandler extends audio.BaseAudioHandler {
  final _commands = StreamController<MediaCommand>.broadcast();

  Stream<MediaCommand> get commands => _commands.stream;

  Future<void> close() => _commands.close();

  @override
  Future<void> play() async => _emit(const MediaPlay());

  @override
  Future<void> pause() async => _emit(const MediaPause());

  @override
  Future<void> skipToNext() async => _emit(const MediaNext());

  @override
  Future<void> skipToPrevious() async => _emit(const MediaPrevious());

  @override
  Future<void> seek(Duration position) async => _emit(MediaSeek(position));

  @override
  Future<void> stop() async => _emit(const MediaStop());

  void _emit(MediaCommand command) {
    if (!_commands.isClosed) _commands.add(command);
  }
}
