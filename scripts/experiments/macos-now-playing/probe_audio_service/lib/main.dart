import 'package:audio_service/audio_service.dart';
import 'package:probe_common/probe_common.dart';

/// 候選一：audio_service。播放器本身仍是 probe_common 的 just_audio，
/// audio_service 只當 Now Playing 的橋（M1 若採用也會這樣用：後端介面在宿主）。
Future<void> main() => runProbe(_AudioServiceBridge());

class _AudioServiceBridge implements NowPlayingBridge {
  late final _Handler _handler;

  @override
  String get name => 'audio_service';

  @override
  Future<void> init(PlayerController controller) async {
    _handler = await AudioService.init(
      builder: () => _Handler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.personal.fmp.exp.now_playing',
        androidNotificationChannelName: 'Now Playing 實驗',
      ),
    );
  }

  @override
  Future<void> setTrack(TrackInfo track) async {
    _handler.mediaItem.add(
      MediaItem(
        id: '${track.index}',
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        artUri: track.artUrl != null ? Uri.parse(track.artUrl!) : Uri.file(track.artPath),
      ),
    );
  }

  @override
  Future<void> setPlayback({required bool playing, required Duration position}) async {
    _handler.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ),
    );
  }
}

class _Handler extends BaseAudioHandler {
  _Handler(this.c);
  final PlayerController c;

  @override
  Future<void> play() async {
    c.logCommand('play');
    await c.play();
  }

  @override
  Future<void> pause() async {
    c.logCommand('pause');
    await c.pause();
  }

  @override
  Future<void> skipToNext() async {
    c.logCommand('next');
    await c.next();
  }

  @override
  Future<void> skipToPrevious() async {
    c.logCommand('previous');
    await c.previous();
  }

  @override
  Future<void> seek(Duration position) async {
    c.logCommand('seek', position.inMilliseconds);
    await c.seek(position);
  }

  @override
  Future<void> stop() async {
    c.logCommand('stop');
    await c.pause();
  }

  // togglePlayPause 在 audio_service 的原生端轉成 click(MediaButton.media)，
  // BaseAudioHandler 預設依 playbackState.playing 呼叫 play/pause，這裡多記一筆。
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    c.logCommand('click', button.name);
    await super.click(button);
  }
}
