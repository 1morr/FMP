import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

/// Android 的系統媒體控制（design §8.3）：以 `audio_service` 顯示通知與鎖定
/// 畫面、接媒體鍵。
///
/// 播放仍由 `JustAudioBackend` 負責，`audio_service` 只當作「媒體工作階段」：
/// 通知上的按鈕、進度條與媒體鍵經 [commands] 回到控制器。
final class AndroidSystemMediaControls implements SystemMediaControls {
  AndroidSystemMediaControls._(this._handler, Log log) {
    // audio_service 在背景做的事失敗時（例如前景服務被拒絕）只進這個 stream，
    // 不聽就沒有人知道。只記 log，不提示使用者。
    _asyncErrors = reportAsyncErrors(audio.AudioService.asyncError, log);
  }

  /// 初始化 `audio_service`（要在 `runApp` 前、開好資料庫後呼叫；失敗時丟出，
  /// 由 `AppPlatform.withMediaControls` 改宣告為沒有）。[log] 記初始化之後
  /// `audio_service` 回報的非同步錯誤。
  static Future<AndroidSystemMediaControls> init(Log log) async {
    final handler = await audio.AudioService.init(
      builder: _Handler.new,
      config: const audio.AudioServiceConfig(
        // 使用者在系統設定看得到的通知頻道名稱。
        androidNotificationChannelId: 'com.personal.fmp.playback',
        androidNotificationChannelName: 'FMP',
        // 暫停時放掉前景服務，通知可以滑掉（舊版也是這樣）。因中斷而暫停的期間
        // 例外：那時對 audio_service 回報還在播放（MediaPhase.interrupted），
        // 前景服務不放；中斷結束續播時 App 在背景，audio_service 的
        // startForegroundService 會被 Android 12 起拒絕，服務不在前景就約一分
        // 鐘後被停、再約一分半後被凍結，音樂就停了。
        androidStopForegroundOnPause: true,
      ),
    );
    return AndroidSystemMediaControls._(handler, log);
  }

  final _Handler _handler;
  late final StreamSubscription<Object> _asyncErrors;

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
    handler.playbackState.add(androidPlaybackStateOf(nowPlaying));
  }

  @override
  Future<void> dispose() async {
    await _asyncErrors.cancel();
    await _handler.close();
  }
}

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

/// 推給 `audio_service` 的播放狀態。[MediaPhase.interrupted] 對成「在播放、
/// 緩衝中」：系統不依速度推算進度，`audio_service` 也不放掉前景服務。
audio.PlaybackState androidPlaybackStateOf(NowPlaying nowPlaying) =>
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
