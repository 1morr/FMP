import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart' show PlaybackStatus;

/// Android、iOS、macOS 的系統媒體控制：audio_service 的 handler 本身
/// （事實 K18）。[show] 的資訊轉成它的 `MediaItem` 與 `PlaybackState`，它
/// 收到的系統指令（通知、鎖屏、控制中心、媒體鍵）轉成 [MediaCommand]。播放器
/// 不在這裡，在宿主的音訊後端。
///
/// 播放／暫停鍵（媒體鍵、耳機鍵）由 audio_service 轉成 [click]，照
/// [playbackState] 的 `playing` 切換，所以 [show] 要即時。Android 的實體播放鍵、
/// 暫停鍵 audio_service 也當成切換（事實 A6），由 [mediaKeys] 修正：有曲目出現
/// 時裝一次（服務可能重建過）。
class AudioServiceControls extends BaseAudioHandler implements MediaControls {
  AudioServiceControls({this.mediaKeys});

  /// 只有 Android 有。
  final MediaKeyFix? mediaKeys;

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
    final previous = mediaItem.value;
    // MediaItem 的 == 只比 id：同一首的長度後來才知道時也要送。
    if (!_sameItem(previous, item)) mediaItem.add(item);
    if (previous?.id != item.id) unawaited(mediaKeys?.install());
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

  static bool _sameItem(MediaItem? a, MediaItem b) =>
      a != null &&
      a.id == b.id &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.duration == b.duration &&
      a.artUri == b.artUri;

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

/// 修正 Android 的媒體鍵（事實 A6）：audio_service 把真正的「播放」「暫停」鍵都
/// 當成切換，已暫停時收到「暫停」鍵會開始播放。原生端（`MediaKeyFix.java`）用
/// 反射把服務的 media session callback 換成會改寫鍵碼的版本，這裡只在服務建好後
/// 經 `fmp/media_keys` 叫它。失敗（服務還沒建好、反射失敗、頻道不在）只寫 debug
/// log，不影響播放；那時媒體鍵照 audio_service 原本的切換。
class MediaKeyFix {
  MediaKeyFix(this._log);

  static const _channel = MethodChannel('fmp/media_keys');

  final Log _log;

  /// 原生端有沒有裝好；任何失敗都是 false，不丟例外。
  Future<bool> install() async {
    try {
      final installed = await _channel.invokeMethod<bool>('install') ?? false;
      if (!installed) _log.debug('The media key fix was not installed');
      return installed;
    } on Object catch (error) {
      // MissingPluginException（沒有 Activity 的引擎）與 PlatformException 都不該
      // 動到播放。
      _log.debug('The media key fix failed', error: error);
      return false;
    }
  }
}
