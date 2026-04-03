import '../../data/models/play_queue.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import 'audio_types.dart';

/// 播放状态
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
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int? currentIndex;

  /// 实际正在播放的歌曲（可能是临时播放的歌曲，也可能是队列中的歌曲）
  /// UI 应使用此字段显示当前播放的歌曲
  final Track? playingTrack;

  /// 队列中当前位置的歌曲（可能与 playingTrack 不同，例如临时播放时）
  final Track? queueTrack;
  final List<Track> queue;
  final List<Track> upcomingTracks;

  /// 隊列版本號，每次隊列結構變化（打亂、恢復順序等）時遞增
  /// 用於讓 UI 檢測是否需要同步
  final int queueVersion;

  /// 是否處於 Mix 播放模式
  final bool isMixMode;

  /// Mix 播放列表標題（隊列頁顯示用）
  final String? mixTitle;

  /// 是否正在加載更多 Mix 歌曲
  final bool isLoadingMoreMix;
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
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.none,
    this.currentIndex,
    this.playingTrack,
    this.queueTrack,
    this.queue = const [],
    this.upcomingTracks = const [],
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.queueVersion = 0,
    this.isMixMode = false,
    this.mixTitle,
    this.isLoadingMoreMix = false,
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

  /// 是否可以播放上一首（由 QueueManager 计算，考虑 shuffle 模式）
  final bool canPlayPrevious;

  /// 是否可以播放下一首（由 QueueManager 计算，考虑 shuffle 模式）
  final bool canPlayNext;

  PlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    FmpAudioProcessingState? processingState,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? currentIndex,
    Track? playingTrack,
    bool clearPlayingTrack = false,
    Track? queueTrack,
    List<Track>? queue,
    List<Track>? upcomingTracks,
    bool? canPlayPrevious,
    bool? canPlayNext,
    int? queueVersion,
    bool? isMixMode,
    String? mixTitle,
    bool? isLoadingMoreMix,
    String? error,
    int? retryAttempt,
    bool? isNetworkError,
    bool? isRetrying,
    DateTime? nextRetryAt,
    int? currentBitrate,
    String? currentContainer,
    String? currentCodec,
    StreamType? currentStreamType,
    List<FmpAudioDevice>? audioDevices,
    FmpAudioDevice? currentAudioDevice,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isLoading: isLoading ?? this.isLoading,
      processingState: processingState ?? this.processingState,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      currentIndex: currentIndex ?? this.currentIndex,
      playingTrack:
          clearPlayingTrack ? null : (playingTrack ?? this.playingTrack),
      queueTrack: queueTrack ?? this.queueTrack,
      queue: queue ?? this.queue,
      upcomingTracks: upcomingTracks ?? this.upcomingTracks,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      queueVersion: queueVersion ?? this.queueVersion,
      isMixMode: isMixMode ?? this.isMixMode,
      mixTitle: mixTitle ?? this.mixTitle,
      isLoadingMoreMix: isLoadingMoreMix ?? this.isLoadingMoreMix,
      error: error,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      isNetworkError: isNetworkError ?? this.isNetworkError,
      isRetrying: isRetrying ?? this.isRetrying,
      nextRetryAt: nextRetryAt,
      currentBitrate: currentBitrate ?? this.currentBitrate,
      currentContainer: currentContainer ?? this.currentContainer,
      currentCodec: currentCodec ?? this.currentCodec,
      currentStreamType: currentStreamType ?? this.currentStreamType,
      audioDevices: audioDevices ?? this.audioDevices,
      currentAudioDevice: currentAudioDevice ?? this.currentAudioDevice,
    );
  }
}
