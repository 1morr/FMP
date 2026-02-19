import 'audio_types.dart';
import '../../data/models/track.dart';

/// 音频播放服务抽象接口
/// Android: JustAudioService (ExoPlayer)
/// Windows/Linux: MediaKitAudioService (libmpv)
abstract class FmpAudioService {
  // === Lifecycle ===
  Future<void> initialize();
  Future<void> dispose();

  // === Streams ===
  Stream<FmpPlayerState> get playerStateStream;
  Stream<bool> get playingStream;
  Stream<FmpAudioProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<double> get speedStream;
  Stream<void> get completedStream;
  Stream<List<FmpAudioDevice>> get audioDevicesStream;
  Stream<FmpAudioDevice?> get audioDeviceStream;

  // === State Getters ===
  bool get isPlaying;
  Duration get position;
  Duration? get duration;
  Duration get bufferedPosition;
  double get speed;
  double get volume;
  FmpAudioProcessingState get processingState;
  List<FmpAudioDevice> get audioDevices;
  FmpAudioDevice? get audioDevice;

  // === Playback Control ===
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> togglePlayPause();

  // === Seeking ===
  Future<void> seekTo(Duration position);
  Future<void> seekForward([Duration? duration]);
  Future<void> seekBackward([Duration? duration]);
  Future<bool> seekToLive();

  // === Speed ===
  Future<void> setSpeed(double speed);
  Future<void> resetSpeed();

  // === Volume (0.0-1.0) ===
  Future<void> setVolume(double volume);

  // === Audio Device ===
  Future<void> setAudioDevice(FmpAudioDevice device);
  Future<void> setAudioDeviceAuto();

  // === Audio Source ===
  Future<Duration?> playUrl(String url, {Map<String, String>? headers, Track? track});
  Future<Duration?> setUrl(String url, {Map<String, String>? headers, Track? track});
  Future<Duration?> playFile(String filePath, {Track? track});
  Future<Duration?> setFile(String filePath, {Track? track});
}
