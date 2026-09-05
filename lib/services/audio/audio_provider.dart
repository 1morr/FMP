import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
// AudioDevice replaced by FmpAudioDevice from audio_types.dart
import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_exception.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/play_history_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../providers/database/database_provider.dart';
import '../../providers/database/repository_providers.dart';
import '../../providers/audio/stream_resolution_provider.dart';
import '../../providers/lyrics/lyrics_provider.dart';
import '../../providers/account/source_auth_context_provider.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../providers/library/library_invalidation_coordinator.dart';
import '../lyrics/lyrics_auto_match_service.dart';
import '../../core/services/toast_service.dart';
import 'audio_types.dart';
import 'buffer_starvation_watchdog.dart';
import 'audio_service.dart';
import 'media_kit_audio_service.dart';
import 'just_audio_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'audio_runtime_platform.dart';
import 'audio_stream_manager.dart';
import 'playback_recovery_coordinator.dart';
import 'playback_request_session.dart';
import 'playback_capabilities.dart';
import 'now_playing_publisher.dart';
import 'queue_commands.dart';
import 'queue_manager.dart';
import 'queue_persistence_manager.dart';
import '../network/connectivity_service.dart';
import 'player_state.dart';
import 'audio_playback_types.dart';
import 'mix_playlist_handler.dart';
import 'play_history_recorder.dart';
import 'mix_playlist_types.dart';
import 'temporary_play_handler.dart';

export 'player_state.dart';

/// 内部异常：表示重试已被安排，调用者不应再次安排重试
class _RetryScheduledException implements Exception {
  const _RetryScheduledException();
}

class QueueState {
  final List<Track> queue;
  final List<Track> upcomingTracks;
  final int? currentIndex;
  final Track? queueTrack;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int queueVersion;
  final bool isMixMode;
  final String? mixTitle;
  final bool isLoadingMoreMix;

  const QueueState({
    this.queue = const [],
    this.upcomingTracks = const [],
    this.currentIndex,
    this.queueTrack,
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.none,
    this.queueVersion = 0,
    this.isMixMode = false,
    this.mixTitle,
    this.isLoadingMoreMix = false,
  });

  QueueState copyWith({
    List<Track>? queue,
    List<Track>? upcomingTracks,
    int? currentIndex,
    Track? queueTrack,
    bool? canPlayPrevious,
    bool? canPlayNext,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? queueVersion,
    bool? isMixMode,
    String? mixTitle,
    bool clearMixTitle = false,
    bool? isLoadingMoreMix,
  }) {
    return QueueState(
      queue: queue ?? this.queue,
      upcomingTracks: upcomingTracks ?? this.upcomingTracks,
      currentIndex: currentIndex ?? this.currentIndex,
      queueTrack: queueTrack ?? this.queueTrack,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      queueVersion: queueVersion ?? this.queueVersion,
      isMixMode: isMixMode ?? this.isMixMode,
      mixTitle: clearMixTitle ? null : (mixTitle ?? this.mixTitle),
      isLoadingMoreMix: isLoadingMoreMix ?? this.isLoadingMoreMix,
    );
  }
}

final queueStateProvider =
    StateProvider<QueueState>((ref) => const QueueState());

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
      savedQueueIndex:
          clearSavedState ? null : (savedQueueIndex ?? this.savedQueueIndex),
      savedPosition:
          clearSavedState ? null : (savedPosition ?? this.savedPosition),
      savedWasPlaying:
          clearSavedState ? null : (savedWasPlaying ?? this.savedWasPlaying),
    );
  }

  @override
  String toString() {
    return '_PlaybackContext(mode: $mode, activeRequestId: $activeRequestId, savedQueueIndex: $savedQueueIndex, savedPosition: $savedPosition, savedWasPlaying: $savedWasPlaying)';
  }
}

class _PendingSeekRequest {
  _PendingSeekRequest({
    required this.position,
    required this.trackKey,
    required this.requestId,
  });

  final Duration position;
  final String trackKey;
  final int requestId;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

class _SeekStabilizationWindow {
  const _SeekStabilizationWindow({
    required this.requestId,
    required this.trackKey,
    required this.until,
  });

  final int requestId;
  final String trackKey;
  final DateTime until;
}

/// 音频控制器 - 管理所有播放相关的状态和操作
/// 协调 AudioService（单曲播放）和 QueueManager（队列管理）
class AudioController extends StateNotifier<PlayerState>
    with Logging
    implements PlaybackRetryExecutor {
  static const _syntheticSourceDiagnostics = <String>{
    'VIP song, payment required',
    'No playback rights due to copyright or region restrictions',
    'Login required',
    'Playback permission denied',
    'No stream URL available',
    'Video unavailable',
    'Access forbidden (HTTP 403)',
    'Resource not found (HTTP 404)',
    'Service temporarily unavailable (HTTP 503)',
  };

  final FmpAudioService _audioService;
  final QueueManager _queueManager;
  late final QueueCommands _queueCommands;
  final AudioStreamManager _audioStreamManager;
  final ToastService _toastService;
  final NowPlayingPublisher _publisher;
  late final PlayHistoryRecorder _playHistory;
  final LyricsAutoMatchService? _lyricsAutoMatchService;
  final SettingsRepository? _settingsRepository;
  final QueuePersistenceManager? _queuePersistenceManager;
  final MixTracksFetcher? _mixTracksFetcher;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isDisposed = false;

  // 防止重复处理完成事件
  bool _isHandlingCompletion = false;
  String? _terminalMediaOpenErrorTrackKey;

  // 导航请求ID - 防止快速点击 next/previous 时的竞态条件
  int _navRequestId = 0;

  // 歌词自动匹配请求ID - 防止旧匹配任务覆盖新匹配任务的 UI 状态
  int _lyricsAutoMatchRequestId = 0;

  // 統一的播放上下文（管理所有播放狀態，包括臨時播放、加載狀態等）
  _PlaybackContext _context = const _PlaybackContext();
  _PendingSeekRequest? _pendingSeek;
  _SeekStabilizationWindow? _seekStabilizationWindow;
  bool _stabilizeSeekAfterNextPlaybackRequest = false;

  // 基于位置检测的备选切歌定时器（解决后台播放 completed 事件丢失问题）
  Timer? _positionCheckTimer;

  late final PlaybackRequestSession _playbackRequestSession;
  late final PlaybackRecoveryCoordinator _recoveryCoordinator;
  late final TemporaryPlayHandler _temporaryPlayHandler;
  late final MixPlaylistHandler _mixPlaylistHandler;
  Future<void>? _mixLoadMoreFuture;
  int _mixStartRequestId = 0;

  // 通知栏/SMTC 更新节流：上次更新的位置
  Duration _lastNotificationPosition = Duration.zero;

  // 当前正在播放的歌曲（独立于队列，确保 UI 显示与实际播放一致）
  Track? _playingTrack;

  /// 播放開始前的回調（用於互斥機制，如停止電台播放）
  Future<void> Function()? onPlaybackStarting;

  /// 檢查電台是否正在播放（由 RadioController 設置，用於避免電台斷流時誤觸發隊列播放）
  bool Function()? isRadioPlaying;

  /// 歌词自动匹配状态回调（用于 UI 显示加载动画）
  void Function(bool isMatching)? onLyricsAutoMatchStateChanged;

  void Function(QueueState queueState)? onQueueStateChanged;

  // ========== 网络重试相关 ==========
  /// 网络恢复监听订阅
  StreamSubscription<void>? _networkRecoverySubscription;

  AudioController({
    required FmpAudioService audioService,
    required QueueManager queueManager,
    required AudioStreamManager audioStreamManager,
    required ToastService toastService,
    required NowPlayingPublisher nowPlayingPublisher,
    PlayHistoryRepository? playHistoryRepository,
    LyricsAutoMatchService? lyricsAutoMatchService,
    SettingsRepository? settingsRepository,
    QueuePersistenceManager? queuePersistenceManager,
    MixTracksFetcher? mixTracksFetcher,
    PlaybackTimeoutBudget budget = const PlaybackTimeoutBudget(),
  })  : _budget = budget,
        _audioService = audioService,
        _queueManager = queueManager,
        _audioStreamManager = audioStreamManager,
        _toastService = toastService,
        _publisher = nowPlayingPublisher,
        _lyricsAutoMatchService = lyricsAutoMatchService,
        _settingsRepository = settingsRepository,
        _queuePersistenceManager = queuePersistenceManager,
        _mixTracksFetcher = mixTracksFetcher,
        super(const PlayerState()) {
    _playHistory = PlayHistoryRecorder(repository: playHistoryRepository);
    _queueCommands = QueueCommands(
      queueManager: _queueManager,
      toastService: _toastService,
    );
    _playbackRequestSession = PlaybackRequestSession(
      budget: _budget,
      audioService: _audioService,
      audioStreamManager: _audioStreamManager,
      getNextTrack: _nextTrackForPrefetch,
      onLoadingStarted: _startSessionLoadingState,
      onLoadingFinished: (requestId, result) {
        if (result.isSuperseded) {
          _discardPendingSeekForRequest(
            requestId,
            reason: 'playback request was superseded',
          );
        }
        if (_context.activeRequestId == requestId && result.isSuperseded) {
          state = state.copyWith(isLoading: false);
          _context = _context.copyWith(activeRequestId: 0);
          _publishCurrentPlaybackState();
        }
      },
      terminalMediaOpenMessage: (track) =>
          t.audio.playbackFailedTrack(title: track.title),
      onTerminalMediaOpenError: _handlePostHandoffTerminalMediaOpen,
    );
    _recoveryCoordinator = PlaybackRecoveryCoordinator(
      retryExecutor: this,
      onRecoveryEvent: _applyRecoveryEvent,
      isRetryableError: _isRetryableError,
    );
    _bufferWatchdog = BufferStarvationWatchdog(
      onStarved: _onBufferStarvation,
      budget: _budget,
    );
    _temporaryPlayHandler = const TemporaryPlayHandler();
    _mixPlaylistHandler = MixPlaylistHandler();
  }

  final PlaybackTimeoutBudget _budget;
  late final BufferStarvationWatchdog _bufferWatchdog;

  /// 已經為哪一首歌出手救過一次。同一首只救一次，否則就變成無限重載。
  String? _bufferStarvationTrackKey;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化
  Future<void> initialize() async {
    if (_isDisposed || _isInitialized || _isInitializing) return;
    _isInitializing = true;

    logInfo('Initializing AudioController...');

    try {
      await _audioService.initialize();
      if (_isDisposed) return;
      logDebug('AudioService initialized');

      await _queueManager.initialize();
      if (_isDisposed) return;
      logDebug('QueueManager initialized');

      // 保存需要恢复的位置（在设置监听器之前，避免被位置流覆盖）
      final positionToRestore = _queueManager.savedPosition;
      logDebug('Position to restore: $positionToRestore');

      // 註冊 audio service 串流訂閱（统一加入 _subscriptions 以便 dispose 取消）。
      void subscribe<T>(Stream<T> stream, void Function(T) handler) {
        _subscriptions.add(stream.listen(handler));
      }

      subscribe(_audioService.playerStateStream, _onPlayerStateChanged);
      subscribe(_audioService.positionStream, _onPositionChanged);
      subscribe(_audioService.durationStream, _onDurationChanged);
      subscribe(
          _audioService.bufferedPositionStream, _onBufferedPositionChanged);
      subscribe(_audioService.speedStream, _onSpeedChanged);
      subscribe(_audioService.audioDevicesStream, _onAudioDevicesChanged);
      subscribe(_audioService.audioDeviceStream, _onAudioDeviceChanged);
      subscribe(_audioService.endReasons, _onPlaybackEnded);

      // 启动基于位置检测的备选切歌机制（解决后台播放 completed 事件丢失问题）
      _startPositionCheckTimer();

      // 监听队列状态变化
      subscribe(_queueManager.stateStream, _onQueueStateChanged);

      // 接管系统媒体控制（通知栏 / SMTC），平台分流由 publisher 负责
      _claimMediaControls();

      // 更新初始状态
      _updateQueueState();

      // 恢復 Mix 播放模式（如果之前有持久化的 Mix metadata）
      final restoredQueueState = _queuePersistenceManager == null
          ? null
          : await _queuePersistenceManager.restoreState();
      final isRestoredMixMode = restoredQueueState?.queue.isMixMode ?? false;
      final playlistId = restoredQueueState?.mixPlaylistId;
      final seedVideoId = restoredQueueState?.mixSeedVideoId;
      final title = restoredQueueState?.mixTitle;
      if (isRestoredMixMode &&
          playlistId != null &&
          seedVideoId != null &&
          title != null) {
        logDebug('Restoring Mix mode: $title');

        // Mix 模式不支持隨機播放，確保關閉
        if (_queueManager.isShuffleEnabled) {
          await _queueManager.setShuffle(false);
          if (_isDisposed) return;
          state = state.copyWith(isShuffleEnabled: false);
        }

        final mixState = _mixPlaylistHandler.start(
          playlistId: playlistId,
          seedVideoId: seedVideoId,
          title: title,
        );
        // 將已有的歌曲添加到 seenVideoIds（避免重複加載）
        mixState.addSeenVideoIds(_queueManager.tracks.map((t) => t.sourceId));

        // 更新 context 和 state
        _context = _context.copyWith(mode: PlayMode.mix);
        state = state.copyWith(
          isMixMode: true,
          mixTitle: title,
        );
        _publishCurrentQueueState();
        _triggerMixLoadMoreIfNearQueueEnd(PlayMode.mix);
      }

      // 恢复音量
      final savedVolume = _queueManager.savedVolume;
      await _audioService.setVolume(savedVolume);
      if (_isDisposed) return;
      state = state.copyWith(volume: savedVolume);
      logDebug('Restored volume: $savedVolume');

      // 恢复播放（如果有保存的歌曲）
      if (_queueManager.currentTrack != null) {
        logDebug('Restoring saved track: ${_queueManager.currentTrack!.title}');
        // 不自动播放，只设置 URL，传入保存的位置
        await _prepareCurrentTrack(
            autoPlay: false, initialPosition: positionToRestore);
        if (_isDisposed) return;
      }

      _isInitialized = true;
      logInfo('AudioController initialized successfully');
    } catch (e, stack) {
      if (_isDisposed) {
        logDebug('AudioController initialization aborted after dispose');
        return;
      }
      logError('Failed to initialize AudioController', e, stack);
      state = state.copyWith(error: 'Initialization failed: $e');
      rethrow;
    } finally {
      _isInitializing = false;
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
    if (_isDisposed) return;
    _isDisposed = true;
    _discardPendingSeek(reason: 'controller disposed');
    _clearSeekStabilizationWindow();
    _lyricsAutoMatchRequestId++;
    onLyricsAutoMatchStateChanged = null;
    _stopPositionCheckTimer();
    _cancelRetryTimer();
    _bufferWatchdog.dispose();
    _recoveryCoordinator.dispose();
    _playbackRequestSession.dispose();
    _networkRecoverySubscription?.cancel();
    _mixLoadMoreFuture = null;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _mixPlaylistHandler.clear();
    _queueManager.dispose();
    // 交还系统媒体控制。刻意**不** dispose 原生句柄：需要跟着 controller
    // 一起消失的是回调绑定，不是 SMTC 本身 —— 原生 session 只在 main.dart
    // 建立一次，dispose 掉之后没有任何程式码会重建它。按钮订阅留着，解绑后
    // 它派发到 null，正是 app 启动时的状态。
    _publisher.release(NowPlayingOwner.music);
    unawaited(_audioService.dispose().catchError((Object e, StackTrace stack) {
      logError('Failed to dispose audio service', e, stack);
    }));
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
        logDebug(
            'Manual retry for network error: ${state.currentTrack!.title}');
        await retryManually();
        return;
      }
      // 如果当前有错误状态，尝试重新播放当前歌曲
      if (state.error != null && state.currentTrack != null) {
        logDebug(
            'Retrying playback for track with error: ${state.currentTrack!.title}');
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
    _discardPendingSeek(reason: 'playback stopped');
    _clearSeekStabilizationWindow();
    await _audioService.stop();
    _clearPlayingTrack();
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    try {
      final deferredSeek = _deferSeekIfPlaybackLoading(position) ??
          _deferSeekIfPlaybackStabilizing(position);
      if (deferredSeek != null) {
        await deferredSeek;
        return;
      }
      await _performSeek(position);
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

  Future<void>? _deferSeekIfPlaybackLoading(Duration position) {
    final requestId = _context.activeRequestId;
    if (requestId <= 0) return null;

    final trackKey =
        state.playingTrack?.uniqueKey ?? state.currentTrack?.uniqueKey;
    if (trackKey == null) return null;

    _discardPendingSeek(reason: 'newer seek queued during playback handoff');
    final pending = _PendingSeekRequest(
      position: position,
      trackKey: trackKey,
      requestId: requestId,
    );
    _pendingSeek = pending;
    logDebug(
      'Deferring seek to $position until playback request $requestId is ready',
    );
    return pending.future;
  }

  Future<void>? _deferSeekIfPlaybackStabilizing(Duration position) {
    final window = _seekStabilizationWindow;
    if (window == null) return null;

    final trackKey =
        state.playingTrack?.uniqueKey ?? state.currentTrack?.uniqueKey;
    final remaining = _remainingSeekStabilizationDelay(
      requestId: window.requestId,
      trackKey: window.trackKey,
    );
    if (remaining <= Duration.zero ||
        trackKey != window.trackKey ||
        _playbackRequestSession.activeRequestId != window.requestId) {
      _clearSeekStabilizationWindow();
      return null;
    }

    _discardPendingSeek(reason: 'newer seek queued during seek stabilization');
    final pending = _PendingSeekRequest(
      position: position,
      trackKey: window.trackKey,
      requestId: window.requestId,
    );
    _pendingSeek = pending;
    logDebug(
      'Deferring seek to $position for $remaining after playback request ${window.requestId}',
    );
    unawaited(_applyPendingSeekIfCurrent(window.requestId));
    return pending.future;
  }

  Future<void> _performSeek(Duration position) async {
    // seek 之後重新緩衝是理所當然的，該給它完整的一份預算重新起算。
    _bufferWatchdog.cancel();
    await _audioService.seekTo(position);
    // 立即保存位置，避免 seek 后马上关闭应用导致进度丢失
    await _queueManager.savePositionNow();
  }

  /// 快进
  Future<void> seekForward([Duration? duration]) async {
    try {
      final seekDuration =
          duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
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
      final seekDuration =
          duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
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
    _playbackRequestSession.cancelActive();
    _discardPendingSeek(reason: 'single-track playback started');
    _clearSeekStabilizationWindow();
    _context = _context.copyWith(activeRequestId: 0);
    state = state.copyWith(isLoading: true, error: null);
    logInfo('Playing single track: ${track.title}');
    try {
      final savedTrack = await _queueManager.playSingle(track);
      await _playTrack(savedTrack);
    } on _RetryScheduledException {
      logDebug('Retry scheduled while playing track: ${track.title}');
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
    _playbackRequestSession.cancelActive();
    _discardPendingSeek(reason: 'temporary playback started');
    _clearSeekStabilizationWindow();
    _context = _context.copyWith(activeRequestId: 0);

    logInfo('Playing temporary track: ${track.title}');

    final nextSnapshot = _temporaryPlayHandler.enterTemporary(
      currentMode: _context.mode,
      currentState: _currentTemporaryPlaybackState(),
      hasQueueTrack: _queueManager.currentTrack != null,
      currentIndex: _queueManager.currentIndex,
      currentPosition: _audioService.position,
      currentWasPlaying: _audioService.isPlaying,
    );

    _context = _context.copyWith(
      mode: PlayMode.temporary,
      savedQueueIndex: nextSnapshot.savedQueueIndex,
      savedPosition: nextSnapshot.savedPosition,
      savedWasPlaying: nextSnapshot.savedWasPlaying,
      clearSavedState: !nextSnapshot.hasSavedState,
    );

    if (_context.hasSavedState) {
      logDebug(
          'Saved playback state: index: ${_context.savedQueueIndex}, position: ${_context.savedPosition}');
    }

    try {
      await _executePlayRequest(
        track: track,
        mode: PlayMode.temporary,
        persist: false,
        countsAsNewPlay: true,
        prefetchNext: false,
      );
    } on SourceApiException catch (e) {
      // 音源 API 错误：尝试恢复原队列
      logWarning(
          '${e.sourceType} API error for temporary track ${track.title}: ${e.message}');
      if (_shouldSkipSourceError(e)) {
        _toastService.showWarning(_sourceCannotPlayMessage(track, e));
      } else {
        _toastService
            .showError(t.audio.playbackFailed(message: _sourceErrorReason(e)));
      }
      if (_context.hasSavedState) {
        await _restoreSavedState();
      } else {
        _context =
            _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      }
    } catch (e, stack) {
      logError('Failed to play temporary track: ${track.title}', e, stack);
      _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      if (_context.hasSavedState) {
        await _restoreSavedState();
      } else {
        _context =
            _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      }
    }
  }

  /// 按保存的隊列索引與位置恢復歌曲播放
  Future<void> _restoreQueuePlayback({
    required RestorePlaybackPlan restorePlan,
    required PlayMode targetMode,
    required String debugLabel,
    bool clearSavedState = false,
  }) async {
    int? requestId;
    logDebug('$debugLabel started');

    try {
      final queue = _queueManager.tracks;
      if (queue.isEmpty) {
        logDebug('$debugLabel aborted: queue is empty');
        if (clearSavedState) {
          _context = _context.copyWith(mode: targetMode, clearSavedState: true);
        }
        _updateQueueState();
        return;
      }

      final targetIndex = restorePlan.savedIndex.clamp(0, queue.length - 1);
      _queueManager.setCurrentIndex(targetIndex);

      final currentTrack = _queueManager.currentTrack;
      if (currentTrack == null) {
        return;
      }
      final requestTrack = _createPlaybackRequestTrack(currentTrack);

      _updatePlayingTrack(currentTrack);
      _updateQueueState();

      final rewind = Duration(seconds: restorePlan.rewindSeconds);
      final adjustedPosition = restorePlan.savedPosition - rewind;
      final restorePosition =
          adjustedPosition.isNegative ? Duration.zero : adjustedPosition;

      final result = await _playbackRequestSession.restore(
        PlaybackRestoreCommand(
          track: requestTrack,
          mode: targetMode,
          position: restorePosition,
          shouldResume: restorePlan.savedWasPlaying,
        ),
      );
      requestId = result.requestId;
      if (result.isSuperseded) {
        return;
      }
      if (result.isTerminalMediaOpenError) {
        _handleTerminalMediaOpenResult(result);
        return;
      }
      if (result.isFailed) {
        final error = result.error!;
        final stackTrace = result.stackTrace ?? StackTrace.current;
        Error.throwWithStackTrace(error, stackTrace);
      }

      final executionTrack = result.track!;
      _replaceQueueTrackIfCurrent(executionTrack);

      if (clearSavedState) {
        _context = _context.copyWith(clearSavedState: true);
      }

      _exitLoadingState(
        requestId,
        executionTrack,
        mode: targetMode,
        streamResult: result.streamResult,
      );
      _updateQueueState();
      logInfo('$debugLabel completed successfully');
    } on SourceApiException catch (e) {
      logWarning(
          '$debugLabel failed: ${e.sourceType} API error: ${e.message}');
      if (clearSavedState) {
        _context = _context.copyWith(clearSavedState: true);
      }
      if (requestId == null || _isSessionSuperseded(requestId)) return;
      final track = _queueManager.currentTrack;
      if (track != null) {
        await _handleSourceError(track, e, targetMode, requestId);
      } else {
        _resetLoadingState(requestId: requestId);
      }
      return;
    } catch (e, stack) {
      logError('Failed during $debugLabel', e, stack);
      if (clearSavedState) {
        _context = _context.copyWith(clearSavedState: true);
      }
    } finally {
      if (requestId != null) {
        _resetLoadingState(requestId: requestId);
      }
    }
  }

  TemporaryPlaybackState _currentTemporaryPlaybackState() {
    return TemporaryPlaybackState(
      savedQueueIndex: _context.savedQueueIndex,
      savedPosition: _context.savedPosition,
      savedWasPlaying: _context.savedWasPlaying,
    );
  }

  /// 恢复保存的播放状态
  /// 注意：直接使用当前队列，不恢复队列内容（用户可能在临时播放期间修改了队列）
  Future<void> _restoreSavedState() async {
    if (!_context.hasSavedState) {
      logDebug('No saved state to restore');
      _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      return;
    }

    final positionSettings = await _queueManager.getPositionRestoreSettings();
    final restorePlan = _temporaryPlayHandler.buildRestorePlan(
      state: _currentTemporaryPlaybackState(),
      rememberPosition: positionSettings.enabled,
      rewindSeconds: positionSettings.tempPlayRewindSeconds,
    );

    if (restorePlan == null) {
      logDebug('No restore plan available');
      _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
      return;
    }

    await _restoreQueuePlayback(
      restorePlan: restorePlan,
      targetMode: PlayMode.queue,
      debugLabel: '_restoreSavedState',
      clearSavedState: true,
    );
  }

  /// 從電台返回到歌曲播放
  Future<void> returnFromRadio({
    required int? savedQueueIndex,
    required Duration savedPosition,
    required bool savedWasPlaying,
  }) async {
    await _ensureInitialized();
    _resetRetryState();

    if (_context.isTemporary && _context.hasSavedState) {
      await _returnToQueue();
      return;
    }

    final restorePlan = _temporaryPlayHandler.buildQueueRestorePlan(
      savedQueueIndex: savedQueueIndex,
      savedPosition: savedPosition,
      savedWasPlaying: savedWasPlaying,
    );
    if (restorePlan == null) {
      if (!savedWasPlaying && state.currentTrack != null) {
        _clearPlayingTrack();
      }
      return;
    }

    await _restoreQueuePlayback(
      restorePlan: restorePlan,
      targetMode: PlayMode.queue,
      debugLabel: 'returnFromRadio',
    );
  }

  /// 播放多首歌曲
  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    await _ensureInitialized();
    _playbackRequestSession.cancelActive();
    _discardPendingSeek(reason: 'queue playback started');
    _clearSeekStabilizationWindow();
    _context = _context.copyWith(activeRequestId: 0);
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

  /// 重新綁定歌曲播放的全局媒體控制回調
  void restoreMediaControlOwnership() => _claimMediaControls();

  Future<void> startMixFromPlaylist(Playlist playlist) async {
    final playlistId = playlist.mixPlaylistId;
    final seedVideoId = playlist.mixSeedVideoId;
    if (playlistId == null || seedVideoId == null) {
      throw StateError(t.library.main.mixInfoIncomplete);
    }

    final fetcher = _mixTracksFetcher;
    if (fetcher == null) {
      throw StateError(t.library.main.cannotLoadMix);
    }

    _playbackRequestSession.cancelActive();
    _discardPendingSeek(reason: 'Mix playback started');
    _clearSeekStabilizationWindow();
    _context = _context.copyWith(activeRequestId: 0);
    final mixStartRequestId = ++_mixStartRequestId;
    final playRequestGeneration = _playbackRequestSession.activeRequestId;
    final result = await fetcher(
      playlistId: playlistId,
      currentVideoId: seedVideoId,
    );
    if (!_isMixStartCurrent(mixStartRequestId, playRequestGeneration)) {
      return;
    }

    if (result.tracks.isEmpty) {
      throw StateError(t.library.main.cannotLoadMix);
    }

    await playMixPlaylist(
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: playlist.name,
      tracks: result.tracks,
    );
  }

  bool _isMixStartCurrent(int mixStartRequestId, int playRequestGeneration) {
    return !_isDisposed &&
        mixStartRequestId == _mixStartRequestId &&
        playRequestGeneration == _playbackRequestSession.activeRequestId;
  }

  /// 播放 Mix 播放列表
  ///
  /// Mix 播放列表是 YouTube 自動生成的播放列表（RD 開頭），使用特殊的播放模式：
  /// - 禁止隨機播放
  /// - 禁止添加/插入歌曲到隊列
  /// - 播放接近尾端時自動加載更多
  /// - 清空隊列時退出 Mix 模式
  Future<void> playMixPlaylist({
    required String playlistId,
    required String seedVideoId,
    required String title,
    required List<Track> tracks,
    int startIndex = 0,
  }) async {
    await _ensureInitialized();
    state = state.copyWith(
      isLoading: true,
      error: null,
      isLoadingMoreMix: false,
    );
    _publishCurrentQueueState();
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
      final mixState = _mixPlaylistHandler.start(
        playlistId: playlistId,
        seedVideoId: seedVideoId,
        title: title,
      );
      // 記錄已加載的視頻 ID（用於去重）
      mixState.addSeenVideoIds(tracks.map((t) => t.sourceId));

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
      _publishCurrentQueueState();

      // 播放第一首（使用 PlayMode.mix 以保持 Mix 模式）
      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        await _executePlayRequest(
          track: currentTrack,
          mode: PlayMode.mix,
          persist: true,
          countsAsNewPlay: true,
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
    final mixState = _mixPlaylistHandler.current;
    if (mixState != null) {
      logDebug('Exiting Mix mode');
      _mixPlaylistHandler.clear();
      _mixLoadMoreFuture = null;
      _context = _context.copyWith(mode: PlayMode.queue);
      state = state.copyWith(
        isMixMode: false,
        clearMixTitle: true,
        isLoadingMoreMix: false,
      );
      _publishCurrentQueueState();
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
        _requestSeekStabilizationForNextPlaybackRequest();
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
    logDebug(
        'next() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

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
        _requestSeekStabilizationForNextPlaybackRequest();
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
    logDebug(
        'previous() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 检测是否脱离队列播放
    if (_isPlayingOutOfQueue) {
      logDebug('Playing out of queue: returning to queue');
      await _returnToQueue();
      return;
    }

    // 如果播放超过3秒，重新开始当前歌曲
    if (_audioService.position.inSeconds >
        AppConstants.previousTrackThresholdSeconds) {
      await _audioService.seekTo(Duration.zero);
    } else {
      final prevIdx = _queueManager.moveToPrevious();
      if (prevIdx != null) {
        // 检查是否被更新的导航请求取代
        if (navId != _navRequestId) {
          logDebug(
              'previous() navId $navId superseded by $_navRequestId, aborting');
          return;
        }
        final track = _queueManager.currentTrack;
        if (track != null) {
          _requestSeekStabilizationForNextPlaybackRequest();
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
    return _applyQueueMutation(
        await _queueCommands.add(track, isMixMode: _context.isMix));
  }

  /// 批量添加到队列
  ///
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addAllToQueue(List<Track> tracks) async {
    await _ensureInitialized();
    return _applyQueueMutation(
        await _queueCommands.addAll(tracks, isMixMode: _context.isMix));
  }

  /// 添加到下一首
  ///
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addNext(Track track) async {
    await _ensureInitialized();
    return _applyQueueMutation(
        await _queueCommands.addNext(track, isMixMode: _context.isMix));
  }

  /// 从队列移除
  Future<void> removeFromQueue(int index) async {
    await _ensureInitialized();
    _applyQueueMutation(await _queueCommands.removeAt(index));
  }

  /// 移动队列中的歌曲
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    await _ensureInitialized();
    _applyQueueMutation(await _queueCommands.move(oldIndex, newIndex));
  }

  /// 随机打乱队列（破坏性）
  Future<void> shuffleQueue() async {
    await _ensureInitialized();
    _applyQueueMutation(
        await _queueCommands.shuffle(isMixMode: _context.isMix));
  }

  /// 清空队列
  ///
  /// 清空之後的兩件事留在這裡：退出 Mix 模式、以及讓還在響的那首歌進入
  /// detached 模式。兩者都是播放工作階段的狀態，不屬於佇列本身。
  Future<void> clearQueue() async {
    await _ensureInitialized();
    final mutation = await _queueCommands.clear();
    if (!mutation.isApplied) {
      _applyQueueMutation(mutation);
      return;
    }

    if (_context.isMix) {
      _exitMixMode();
    }
    if (_playingTrack != null && !_context.isTemporary) {
      _context = _context.copyWith(mode: PlayMode.detached);
      logDebug('Entered detached mode after clearing queue');
    }
    _updateQueueState();
  }

  /// 把一次佇列變更的結果投影到 `PlayerState`。
  ///
  /// 回傳值沿用原本的語意：只有真的改到佇列才算成功，被擋下與失敗都是 false。
  bool _applyQueueMutation(QueueMutation mutation) {
    switch (mutation.status) {
      case QueueMutationStatus.applied:
        _updateQueueState();
        return true;
      case QueueMutationStatus.blocked:
        return false;
      case QueueMutationStatus.failed:
        state = state.copyWith(error: mutation.error.toString());
        return false;
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
    _publishPlayModes();
  }

  /// 设置循环模式
  Future<void> setLoopMode(LoopMode mode) async {
    logDebug('Setting loop mode: $mode');
    await _queueManager.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);
    _publishPlayModes();
  }

  /// 循环切换循环模式
  Future<void> cycleLoopMode() async {
    await _queueManager.cycleLoopMode();
    state = state.copyWith(loopMode: _queueManager.loopMode);
    _publishPlayModes();
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
  Future<void> setAudioDevice(FmpAudioDevice device) async {
    await _audioService.setAudioDevice(device);
    await _settingsRepository?.update((s) {
      s.preferredAudioDeviceId = device.name;
      s.preferredAudioDeviceName = device.description;
    });
  }

  /// 设置为自动选择音频设备（跟随系统默认）
  Future<void> setAudioDeviceAuto() async {
    await _audioService.setAudioDeviceAuto();
    await _settingsRepository?.update((s) {
      s.preferredAudioDeviceId = null;
      s.preferredAudioDeviceName = null;
    });
  }

  /// 裝置清單就緒之後套用記住的輸出裝置。
  ///
  /// 只在啟動後套用一次：之後使用者自己選的裝置優先，而且裝置清單會因為
  /// 插拔而反覆變動，每次都套用會把使用者的當下選擇蓋掉。
  bool _restoredPreferredAudioDevice = false;

  Future<void> _restorePreferredAudioDevice(
      List<FmpAudioDevice> devices) async {
    if (_restoredPreferredAudioDevice || devices.isEmpty) return;
    final repo = _settingsRepository;
    if (repo == null) return;
    _restoredPreferredAudioDevice = true;

    final settings = await repo.get();
    final preferredId = settings.preferredAudioDeviceId;
    if (preferredId == null || preferredId.isEmpty) return;
    if (_isDisposed) return;

    // 裝置可能已經拔掉了 —— 找不到就維持系統預設，不要把設定清掉，
    // 使用者把耳機插回來時還會想要它。
    final match = devices.where((d) => d.name == preferredId).firstOrNull;
    if (match == null) {
      logInfo('Preferred audio device "$preferredId" is not connected');
      return;
    }
    logInfo('Restoring preferred audio device: ${match.name}');
    await _audioService.setAudioDevice(match);
  }

  // ========== 基于位置检测的备选切歌机制（解决后台播放 completed 事件丢失问题）========== //

  void _startPositionCheckTimer() {
    _stopPositionCheckTimer();
    _positionCheckTimer = Timer.periodic(
      AppConstants.positionCheckInterval,
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
    if (remaining <= AppConstants.positionCheckThreshold) {
      logDebug(
          'Position check triggered auto-next: position=$position, duration=$duration');
      // 走到這裡代表 remaining 已在容忍窗內，是真的播完。
      _onPlaybackEnded(const EndedNaturally());
    }
  }

  // ========== 私有方法 ==========

  Track _createPlaybackRequestTrack(Track track) => track.copy();

  void _replaceQueueTrackIfCurrent(Track updatedTrack) {
    final queueTrack = _queueManager.currentTrack;
    if (queueTrack == null || queueTrack.id != updatedTrack.id) {
      return;
    }
    _queueManager.replaceTrack(updatedTrack.copy());
  }

  void _triggerMixLoadMoreIfNearQueueEnd(PlayMode mode) {
    if (!_shouldLoadMoreMixTracks(mode)) return;

    final remaining =
        _queueManager.tracks.length - 1 - _queueManager.currentIndex;
    logDebug(
        'Mix mode: $remaining tracks remaining, loading more before queue end...');
    _scheduleMixLoadMore();
  }

  bool _shouldLoadMoreMixTracks(PlayMode mode) {
    if (mode != PlayMode.mix) return false;
    if (_mixLoadMoreFuture != null) return false;

    final queueLength = _queueManager.tracks.length;
    if (queueLength == 0) return false;

    final remaining = queueLength - 1 - _queueManager.currentIndex;
    final threshold =
        queueLength > AppConstants.mixLoadMoreRemainingThreshold + 1
            ? AppConstants.mixLoadMoreRemainingThreshold
            : 0;
    return remaining <= threshold;
  }

  void _scheduleMixLoadMore() {
    if (_mixLoadMoreFuture != null) return;

    final future = _loadMoreMixTracks();
    _mixLoadMoreFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_mixLoadMoreFuture, future)) {
          _mixLoadMoreFuture = null;
        }
      }),
    );
  }

  QueueState _createQueueStateFromCurrentState({int? queueVersion}) {
    return QueueState(
      queue: state.queue,
      upcomingTracks: state.upcomingTracks,
      currentIndex: state.currentIndex,
      queueTrack: state.queueTrack,
      isShuffleEnabled: state.isShuffleEnabled,
      loopMode: state.loopMode,
      canPlayPrevious: state.canPlayPrevious,
      canPlayNext: state.canPlayNext,
      queueVersion: queueVersion ?? state.queueVersion,
      isMixMode: state.isMixMode,
      mixTitle: state.mixTitle,
      isLoadingMoreMix: state.isLoadingMoreMix,
    );
  }

  void _publishCurrentQueueState() {
    onQueueStateChanged?.call(_createQueueStateFromCurrentState());
  }

  /// 接管系统媒体控制。
  ///
  /// 通知栏与 SMTC 的差异、以及哪些按钮该出现，全部由 [NowPlayingPublisher]
  /// 依 [PlaybackCapabilities] 决定 —— 这里只负责说「音乐这个模式支援什么」。
  void _claimMediaControls() {
    _publisher.claim(
      NowPlayingOwner.music,
      commands: MediaControlCommands(
        play: play,
        pause: pause,
        stop: stop,
        skipToNext: next,
        skipToPrevious: previous,
        seek: seekTo,
        setLoopMode: setLoopMode,
        setShuffleEnabled: (enabled) async {
          if (enabled != _queueManager.isShuffleEnabled) {
            await toggleShuffle();
          }
        },
      ),
      capabilities: PlaybackCapabilities.music,
    );
    _publishPlayModes();
  }

  void _publishPlayModes() {
    _publisher.publishPlayModes(
      NowPlayingOwner.music,
      loopMode: _queueManager.loopMode,
      shuffleEnabled: _queueManager.isShuffleEnabled,
    );
  }

  /// 更新正在播放的歌曲（UI 显示用）
  void _updatePlayingTrack(Track track, {bool countsAsNewPlay = false}) {
    if (_isDisposed) return;
    // 換歌才清掉「已經救過一次」的記號。刻意不放在 _startSessionLoadingState：
    // 那條路連 T3 自己發起的重試也會走到，等於每次重試都把自己的護欄清掉。
    if (_bufferStarvationTrackKey != null &&
        _bufferStarvationTrackKey != track.uniqueKey) {
      _bufferStarvationTrackKey = null;
    }
    _playingTrack = track;
    state = state.copyWith(playingTrack: track);

    // 更新系统媒体控制的媒体信息（通知栏 / SMTC）
    _publisher.publishTrack(NowPlayingOwner.music, track);

    // 一次播放請求裡這個方法會被呼叫兩次（先更新 UI，拿到 URL 後再補記），
    // 靠旗標避免記兩筆。這不是「聽滿幾秒才算」的門檻。
    if (countsAsNewPlay) {
      _playHistory.record(track);
    }

    logDebug('Updated playing track: ${track.title}');
  }

  /// 尝试自动匹配歌词（异步，不阻塞播放）
  Future<void> _tryAutoMatchLyrics(Track track) async {
    final requestId = ++_lyricsAutoMatchRequestId;
    final autoMatchService = _lyricsAutoMatchService;
    final settingsRepo = _settingsRepository;

    if (autoMatchService == null || settingsRepo == null) return;

    try {
      // 检查设置是否启用自动匹配
      final settings = await settingsRepo.get();
      if (requestId != _lyricsAutoMatchRequestId || _isDisposed) return;
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
        enabledSources: enabledSources,
        allowPlainLyricsAutoMatch: settings.allowPlainLyricsAutoMatch,
      );
      if (requestId != _lyricsAutoMatchRequestId || _isDisposed) return;
      if (matched) {
        logInfo('Auto-matched lyrics for: ${track.title}');
      }
    } catch (e) {
      if (requestId == _lyricsAutoMatchRequestId && !_isDisposed) {
        logWarning('Auto-match lyrics failed for ${track.title}: $e');
      }
    } finally {
      if (requestId == _lyricsAutoMatchRequestId && !_isDisposed) {
        onLyricsAutoMatchStateChanged?.call(false);
      }
    }
  }

  /// 清除正在播放的歌曲
  void _clearPlayingTrack() {
    _playingTrack = null;
    state = state.copyWith(
      clearPlayingTrack: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      clearDuration: true,
      replaceCurrentStreamMetadata: true,
    );

    // 系统媒体控制转为停止状态
    _publisher.publishStopped(NowPlayingOwner.music);

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
    final mixState = _mixPlaylistHandler.current;
    if (mixState == null || !_mixPlaylistHandler.markLoading(mixState)) {
      return;
    }

    final queue = _queueManager.tracks;
    if (queue.isEmpty) {
      _mixPlaylistHandler.finishLoading(mixState);
      return;
    }

    state = state.copyWith(isLoadingMoreMix: true);
    _publishCurrentQueueState();
    logInfo('Loading more Mix tracks...');

    const minNewTracksRequired = AppConstants.mixMinNewTracksRequired;
    const maxAttempts = AppConstants.mixMaxLoadAttempts;
    const sameVideoRetries = AppConstants.mixSameVideoRetries;
    const retryDelay = AppConstants.mixRetryDelay;

    // 收集所有新歌曲，最後一次性添加
    final collectedTracks = <Track>[];
    final collectedVideoIds = <String>{};
    int attempt = 0;
    final fetcher = _mixTracksFetcher;
    if (fetcher == null) {
      logWarning('Mix load failed: YouTube source unavailable');
      _toastService.showInfo(t.audio.mixLoadMoreError);
      _mixPlaylistHandler.finishLoading(mixState);
      if (_mixPlaylistHandler.isCurrent(mixState)) {
        state = state.copyWith(isLoadingMoreMix: false);
        _publishCurrentQueueState();
      }
      return;
    }

    try {
      while (collectedTracks.length < minNewTracksRequired &&
          attempt < maxAttempts) {
        if (!_mixPlaylistHandler.isCurrent(mixState)) {
          logDebug('Mix mode exited during load-more, aborting');
          return;
        }

        attempt++;

        // 選擇種子視頻：前 3 次用最後一首，之後用不同的視頻
        String seedVideoId;
        if (attempt <= sameVideoRetries) {
          seedVideoId = queue.last.sourceId;
          logDebug(
              'Attempt $attempt/$maxAttempts: using last track as seed ($seedVideoId)');
        } else {
          // 從隊列倒數第 2 ~ 倒數第 10 首中選擇一個不同的種子
          final seedIndex = queue.length - 1 - (attempt - sameVideoRetries);
          if (seedIndex >= 0) {
            seedVideoId = queue[seedIndex].sourceId;
            logDebug(
                'Attempt $attempt/$maxAttempts: using track at index $seedIndex as seed ($seedVideoId)');
          } else {
            seedVideoId = queue.last.sourceId;
            logDebug(
                'Attempt $attempt/$maxAttempts: fallback to last track as seed ($seedVideoId)');
          }
        }

        try {
          final result = await fetcher(
            playlistId: mixState.playlistId,
            currentVideoId: seedVideoId,
          );

          if (!_mixPlaylistHandler.isCurrent(mixState)) {
            logDebug('Mix mode exited after load-more fetch, aborting');
            return;
          }

          // 過濾已存在的歌曲（包括已在隊列中的和本輪已收集的）
          final newTracks = result.tracks
              .where((t) =>
                  !mixState.seenVideoIds.contains(t.sourceId) &&
                  !collectedVideoIds.contains(t.sourceId))
              .toList();

          if (newTracks.isNotEmpty) {
            logDebug(
                'Attempt $attempt: got ${newTracks.length} new tracks (total: ${collectedTracks.length + newTracks.length})');
            collectedTracks.addAll(newTracks);
            collectedVideoIds.addAll(newTracks.map((t) => t.sourceId));
          } else {
            logDebug('Attempt $attempt: no new tracks (all duplicates)');
          }

          // 如果還沒達到目標且還有重試次數，等待後繼續
          if (collectedTracks.length < minNewTracksRequired &&
              attempt < maxAttempts) {
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

      if (!_mixPlaylistHandler.isCurrent(mixState)) {
        logDebug('Mix mode exited before applying load-more results, aborting');
        return;
      }

      // 一次性添加所有收集到的新歌曲
      if (collectedTracks.isNotEmpty) {
        logInfo(
            'Mix load complete: adding ${collectedTracks.length} new tracks in $attempt attempts');
        mixState.addSeenVideoIds(collectedTracks.map((t) => t.sourceId));
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
      _mixPlaylistHandler.finishLoading(mixState);
      if (_mixPlaylistHandler.isCurrent(mixState)) {
        state = state.copyWith(isLoadingMoreMix: false);
        _publishCurrentQueueState();
      }
    }
  }

  // ========== 統一播放入口 ========== //

  /// 進入 session 加載狀態（統一的 UI 更新邏輯）
  void _startSessionLoadingState(int requestId) {
    _terminalMediaOpenErrorTrackKey = null;
    _seekStabilizationWindow = null;
    _discardPendingSeek(reason: 'new playback request started');
    _bufferWatchdog.cancel();
    state = state.copyWith(
      isLoading: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      error: null,
      clearDuration: true,
      replaceCurrentStreamMetadata: true,
    );
    _context = _context.copyWith(activeRequestId: requestId);
    _publishLoadingState();
  }

  void _publishLoadingState() {
    _publishPlaybackState(
      isPlaying: false,
      position: Duration.zero,
      processingState: FmpAudioProcessingState.loading,
    );
  }

  /// 速度与缓冲位置在这里读好再传出去 —— [NowPlayingPublisher] 刻意不认识
  /// [FmpAudioService]，维持成纯 sink。
  void _publishPlaybackState({
    required bool isPlaying,
    required Duration position,
    required FmpAudioProcessingState processingState,
  }) {
    _publisher.publishPlaybackState(
      NowPlayingOwner.music,
      isPlaying: isPlaying,
      position: position,
      bufferedPosition: _audioService.bufferedPosition,
      processingState: processingState,
      duration: _audioService.duration,
      speed: _audioService.speed,
    );
  }

  void _publishCurrentPlaybackState() {
    _publishPlaybackState(
      isPlaying: _audioService.isPlaying,
      position: _audioService.position,
      processingState: _audioService.processingState,
    );
  }

  /// 退出加載狀態
  /// [requestId] - 當前請求的 ID，用於驗證是否應該退出
  /// [trackWithUrl] - 成功獲取 URL 後的歌曲（用於更新 playingTrack）
  /// [mode] - 播放模式（用於更新 _context）
  /// [countsAsNewPlay] - 這次是否算一次新的播放。同時閘住播放歷史與歌詞
  ///   自動匹配 —— 重試與啟動還原都不算，否則會重複記錄、重複配歌詞
  /// [streamResult] - 音頻流選擇結果（碼率、格式等信息）
  void _exitLoadingState(
    int requestId,
    Track? trackWithUrl, {
    PlayMode? mode,
    bool countsAsNewPlay = false,
    AudioStreamResult? streamResult,
    bool stabilizeSeekAfterReady = false,
  }) {
    if (_isSessionSuperseded(requestId)) return;

    state = state.copyWith(
      isLoading: false,
      // 更新音頻流信息
      currentBitrate: streamResult?.bitrate,
      currentContainer: streamResult?.container,
      currentCodec: streamResult?.codec,
      currentStreamType: streamResult?.streamType,
      replaceCurrentStreamMetadata: true,
    );
    _context = _context.copyWith(activeRequestId: 0, mode: mode);

    if (trackWithUrl != null) {
      _updatePlayingTrack(trackWithUrl, countsAsNewPlay: countsAsNewPlay);
      if (stabilizeSeekAfterReady) {
        _startSeekStabilizationWindow(requestId, trackWithUrl);
      }
    }
    unawaited(_applyPendingSeekIfCurrent(requestId));
  }

  /// 重置加載狀態（在請求被取代或失敗時使用）
  void _resetLoadingState({int? requestId}) {
    if (_isDisposed) return;
    if (requestId != null && _isSessionSuperseded(requestId)) {
      return;
    }
    if (requestId != null) {
      _discardPendingSeekForRequest(
        requestId,
        reason: 'playback loading state reset',
      );
    } else {
      _discardPendingSeek(reason: 'playback loading state reset');
    }
    state = state.copyWith(isLoading: false);
    _context = _context.copyWith(activeRequestId: 0);
    _publishCurrentPlaybackState();
  }

  void _resetSourceErrorLoadingState(int requestId) {
    if (_isDisposed || _isSessionSuperseded(requestId)) return;
    _discardPendingSeekForRequest(
      requestId,
      reason: 'source error reset playback loading state',
    );
    _context = _context.copyWith(activeRequestId: 0);
    _publishCurrentPlaybackState();
  }

  void _clearMatchingSessionLoadingContext(int requestId) {
    if (_isDisposed || _context.activeRequestId != requestId) return;
    _discardPendingSeekForRequest(
      requestId,
      reason: 'playback loading context cleared',
    );
    _context = _context.copyWith(activeRequestId: 0);
    _publishCurrentPlaybackState();
  }

  Future<void> _applyPendingSeekIfCurrent(int requestId) async {
    final pending = _pendingSeek;
    if (pending == null || pending.requestId != requestId) return;

    final stabilizationDelay = _remainingSeekStabilizationDelay(
      requestId: requestId,
      trackKey: pending.trackKey,
    );
    if (stabilizationDelay > Duration.zero) {
      logDebug(
        'Waiting $stabilizationDelay before applying deferred seek for request $requestId',
      );
      await Future<void>.delayed(stabilizationDelay);
      if (_pendingSeek != pending) return;
    }

    final currentTrackKey =
        state.playingTrack?.uniqueKey ?? state.currentTrack?.uniqueKey;
    if (_isSessionSuperseded(requestId) ||
        currentTrackKey != pending.trackKey) {
      _discardPendingSeekForRequest(
        requestId,
        reason: 'pending seek no longer matches current track',
      );
      return;
    }

    _pendingSeek = null;
    logDebug(
      'Applying deferred seek to ${pending.position} for request $requestId',
    );
    try {
      await _performSeek(pending.position);
    } catch (e, stack) {
      logError(
          'Failed to apply deferred seek to ${pending.position}', e, stack);
    } finally {
      pending.complete();
    }
  }

  void _requestSeekStabilizationForNextPlaybackRequest() {
    _stabilizeSeekAfterNextPlaybackRequest = true;
  }

  bool _consumeSeekStabilizationForNextPlaybackRequest() {
    final shouldStabilize = _stabilizeSeekAfterNextPlaybackRequest;
    _stabilizeSeekAfterNextPlaybackRequest = false;
    return shouldStabilize;
  }

  void _startSeekStabilizationWindow(int requestId, Track track) {
    final until = DateTime.now().add(AppConstants.seekStabilizationDelay);
    _seekStabilizationWindow = _SeekStabilizationWindow(
      requestId: requestId,
      trackKey: track.uniqueKey,
      until: until,
    );
    logDebug(
      'Stabilizing seeks for request $requestId until $until',
    );
  }

  Duration _remainingSeekStabilizationDelay({
    required int requestId,
    required String trackKey,
  }) {
    final window = _seekStabilizationWindow;
    if (window == null ||
        window.requestId != requestId ||
        window.trackKey != trackKey) {
      return Duration.zero;
    }

    final remaining = window.until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _seekStabilizationWindow = null;
      return Duration.zero;
    }
    return remaining;
  }

  void _clearSeekStabilizationWindow() {
    _seekStabilizationWindow = null;
    _stabilizeSeekAfterNextPlaybackRequest = false;
  }

  void _discardPendingSeekForRequest(
    int requestId, {
    required String reason,
  }) {
    final pending = _pendingSeek;
    if (pending == null || pending.requestId != requestId) return;
    _pendingSeek = null;
    logDebug(
      'Discarding deferred seek to ${pending.position} for request $requestId: $reason',
    );
    pending.complete();
  }

  void _discardPendingSeek({required String reason}) {
    final pending = _pendingSeek;
    if (pending == null) return;
    _pendingSeek = null;
    logDebug(
      'Discarding deferred seek to ${pending.position} for request ${pending.requestId}: $reason',
    );
    pending.complete();
  }

  void _handleTerminalMediaOpenResult(PlaybackSessionResult result) {
    final resultTrack = result.track;
    if (resultTrack != null &&
        state.playingTrack?.uniqueKey != resultTrack.uniqueKey) {
      logDebug(
        'Ignoring stale terminal media open result for: ${resultTrack.title}',
      );
      return;
    }
    _handleTerminalMediaOpen(
      track: resultTrack,
      message: result.message,
      requestId: result.requestId,
    );
  }

  void _handlePostHandoffTerminalMediaOpen({
    required Track track,
    required String message,
  }) {
    if (_isDisposed || state.playingTrack?.uniqueKey != track.uniqueKey) {
      return;
    }
    _handleTerminalMediaOpen(track: track, message: message);
  }

  void _handleTerminalMediaOpen({
    required Track? track,
    required String? message,
    int? requestId,
  }) {
    if (message != null) {
      _toastService.showError(message);
    }
    _terminalMediaOpenErrorTrackKey =
        track?.uniqueKey ?? state.playingTrack?.uniqueKey;
    state = state.copyWith(
      error: message,
      isLoading: false,
      isPlaying: false,
      isBuffering: false,
      processingState: FmpAudioProcessingState.idle,
    );
    if (requestId != null) {
      _clearMatchingSessionLoadingContext(requestId);
    }
  }

  /// 檢查當前請求是否已被新請求取代
  bool _isSessionSuperseded(int requestId) {
    return _playbackRequestSession.isSuperseded(requestId);
  }

  Track? _nextTrackForPrefetch() {
    final nextIndex = _queueManager.getNextIndex();
    if (nextIndex == null) {
      return null;
    }
    final tracks = _queueManager.tracks;
    if (nextIndex < 0 || nextIndex >= tracks.length) {
      return null;
    }
    return tracks[nextIndex];
  }

  void _scheduleRetryForSessionRequest(
      int requestId, Track track, Duration? position, PlayMode mode) {
    if (_isSessionSuperseded(requestId)) return;
    _scheduleRetry(track, position, mode);
  }

  /// 統一的播放請求入口
  /// 所有播放操作都應該通過這個方法來執行
  ///
  /// [track] - 要播放的歌曲
  /// [mode] - 播放模式（queue/temporary/detached）
  /// [persist] - 是否將 URL 保存到數據庫
  /// [countsAsNewPlay] - 這次是否算一次新的播放。同時閘住播放歷史與歌詞
  ///   自動匹配 —— 重試與啟動還原都不算，否則會重複記錄、重複配歌詞
  /// [prefetchNext] - 是否預取下一首
  Future<void> _executePlayRequest({
    required Track track,
    required PlayMode mode,
    bool persist = true,
    bool countsAsNewPlay = true,
    bool prefetchNext = true,
  }) async {
    // 保存當前播放位置，用於網路錯誤重試時恢復
    // 必須在 session loading state（重置 position 為 zero）之前保存
    final positionBeforeLoad = state.position;

    // 階段 1：立即更新 UI（在任何 await 之前）
    _updatePlayingTrack(track);
    _updateQueueState();

    bool completedSuccessfully = false;
    int? requestId;
    final stabilizeSeekAfterReady =
        _consumeSeekStabilizationForNextPlaybackRequest();

    try {
      final requestTrack = _createPlaybackRequestTrack(track);
      final result = await _playbackRequestSession.start(
        PlaybackSessionCommand(
          track: requestTrack,
          mode: mode,
          persist: persist,
          prefetchNext: prefetchNext,
          positionBeforeLoad: positionBeforeLoad,
          onPlaybackStarting: onPlaybackStarting,
        ),
      );
      requestId = result.requestId;
      logDebug(
          '_executePlayRequest session finished for: ${track.title} (requestId: $requestId, mode: $mode, result: ${result.kind})');

      if (result.isSuperseded) {
        return;
      }
      if (result.isTerminalMediaOpenError) {
        _handleTerminalMediaOpenResult(result);
        return;
      }
      if (result.isFailed) {
        final error = result.error!;
        final stackTrace = result.stackTrace ?? StackTrace.current;
        Error.throwWithStackTrace(error, stackTrace);
      }

      final trackWithUrl = result.track!;
      final streamResult = result.streamResult;
      _replaceQueueTrackIfCurrent(trackWithUrl);

      // 階段 6：完成
      _exitLoadingState(result.requestId, trackWithUrl,
          mode: mode,
          countsAsNewPlay: countsAsNewPlay,
          streamResult: streamResult,
          stabilizeSeekAfterReady: stabilizeSeekAfterReady);
      completedSuccessfully = true;

      // 更新隊列狀態
      _updateQueueState();

      // 自动匹配歌词（后台执行，不阻塞播放）
      if (countsAsNewPlay) {
        unawaited(_tryAutoMatchLyrics(track));
      }

      // Mix 模式：接近尾端時提前加載更多歌曲
      _triggerMixLoadMoreIfNearQueueEnd(mode);

      logDebug(
          '_executePlayRequest completed successfully for: ${track.title}');
    } on SourceApiException catch (e) {
      logWarning(
          '${e.sourceType} API error for ${track.title}: ${e.message}');
      // 网络错误和超时：走重试逻辑，而非通用错误处理
      if (_shouldRetrySourceError(e)) {
        if (requestId == null || _isSessionSuperseded(requestId)) return;
        _scheduleSessionRetry(requestId, track, positionBeforeLoad, mode);
      }
      if (requestId == null || _isSessionSuperseded(requestId)) return;
      await _handleSourceError(track, e, mode, requestId);
    } catch (e, stack) {
      if (requestId != null && _isSessionSuperseded(requestId)) {
        logDebug(
            'Play request $requestId superseded after playback failure, ignoring error');
        return;
      }
      logError('Failed to play track: ${track.title}', e, stack);

      // Check if original error is retryable
      if (_isRetryableError(e)) {
        if (requestId == null || _isSessionSuperseded(requestId)) return;
        _scheduleSessionRetry(requestId, track, positionBeforeLoad, mode);
      }

      if (requestId != null && _isSessionSuperseded(requestId)) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
      if (requestId != null) {
        _resetSourceErrorLoadingState(requestId);
      }
      // 逾時要說是逾時。「播放失敗」對使用者來說看不出下一步該做什麼，
      // 「連線逾時」至少指向網路。
      _toastService.showError(
        e is PlaybackTimeoutException
            ? t.audio.cannotPlayReason(
                title: track.title,
                reason: t.audio.sourceErrorTimeout,
              )
            : t.audio.playbackFailedTrack(title: track.title),
      );
    } finally {
      if (requestId != null &&
          !completedSuccessfully &&
          _isSessionSuperseded(requestId)) {
        logDebug('Play request $requestId was superseded, resetting isLoading');
        _resetLoadingState(requestId: requestId);
      }
    }
  }

  /// 排程播放請求的重試並擲出 [_RetryScheduledException]（一定 throw）。
  ///
  /// 呼叫端須先確認「可重試」且已通過 superseded 檢查（superseded 時呼叫端自行
  /// return，不可進到此處）。封裝 reset→schedule→throw 三步，取代兩處逐字重複（C12）。
  Never _scheduleSessionRetry(
    int requestId,
    Track track,
    Duration? positionBeforeLoad,
    PlayMode mode,
  ) {
    _resetLoadingState(requestId: requestId);
    _scheduleRetryForSessionRequest(requestId, track, positionBeforeLoad, mode);
    throw const _RetryScheduledException();
  }

  /// 處理音源 API 錯誤的統一邏輯
  Future<void> _handleSourceError(
      Track track, SourceApiException e, PlayMode mode, int requestId) async {
    final cannotPlayMessage = _sourceCannotPlayMessage(track, e);
    if (_shouldSkipSourceError(e)) {
      logInfo('Track unavailable (${e.sourceType}): ${track.title}');
      final nextIdx = _queueManager.getNextIndex();
      if (nextIdx != null && mode == PlayMode.queue) {
        _resetLoadingState(requestId: requestId);
        _toastService.showWarning(
          _sourceCannotPlayMessage(track, e, skipped: true),
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!_isSessionSuperseded(requestId)) {
            next();
          }
        });
      } else {
        try {
          if (!_isSessionSuperseded(requestId)) {
            await _audioService.stop();
          }
        } catch (stopError) {
          logError(
              'Failed to stop player during source error handling', stopError);
        }
        if (_isSessionSuperseded(requestId)) return;
        state = state.copyWith(
          error: cannotPlayMessage,
          isLoading: false,
          queueTrack: _queueManager.currentTrack,
        );
        _resetSourceErrorLoadingState(requestId);
        _toastService.showError(cannotPlayMessage);
      }
    } else if (e.kind == SourceErrorKind.rateLimited) {
      logWarning('Rate limited (${e.sourceType}): ${track.title}');
      state = state.copyWith(
        error: e.message,
        isLoading: false,
      );
      _resetSourceErrorLoadingState(requestId);
      _toastService.showWarning(e.message);
    } else {
      final message = t.audio.playbackFailed(message: _sourceErrorReason(e));
      state = state.copyWith(
        error: message,
        isLoading: false,
      );
      _resetSourceErrorLoadingState(requestId);
      _toastService.showError(message);
    }
  }

  // ========== 网络重试逻辑 ========== //

  String _sourceCannotPlayMessage(
    Track track,
    SourceApiException error, {
    bool skipped = false,
  }) {
    final reason = _sourceErrorReason(error);
    return skipped
        ? t.audio.cannotPlaySkippedReason(title: track.title, reason: reason)
        : t.audio.cannotPlayReason(title: track.title, reason: reason);
  }

  String _sourceErrorReason(SourceApiException error) {
    final diagnostic = _sourceDiagnosticOrNull(error);
    if (diagnostic != null) return diagnostic;

    return switch (error.kind) {
      SourceErrorKind.unavailable => t.audio.sourceErrorUnavailable,
      SourceErrorKind.geoRestricted => t.audio.sourceErrorGeoRestricted,
      SourceErrorKind.vipRequired => t.audio.sourceErrorVipRequired,
      SourceErrorKind.loginRequired => t.audio.sourceErrorLoginRequired,
      SourceErrorKind.permissionDenied =>
        error.sourceType == SourceIds.bilibili
            ? t.audio.sourceErrorBilibiliPermissionDenied
            : t.audio.sourceErrorPermissionDenied,
      SourceErrorKind.network => t.audio.sourceErrorNetwork,
      SourceErrorKind.timeout => t.audio.sourceErrorTimeout,
      SourceErrorKind.rateLimited => error.message,
      SourceErrorKind.unknown =>
        error.message.trim().isNotEmpty ? error.message : t.error.unknownError,
    };
  }

  String? _sourceDiagnosticOrNull(SourceApiException error) {
    final message = error.message.trim();
    if (message.isEmpty) return null;
    if (_isLowSignalSourceDiagnostic(error, message)) return null;
    if (_syntheticSourceDiagnostics.contains(message)) return null;
    return message;
  }

  bool _isLowSignalSourceDiagnostic(
    SourceApiException error,
    String message,
  ) {
    if (message == error.code) return true;
    return RegExp(r'^-?\d+$').hasMatch(message);
  }

  bool _shouldRetrySourceError(SourceApiException error) =>
      error.kind.isRetryable;

  bool _shouldSkipSourceError(SourceApiException error) =>
      error.kind.shouldSkipTrack;

  /// 「串流解析階段」拋出的例外可不可以重試。
  ///
  /// 這裡處理的是 Dart 例外（音源 adapter 或 `MediaHandoff` 拋的），不是後端播
  /// 放器的事件 —— 後者已由 [PlaybackEndReason] 型別化。判斷一律看型別：
  ///
  /// - 音源 adapter 把 dio 的錯誤全部包成 [SourceApiException]（三個 adapter
  ///   共 22 處 `on DioException catch`），所以 `DioException` 不會逃到這裡；
  /// - `MediaHandoff` 直接用 `dart:io` 的 `HttpClient`，會拋下面那幾種。
  bool _isRetryableError(Object error) {
    // 預算逾時走的是「已經換過一次 fallback 了，停下並通知」，不進退避階梯。
    // 必須排在 TimeoutException 之前 —— 這一行就是 D2 的決策本身。
    if (error is PlaybackTimeoutException) return false;
    if (error is SourceApiException) return error.kind.isRetryable;
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is TlsException) return true;
    if (error is TimeoutException) return true;

    // 沒有列舉到的型別一律不重試，但要留下痕跡 —— 靜默地「猜它是網路錯誤」
    // 正是 issue #41 那類 bug 的來源。看到這行就把該型別補進上面的清單。
    logWarning(
        'Unclassified playback error, not retrying: ${error.runtimeType} $error');
    return false;
  }

  PlayMode get _currentRecoveryMode =>
      _context.isMix ? PlayMode.mix : PlayMode.queue;

  @override
  Future<PlaybackSessionResult> retryPlayback({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  }) async {
    logInfo('Retrying playback for: ${track.title}, savedPosition: $position');

    _updatePlayingTrack(track);
    _updateQueueState();

    final requestTrack = _createPlaybackRequestTrack(track);
    final result = await _playbackRequestSession.start(
      PlaybackSessionCommand(
        track: requestTrack,
        mode: mode,
        persist: false,
        prefetchNext: true,
        positionBeforeLoad: position ?? state.position,
        onPlaybackStarting: onPlaybackStarting,
      ),
    );

    logDebug(
        'retryPlayback session finished for: ${track.title} (requestId: ${result.requestId}, mode: $mode, result: ${result.kind})');

    if (result.isCompleted) {
      final trackWithUrl = result.track!;
      _replaceQueueTrackIfCurrent(trackWithUrl);
      _exitLoadingState(
        result.requestId,
        trackWithUrl,
        mode: mode,
        countsAsNewPlay: false,
        streamResult: result.streamResult,
      );
      _updateQueueState();

      state = state.copyWith(
        isNetworkError: false,
        isRetrying: false,
        retryAttempt: 0,
        nextRetryAt: null,
        clearNextRetryAt: true,
        error: null,
      );

      if (position != null && position > Duration.zero) {
        await Future<void>.delayed(AppConstants.seekStabilizationDelay);
        if (!_isDisposed && state.currentTrack?.uniqueKey == track.uniqueKey) {
          await seekTo(position);
        }
      }

      logInfo('Retry playback succeeded for: ${track.title}');
      return result;
    }

    if (!result.isSuperseded) {
      _resetLoadingState(requestId: result.requestId);
    }
    return result;
  }

  void _applyRecoveryEvent(
    PlaybackRecoveryEvent event, {
    bool showNonRetryableToast = false,
  }) {
    if (_isDisposed) return;

    switch (event.kind) {
      case PlaybackRecoveryEventKind.retryStarted:
        _applyRecoveryState(event.state, clearError: true);
      case PlaybackRecoveryEventKind.retryScheduled:
        final attempt = event.state.retryAttempt + 1;
        logInfo(
            'Scheduling retry $attempt/${NetworkRetryConfig.maxRetries} for: ${event.track?.title ?? 'unknown track'}');
        _applyRecoveryState(event.state);
      case PlaybackRecoveryEventKind.retryExhausted:
        logInfo(
            'Max retry attempts reached for: ${event.track?.title ?? 'unknown track'}');
        _applyRecoveryState(event.state);
      case PlaybackRecoveryEventKind.retrySucceeded:
        _applyRecoveryState(event.state, clearError: true);
      case PlaybackRecoveryEventKind.recoveryFailedNonRetryable:
        _applyRecoveryState(event.state);
        final result = event.result;
        if (result != null && result.isTerminalMediaOpenError) {
          _handleTerminalMediaOpenResult(result);
          return;
        }
        state = state.copyWith(error: event.error?.toString());
        final track = event.track;
        if (showNonRetryableToast && track != null) {
          _toastService
              .showError(t.audio.playbackFailedTrack(title: track.title));
        }
      case PlaybackRecoveryEventKind.staleEventIgnored:
        return;
    }
  }

  void _applyRecoveryState(
    PlaybackRecoveryState recoveryState, {
    bool clearError = false,
  }) {
    state = state.copyWith(
      isNetworkError: recoveryState.isNetworkError,
      isRetrying: recoveryState.isRetrying,
      retryAttempt: recoveryState.retryAttempt,
      nextRetryAt: recoveryState.nextRetryAt,
      clearNextRetryAt: recoveryState.nextRetryAt == null,
      error: clearError ? null : state.error,
    );
  }

  /// 安排重试（漸進式延遲）
  void _scheduleRetry(Track track, Duration? position, PlayMode mode) {
    final event = _recoveryCoordinator.scheduleRetry(
      track: track,
      position: position,
      mode: mode,
    );
    _applyRecoveryEvent(event);
  }

  /// 网络恢复时自动恢复播放
  Future<void> _onNetworkRecovered() async {
    logInfo(
        '_onNetworkRecovered called, recoveryTrack: ${_recoveryCoordinator.recoveryTrack?.title}');
    final event = await _recoveryCoordinator.onNetworkRecovered(
      mode: _currentRecoveryMode,
    );
    _applyRecoveryEvent(event, showNonRetryableToast: true);
  }

  /// 重置重试状态
  void _resetRetryState() {
    _applyRecoveryEvent(_recoveryCoordinator.reset());
  }

  /// 取消待处理的重试
  void _cancelRetryTimer() {
    _recoveryCoordinator.reset();
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
    final event = await _recoveryCoordinator.retryManually(
      fallbackTrack: state.playingTrack,
      fallbackPosition: state.position,
      mode: _currentRecoveryMode,
    );
    _applyRecoveryEvent(event, showNonRetryableToast: true);
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
        (_playingTrack != null &&
            queueTrack != null &&
            _playingTrack!.id != queueTrack.id) ||
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

    logDebug(
        'Audio URL expired for: ${track.title}, re-fetching and resuming from ${state.position}');
    final position = state.position;
    final trackKey = track.uniqueKey;
    final previousRequestId = _playbackRequestSession.activeRequestId;
    final requestTrack = _createPlaybackRequestTrack(track);
    await _playTrack(requestTrack);
    final resumedRequestId = _playbackRequestSession.activeRequestId;

    if (_isDisposed) return true;
    if (resumedRequestId == previousRequestId ||
        _playbackRequestSession.activeRequestId != resumedRequestId) {
      return true;
    }
    if (state.currentTrack?.uniqueKey != trackKey) return true;

    // 播放成功后恢复到之前的位置
    if (position.inSeconds > 0) {
      await Future.delayed(AppConstants.seekStabilizationDelay);
      if (_isDisposed) return true;
      if (_playbackRequestSession.activeRequestId != resumedRequestId) {
        return true;
      }
      if (state.currentTrack?.uniqueKey != trackKey) return true;
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
      countsAsNewPlay: true,
      prefetchNext: true,
    );
  }

  /// 准备当前歌曲（不自动播放）
  Future<void> _prepareCurrentTrack(
      {bool autoPlay = false, Duration? initialPosition}) async {
    if (_isDisposed) return;
    final track = _queueManager.currentTrack;
    if (track == null) return;

    int? requestId;
    try {
      _updatePlayingTrack(track);
      _updateQueueState();

      final requestTrack = _createPlaybackRequestTrack(track);
      final positionToSeek = initialPosition ?? _queueManager.savedPosition;
      logDebug('Attempting to restore position: $positionToSeek');

      Duration restorePosition = Duration.zero;
      if (positionToSeek > Duration.zero) {
        final positionSettings =
            await _queueManager.getPositionRestoreSettings();
        if (_isDisposed) return;
        final rewind = Duration(seconds: positionSettings.restartRewindSeconds);
        final adjustedPosition = positionToSeek - rewind;
        restorePosition =
            adjustedPosition.isNegative ? Duration.zero : adjustedPosition;
        logDebug(
            'Seeking to position: $restorePosition (original: $positionToSeek, rewind: ${rewind.inSeconds}s)');
      } else {
        logDebug('No saved position to restore (position is zero)');
      }

      final mode = _context.isMix ? PlayMode.mix : PlayMode.queue;
      final result = await _playbackRequestSession.restore(
        PlaybackRestoreCommand(
          track: requestTrack,
          mode: mode,
          position: restorePosition,
          shouldResume: autoPlay,
        ),
      );
      requestId = result.requestId;
      if (result.isSuperseded || _isDisposed) {
        return;
      }
      if (result.isTerminalMediaOpenError) {
        _handleTerminalMediaOpenResult(result);
        return;
      }
      if (result.isFailed) {
        final error = result.error!;
        final stackTrace = result.stackTrace ?? StackTrace.current;
        Error.throwWithStackTrace(error, stackTrace);
      }

      final executionTrack = result.track!;
      _replaceQueueTrackIfCurrent(executionTrack);
      _exitLoadingState(
        requestId,
        executionTrack,
        mode: mode,
        streamResult: result.streamResult,
      );
      _updateQueueState();

      final nextTrack = _nextTrackForPrefetch();
      if (nextTrack != null) {
        // 佇列裡的實例，不是 copy() —— 見 _prefetchNextIfRequested 的說明。
        unawaited(_audioStreamManager.prefetchTrack(nextTrack));
      }
    } catch (e, stack) {
      if (_isDisposed) return;
      logError('Failed to prepare track: ${track.title}', e, stack);
      if (requestId != null) {
        _resetLoadingState(requestId: requestId);
      }
    }
  }

  void _onPlayerStateChanged(FmpPlayerState playerState) {
    if (_isDisposed) return;
    // 電台播放中的狀態變化由 RadioController 處理，AudioController 不應更新自身狀態
    if (isRadioPlaying?.call() == true) {
      // 進電台時如果計時器正在跑，之後就再也收不到事件來取消它了。
      _bufferWatchdog.cancel();
      return;
    }
    if (_terminalMediaOpenErrorTrackKey != null &&
        state.playingTrack?.uniqueKey == _terminalMediaOpenErrorTrackKey &&
        state.error != null) {
      logDebug('Backend state ignored after terminal media open error');
      return;
    }

    // 音訊裝置剛失敗：引擎可能仍宣稱在播（mpv 沒有輸出裝置也會把 playing
    // 翻真），把它收回，否則 UI 會停在「正在播放」卻完全沒有聲音。
    if (playerState.playing && _isWithinOutputDeviceFailureGuard) {
      logDebug('Pausing: audio output device failed moments ago');
      unawaited(_audioService.pause());
      return;
    }

    final isBackendIdleDuringControllerLoad = _context.isInLoadingState &&
        playerState.processingState == FmpAudioProcessingState.idle;
    final effectiveProcessingState = isBackendIdleDuringControllerLoad
        ? FmpAudioProcessingState.loading
        : playerState.processingState;
    final effectiveIsPlaying =
        isBackendIdleDuringControllerLoad ? false : playerState.playing;
    final effectivePosition =
        _context.isInLoadingState ? Duration.zero : _audioService.position;

    logDebug(
        'PlayerState changed: playing=${playerState.playing}, processingState=${playerState.processingState}');
    state = state.copyWith(
      isPlaying: effectiveIsPlaying,
      isBuffering:
          effectiveProcessingState == FmpAudioProcessingState.buffering,
      // 防止播放器状态事件覆盖 URL 获取期间的 loading 状态
      isLoading: _context.isInLoadingState ||
          effectiveProcessingState == FmpAudioProcessingState.loading,
      processingState: effectiveProcessingState,
      error: state.error,
    );

    // 重新緩衝屬於 playing 的子狀態：這裡只餵資料，升不升級成失敗由 watchdog 判斷。
    _bufferWatchdog.onPlayerStateChanged(
      isBuffering:
          effectiveProcessingState == FmpAudioProcessingState.buffering,
      isPlaying: effectiveIsPlaying,
      isSuppressed: _context.isInLoadingState ||
          state.isRetrying ||
          state.isNetworkError ||
          _isWithinOutputDeviceFailureGuard,
    );

    // 更新系统媒体控制的播放状态（通知栏 / SMTC）
    //
    // 两个表面统一送 effective 值。过去 SMTC 收的是后端原始值，所以
    // AGENTS.md 那条「控制器拥有的载入阶段，后端 idle 事件不得覆盖
    // loading 状态」只在 Android 通知栏成立 —— 没有理由只保护一个平台。
    _publishPlaybackState(
      isPlaying: effectiveIsPlaying,
      position: effectivePosition,
      processingState: effectiveProcessingState,
    );
  }

  void _onPositionChanged(Duration position) {
    if (_isDisposed) return;
    // 電台播放中的位置變化與音樂播放器無關
    if (isRadioPlaying?.call() == true) return;
    // 加载期间忽略位置更新（防止旧歌曲的位置覆盖已重置的进度条）
    if (_context.isInLoadingState) return;

    state = state.copyWith(position: position, error: state.error);
    // 更新 QueueManager 的位置（用于恢复播放）
    _queueManager.updatePosition(position);

    // 节流通知栏/SMTC 更新：每 500ms 最多更新一次，减少 IPC 开销
    final shouldUpdateNotification =
        (position.inMilliseconds - _lastNotificationPosition.inMilliseconds)
                .abs() >=
            500;
    if (!shouldUpdateNotification) return;
    _lastNotificationPosition = position;

    // 更新系统媒体控制的进度（通知栏 / SMTC）
    _publishPlaybackState(
      isPlaying: _audioService.isPlaying,
      position: position,
      processingState: _audioService.processingState,
    );
  }

  /// T3：連續緩衝超過預算 —— 引擎還沒喊失敗，但已經播不動了。
  ///
  /// 政策與 T1/T2 一致（D2）：換一次串流再試，仍失敗就停下並通知。**不進
  /// 1/2/4/8/16 的退避階梯**，也不自動跳下一首。這裡刻意不自己開流 ——
  /// 那會變成繞過 [PlaybackRequestSession] 的第二條播放路徑。作廢快取的解析
  /// 結果之後交給 retryPlayback 重發一次請求，`_execute` 內建的「fallback
  /// 一次」就是那一次機會。
  Future<void> _onBufferStarvation() async {
    if (_isDisposed) return;
    final track = state.playingTrack;
    if (track == null) return;
    if (_context.isInLoadingState || state.isRetrying || state.isNetworkError) {
      return;
    }

    if (_bufferStarvationTrackKey == track.uniqueKey) {
      _failStalledPlayback(track);
      return;
    }
    _bufferStarvationTrackKey = track.uniqueKey;

    logWarning('Buffer starved during playback: ${track.title}');
    // 卡住的多半就是這條串流本身，重試前先讓它重新解析。
    _audioStreamManager.invalidateResolvedStream(track);

    final result = await retryPlayback(
      track: track,
      position: state.position,
      mode: _currentRecoveryMode,
    );
    if (_isDisposed || result.isCompleted || result.isSuperseded) return;
    _failStalledPlayback(track);
  }

  void _failStalledPlayback(Track track) {
    if (_isDisposed) return;
    state = state.copyWith(isPlaying: false, isLoading: false);
    _toastService.showError(
      t.audio.cannotPlayReason(
        title: track.title,
        reason: t.audio.sourceErrorTimeout,
      ),
    );
  }

  /// 傳輸層失敗：連線中斷、逾時、DNS、TLS。分類由後端完成。
  void _onTransportFailure(TransportFailed failure) {
    logError('Transport failure during playback: $failure');

    // 获取当前播放的歌曲
    final track = state.playingTrack;
    if (track == null) {
      logDebug('No playing track, ignoring error');
      return;
    }

    logWarning('Network error detected during playback: ${track.title}');

    // URL 沒過期不等於 URL 還能用。失敗過的那一個必須從可重用的解析結果裡拿掉，
    // 否則重試會一次又一次拿到同一個死 URL。
    _audioStreamManager.invalidateResolvedStream(track);

    final activeRetryRequestId = state.isRetrying && _context.isInLoadingState
        ? _context.activeRequestId
        : null;
    if (activeRetryRequestId != null) {
      _playbackRequestSession.cancelActive();
      _discardPendingSeek(reason: 'active retry handoff cancelled');
    }
    final retryRequestGeneration = _playbackRequestSession.activeRequestId;

    // 保存當前位置，stop() 可能會透過 positionStream 將 position 重置為 zero
    final positionBeforeStop = state.position;

    // 停止播放并触发重试
    _audioService.stop().then((_) {
      if (!_isAudioErrorRetryContextCurrent(track, retryRequestGeneration)) {
        return;
      }
      state = state.copyWith(isLoading: false, isPlaying: false);
      _resetLoadingState();
      final event = _recoveryCoordinator.onBackendNetworkError(
        track: track,
        position: positionBeforeStop,
        isActiveRetryHandoff: activeRetryRequestId != null,
        mode: _currentRecoveryMode,
      );
      _applyRecoveryEvent(event);
    }).catchError((e) {
      if (!_isAudioErrorRetryContextCurrent(track, retryRequestGeneration)) {
        return;
      }
      logError('Failed to stop player after error', e);
      // stop() 失败时仍需触发重试，否则播放器会卡在错误状态
      state = state.copyWith(isLoading: false, isPlaying: false);
      _resetLoadingState();
      final event = _recoveryCoordinator.onBackendNetworkError(
        track: track,
        position: positionBeforeStop,
        isActiveRetryHandoff: activeRetryRequestId != null,
        mode: _currentRecoveryMode,
      );
      _applyRecoveryEvent(event);
    });
  }

  bool _isAudioErrorRetryContextCurrent(
    Track track,
    int requestGeneration,
  ) {
    return !_isDisposed &&
        _playbackRequestSession.activeRequestId == requestGeneration &&
        state.playingTrack?.uniqueKey == track.uniqueKey &&
        state.currentTrack?.uniqueKey == track.uniqueKey;
  }

  void _recoverFromPrematureCompletion(Duration position) {
    final track = state.playingTrack ?? state.currentTrack;
    if (track == null) {
      logDebug('Premature completion ignored: no current track to recover');
      return;
    }

    state = state.copyWith(isLoading: false, isPlaying: false);
    _resetLoadingState();
    // 提前結束多半是這條串流本身出了問題（實測「零位元組」就長這樣），
    // 重試前先讓它重新解析，別再拿同一個 URL。
    _audioStreamManager.invalidateResolvedStream(track);
    final event = _recoveryCoordinator.onPrematureCompletion(
      track: track,
      position: position,
      mode: _currentRecoveryMode,
    );
    _applyRecoveryEvent(event);
  }

  void _onDurationChanged(Duration? duration) {
    if (_isDisposed) return;
    if (isRadioPlaying?.call() == true) return;
    state = state.copyWith(
      duration: duration,
      clearDuration: duration == null,
      error: state.error,
    );
  }

  void _onBufferedPositionChanged(Duration bufferedPosition) {
    if (_isDisposed) return;
    if (isRadioPlaying?.call() == true) return;
    state = state.copyWith(
      bufferedPosition: bufferedPosition,
      error: state.error,
    );
  }

  void _onSpeedChanged(double speed) {
    if (_isDisposed) return;
    state = state.copyWith(speed: speed, error: state.error);
  }

  void _onAudioDevicesChanged(List<FmpAudioDevice> devices) {
    if (_isDisposed) return;
    logDebug('Audio devices updated: ${devices.length} devices');
    state = state.copyWith(audioDevices: devices, error: state.error);
    unawaited(_restorePreferredAudioDevice(devices));
  }

  void _onAudioDeviceChanged(FmpAudioDevice? device) {
    if (_isDisposed) return;
    logDebug('Current audio device: ${device?.name ?? "auto"}');
    state = state.copyWith(currentAudioDevice: device, error: state.error);
  }

  Future<bool> _advanceAfterPendingMixLoadMore() async {
    if (!_context.isMix) return false;

    final pendingLoad = _mixLoadMoreFuture;
    if (pendingLoad == null) return false;

    logDebug('Mix queue end reached while load-more is pending; waiting...');
    await pendingLoad;
    if (_isDisposed || !_context.isMix) return false;

    final nextIdx = _queueManager.moveToNext();
    if (nextIdx == null) return false;

    final track = _queueManager.currentTrack;
    if (track == null) return false;

    await _playTrack(track);
    return true;
  }

  /// 後端回報「播放停下來了」的統一入口。
  ///
  /// 這裡只做型別分派：**判斷是哪一種結束是後端的責任**，因為只有後端知道自己
  /// 面對的是 mpv 還是 ExoPlayer。上層過去靠比對錯誤字串，實測會把「音訊輸出
  /// 裝置開不起來」誤判成「這首歌開不起來」（issue #41），而且兩個後端連走哪
  /// 條通道都不一致。
  void _onPlaybackEnded(PlaybackEndReason reason) {
    if (_isDisposed) return;

    // 電台的結束與失敗由 RadioController 自行處理（重連等），這裡不介入 ——
    // **輸出裝置失效除外**。裝置壞掉與現在播的是歌還是電台無關，而
    // RadioController 從來沒有訂閱過 endReasons，所以過去電台播放中拔掉音效
    // 裝置是零回饋（issue #41 症狀二）。_onOutputDeviceFailure 只發 toast、
    // 不動任何播放狀態，在電台情境下安全。
    if (isRadioPlaying?.call() == true) {
      if (reason case OutputDeviceFailed(:final raw)) {
        _onOutputDeviceFailure(raw);
        return;
      }
      logDebug('Playback end ignored: radio is playing ($reason)');
      return;
    }

    switch (reason) {
      case EndedNaturally():
        _onTrackCompleted();
      case EndedPrematurely(:final at, :final expected):
        if (!_canHandlePlaybackEnd()) return;
        logWarning(
            'Track ended before its natural end; scheduling retry: at=$at, expected=$expected');
        _recoverFromPrematureCompletion(at);
      case TransportFailed():
        _onTransportFailure(reason);
      case OutputDeviceFailed(:final raw):
        _onOutputDeviceFailure(raw);
      case MediaUnopenable(:final raw):
      case DecoderFailed(:final raw):
        _onMediaOpenFailure(raw);
      case UnclassifiedFailure(:final raw):
        // 顯性地丟棄：至少留下一行，而不是消失在一串字串比對之後。
        logWarning('Unclassified playback failure, ignoring: $raw');
    }
  }

  /// 播放結束事件是否該被處理（載入中／重試中／網路錯誤狀態下一律不處理）。
  bool _canHandlePlaybackEnd() {
    if (_context.isInLoadingState || state.isRetrying || state.isNetworkError) {
      logDebug('Playback end ignored during loading/retry state');
      return false;
    }
    return true;
  }

  /// 音訊「輸出裝置」失敗 —— 與這首歌無關，所以不能報「播放失敗: <歌名>」。
  ///
  /// 一次裝置失敗會連續產生多則訊息（實測 mpv 一次吐三條：`ao` 的兩條加上
  /// `cplayer` 的一條），所以這裡只對第一條做事，其餘在抑制窗內併掉。
  void _onOutputDeviceFailure(String raw) {
    logError('Audio output device failed: $raw');

    final now = DateTime.now();
    final last = _lastOutputDeviceFailureAt;
    _lastOutputDeviceFailureAt = now;
    if (last != null &&
        now.difference(last) < _outputDeviceFailureSuppressWindow) {
      return;
    }

    _toastService.showError(t.audio.audioOutputFailed);
  }

  /// 同一次裝置失敗的連續訊息在這個窗內只處理第一條（實測 mpv 一次吐三條）。
  static const _outputDeviceFailureSuppressWindow = Duration(seconds: 3);
  DateTime? _lastOutputDeviceFailureAt;

  /// 裝置失敗之後，這段時間內任何「開始播放」都要立刻收回。
  ///
  /// 失敗訊息會在播放 handoff **完成之前**抵達（實測：錯誤 48.68，
  /// `_ensurePlayback` 49.81 才把 playing 設回 true），所以不能用定時暫停去賭
  /// 順序 —— 改成看到 playing 翻真就收回。不 stop、不 cancelActive：媒體本身是
  /// 好的，使用者修好裝置後按播放即可繼續。
  static const _outputDeviceFailureGuardWindow = Duration(seconds: 5);

  bool get _isWithinOutputDeviceFailureGuard {
    final last = _lastOutputDeviceFailureAt;
    return last != null &&
        DateTime.now().difference(last) < _outputDeviceFailureGuardWindow;
  }

  void _onMediaOpenFailure(String raw) {
    final track = state.playingTrack;
    if (track == null) {
      logDebug('Media open failure ignored: no playing track ($raw)');
      return;
    }
    _audioStreamManager.invalidateResolvedStream(track);
    unawaited(_playbackRequestSession.onMediaOpenError(
      error: raw,
      track: track,
      positionAtError: state.position,
    ));
  }

  void _onTrackCompleted() {
    // 防止重复处理
    if (_isHandlingCompletion) return;

    if (!_canHandlePlaybackEnd()) return;

    _isHandlingCompletion = true;

    // 使用 Future.microtask 来避免在流监听器中直接操作
    Future.microtask(() async {
      try {
        logDebug(
            'Track completed, loopMode: ${_queueManager.loopMode}, shuffle: ${_queueManager.isShuffleEnabled}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');
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
        } else if (!await _advanceAfterPendingMixLoadMore()) {
          logDebug('No next track available');
          // 隊列播完了，但後端仍可能回報 playing（位置停在結尾）。不暫停的話
          // 位置檢查計時器每秒都會再判定一次「播完」—— 實測會無限重複觸發。
          if (_audioService.isPlaying) {
            await _audioService.pause();
          }
        }
      } catch (e, stack) {
        logError('Track completion handler failed', e, stack);
      } finally {
        _isHandlingCompletion = false;
      }
    });
  }

  void _onQueueStateChanged(void _) {
    if (_isDisposed) return;
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
        final targetIndex =
            _context.savedQueueIndex!.clamp(0, queue.length - 1);
        if (_queueManager.isShuffleEnabled) {
          // Shuffle 模式：从当前 shuffle 索引获取后续歌曲
          upcomingTracks =
              _queueManager.getUpcomingTracksFromIndex(targetIndex, count: 5);
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

    logDebug(
        'Updating queue state: ${queue.length} tracks, index: $currentIndex, queueTrack: ${queueTrack?.title ?? "null"}, playingTrack: ${_playingTrack?.title ?? "null"}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');
    final nextQueueVersion = state.queueVersion + 1;
    state = state.copyWith(
      queue: queue,
      upcomingTracks: upcomingTracks,
      currentIndex: currentIndex,
      queueTrack: queueTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: canPlayPrevious,
      canPlayNext: canPlayNext,
      queueVersion: nextQueueVersion,
    );
    onQueueStateChanged?.call(
      _createQueueStateFromCurrentState(queueVersion: nextQueueVersion),
    );
  }
}

// ========== Providers ==========

/// AudioService Provider（平台条件选择）
/// Android/iOS: JustAudioService (ExoPlayer, 更轻量)
/// Windows/Linux: MediaKitAudioService (libmpv, 支持设备切换)
final audioServiceProvider = Provider<FmpAudioService>((ref) {
  final runtimePlatform = ref.watch(audioRuntimePlatformProvider);
  if (runtimePlatform == AudioRuntimePlatform.mobile) {
    return JustAudioService();
  }
  return MediaKitAudioService();
});

final queuePersistenceManagerProvider =
    Provider<QueuePersistenceManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;

  return QueuePersistenceManager(
    queueRepository: QueueRepository(db),
    trackRepository: TrackRepository(db),
    settingsRepository: SettingsRepository(db),
  );
});

final audioStreamManagerProvider = Provider<AudioStreamManager>((ref) {
  final manager = AudioStreamManager(
    streamResolutionService: ref.watch(streamResolutionServiceProvider),
    sourceAuthContext: ref.watch(sourceAuthContextProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// QueueManager Provider
final queueManagerProvider = Provider<QueueManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final queuePersistenceManager = ref.watch(queuePersistenceManagerProvider);

  return QueueManager(
    queueRepository: QueueRepository(db),
    trackRepository: TrackRepository(db),
    queuePersistenceManager: queuePersistenceManager,
  );
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
    audioStreamManager: ref.watch(audioStreamManagerProvider),
    toastService: toastService,
    nowPlayingPublisher: ref.watch(nowPlayingPublisherProvider),
    playHistoryRepository: playHistoryRepository,
    // Lyrics settings must not rebuild the playback controller. The latest
    // values are read from SettingsRepository when auto-match actually runs.
    lyricsAutoMatchService: ref.read(lyricsAutoMatchServiceProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    queuePersistenceManager: ref.watch(queuePersistenceManagerProvider),
    mixTracksFetcher: ref
        .watch(sourceManagerProvider)
        .dynamicPlaylistSource(SourceIds.youtube)
        ?.fetchMixTracks,
  );

  // 设置网络恢复监听（用于断网重连自动恢复播放）
  final connectivityNotifier = ref.watch(connectivityProvider.notifier);
  controller
      .setupNetworkRecoveryListener(connectivityNotifier.onNetworkRecovered);

  // 设置歌词自动匹配状态回调
  controller.onLyricsAutoMatchStateChanged = (isMatching) {
    ref.read(lyricsAutoMatchingProvider.notifier).state = isMatching;
  };

  controller.onQueueStateChanged = (queueState) {
    ref.read(queueStateProvider.notifier).state = queueState;
  };

  final downloadPathSubscription =
      ref.watch(audioStreamManagerProvider).downloadPathsChangedStream.listen(
    (event) {
      final playlistIds = <int>{};
      for (final info in event.track.playlistInfo) {
        if (info.playlistId > 0) {
          playlistIds.add(info.playlistId);
        }
      }
      ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
            savePaths: event.removedPaths,
            affectedPlaylistIds: playlistIds,
            includeDownloadedCategories: event.removedPaths.isNotEmpty,
            fileExistsChanged: false,
          );
      for (final path in event.removedPaths) {
        ref.read(fileExistsCacheProvider.notifier).remove(path);
      }
    },
  );
  ref.onDispose(downloadPathSubscription.cancel);

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
  return ref.watch(audioControllerProvider.select((s) => s.currentTrack));
});

/// 当前进度
final positionProvider = Provider<Duration>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.position));
});

/// 总时长
final durationProvider = Provider<Duration?>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.duration));
});

/// 播放队列
final queueProvider = Provider<List<Track>>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queue));
});

final queueVersionProvider = Provider<int>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueVersion));
});

final queueTrackProvider = Provider<Track?>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueTrack));
});

/// 是否启用随机播放
final isShuffleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.isShuffleEnabled));
});

/// 循环模式
final loopModeProvider = Provider<LoopMode>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.loopMode));
});
