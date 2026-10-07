import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;

import 'package:fmp/platform/media_controls/media_controls.dart';

/// Android 的系統媒體控制（design §8.3）：以 `audio_service` 顯示通知與鎖定
/// 畫面、接媒體鍵。
///
/// 播放仍由 `JustAudioBackend` 負責，`audio_service` 只當作「媒體工作階段」：
/// 通知上的按鈕、進度條與媒體鍵經 [commands] 回到控制器。
final class AndroidSystemMediaControls implements SystemMediaControls {
  AndroidSystemMediaControls._(this._handler);

  /// 初始化 `audio_service`（要在 `runApp` 前、開好資料庫後呼叫；失敗時丟出，
  /// 由 `AppPlatform.withMediaControls` 改宣告為沒有）。
  static Future<AndroidSystemMediaControls> init() async {
    final handler = await audio.AudioService.init(
      builder: _Handler.new,
      config: const audio.AudioServiceConfig(
        // 使用者在系統設定看得到的通知頻道名稱。
        androidNotificationChannelId: 'com.personal.fmp.playback',
        androidNotificationChannelName: 'FMP',
        // 暫停時放掉前景服務，通知可以滑掉（舊版也是這樣）。
        androidStopForegroundOnPause: true,
      ),
    );
    return AndroidSystemMediaControls._(handler);
  }

  final _Handler _handler;

  @override
  Stream<MediaCommand> get commands => _handler.commands;

  @override
  Future<void> publish(NowPlaying nowPlaying) async {
    final handler = _handler;
    if (nowPlaying.hasTrack) {
      handler.mediaItem.add(
        audio.MediaItem(
          id: nowPlaying.id,
          title: nowPlaying.title,
          artist: nowPlaying.uploader,
          duration: nowPlaying.duration,
          // file:// 的 artUri 由 audio_service 直接交給平台，不再自己下載
          // （所以不傳 cacheManager）。
          artUri: nowPlaying.artworkFile,
        ),
      );
    }
    handler.playbackState.add(
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
        // seek 讓 Android 13 起的通知有進度條；不放快轉、倒轉。
        systemActions: const {audio.MediaAction.seek, audio.MediaAction.stop},
        processingState: switch (nowPlaying.phase) {
          MediaPhase.idle => audio.AudioProcessingState.idle,
          MediaPhase.loading => audio.AudioProcessingState.loading,
          MediaPhase.buffering => audio.AudioProcessingState.buffering,
          MediaPhase.ready => audio.AudioProcessingState.ready,
        },
        playing: nowPlaying.playing,
        updatePosition: nowPlaying.position,
        speed: nowPlaying.speed,
      ),
    );
  }

  @override
  Future<void> dispose() => _handler.close();
}

/// `audio_service` 的 handler：只把系統的呼叫轉成 [MediaCommand]，不改任何
/// 狀態（控制器是唯一的寫入者）。
final class _Handler extends audio.BaseAudioHandler {
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
