import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/playback_media.dart';

/// 音訊播放服務抽象介面
/// Android: JustAudioService (ExoPlayer)
/// Windows: MediaKitAudioService (libmpv)
///
/// **音訊焦點與中斷處理只有 Android 有**，不屬於這個介面的共同契約：
/// `audio_session` 只為 android、ios、macos、web 出 plugin，Windows 上
/// `setActive` 什麼都不做就回傳 true，`interruptionEventStream` 與
/// `becomingNoisyEventStream` 永遠不發事件。所以來電 duck、中斷暫停、拔耳機
/// 暫停都是 Android 專屬行為，不要替 `MediaKitAudioService` 寫斷言它們的測試。
///
/// 其餘兩個後端不一樣、而上層會碰到的地方，寫在各成員上。只是 API 名稱或
/// 內部做法不同、語意一致的（速度、`stop()` 要清哪些欄位、gapless 推進訊號
/// 從哪裡來）不列。
abstract class FmpAudioService {
  // === Lifecycle ===
  Future<void> initialize();
  Future<void> dispose();

  // === Streams ===
  Stream<FmpPlayerState> get playerStateStream;
  Stream<bool> get playingStream;

  /// Android 直譯 ExoPlayer 的狀態。桌面沒有對應的狀態可讀，是用 media_kit 的
  /// 幾個 stream 合成的：`buffering` 來自它的 `stream.buffering`，而且
  /// 必須排在「正在播放」之前判斷 —— 反過來的話桌面永遠報不出播放中的
  /// buffering，T3 緩衝飢餓看門狗在 Windows 上就不可達（`16318b87` 修過）。
  Stream<FmpAudioProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// 兩邊的量級不同，不能拿來推斷網路進度。Android 是 ExoPlayer 目前這一段
  /// 已緩衝到哪裡（`AndroidLoadControl` 上限 20 秒）；桌面的 mpv 設了
  /// `cache-secs=7200`，整首歌會一口氣抓完，進度條很快就滿格。
  Stream<Duration> get bufferedPositionStream;
  Stream<double> get speedStream;

  /// 只有桌面有：Android 永遠是空清單，[audioDeviceStream] 永遠是 null，
  /// [setAudioDevice] / [setAudioDeviceAuto] 什麼都不做。UI 用
  /// `isDesktopPlatform` 決定要不要畫選擇器，不是看清單是否為空。
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

  /// 開流並開始播放，回傳時長。**回傳的時機兩邊不同**，上層不能把「回傳了」
  /// 當成「已經在出聲」：
  /// - Android 在來源設好後就回傳，`play()` 不 await —— just_audio 的 `play()`
  ///   會等平台請求完成，首播可能卡好幾秒，UI 會一直停在載入中。所以上層的
  ///   `PlaybackTimeoutBudget.mediaOpen` 在 Android 上只量到來源設好為止。
  /// - 桌面最多等 5 秒到 ready 才呼叫 `play()`；0.5 秒後仍是 idle 就丟
  ///   `StreamOpenFailedException`。這段期間使用者按了暫停，會照樣回傳但不播。
  ///
  /// [playUrl] / [playFile] 同理。
  Future<Duration?> playMedia(PreparedPlaybackMedia media);
  Future<Duration?> setMedia(PreparedPlaybackMedia media);
  Future<Duration?> playUrl(
    String url, {
    Map<String, String>? headers,
    Track? track,
  });
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Track? track,
  });
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
