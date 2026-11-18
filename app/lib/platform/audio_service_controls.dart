import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart' show PlaybackStatus;

/// Android、iOS、macOS 的系統媒體控制：audio_service 的 handler 本身
/// （事實 K18）。[show] 的資訊轉成它的 `MediaItem` 與 `PlaybackState`，它
/// 收到的系統指令（通知、鎖屏、控制中心、媒體鍵）轉成 [MediaCommand]。播放器
/// 不在這裡，在宿主的音訊後端。
///
/// 播放／暫停鍵（媒體鍵、耳機鍵）由 audio_service 轉成 [click]，照
/// [playbackState] 的 `playing` 切換，所以 [show] 要即時；Android 的實體
/// 播放鍵、暫停鍵也被它當成切換（事實 A6）。
class AudioServiceControls extends BaseAudioHandler implements MediaControls {
  final _commands = StreamController<MediaCommand>.broadcast();

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  void show(NowPlaying? nowPlaying) {
    if (nowPlaying == null) {
      mediaItem.add(null);
      playbackState.add(PlaybackState());
      return;
    }
    final track = nowPlaying.track;
    final item = MediaItem(
      id: track.ref.logId,
      title: track.title,
      artist: track.author,
      duration: nowPlaying.duration,
      artUri: switch (track.coverUrl) {
        final url? => Uri.tryParse(url),
        null => null,
      },
    );
    if (mediaItem.value != item) mediaItem.add(item);
    final controls = [
      if (nowPlaying.canPrevious) MediaControl.skipToPrevious,
      nowPlaying.playing ? MediaControl.pause : MediaControl.play,
      if (nowPlaying.canNext) MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: [
          for (var i = 0; i < controls.length; i++) i,
        ],
        systemActions: {if (nowPlaying.duration != null) MediaAction.seek},
        processingState: switch (nowPlaying.status) {
          PlaybackStatus.resolving ||
          PlaybackStatus.loading => AudioProcessingState.loading,
          PlaybackStatus.buffering => AudioProcessingState.buffering,
          PlaybackStatus.playing ||
          PlaybackStatus.paused => AudioProcessingState.ready,
          PlaybackStatus.completed => AudioProcessingState.completed,
          PlaybackStatus.failed => AudioProcessingState.error,
        },
        playing: nowPlaying.playing,
        updatePosition: nowPlaying.position,
      ),
    );
  }

  @override
  Future<void> play() async => _commands.add(const PlayCommand());

  @override
  Future<void> pause() async => _commands.add(const PauseCommand());

  @override
  Future<void> skipToNext() async => _commands.add(const NextCommand());

  @override
  Future<void> skipToPrevious() async => _commands.add(const PreviousCommand());

  @override
  Future<void> seek(Duration position) async =>
      _commands.add(SeekCommand(position));

  /// Android 滑掉暫停中的通知、或系統要停止時：暫停就好，佇列與位置留著。
  @override
  Future<void> stop() async => _commands.add(const PauseCommand());
}
