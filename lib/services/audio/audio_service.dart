import 'audio_types.dart';
import '../../data/models/track.dart';
import 'playback_media.dart';

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
  Stream<List<FmpAudioDevice>> get audioDevicesStream;
  Stream<FmpAudioDevice?> get audioDeviceStream;

  /// 播放為什麼停下來 —— 正常播完與各種失敗走同一條通道。
  ///
  /// 取代先前的 `completedStream` + `Stream<String> errorStream`：實測顯示兩個
  /// 後端對同一個網路條件會選用不同的通道（一邊 completed、一邊 error），
  /// 分成兩條流會逼上層去猜。翻譯成 [PlaybackEndReason] 的責任在後端。
  Stream<PlaybackEndReason> get endReasons;

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
  Future<Duration?> playMedia(PreparedPlaybackMedia media);
  Future<Duration?> setMedia(PreparedPlaybackMedia media);
  Future<Duration?> playUrl(String url,
      {Map<String, String>? headers, Track? track});
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers, Track? track});
  Future<Duration?> playFile(String filePath, {Track? track});
  Future<Duration?> setFile(String filePath, {Track? track});

  // === Next Medium ===

  /// 交給後端「緊接著這一個之後要播的媒體」。傳 null 清除。
  ///
  /// 後端會把它先開起來，並在目前媒體自然播完時**自己**接上去。這段期間推進權
  /// 屬於後端 —— 控制器不會收到 [EndedNaturally]，改為收到 [advancedToNext]。
  ///
  /// 只有在目前已經有媒體在播（或已設定）時才有意義；沒有的話後端會忽略它。
  Future<void> setNextMedia(PreparedPlaybackMedia? media);

  /// 後端自行接上前瞻媒體時發出，帶著當初交出去的那一個。
  ///
  /// 帶著身分而不是 `void`：交出去之後佇列還可能被改動，收到事件的一方要能
  /// 確認接上去的是不是自己當初交出去的那一個。
  Stream<PreparedPlaybackMedia> get advancedToNext;
}
