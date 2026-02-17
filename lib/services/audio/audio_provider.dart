import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show AudioDevice;
import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_exception.dart';
import '../../data/sources/youtube_source.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/play_history_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/lyrics_provider.dart';
import '../lyrics/lyrics_auto_match_service.dart';
import '../../core/services/toast_service.dart';
import '../../main.dart' show audioHandler, windowsSmtcHandler;
import 'audio_handler.dart';
import 'windows_smtc_handler.dart';
import 'audio_types.dart';
import 'media_kit_audio_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'queue_manager.dart';
import '../network/connectivity_service.dart';

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
  final List<AudioDevice> audioDevices;
  /// 当前音频输出设备
  final AudioDevice? currentAudioDevice;

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
    List<AudioDevice>? audioDevices,
    AudioDevice? currentAudioDevice,
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
      playingTrack: playingTrack ?? this.playingTrack,
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

/// 内部异常：表示重试已被安排，调用者不应再次安排重试
class _RetryScheduledException implements Exception {
  const _RetryScheduledException();
}

/// 播放模式枚举
enum PlayMode {
  /// 正常隊列播放
  queue,
  /// 臨時播放（播放完成後恢復原隊列位置）
  temporary,
  /// 脫離隊列（隊列被清空或修改後的狀態，播放的歌曲不在隊列中）
  detached,
  /// Mix 播放列表模式（無限加載，禁止隨機和添加歌曲）
  mix,
}

/// 統一的內部播放上下文
/// 管理播放模式、臨時播放狀態、加載狀態等
class _PlaybackContext {
  /// 當前播放模式
  final PlayMode mode;
  
  /// 活動的請求 ID（用於防止競態條件）
  /// 當 > 0 時，表示正在進行播放請求（通過 isInLoadingState 檢查）
  final int activeRequestId;

  /// 臨時播放保存的隊列索引
  final int? savedQueueIndex;
  
  /// 臨時播放保存的播放位置
  final Duration? savedPosition;
  
  /// 臨時播放保存的播放狀態（是否正在播放）
  final bool? savedWasPlaying;

  const _PlaybackContext({
    this.mode = PlayMode.queue,
    this.activeRequestId = 0,
    this.savedQueueIndex,
    this.savedPosition,
    this.savedWasPlaying,
  });

  /// 是否處於臨時播放模式
  bool get isTemporary => mode == PlayMode.temporary;

  /// 是否處於 Mix 播放模式
  bool get isMix => mode == PlayMode.mix;

  /// 是否處於加載狀態（正在進行播放請求）
  bool get isInLoadingState => activeRequestId > 0;
  
  /// 是否有保存的臨時播放狀態
  bool get hasSavedState => savedQueueIndex != null;

  _PlaybackContext copyWith({
    PlayMode? mode,
    int? activeRequestId,
    int? savedQueueIndex,
    Duration? savedPosition,
    bool? savedWasPlaying,
    bool clearSavedState = false,
  }) {
    return _PlaybackContext(
      mode: mode ?? this.mode,
      activeRequestId: activeRequestId ?? this.activeRequestId,
      savedQueueIndex: clearSavedState ? null : (savedQueueIndex ?? this.savedQueueIndex),
      savedPosition: clearSavedState ? null : (savedPosition ?? this.savedPosition),
      savedWasPlaying: clearSavedState ? null : (savedWasPlaying ?? this.savedWasPlaying),
    );
  }

  @override
  String toString() {
    return '_PlaybackContext(mode: $mode, activeRequestId: $activeRequestId, savedQueueIndex: $savedQueueIndex, savedPosition: $savedPosition, savedWasPlaying: $savedWasPlaying)';
  }
}

/// 带有请求 ID 的锁包装类
/// 用于确保只有正确的请求才能完成锁，避免完成错误的锁
class _LockWithId {
  final int requestId;
  final Completer<void> completer;

  _LockWithId(this.requestId) : completer = Completer<void>();

  /// 只有当锁仍然属于指定请求时才完成
  void completeIf(int expectedRequestId) {
    if (requestId == expectedRequestId && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// 检查锁是否属于指定请求
  bool belongsTo(int checkRequestId) => requestId == checkRequestId;
}

/// Mix 播放列表狀態
/// 用於追蹤 Mix 模式下的播放列表信息和去重
class _MixPlaylistState {
  /// Mix 播放列表 ID（以 RD 開頭）
  final String playlistId;

  /// 種子影片 ID（用於首次加載）
  final String seedVideoId;

  /// Mix 播放列表標題
  final String title;

  /// 已見過的影片 ID 集合（用於去重）
  final Set<String> seenVideoIds;

  /// 是否正在加載更多
  bool isLoadingMore = false;

  _MixPlaylistState({
    required this.playlistId,
    required this.seedVideoId,
    required this.title,
    Set<String>? seenVideoIds,
  }) : seenVideoIds = seenVideoIds ?? {};

  /// 添加影片 ID 到已見集合
  void addSeenVideoIds(Iterable<String> ids) {
    seenVideoIds.addAll(ids);
  }
}

/// 音频控制器 - 管理所有播放相关的状态和操作
/// 协调 AudioService（单曲播放）和 QueueManager（队列管理）
class AudioController extends StateNotifier<PlayerState> with Logging {
  final MediaKitAudioService _audioService;
  final QueueManager _queueManager;
  final ToastService _toastService;
  final FmpAudioHandler _audioHandler;
  final WindowsSmtcHandler _windowsSmtcHandler;
  final PlayHistoryRepository? _playHistoryRepository;
  final LyricsAutoMatchService? _lyricsAutoMatchService;
  final SettingsRepository? _settingsRepository;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;

  // 防止重复处理完成事件
  bool _isHandlingCompletion = false;

  // 播放锁 - 防止快速切歌时的竞态条件
  _LockWithId? _playLock;
  int _playRequestId = 0;

  // 导航请求ID - 防止快速点击 next/previous 时的竞态条件
  int _navRequestId = 0;

  // 統一的播放上下文（管理所有播放狀態，包括臨時播放、加載狀態等）
  _PlaybackContext _context = const _PlaybackContext();

  // 基于位置检测的备选切歌定时器（解决后台播放 completed 事件丢失问题）
  Timer? _positionCheckTimer;
  static const Duration _positionCheckInterval = Duration(seconds: 1);
  static const Duration _positionThreshold = Duration(milliseconds: 500);

  // 当前正在播放的歌曲（独立于队列，确保 UI 显示与实际播放一致）
  Track? _playingTrack;

  /// 播放開始前的回調（用於互斥機制，如停止電台播放）
  Future<void> Function()? onPlaybackStarting;

  /// 歌词自动匹配状态回调（用于 UI 显示加载动画）
  void Function(bool isMatching)? onLyricsAutoMatchStateChanged;

  // Mix 播放列表状态（僅在 Mix 模式下有效）
  _MixPlaylistState? _mixState;

  // ========== 网络重试相关 ==========
  /// 重试定时器
  Timer? _retryTimer;
  /// 当前重试次数
  int _retryAttempt = 0;
  /// 网络恢复后需要重新播放的歌曲
  Track? _trackToRecoverAfterReconnect;
  /// 网络恢复后需要恢复到的播放位置
  Duration? _positionToRecoverAfterReconnect;
  /// 网络恢复监听订阅
  StreamSubscription<void>? _networkRecoverySubscription;

  AudioController({
    required MediaKitAudioService audioService,
    required QueueManager queueManager,
    required ToastService toastService,
    required FmpAudioHandler audioHandler,
    required WindowsSmtcHandler windowsSmtcHandler,
    PlayHistoryRepository? playHistoryRepository,
    LyricsAutoMatchService? lyricsAutoMatchService,
    SettingsRepository? settingsRepository,
  })  : _audioService = audioService,
        _queueManager = queueManager,
        _toastService = toastService,
        _audioHandler = audioHandler,
        _windowsSmtcHandler = windowsSmtcHandler,
        _playHistoryRepository = playHistoryRepository,
        _lyricsAutoMatchService = lyricsAutoMatchService,
        _settingsRepository = settingsRepository,
        super(const PlayerState());

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    logInfo('Initializing AudioController...');

    try {
      await _audioService.initialize();
      logDebug('AudioService initialized');

      await _queueManager.initialize();
      logDebug('QueueManager initialized');

      // 保存需要恢复的位置（在设置监听器之前，避免被位置流覆盖）
      final positionToRestore = _queueManager.savedPosition;
      logDebug('Position to restore: $positionToRestore');

      // 监听播放器状态
      _subscriptions.add(
        _audioService.playerStateStream.listen(_onPlayerStateChanged),
      );

      // 监听进度
      _subscriptions.add(
        _audioService.positionStream.listen(_onPositionChanged),
      );

      // 监听时长
      _subscriptions.add(
        _audioService.durationStream.listen(_onDurationChanged),
      );

      // 监听缓冲进度
      _subscriptions.add(
        _audioService.bufferedPositionStream.listen(_onBufferedPositionChanged),
      );

      // 监听速度
      _subscriptions.add(
        _audioService.speedStream.listen(_onSpeedChanged),
      );

      // 监听音频设备列表变化
      _subscriptions.add(
        _audioService.audioDevicesStream.listen(_onAudioDevicesChanged),
      );

      // 监听当前音频设备变化
      _subscriptions.add(
        _audioService.audioDeviceStream.listen(_onAudioDeviceChanged),
      );

      // 监听歌曲完成事件
      _subscriptions.add(
        _audioService.completedStream.listen(_onTrackCompleted),
      );

      // 启动基于位置检测的备选切歌机制（解决后台播放 completed 事件丢失问题）
      _startPositionCheckTimer();

      // 监听队列状态变化
      _subscriptions.add(
        _queueManager.stateStream.listen(_onQueueStateChanged),
      );

      // 设置 AudioHandler 回调（仅在 Android/iOS 上有效）
      if (Platform.isAndroid || Platform.isIOS) {
        _setupAudioHandler();
      }

      // 设置 Windows SMTC 回调（仅在 Windows 上有效）
      if (Platform.isWindows) {
        _setupWindowsSmtc();
      }

      // 更新初始状态
      _updateQueueState();

      // 恢復 Mix 播放模式（如果之前是 Mix 模式）
      if (_queueManager.isMixMode) {
        final playlistId = _queueManager.mixPlaylistId;
        final seedVideoId = _queueManager.mixSeedVideoId;
        final title = _queueManager.mixTitle;

        if (playlistId != null && seedVideoId != null && title != null) {
          logDebug('Restoring Mix mode: $title');

          // Mix 模式不支持隨機播放，確保關閉
          if (_queueManager.isShuffleEnabled) {
            await _queueManager.setShuffle(false);
            state = state.copyWith(isShuffleEnabled: false);
          }

          _mixState = _MixPlaylistState(
            playlistId: playlistId,
            seedVideoId: seedVideoId,
            title: title,
          );
          // 將已有的歌曲添加到 seenVideoIds（避免重複加載）
          _mixState!.addSeenVideoIds(_queueManager.tracks.map((t) => t.sourceId));
          
          // 更新 context 和 state
          _context = _context.copyWith(mode: PlayMode.mix);
          state = state.copyWith(
            isMixMode: true,
            mixTitle: title,
          );
        }
      }

      // 恢复音量
      final savedVolume = _queueManager.savedVolume;
      await _audioService.setVolume(savedVolume);
      state = state.copyWith(volume: savedVolume);
      logDebug('Restored volume: $savedVolume');

      // 恢复播放（如果有保存的歌曲）
      if (_queueManager.currentTrack != null) {
        logDebug('Restoring saved track: ${_queueManager.currentTrack!.title}');
        // 不自动播放，只设置 URL，传入保存的位置
        await _prepareCurrentTrack(autoPlay: false, initialPosition: positionToRestore);
      }

      _isInitialized = true;
      _isInitializing = false;
      logInfo('AudioController initialized successfully');
    } catch (e, stack) {
      _isInitializing = false;
      logError('Failed to initialize AudioController', e, stack);
      state = state.copyWith(error: 'Initialization failed: $e');
      rethrow;
    }
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      logWarning('AudioController not initialized, initializing now...');
      await initialize();
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _stopPositionCheckTimer();
    _cancelRetryTimer();
    _networkRecoverySubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _mixState = null;
    _queueManager.dispose();
    _audioService.dispose();
    super.dispose();
  }

  // ========== 播放控制 ==========

  /// 播放
  Future<void> play() async {
    try {
      // 如果当前歌曲的 URL 已过期（如暂停过夜），重新获取 URL 并从当前位置恢复
      if (await _resumeWithFreshUrlIfNeeded()) return;
      await _audioService.play();
    } catch (e, stack) {
      logError('Failed to play', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      await _audioService.pause();
    } catch (e, stack) {
      logError('Failed to pause', e, stack);
    }
  }

  /// 切换播放/暂停
  /// 如果当前歌曲有错误状态，尝试重新播放当前歌曲
  Future<void> togglePlayPause() async {
    try {
      // 如果当前有网络错误状态，触发手动重试
      if (state.isNetworkError && state.currentTrack != null) {
        logDebug('Manual retry for network error: ${state.currentTrack!.title}');
        await retryManually();
        return;
      }
      // 如果当前有错误状态，尝试重新播放当前歌曲
      if (state.error != null && state.currentTrack != null) {
        logDebug('Retrying playback for track with error: ${state.currentTrack!.title}');
        await _playTrack(state.currentTrack!);
        return;
      }
      // 如果当前是暂停状态且 URL 已过期（如暂停过夜），重新获取 URL 并从当前位置恢复
      if (!state.isPlaying && await _resumeWithFreshUrlIfNeeded()) return;
      await _audioService.togglePlayPause();
    } catch (e, stack) {
      logError('Failed to togglePlayPause', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 停止
  Future<void> stop() async {
    await _audioService.stop();
    _clearPlayingTrack();
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    try {
      await _audioService.seekTo(position);
      // 立即保存位置，避免 seek 后马上关闭应用导致进度丢失
      await _queueManager.savePositionNow();
    } catch (e, stack) {
      logError('Failed to seekTo $position', e, stack);
    }
  }

  /// 跳转到百分比位置
  Future<void> seekToProgress(double progress) async {
    final duration = state.duration;
    if (duration != null) {
      final position = Duration(
        milliseconds: (duration.inMilliseconds * progress).round(),
      );
      await seekTo(position);
    }
  }

  /// 快进
  Future<void> seekForward([Duration? duration]) async {
    try {
      final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
      await _audioService.seekForward(seekDuration);
      // 立即保存位置
      await _queueManager.savePositionNow();
    } catch (e, stack) {
      logError('Failed to seekForward', e, stack);
    }
  }

  /// 快退
  Future<void> seekBackward([Duration? duration]) async {
    try {
      final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
      await _audioService.seekBackward(seekDuration);
      // 立即保存位置
      await _queueManager.savePositionNow();
    } catch (e, stack) {
      logError('Failed to seekBackward', e, stack);
    }
  }

  // ========== 队列控制 ==========

  /// 播放单首歌曲
  Future<void> playSingle(Track track) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置网络重试状态
    state = state.copyWith(isLoading: true, error: null);
    logInfo('Playing single track: ${track.title}');
    try {
      final savedTrack = await _queueManager.playSingle(track);
      await _playTrack(savedTrack);
    } catch (e, stack) {
      logError('Failed to play track: ${track.title}', e, stack);
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// 播放单首歌曲 (别名方法)
  Future<void> playTrack(Track track) => playSingle(track);

  /// 临时播放单首歌曲（播放完成后恢复原队列位置）
  /// 用于搜索页面和歌单页面点击歌曲时的行为
  Future<void> playTemporary(Track track) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置网络重试状态

    // 【重要】立即保存当前状态（在任何 async 操作之前，因为 stop() 会重置这些值）
    final savedPosition = _audioService.position;
    final savedIsPlaying = _audioService.isPlaying;

    logInfo('Playing temporary track: ${track.title}');

    // 只在第一次进入临时播放时保存状态（避免连续临时播放时覆盖原始状态）
    if (!_context.isTemporary) {
      if (_queueManager.currentTrack != null) {
        // 有队列歌曲：保存状态并进入临时模式
        _context = _context.copyWith(
          mode: PlayMode.temporary,
          savedQueueIndex: _queueManager.currentIndex,
          savedPosition: savedPosition,
          savedWasPlaying: savedIsPlaying,
        );
        logDebug('Saved playback state: index: ${_context.savedQueueIndex}, position: ${_context.savedPosition}');
      } else {
        // 没有队列歌曲：只设置模式（不保存状态）
        _context = _context.copyWith(mode: PlayMode.temporary);
      }
    }
    // 如果已经是 temporary 模式，保留原始保存的状态

    try {
      await _executePlayRequest(
        track: track,
        mode: PlayMode.temporary,
        persist: false,
        recordHistory: true,
        prefetchNext: false,
      );
    } on SourceApiException catch (e) {
      // 音源 API 错误：尝试恢复原队列
      logWarning('${e.sourceType.name} API error for temporary track ${track.title}: ${e.message}');
      if (e.isUnavailable || e.isGeoRestricted) {
        _toastService.showWarning(t.audio.cannotPlay(title: track.title));
      } else {
        _toastService.showError(t.audio.playbackFailed(message: e.message));
      }
      if (_context.hasSavedState) {
        await _restoreSavedState();
      } else {
        _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      }
    } catch (e, stack) {
      logError('Failed to play temporary track: ${track.title}', e, stack);
      _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      if (_context.hasSavedState) {
        await _restoreSavedState();
      } else {
        _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      }
    }
  }

  /// 恢复保存的播放状态
  /// 注意：直接使用当前队列，不恢复队列内容（用户可能在临时播放期间修改了队列）
  Future<void> _restoreSavedState() async {
    // 【重要】递增 _playRequestId 来取消任何正在进行的播放请求
    // 这样可以防止临时播放的 URL 获取完成后继续播放
    final requestId = ++_playRequestId;
    _context = _context.copyWith(activeRequestId: requestId);
    logDebug('_restoreSavedState started (requestId: $requestId)');

    // 检查是否有保存的状态
    if (!_context.hasSavedState) {
      logDebug('No saved state to restore');
      _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      return;
    }

    final savedIndex = _context.savedQueueIndex!;
    final savedPosition = _context.savedPosition ?? Duration.zero;
    final savedWasPlaying = _context.savedWasPlaying ?? false;

    logDebug('Restoring playback state: index: $savedIndex, position: $savedPosition');

    try {
      final queue = _queueManager.tracks;
      
      // 如果队列为空，直接退出临时播放模式
      if (queue.isEmpty) {
        logDebug('Queue is empty, exiting temporary play mode');
        _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
        _updateQueueState();
        return;
      }

      // 将索引限制在有效范围内（队列可能在临时播放期间被修改）
      final targetIndex = savedIndex.clamp(0, queue.length - 1);
      _queueManager.setCurrentIndex(targetIndex);

      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        // 【重要】立即更新 UI 和状态，让用户看到即时反馈
        _updatePlayingTrack(currentTrack);
        _updateQueueState();
        state = state.copyWith(isLoading: true, position: Duration.zero, error: null);
        await _audioService.stop();

        // 准备歌曲
        final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(currentTrack);
        
        // 【重要】检查是否被新请求取代（例如用户在恢复期间又点击了其他歌曲）
        if (_isSuperseded(requestId)) {
          logDebug('_restoreSavedState request $requestId superseded after URL fetch, aborting');
          return;
        }
        
        final url = localPath ?? trackWithUrl.audioUrl;

        if (url != null) {
          if (localPath != null) {
            await _audioService.setFile(url);
          } else {
            final headers = _getHeadersForTrack(trackWithUrl);
            await _audioService.setUrl(url, headers: headers);
          }
          
          // 检查是否被取代
          if (_isSuperseded(requestId)) {
            logDebug('_restoreSavedState request $requestId superseded after setUrl, aborting');
            await _audioService.stop();
            return;
          }

          // 更新正在播放的歌曲（可能有 URL 更新）
          _updatePlayingTrack(trackWithUrl);

          // 恢复播放位置（受"记住播放位置"设置控制）
          final positionSettings = await _queueManager.getPositionRestoreSettings();
          if (positionSettings.enabled && savedPosition > Duration.zero) {
            final rewind = Duration(seconds: positionSettings.tempPlayRewindSeconds);
            final restorePosition = savedPosition - rewind;
            await _audioService.seekTo(restorePosition.isNegative ? Duration.zero : restorePosition);
          }

          // 如果之前正在播放，恢复播放
          if (savedWasPlaying) {
            await _audioService.play();
            logDebug('Resumed playback after restore');
          }
        }
      }

      // 清除临时播放状态
      _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);

      _updateQueueState();
      logInfo('Playback state restored successfully');
    } catch (e, stack) {
      logError('Failed to restore playback state', e, stack);
      _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
    } finally {
      _resetLoadingState();
    }
  }

  /// 播放多首歌曲
  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    await _ensureInitialized();
    state = state.copyWith(isLoading: true, error: null);
    logInfo('Playing ${tracks.length} tracks, starting at index $startIndex');
    try {
      await _queueManager.playAll(tracks, startIndex: startIndex);
      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        await _playTrack(currentTrack);
      }
    } catch (e, stack) {
      logError('Failed to play tracks', e, stack);
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// 播放歌单 (别名方法)
  Future<void> playPlaylist(List<Track> tracks, {int startIndex = 0}) =>
      playAll(tracks, startIndex: startIndex);

  /// 播放 Mix 播放列表
  /// 
  /// Mix 播放列表是 YouTube 自動生成的播放列表（RD 開頭），使用特殊的播放模式：
  /// - 禁止隨機播放
  /// - 禁止添加/插入歌曲到隊列
  /// - 播放到最後一首時自動加載更多
  /// - 清空隊列時退出 Mix 模式
  Future<void> playMixPlaylist({
    required String playlistId,
    required String seedVideoId,
    required String title,
    required List<Track> tracks,
    int startIndex = 0,
  }) async {
    await _ensureInitialized();
    state = state.copyWith(isLoading: true, error: null);
    logInfo('Playing Mix playlist: $title with ${tracks.length} tracks');

    try {
      // 清空當前隊列並設置 Mix 模式
      await _queueManager.clear();

      // Mix 模式不支持隨機播放，強制關閉
      if (_queueManager.isShuffleEnabled) {
        await _queueManager.setShuffle(false);
        state = state.copyWith(isShuffleEnabled: false);
      }

      // 初始化 Mix 狀態
      _mixState = _MixPlaylistState(
        playlistId: playlistId,
        seedVideoId: seedVideoId,
        title: title,
      );
      // 記錄已加載的視頻 ID（用於去重）
      _mixState!.addSeenVideoIds(tracks.map((t) => t.sourceId));

      // 添加歌曲到隊列
      await _queueManager.playAll(tracks, startIndex: startIndex);

      // 持久化 Mix 狀態到數據庫
      await _queueManager.setMixMode(
        enabled: true,
        playlistId: playlistId,
        seedVideoId: seedVideoId,
        title: title,
      );

      // 更新 PlayerState（先設置，因為 _executePlayRequest 會重置 isLoading）
      state = state.copyWith(
        isMixMode: true,
        mixTitle: title,
      );

      // 播放第一首（使用 PlayMode.mix 以保持 Mix 模式）
      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        await _executePlayRequest(
          track: currentTrack,
          mode: PlayMode.mix,
          persist: true,
          recordHistory: true,
        );
      }
    } catch (e, stack) {
      logError('Failed to play Mix playlist', e, stack);
      _exitMixMode();
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// 退出 Mix 模式
  void _exitMixMode() {
    if (_mixState != null) {
      logDebug('Exiting Mix mode');
      _mixState = null;
      _context = _context.copyWith(mode: PlayMode.queue);
      state = state.copyWith(
        isMixMode: false,
        mixTitle: null,
      );
      // 清除持久化的 Mix 狀態
      _queueManager.clearMixMode();
    }
  }

  /// 播放队列中指定索引的歌曲
  Future<void> playAt(int index) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置网络重试状态
    logDebug('Playing at index: $index');
    try {
      _queueManager.setCurrentIndex(index);
      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        await _playTrack(currentTrack);
      }
    } catch (e, stack) {
      logError('Failed to play at index $index', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 下一首
  Future<void> next() async {
    await _ensureInitialized();
    _resetRetryState(); // 重置网络重试状态

    // 获取导航请求 ID，防止快速点击导致竞态条件
    final navId = ++_navRequestId;
    logDebug('next() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 检测是否脱离队列播放
    if (_isPlayingOutOfQueue) {
      logDebug('Playing out of queue: returning to queue');
      await _returnToQueue();
      return;
    }

    final nextIdx = _queueManager.moveToNext();
    if (nextIdx != null) {
      // 检查是否被更新的导航请求取代
      if (navId != _navRequestId) {
        logDebug('next() navId $navId superseded by $_navRequestId, aborting');
        return;
      }
      final track = _queueManager.currentTrack;
      if (track != null) {
        await _playTrack(track);
      }
    }
  }

  /// 上一首
  Future<void> previous() async {
    await _ensureInitialized();
    _resetRetryState(); // 重置网络重试状态

    // 获取导航请求 ID，防止快速点击导致竞态条件
    final navId = ++_navRequestId;
    logDebug('previous() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 检测是否脱离队列播放
    if (_isPlayingOutOfQueue) {
      logDebug('Playing out of queue: returning to queue');
      await _returnToQueue();
      return;
    }

    // 如果播放超过3秒，重新开始当前歌曲
    if (_audioService.position.inSeconds > 3) {
      await _audioService.seekTo(Duration.zero);
    } else {
      final prevIdx = _queueManager.moveToPrevious();
      if (prevIdx != null) {
        // 检查是否被更新的导航请求取代
        if (navId != _navRequestId) {
          logDebug('previous() navId $navId superseded by $_navRequestId, aborting');
          return;
        }
        final track = _queueManager.currentTrack;
        if (track != null) {
          await _playTrack(track);
        }
      }
    }
  }

  /// 添加到队列
  /// 
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addToQueue(Track track) async {
    await _ensureInitialized();
    
    // Mix 模式下禁止添加歌曲
    if (_context.isMix) {
      _toastService.showInfo(t.audio.mixPlaylistNoAdd);
      return false;
    }
    
    logInfo('Adding to queue: ${track.title}');
    try {
      final added = await _queueManager.add(track);
      if (!added) {
        _toastService.showError(t.audio.queueFull(count: AppConstants.maxQueueSize));
        return false;
      }
      _updateQueueState();
      return true;
    } catch (e, stack) {
      logError('Failed to add track to queue', e, stack);
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 批量添加到队列
  /// 
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addAllToQueue(List<Track> tracks) async {
    await _ensureInitialized();
    
    // Mix 模式下禁止添加歌曲
    if (_context.isMix) {
      _toastService.showInfo(t.audio.mixPlaylistNoAdd);
      return false;
    }
    
    logInfo('Adding ${tracks.length} tracks to queue');
    try {
      await _queueManager.addAll(tracks);
      _updateQueueState();
      return true;
    } catch (e, stack) {
      logError('Failed to add tracks to queue', e, stack);
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 添加到下一首
  /// 
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addNext(Track track) async {
    await _ensureInitialized();
    
    // Mix 模式下禁止添加歌曲
    if (_context.isMix) {
      _toastService.showInfo(t.audio.mixPlaylistNoAdd);
      return false;
    }
    
    logInfo('Adding next: ${track.title}');
    try {
      await _queueManager.addNext(track);
      _updateQueueState();
      return true;
    } catch (e, stack) {
      logError('Failed to add track as next', e, stack);
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 从队列移除
  Future<void> removeFromQueue(int index) async {
    await _ensureInitialized();
    logDebug('Removing from queue at index: $index');
    try {
      await _queueManager.removeAt(index);
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to remove from queue at index $index', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 移动队列中的歌曲
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    await _ensureInitialized();
    logDebug('Moving in queue: $oldIndex -> $newIndex');
    try {
      await _queueManager.move(oldIndex, newIndex);
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to move in queue', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 随机打乱队列（破坏性）
  Future<void> shuffleQueue() async {
    await _ensureInitialized();
    
    // Mix 模式下禁止隨機播放（UI 應該已禁用按鈕，這是額外保護）
    if (_context.isMix) return;
    
    logInfo('Shuffling queue');
    try {
      await _queueManager.shuffle();
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to shuffle queue', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 清空队列
  Future<void> clearQueue() async {
    await _ensureInitialized();
    logInfo('Clearing queue');
    try {
      await _queueManager.clear();
      
      // 退出 Mix 模式（如果有）
      if (_context.isMix) {
        _exitMixMode();
      }
      
      // 如果還有歌曲在播放，且不是臨時播放模式，則進入 detached 模式
      if (_playingTrack != null && !_context.isTemporary) {
        _context = _context.copyWith(mode: PlayMode.detached);
        logDebug('Entered detached mode after clearing queue');
      }
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to clear queue', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  // ========== 播放速度 ==========

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    await _audioService.setSpeed(speed);
  }

  /// 重置播放速度
  Future<void> resetSpeed() async {
    await _audioService.resetSpeed();
  }

  // ========== 播放模式 ==========

  /// 切换随机播放
  Future<void> toggleShuffle() async {
    // Mix 模式下禁止隨機播放（UI 應該已禁用按鈕，這是額外保護）
    if (_context.isMix) return;
    
    logDebug('Toggling shuffle');
    await _queueManager.toggleShuffle();
    state = state.copyWith(isShuffleEnabled: _queueManager.isShuffleEnabled);

    // 更新 AudioHandler 的随机播放状态（用于通知栏）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updateShuffleMode(_queueManager.isShuffleEnabled);
    }
  }

  /// 设置循环模式
  Future<void> setLoopMode(LoopMode mode) async {
    logDebug('Setting loop mode: $mode');
    await _queueManager.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);

    // 更新 AudioHandler 的循环模式（用于通知栏）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updateRepeatMode(mode);
    }
  }

  /// 循环切换循环模式
  Future<void> cycleLoopMode() async {
    await _queueManager.cycleLoopMode();
    state = state.copyWith(loopMode: _queueManager.loopMode);

    // 更新 AudioHandler 的循环模式（用于通知栏）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updateRepeatMode(_queueManager.loopMode);
    }
  }

  // ========== 音量 ==========

  // 静音前的音量（用于恢复）
  double _volumeBeforeMute = 1.0;

  /// 设置音量
  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 保存音量设置
    await _queueManager.saveVolume(volume);
  }

  /// 静音切换
  Future<void> toggleMute() async {
    if (state.volume > 0) {
      // 保存静音前的音量
      _volumeBeforeMute = state.volume;
      await setVolume(0);
    } else {
      // 恢复静音前的音量
      await setVolume(_volumeBeforeMute);
    }
  }

  /// 调整音量
  ///
  /// [delta] - 音量变化量，正数增加，负数减少
  Future<void> adjustVolume(double delta) async {
    final newVolume = (state.volume + delta).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  // ========== 音频输出设备 ========== //

  /// 设置音频输出设备
  Future<void> setAudioDevice(AudioDevice device) async {
    await _audioService.setAudioDevice(device);
  }

  /// 设置为自动选择音频设备（跟随系统默认）
  Future<void> setAudioDeviceAuto() async {
    await _audioService.setAudioDeviceAuto();
  }

  // ========== 基于位置检测的备选切歌机制（解决后台播放 completed 事件丢失问题）========== //

  void _startPositionCheckTimer() {
    _stopPositionCheckTimer();
    _positionCheckTimer = Timer.periodic(
      _positionCheckInterval,
      (_) => _checkPositionForAutoNext(),
    );
    logDebug('Position check timer started');
  }

  void _stopPositionCheckTimer() {
    _positionCheckTimer?.cancel();
    _positionCheckTimer = null;
  }

  void _checkPositionForAutoNext() {
    if (!_audioService.isPlaying) return;

    final position = _audioService.position;
    final duration = _audioService.duration;

    if (duration == null || duration.inMilliseconds <= 0) return;

    final remaining = duration - position;
    if (remaining <= _positionThreshold) {
      logDebug('Position check triggered auto-next: position=$position, duration=$duration');
      _onTrackCompleted(null);
    }
  }

  // ========== 私有方法 ==========

  /// 设置 AudioHandler 回调函数
  void _setupAudioHandler() {
    _audioHandler.onPlay = play;
    _audioHandler.onPause = pause;
    _audioHandler.onStop = stop;
    _audioHandler.onSkipToNext = next;
    _audioHandler.onSkipToPrevious = previous;
    _audioHandler.onSeek = seekTo;
    _audioHandler.onSetRepeatMode = (repeatMode) async {
      final loopMode = _repeatModeToLoopMode(repeatMode);
      await setLoopMode(loopMode);
    };
    _audioHandler.onSetShuffleMode = (shuffleMode) async {
      final shouldShuffle = shuffleMode != AudioServiceShuffleMode.none;
      if (shouldShuffle != _queueManager.isShuffleEnabled) {
        await toggleShuffle();
      }
    };

    // 初始化播放状态
    _audioHandler.initPlaybackState(
      isPlaying: _audioService.isPlaying,
      repeatMode: _loopModeToRepeatMode(_queueManager.loopMode),
      shuffleMode: _queueManager.isShuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );

    logDebug('AudioHandler callbacks set up');
  }

  /// 设置 Windows SMTC 回调函数
  void _setupWindowsSmtc() {
    _windowsSmtcHandler.onPlay = play;
    _windowsSmtcHandler.onPause = pause;
    _windowsSmtcHandler.onStop = stop;
    _windowsSmtcHandler.onSkipToNext = next;
    _windowsSmtcHandler.onSkipToPrevious = previous;
    _windowsSmtcHandler.onSeek = seekTo;

    logDebug('Windows SMTC callbacks set up');
  }

  /// 转换 LoopMode 到 AudioServiceRepeatMode
  AudioServiceRepeatMode _loopModeToRepeatMode(LoopMode loopMode) {
    switch (loopMode) {
      case LoopMode.none:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  /// 转换 AudioServiceRepeatMode 到 LoopMode
  LoopMode _repeatModeToLoopMode(AudioServiceRepeatMode repeatMode) {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.none;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        return LoopMode.all;
    }
  }

  /// 更新正在播放的歌曲（UI 显示用）
  void _updatePlayingTrack(Track track, {bool recordHistory = false}) {
    _playingTrack = track;
    state = state.copyWith(playingTrack: track);

    // 更新 AudioHandler 的媒体信息（用于通知栏显示）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updateCurrentMediaItem(track);
    }

    // 更新 Windows SMTC 的媒体信息
    if (Platform.isWindows) {
      _windowsSmtcHandler.updateCurrentMediaItem(track);
    }

    // 只在明确要求时记录到播放历史（避免重复记录）
    if (recordHistory) {
      _recordPlayHistory(track);
    }

    logDebug('Updated playing track: ${track.title}');
  }

  /// 记录播放历史（异步，不阻塞播放）
  void _recordPlayHistory(Track track) {
    final repo = _playHistoryRepository;
    if (repo == null) return;
    
    // 异步记录，不阻塞播放
    Future.microtask(() async {
      try {
        await repo.addHistory(track);
        logDebug('Recorded play history: ${track.title}');
      } catch (e) {
        logWarning('Failed to record play history: $e');
      }
    });
  }

  /// 尝试自动匹配歌词（异步，不阻塞播放）
  Future<void> _tryAutoMatchLyrics(Track track) async {
    final autoMatchService = _lyricsAutoMatchService;
    final settingsRepo = _settingsRepository;
    
    if (autoMatchService == null || settingsRepo == null) return;
    
    try {
      // 检查设置是否启用自动匹配
      final settings = await settingsRepo.get();
      if (!settings.autoMatchLyrics) {
        logDebug('Auto-match lyrics disabled in settings');
        return;
      }
      
      // 通知 UI 开始自动匹配
      onLyricsAutoMatchStateChanged?.call(true);
      
      // 后台执行自动匹配（按用户配置的源优先级）
      final enabledSources = settings.lyricsSourcePriorityList
          .where((s) => !settings.disabledLyricsSourcesSet.contains(s))
          .toList();
      final matched = await autoMatchService.tryAutoMatch(
        track,
        enabledSources: enabledSources.isNotEmpty ? enabledSources : null,
      );
      if (matched) {
        logInfo('Auto-matched lyrics for: ${track.title}');
      }
    } catch (e) {
      logWarning('Auto-match lyrics failed for ${track.title}: $e');
    } finally {
      onLyricsAutoMatchStateChanged?.call(false);
    }
  }

  /// 清除正在播放的歌曲
  void _clearPlayingTrack() {
    _playingTrack = null;
    state = state.copyWith(playingTrack: null);

    // 更新 Windows SMTC 为停止状态
    if (Platform.isWindows) {
      _windowsSmtcHandler.setStoppedState();
    }

    logDebug('Cleared playing track');
  }

  /// 加載更多 Mix 播放列表歌曲
  ///
  /// 使用重試機制確保每次至少獲取 10 首新歌曲：
  /// 1. 先用最後一首歌曲作為種子重試 3 次
  /// 2. 如果仍不足，嘗試用隊列中其他歌曲作為種子
  /// 3. 最多嘗試 10 次，每次間隔 1 秒
  /// 4. 收集所有新歌曲後一次性添加到隊列
  Future<void> _loadMoreMixTracks() async {
    if (_mixState == null || _mixState!.isLoadingMore) return;

    final queue = _queueManager.tracks;
    if (queue.isEmpty) return;

    _mixState!.isLoadingMore = true;
    state = state.copyWith(isLoadingMoreMix: true);
    logInfo('Loading more Mix tracks...');

    const minNewTracksRequired = 10;
    const maxAttempts = 10;
    const sameVideoRetries = 3;
    const retryDelay = Duration(seconds: 1);

    // 收集所有新歌曲，最後一次性添加
    final collectedTracks = <Track>[];
    final collectedVideoIds = <String>{};
    int attempt = 0;
    YouTubeSource? youtubeSource;

    try {
      youtubeSource = YouTubeSource();

      while (collectedTracks.length < minNewTracksRequired && attempt < maxAttempts) {
        attempt++;

        // 選擇種子視頻：前 3 次用最後一首，之後用不同的視頻
        String seedVideoId;
        if (attempt <= sameVideoRetries) {
          seedVideoId = queue.last.sourceId;
          logDebug('Attempt $attempt/$maxAttempts: using last track as seed ($seedVideoId)');
        } else {
          // 從隊列倒數第 2 ~ 倒數第 10 首中選擇一個不同的種子
          final seedIndex = queue.length - 1 - (attempt - sameVideoRetries);
          if (seedIndex >= 0) {
            seedVideoId = queue[seedIndex].sourceId;
            logDebug('Attempt $attempt/$maxAttempts: using track at index $seedIndex as seed ($seedVideoId)');
          } else {
            seedVideoId = queue.last.sourceId;
            logDebug('Attempt $attempt/$maxAttempts: fallback to last track as seed ($seedVideoId)');
          }
        }

        try {
          final result = await youtubeSource.fetchMixTracks(
            playlistId: _mixState!.playlistId,
            currentVideoId: seedVideoId,
          );

          // 過濾已存在的歌曲（包括已在隊列中的和本輪已收集的）
          final newTracks = result.tracks
              .where((t) => !_mixState!.seenVideoIds.contains(t.sourceId) &&
                           !collectedVideoIds.contains(t.sourceId))
              .toList();

          if (newTracks.isNotEmpty) {
            logDebug('Attempt $attempt: got ${newTracks.length} new tracks (total: ${collectedTracks.length + newTracks.length})');
            collectedTracks.addAll(newTracks);
            collectedVideoIds.addAll(newTracks.map((t) => t.sourceId));
          } else {
            logDebug('Attempt $attempt: no new tracks (all duplicates)');
          }

          // 如果還沒達到目標且還有重試次數，等待後繼續
          if (collectedTracks.length < minNewTracksRequired && attempt < maxAttempts) {
            await Future.delayed(retryDelay);
          }
        } catch (e) {
          logWarning('Attempt $attempt failed: $e');
          // 單次請求失敗，等待後繼續嘗試
          if (attempt < maxAttempts) {
            await Future.delayed(retryDelay);
          }
        }
      }

      // 一次性添加所有收集到的新歌曲
      if (collectedTracks.isNotEmpty) {
        logInfo('Mix load complete: adding ${collectedTracks.length} new tracks in $attempt attempts');
        _mixState!.addSeenVideoIds(collectedTracks.map((t) => t.sourceId));
        await _queueManager.addAll(collectedTracks);
        _updateQueueState();
      } else {
        logWarning('Mix load failed: no new tracks after $attempt attempts');
        _toastService.showInfo(t.audio.mixLoadMoreFailed);
      }
    } catch (e, stack) {
      logError('Failed to load more Mix tracks', e, stack);
      _toastService.showInfo(t.audio.mixLoadMoreError);
    } finally {
      youtubeSource?.dispose();
      _mixState!.isLoadingMore = false;
      state = state.copyWith(isLoadingMoreMix: false);
    }
  }

  /// 获取播放音频所需的 HTTP 请求头
  /// Bilibili 需要 Referer 头，YouTube 需要 Origin 和 Referer 头
  Map<String, String>? _getHeadersForTrack(Track track) {
    switch (track.sourceType) {
      case SourceType.bilibili:
        return {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        };
      case SourceType.youtube:
        return {
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        };
    }
  }

  // ========== 統一播放入口 ========== //

  /// 進入加載狀態（統一的 UI 更新邏輯）
  /// 返回請求 ID，用於後續的取代檢測
  int _enterLoadingState() {
    state = state.copyWith(isLoading: true, position: Duration.zero, error: null);
    final requestId = ++_playRequestId;
    _context = _context.copyWith(activeRequestId: requestId);
    return requestId;
  }

  /// 退出加載狀態
  /// [requestId] - 當前請求的 ID，用於驗證是否應該退出
  /// [trackWithUrl] - 成功獲取 URL 後的歌曲（用於更新 playingTrack）
  /// [mode] - 播放模式（用於更新 _context）
  /// [recordHistory] - 是否記錄播放歷史
  /// [streamResult] - 音頻流選擇結果（碼率、格式等信息）
  void _exitLoadingState(
    int requestId, 
    Track? trackWithUrl, {
    PlayMode? mode, 
    bool recordHistory = false,
    AudioStreamResult? streamResult,
  }) {
    // 只有當請求沒有被取代時才更新狀態
    if (requestId == _playRequestId) {
      state = state.copyWith(
        isLoading: false,
        // 更新音頻流信息
        currentBitrate: streamResult?.bitrate,
        currentContainer: streamResult?.container,
        currentCodec: streamResult?.codec,
        currentStreamType: streamResult?.streamType,
      );
      _context = _context.copyWith(activeRequestId: 0, mode: mode);
      
      if (trackWithUrl != null) {
        _updatePlayingTrack(trackWithUrl, recordHistory: recordHistory);
      }
    }
  }

  /// 重置加載狀態（在請求被取代或失敗時使用）
  void _resetLoadingState() {
    state = state.copyWith(isLoading: false);
    _context = _context.copyWith(activeRequestId: 0);
  }

  /// 檢查當前請求是否已被新請求取代
  bool _isSuperseded(int requestId) {
    return requestId != _playRequestId;
  }

  /// 統一的播放請求入口
  /// 所有播放操作都應該通過這個方法來執行
  /// 
  /// [track] - 要播放的歌曲
  /// [mode] - 播放模式（queue/temporary/detached）
  /// [persist] - 是否將 URL 保存到數據庫
  /// [recordHistory] - 是否記錄播放歷史
  /// [prefetchNext] - 是否預取下一首
  Future<void> _executePlayRequest({
    required Track track,
    required PlayMode mode,
    bool persist = true,
    bool recordHistory = true,
    bool prefetchNext = true,
  }) async {
    // 階段 1：立即更新 UI（在任何 await 之前）
    _updatePlayingTrack(track);
    _updateQueueState();

    // 階段 2：進入加載狀態
    final requestId = _enterLoadingState();
    logDebug('_executePlayRequest started for: ${track.title} (requestId: $requestId, mode: $mode)');

    // 互斥：停止電台播放（如果有）
    await onPlaybackStarting?.call();

    // 階段 3：停止當前播放
    await _audioService.stop();

    // 等待之前的播放操作完成
    if (_playLock != null && !_playLock!.completer.isCompleted) {
      logDebug('Waiting for previous play operation to complete...');
      _playLock!.completeIf(_playLock!.requestId);
      await _playLock!.completer.future.timeout(
        AppConstants.playLockTimeout,
        onTimeout: () {
          logWarning('Previous play operation timed out, proceeding anyway');
        },
      );
    }

    // 檢查是否已被取代
    if (_isSuperseded(requestId)) {
      logDebug('Play request $requestId superseded by $_playRequestId, aborting');
      return;
    }

    // 創建新的鎖
    _playLock = _LockWithId(requestId);
    bool completedSuccessfully = false;
    String? attemptedUrl; // 保存嘗試播放的 URL，用於 fallback 時排除

    try {
      // 階段 4：獲取 URL
      logDebug('Fetching audio URL for: ${track.title}');
      final (trackWithUrl, localPath, streamResult) = await _queueManager.ensureAudioStream(track, persist: persist);

      // 檢查是否被取代
      if (_isSuperseded(requestId)) {
        logDebug('Play request $requestId superseded after URL fetch, aborting');
        return;
      }

      final url = localPath ?? trackWithUrl.audioUrl;
      attemptedUrl = url; // 保存用於 fallback
      if (url == null) {
        throw Exception('No audio URL available for: ${track.title}');
      }

      final urlType = localPath != null ? 'downloaded' : 'stream';
      logDebug('Playing track: ${track.title}, URL type: $urlType, source: ${track.sourceType}');

      // 階段 5：播放
      if (localPath != null) {
        await _audioService.playFile(url, track: trackWithUrl);
      } else {
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
      }

      // 檢查是否被取代
      if (_isSuperseded(requestId)) {
        logDebug('Play request $requestId superseded after playUrl, stopping');
        await _audioService.stop();
        return;
      }

      // 預取下一首
      if (prefetchNext) {
        _queueManager.prefetchNext();
      }

      // 階段 6：完成
      _exitLoadingState(requestId, trackWithUrl, mode: mode, recordHistory: recordHistory, streamResult: streamResult);
      completedSuccessfully = true;
      
      // 更新隊列狀態
      _updateQueueState();
      
      // 自动匹配歌词（后台执行，不阻塞播放）
      if (recordHistory) {
        unawaited(_tryAutoMatchLyrics(track));
      }
      
      // Mix 模式：當開始播放最後一首時，立即加載更多歌曲
      if (mode == PlayMode.mix && _queueManager.currentIndex == _queueManager.tracks.length - 1) {
        logDebug('Mix mode: started playing last track, loading more...');
        // 使用 unawaited 避免阻塞當前播放
        unawaited(_loadMoreMixTracks());
      }
      
      logDebug('_executePlayRequest completed successfully for: ${track.title}');
    } on SourceApiException catch (e) {
      logWarning('${e.sourceType.name} API error for ${track.title}: ${e.message}');
      _handleSourceError(track, e, mode);
    } catch (e, stack) {
      logError('Failed to play track: ${track.title}', e, stack);

      // Try fallback URL for YouTube tracks (e.g. audio-only stream proxy failure)
      if (track.sourceType == SourceType.youtube && !_isSuperseded(requestId)) {
        try {
          logInfo('Attempting fallback stream for: ${track.title} (failed URL: $attemptedUrl)');
          final fallbackResult = await _queueManager.getAlternativeAudioStream(track, failedUrl: attemptedUrl);
          
          if (fallbackResult != null && !_isSuperseded(requestId)) {
            final fallbackUrl = fallbackResult.url;
            final headers = _getHeadersForTrack(track);
            await _audioService.playUrl(fallbackUrl, headers: headers, track: track);
            
            if (!_isSuperseded(requestId)) {
              track.audioUrl = fallbackUrl;
              _exitLoadingState(requestId, track, mode: mode, recordHistory: recordHistory, streamResult: fallbackResult);
              completedSuccessfully = true;
              _updateQueueState();
              logInfo('Fallback playback succeeded for: ${track.title}');

              if (prefetchNext) {
                _queueManager.prefetchNext();
              }
              return;
            }
          }
        } catch (fallbackError) {
          logError('Fallback also failed for: ${track.title}', fallbackError);
          // Check if fallback error is also a network error
          if (_isNetworkError(fallbackError)) {
            await _audioService.stop();
            state = state.copyWith(isLoading: false);
            _resetLoadingState();
            _scheduleRetry(track, state.position);
            throw const _RetryScheduledException();
          }
        }
      }

      // Check if original error is a network error
      if (_isNetworkError(e)) {
        await _audioService.stop();
        state = state.copyWith(isLoading: false);
        _resetLoadingState();
        _scheduleRetry(track, state.position);
        throw const _RetryScheduledException();
      }

      await _audioService.stop();
      state = state.copyWith(error: e.toString(), isLoading: false);
      _resetLoadingState();
      _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
    } finally {
      _playLock?.completeIf(requestId);
      
      if (!completedSuccessfully && _isSuperseded(requestId)) {
        logDebug('Play request $requestId was superseded, resetting isLoading');
        _resetLoadingState();
      }
    }
  }

  /// 處理音源 API 錯誤的統一邏輯
  void _handleSourceError(Track track, SourceApiException e, PlayMode mode) {
    if (e.isUnavailable || e.isGeoRestricted) {
      logInfo('Track unavailable (${e.sourceType.name}): ${track.title}');
      final nextIdx = _queueManager.getNextIndex();
      if (nextIdx != null && mode == PlayMode.queue) {
        _resetLoadingState();
        _toastService.showWarning(t.audio.cannotPlaySkipped(title: track.title));
        Future.delayed(const Duration(milliseconds: 300), () {
          next();
        });
      } else {
        _audioService.stop();
        state = state.copyWith(
          error: t.audio.playbackFailed(message: e.message),
          isLoading: false,
        );
        _resetLoadingState();
        _toastService.showError(t.audio.cannotPlay(title: track.title));
      }
    } else if (e.isRateLimited) {
      logWarning('Rate limited (${e.sourceType.name}): ${track.title}');
      state = state.copyWith(
        error: e.message,
        isLoading: false,
      );
      _resetLoadingState();
      _toastService.showWarning(e.message);
    } else {
      state = state.copyWith(
        error: t.audio.playbackFailed(message: e.message),
        isLoading: false,
      );
      _resetLoadingState();
    }
  }

  // ========== 网络重试逻辑 ========== //

  /// 判断是否为网络错误
  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('socket') ||
           errorStr.contains('connection') ||
           errorStr.contains('network') ||
           errorStr.contains('timeout') ||
           errorStr.contains('unreachable') ||
           errorStr.contains('host') ||
           errorStr.contains('dns') ||
           errorStr.contains('errno') ||
           errorStr.contains('failed host lookup');
  }

  /// 安排重试（漸進式延遲）
  void _scheduleRetry(Track track, Duration? position) {
    if (_retryAttempt >= NetworkRetryConfig.maxRetries) {
      logInfo('Max retry attempts reached for: ${track.title}');
      _trackToRecoverAfterReconnect = track;
      _positionToRecoverAfterReconnect = position;
      state = state.copyWith(
        isNetworkError: true,
        isRetrying: false,
        retryAttempt: _retryAttempt,
        nextRetryAt: null,
      );
      return;
    }

    final delay = NetworkRetryConfig.getRetryDelay(_retryAttempt);
    final nextRetryTime = DateTime.now().add(delay);
    
    logInfo('Scheduling retry ${_retryAttempt + 1}/${NetworkRetryConfig.maxRetries} for: ${track.title} in ${delay.inSeconds}s');

    state = state.copyWith(
      isNetworkError: true,
      isRetrying: true,
      retryAttempt: _retryAttempt,
      nextRetryAt: nextRetryTime,
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryPlayback(track, position);
    });
  }

  /// 执行重试
  Future<void> _retryPlayback(Track track, Duration? position) async {
    _retryAttempt++;
    logInfo('Retrying playback ($_retryAttempt/${NetworkRetryConfig.maxRetries}) for: ${track.title}');

    try {
      // 更新状态为重试中
      state = state.copyWith(
        isRetrying: true,
        retryAttempt: _retryAttempt,
        nextRetryAt: null,
        error: null,
      );

      // 保持当前模式
      final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
      await _executePlayRequest(
        track: track,
        mode: currentMode,
        persist: false, // 重试时不需要再次持久化
        recordHistory: false, // 重试时不重复记录历史
        prefetchNext: true,
      );

      // 重试成功，重置状态
      _resetRetryState();
      
      // 如果有保存的位置，尝试恢复
      if (position != null && position.inSeconds > 0) {
        await Future.delayed(AppConstants.seekStabilizationDelay);
        await seekTo(position);
      }
      
      logInfo('Retry playback succeeded for: ${track.title}');
    } on _RetryScheduledException {
      // 重试已在 _executePlayRequest 中安排，不需要额外处理
      logDebug('Retry already scheduled by _executePlayRequest');
    } catch (e) {
      logError('Retry playback failed for: ${track.title}', e);
      if (_isNetworkError(e)) {
        _scheduleRetry(track, position);
      } else {
        // 非网络错误，不再重试
        _resetRetryState();
        state = state.copyWith(error: e.toString());
        _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      }
    }
  }

  /// 网络恢复时自动恢复播放
  Future<void> _onNetworkRecovered() async {
    logInfo('_onNetworkRecovered called, trackToRecover: ${_trackToRecoverAfterReconnect?.title}');
    if (_trackToRecoverAfterReconnect == null) {
      logDebug('No track to recover, skipping');
      return;
    }

    final track = _trackToRecoverAfterReconnect!;
    final position = _positionToRecoverAfterReconnect;
    
    logInfo('Network recovered, attempting to resume playback for: ${track.title}');
    
    _trackToRecoverAfterReconnect = null;
    _positionToRecoverAfterReconnect = null;
    _retryAttempt = 0; // 重置重试计数

    // 延迟一下确保网络稳定
    await Future.delayed(AppConstants.seekStabilizationDelay);

    try {
      final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
      await _executePlayRequest(
        track: track,
        mode: currentMode,
        persist: false,
        recordHistory: false,
        prefetchNext: true,
      );

      _resetRetryState();
      
      // 恢复播放位置
      if (position != null && position.inSeconds > 0) {
        await Future.delayed(AppConstants.seekStabilizationDelay);
        await seekTo(position);
      }
      
      logInfo('Network recovery playback succeeded for: ${track.title}');
    } on _RetryScheduledException {
      // 重试已在 _executePlayRequest 中安排
      logDebug('Retry scheduled after network recovery attempt');
    } catch (e) {
      logError('Network recovery playback failed for: ${track.title}', e);
      if (_isNetworkError(e)) {
        _scheduleRetry(track, position);
      } else {
        _resetRetryState();
        state = state.copyWith(error: e.toString());
        _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      }
    }
  }

  /// 重置重试状态
  void _resetRetryState() {
    _cancelRetryTimer();
    _retryAttempt = 0;
    _trackToRecoverAfterReconnect = null;
    _positionToRecoverAfterReconnect = null;
    state = state.copyWith(
      isNetworkError: false,
      isRetrying: false,
      retryAttempt: 0,
      nextRetryAt: null,
    );
  }

  /// 取消待处理的重试
  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 设置网络恢复监听（需要在初始化时从外部传入 Ref）
  void setupNetworkRecoveryListener(Stream<void> networkRecoveredStream) {
    logDebug('Setting up network recovery listener');
    _networkRecoverySubscription?.cancel();
    _networkRecoverySubscription = networkRecoveredStream.listen((_) {
      logDebug('Network recovery event received from stream');
      _onNetworkRecovered();
    });
    logDebug('Network recovery listener set up successfully');
  }

  /// 手动触发重试（用户点击重试按钮）
  Future<void> retryManually() async {
    final track = _trackToRecoverAfterReconnect ?? state.playingTrack;
    if (track == null) return;

    _retryAttempt = 0; // 重置重试计数
    _cancelRetryTimer();
    
    final position = _positionToRecoverAfterReconnect ?? state.position;
    _trackToRecoverAfterReconnect = null;
    _positionToRecoverAfterReconnect = null;

    try {
      final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
      await _executePlayRequest(
        track: track,
        mode: currentMode,
        persist: false,
        recordHistory: false,
        prefetchNext: true,
      );

      _resetRetryState();
      
      if (position.inSeconds > 0) {
        await Future.delayed(AppConstants.seekStabilizationDelay);
        await seekTo(position);
      }
      
      logInfo('Manual retry succeeded for: ${track.title}');
    } on _RetryScheduledException {
      // 重试已在 _executePlayRequest 中安排
      logDebug('Retry scheduled after manual retry attempt');
    } catch (e) {
      if (_isNetworkError(e)) {
        _scheduleRetry(track, position);
      } else {
        _resetRetryState();
        state = state.copyWith(error: e.toString());
        _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      }
    }
  }

  // ========== 脫離隊列檢測 ========== //

  /// 檢測當前是否脫離隊列
  /// 情況1：臨時播放模式
  /// 情況2：清空隊列後繼續播放的歌曲
  /// 情況3：播放的歌曲與隊列當前位置不一致
  bool get _isPlayingOutOfQueue {
    final queueTrack = _queueManager.currentTrack;
    final queue = _queueManager.tracks;
    
    return _context.mode == PlayMode.temporary ||
           _context.mode == PlayMode.detached ||
           (_playingTrack != null && queueTrack != null && _playingTrack!.id != queueTrack.id) ||
           (_playingTrack != null && queueTrack == null && queue.isNotEmpty);
  }

  /// 統一「返回隊列」邏輯
  /// 如果有保存的臨時播放狀態，恢復到該位置
  /// 否則播放隊列第一首
  Future<void> _returnToQueue() async {
    if (_context.isTemporary && _context.hasSavedState) {
      await _restoreSavedState();
    } else {
      await _playFirstInQueue();
    }
  }

  /// 播放隊列第一首歌曲
  Future<void> _playFirstInQueue() async {
    // 清除臨時播放狀態
    _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
    
    final queue = _queueManager.tracks;
    if (queue.isNotEmpty) {
      _queueManager.setCurrentIndex(0);
      final track = _queueManager.currentTrack;
      if (track != null) {
        await _playTrack(track);
      }
    }
    _updateQueueState();
  }

  /// 检查当前歌曲的 URL 是否已过期，如果过期则重新获取 URL 并从当前位置恢复播放。
  /// 返回 true 表示已处理（调用方应 return），false 表示无需处理。
  ///
  /// 典型场景：用户暂停后长时间不操作（如过夜），音频 URL 已过期，
  /// 直接调用 player.play() 会导致 "Error decoding audio"。
  Future<bool> _resumeWithFreshUrlIfNeeded() async {
    final track = state.currentTrack;
    if (track == null) return false;

    // 只在 URL 确实过期时触发（有 URL 但已过期）
    if (track.audioUrl == null || track.hasValidAudioUrl) return false;

    // 排除已下载的本地文件（本地文件不会过期）
    if (track.allDownloadPaths.any((p) => File(p).existsSync())) return false;

    logDebug('Audio URL expired for: ${track.title}, re-fetching and resuming from ${state.position}');
    final position = state.position;
    await _playTrack(track);

    // 播放成功后恢复到之前的位置
    if (position.inSeconds > 0) {
      await Future.delayed(AppConstants.seekStabilizationDelay);
      await seekTo(position);
    }
    return true;
  }

  /// 播放指定歌曲（委託給統一入口）
  Future<void> _playTrack(Track track) async {
    // 保持當前模式：如果在 Mix 模式，繼續使用 Mix 模式
    final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
    await _executePlayRequest(
      track: track,
      mode: currentMode,
      persist: true,
      recordHistory: true,
      prefetchNext: true,
    );
  }

  /// 准备当前歌曲（不自动播放）
  Future<void> _prepareCurrentTrack({bool autoPlay = false, Duration? initialPosition}) async {
    final track = _queueManager.currentTrack;
    if (track == null) return;

    try {
      final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(track);
      final url = localPath ?? trackWithUrl.audioUrl;

      if (url == null) return;

      if (localPath != null) {
        await _audioService.setFile(url);
      } else {
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.setUrl(url, headers: headers);
      }

      // 设置正在播放的歌曲（用于 UI 显示）
      _updatePlayingTrack(trackWithUrl);

      // 恢复播放位置（优先使用传入的位置，否则使用 QueueManager 保存的位置）
      final positionToSeek = initialPosition ?? _queueManager.savedPosition;
      logDebug('Attempting to restore position: $positionToSeek');
      if (positionToSeek > Duration.zero) {
        // 应用回退秒数设置
        final positionSettings = await _queueManager.getPositionRestoreSettings();
        final rewind = Duration(seconds: positionSettings.restartRewindSeconds);
        final adjustedPosition = positionToSeek - rewind;
        final finalPosition = adjustedPosition.isNegative ? Duration.zero : adjustedPosition;
        logDebug('Seeking to position: $finalPosition (original: $positionToSeek, rewind: ${rewind.inSeconds}s)');
        await _audioService.seekTo(finalPosition);
        logDebug('Seek completed');
      } else {
        logDebug('No saved position to restore (position is zero)');
      }

      if (autoPlay) {
        await _audioService.play();
      }

      // 預取下一首歌曲的 URL（程序重啟後首次切歌不需要等待）
      _queueManager.prefetchNext();

      // 确保清除加载状态
      _resetLoadingState();
    } catch (e) {
      logError('Failed to prepare track: ${track.title}', e);
      _resetLoadingState();
    }
  }

  void _onPlayerStateChanged(MediaKitPlayerState playerState) {
    logDebug('PlayerState changed: playing=${playerState.playing}, processingState=${playerState.processingState}');
    state = state.copyWith(
      isPlaying: playerState.playing,
      isBuffering: playerState.processingState == FmpAudioProcessingState.buffering,
      // 防止播放器状态事件覆盖 URL 获取期间的 loading 状态
      isLoading: _context.isInLoadingState || playerState.processingState == FmpAudioProcessingState.loading,
      processingState: playerState.processingState,
    );

    // 更新 AudioHandler 的播放状态（用于通知栏）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updatePlaybackState(
        isPlaying: playerState.playing,
        position: _audioService.position,
        bufferedPosition: _audioService.bufferedPosition,
        processingState: playerState.processingState,
        duration: _audioService.duration,
        speed: _audioService.speed,
      );
    }

    // 更新 Windows SMTC 的播放状态
    if (Platform.isWindows) {
      _windowsSmtcHandler.updatePlaybackState(
        isPlaying: playerState.playing,
        position: _audioService.position,
        duration: _audioService.duration,
      );
    }
  }

  void _onPositionChanged(Duration position) {
    // 加载期间忽略位置更新（防止旧歌曲的位置覆盖已重置的进度条）
    if (_context.isInLoadingState) return;

    state = state.copyWith(position: position);
    // 更新 QueueManager 的位置（用于恢复播放）
    _queueManager.updatePosition(position);

    // 更新 AudioHandler 的播放状态（用于通知栏进度显示）
    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler.updatePlaybackState(
        isPlaying: _audioService.isPlaying,
        position: position,
        bufferedPosition: _audioService.bufferedPosition,
        processingState: _audioService.processingState,
        duration: _audioService.duration,
        speed: _audioService.speed,
      );
    }

    // 更新 Windows SMTC 的播放状态（用于进度显示）
    if (Platform.isWindows) {
      _windowsSmtcHandler.updatePlaybackState(
        isPlaying: _audioService.isPlaying,
        position: position,
        duration: _audioService.duration,
      );
    }
  }

  void _onDurationChanged(Duration? duration) {
    state = state.copyWith(duration: duration);
  }

  void _onBufferedPositionChanged(Duration bufferedPosition) {
    state = state.copyWith(bufferedPosition: bufferedPosition);
  }

  void _onSpeedChanged(double speed) {
    state = state.copyWith(speed: speed);
  }

  void _onAudioDevicesChanged(List<AudioDevice> devices) {
    logDebug('Audio devices updated: ${devices.length} devices');
    state = state.copyWith(audioDevices: devices);
  }

  void _onAudioDeviceChanged(AudioDevice? device) {
    logDebug('Current audio device: ${device?.name ?? "auto"}');
    state = state.copyWith(currentAudioDevice: device);
  }

  void _onTrackCompleted(void _) {
    // 防止重复处理
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    logDebug('Track completed, loopMode: ${_queueManager.loopMode}, shuffle: ${_queueManager.isShuffleEnabled}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 使用 Future.microtask 来避免在流监听器中直接操作
    Future.microtask(() async {
      try {
        // 单曲循环优先：即使在临时播放模式下也继续循环播放
        if (_queueManager.loopMode == LoopMode.one) {
          // 单曲循环：重新播放当前歌曲
          logDebug('LoopOne mode: replaying current track');
          final track = _playingTrack;
          if (track != null) {
            await _playTrack(track);
          }
          return;
        }

        // 检测是否脱离队列播放
        if (_isPlayingOutOfQueue) {
          logDebug('Track completed while playing out of queue');
          await _returnToQueue();
          return;
        }

        // 正常队列播放：移动到下一首
        final nextIdx = _queueManager.moveToNext();
        if (nextIdx != null) {
          final track = _queueManager.currentTrack;
          if (track != null) {
            await _playTrack(track);
          }
        } else {
          logDebug('No next track available');
        }
      } catch (e, stack) {
        logError('Track completion handler failed', e, stack);
      } finally {
        _isHandlingCompletion = false;
      }
    });
  }

  void _onQueueStateChanged(void _) {
    _updateQueueState();
  }

  void _updateQueueState() {
    final queue = _queueManager.tracks;
    final currentIndex = _queueManager.currentIndex;

    // 队列中当前位置的歌曲（注意：这与 playingTrack 可能不同）
    final queueTrack = _queueManager.currentTrack;

    // 计算 upcomingTracks 和导航按钮状态
    List<Track> upcomingTracks;
    bool canPlayPrevious;
    bool canPlayNext;

    // 检测是否脱离队列播放
    if (_isPlayingOutOfQueue) {
      // 当前播放的歌曲脱离队列：点击"下一首"会去到队列中保存的索引位置
      if (_context.isTemporary && _context.hasSavedState && queue.isNotEmpty) {
        // 临时播放模式：显示当前队列中从保存位置开始的歌曲
        final targetIndex = _context.savedQueueIndex!.clamp(0, queue.length - 1);
        if (_queueManager.isShuffleEnabled) {
          // Shuffle 模式：从当前 shuffle 索引获取后续歌曲
          upcomingTracks = _queueManager.getUpcomingTracksFromIndex(targetIndex, count: 5);
        } else {
          // 顺序模式：显示当前队列中从保存位置开始的歌曲（最多5首）
          final endIndex = (targetIndex + 5).clamp(0, queue.length);
          upcomingTracks = queue.sublist(targetIndex, endIndex);
        }
      } else {
        // 没有保存的状态，或非临时播放但脱离队列：显示当前队列从索引 0 开始的歌曲
        final endIdx = 5.clamp(0, queue.length);
        upcomingTracks = queue.sublist(0, endIdx);
      }

      // 脱离队列模式下，上一首/下一首都会去到队列，所以只要队列不为空就可用
      canPlayPrevious = queue.isNotEmpty;
      canPlayNext = queue.isNotEmpty;
    } else {
      upcomingTracks = _queueManager.getUpcomingTracks(count: 5);
      canPlayPrevious = _queueManager.hasPrevious;
      canPlayNext = _queueManager.hasNext;
    }

    logDebug('Updating queue state: ${queue.length} tracks, index: $currentIndex, queueTrack: ${queueTrack?.title ?? "null"}, playingTrack: ${_playingTrack?.title ?? "null"}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');
    state = state.copyWith(
      queue: queue,
      upcomingTracks: upcomingTracks,
      currentIndex: currentIndex,
      queueTrack: queueTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: canPlayPrevious,
      canPlayNext: canPlayNext,
      queueVersion: state.queueVersion + 1,
    );
  }
}

// ========== Providers ==========

/// AudioService Provider
final audioServiceProvider = Provider<MediaKitAudioService>((ref) {
  final service = MediaKitAudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// QueueManager Provider
final queueManagerProvider = Provider<QueueManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final sourceManager = ref.watch(sourceManagerProvider);

  final queueRepository = QueueRepository(db);
  final trackRepository = TrackRepository(db);
  final settingsRepository = SettingsRepository(db);

  final manager = QueueManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: sourceManager,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

/// AudioController Provider
final audioControllerProvider =
    StateNotifierProvider<AudioController, PlayerState>((ref) {
  final audioService = ref.watch(audioServiceProvider);
  final queueManager = ref.watch(queueManagerProvider);
  final toastService = ref.watch(toastServiceProvider);
  
  // 获取播放历史仓库（可能为 null，如果数据库未初始化）
  PlayHistoryRepository? playHistoryRepository;
  try {
    playHistoryRepository = ref.watch(playHistoryRepositoryProvider);
  } catch (_) {
    // 数据库未初始化时忽略
  }

  final controller = AudioController(
    audioService: audioService,
    queueManager: queueManager,
    toastService: toastService,
    audioHandler: audioHandler,
    windowsSmtcHandler: windowsSmtcHandler,
    playHistoryRepository: playHistoryRepository,
    lyricsAutoMatchService: ref.watch(lyricsAutoMatchServiceProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  );

  // 设置网络恢复监听（用于断网重连自动恢复播放）
  final connectivityNotifier = ref.watch(connectivityProvider.notifier);
  controller.setupNetworkRecoveryListener(connectivityNotifier.onNetworkRecovered);

  // 设置歌词自动匹配状态回调
  controller.onLyricsAutoMatchStateChanged = (isMatching) {
    ref.read(lyricsAutoMatchingProvider.notifier).state = isMatching;
  };

  // 启动初始化（异步，但不阻塞）
  // _ensureInitialized 会在每个操作前确保初始化完成
  Future.microtask(() => controller.initialize());

  return controller;
});

/// 便捷 Providers

/// 当前播放状态
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(audioControllerProvider).isPlaying;
});

/// 当前歌曲
final currentTrackProvider = Provider<Track?>((ref) {
  return ref.watch(audioControllerProvider).currentTrack;
});

/// 当前进度
final positionProvider = Provider<Duration>((ref) {
  return ref.watch(audioControllerProvider).position;
});

/// 总时长
final durationProvider = Provider<Duration?>((ref) {
  return ref.watch(audioControllerProvider).duration;
});

/// 播放队列
final queueProvider = Provider<List<Track>>((ref) {
  return ref.watch(audioControllerProvider).queue;
});

/// 是否启用随机播放
final isShuffleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(audioControllerProvider).isShuffleEnabled;
});

/// 循环模式
final loopModeProvider = Provider<LoopMode>((ref) {
  return ref.watch(audioControllerProvider).loopMode;
});
