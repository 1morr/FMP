import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import 'audio_types.dart';

/// 單曲播放狀態。
///
/// **佇列的形狀不在這裡。** 內容、索引、隨機／迴圈、Mix 身分全部住在
/// `QueueState`（`queue_state.dart`），由 `queueStateProvider` 送出。這兩個
/// 型別曾經各存一份同樣的 12 個欄位，靠 `AudioController` 每次逐欄位抄過去
/// 維持一致 —— 抄漏一個就是一個看不見的 bug。位置每秒更新一次而佇列很少變，
/// 分開也讓佇列清單不必跟著位置重建。
class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isLoading;
  final FmpAudioProcessingState processingState;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;

  /// 實際正在播放的歌曲（可能是臨時播放的歌曲，也可能是佇列中的歌曲）
  /// UI 應使用此欄位顯示當前播放的歌曲
  final Track? playingTrack;
  final String? error;

  // ========== 网络重试状态 ==========
  /// 当前重试次数 (0 = 未重试)
  final int retryAttempt;

  /// 是否为网络错误
  final bool isNetworkError;

  /// 是否正在重试中
  final bool isRetrying;

  /// 下次重试时间（用于 UI 倒计时显示）
  final DateTime? nextRetryAt;

  // ========== 音频流元信息 ==========
  /// 当前音频流码率 (bps)
  final int? currentBitrate;

  /// 当前音频流容器格式 (mp4, webm, m4a)
  final String? currentContainer;

  /// 当前音频流编码 (aac, opus)
  final String? currentCodec;

  /// 当前流类型 (audioOnly, muxed, hls)
  final StreamType? currentStreamType;

  // ========== 音频输出设备 ==========
  /// 可用音频输出设备列表
  final List<FmpAudioDevice> audioDevices;

  /// 当前音频输出设备
  final FmpAudioDevice? currentAudioDevice;

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isLoading = false,
    this.processingState = FmpAudioProcessingState.idle,
    this.position = Duration.zero,
    this.duration,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.playingTrack,
    this.error,
    this.retryAttempt = 0,
    this.isNetworkError = false,
    this.isRetrying = false,
    this.nextRetryAt,
    this.currentBitrate,
    this.currentContainer,
    this.currentCodec,
    this.currentStreamType,
    this.audioDevices = const [],
    this.currentAudioDevice,
  });

  /// 向后兼容：返回正在播放的歌曲
  Track? get currentTrack => playingTrack;

  /// 是否有歌曲在播放/暂停
  bool get hasCurrentTrack => currentTrack != null;

  /// 当前进度百分比 (0.0 - 1.0)
  double get progress {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration!.inMilliseconds;
  }

  /// 缓冲进度百分比 (0.0 - 1.0)
  double get bufferedProgress {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return bufferedPosition.inMilliseconds / duration!.inMilliseconds;
  }

  PlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    FmpAudioProcessingState? processingState,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    Track? playingTrack,
    bool clearPlayingTrack = false,
    String? error,
    int? retryAttempt,
    bool? isNetworkError,
    bool? isRetrying,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    int? currentBitrate,
    String? currentContainer,
    String? currentCodec,
    StreamType? currentStreamType,
    bool replaceCurrentStreamMetadata = false,
    List<FmpAudioDevice>? audioDevices,
    FmpAudioDevice? currentAudioDevice,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isLoading: isLoading ?? this.isLoading,
      processingState: processingState ?? this.processingState,
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      playingTrack:
          clearPlayingTrack ? null : (playingTrack ?? this.playingTrack),
      error: error,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      isNetworkError: isNetworkError ?? this.isNetworkError,
      isRetrying: isRetrying ?? this.isRetrying,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      currentBitrate: replaceCurrentStreamMetadata
          ? currentBitrate
          : (currentBitrate ?? this.currentBitrate),
      currentContainer: replaceCurrentStreamMetadata
          ? currentContainer
          : (currentContainer ?? this.currentContainer),
      currentCodec: replaceCurrentStreamMetadata
          ? currentCodec
          : (currentCodec ?? this.currentCodec),
      currentStreamType: replaceCurrentStreamMetadata
          ? currentStreamType
          : (currentStreamType ?? this.currentStreamType),
      audioDevices: audioDevices ?? this.audioDevices,
      currentAudioDevice: currentAudioDevice ?? this.currentAudioDevice,
    );
  }
}
