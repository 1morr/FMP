import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../providers/database_provider.dart';
import '../toast_service.dart';
import 'audio_service.dart';
import 'queue_manager.dart';

/// 播放状态
class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isLoading;
  final just_audio.ProcessingState processingState;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int? currentIndex;
  final Track? currentTrack;
  final List<Track> queue;
  final String? error;

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isLoading = false,
    this.processingState = just_audio.ProcessingState.idle,
    this.position = Duration.zero,
    this.duration,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.none,
    this.currentIndex,
    this.currentTrack,
    this.queue = const [],
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.error,
  });

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
    just_audio.ProcessingState? processingState,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? currentIndex,
    Track? currentTrack,
    List<Track>? queue,
    bool? canPlayPrevious,
    bool? canPlayNext,
    String? error,
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
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      error: error,
    );
  }
}

/// 音频控制器 - 管理所有播放相关的状态和操作
/// 协调 AudioService（单曲播放）和 QueueManager（队列管理）
class AudioController extends StateNotifier<PlayerState> with Logging {
  final AudioService _audioService;
  final QueueManager _queueManager;
  final ToastService _toastService;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;

  // 防止重复处理完成事件
  bool _isHandlingCompletion = false;

  // 播放锁 - 防止快速切歌时的竞态条件
  Completer<void>? _playLock;
  int _playRequestId = 0;

  AudioController({
    required AudioService audioService,
    required QueueManager queueManager,
    required ToastService toastService,
  })  : _audioService = audioService,
        _queueManager = queueManager,
        _toastService = toastService,
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

      // 监听歌曲完成事件
      _subscriptions.add(
        _audioService.completedStream.listen(_onTrackCompleted),
      );

      // 监听队列状态变化
      _subscriptions.add(
        _queueManager.stateStream.listen(_onQueueStateChanged),
      );

      // 更新初始状态
      _updateQueueState();

      // 恢复音量
      final savedVolume = _queueManager.savedVolume;
      await _audioService.setVolume(savedVolume);
      state = state.copyWith(volume: savedVolume);
      logDebug('Restored volume: $savedVolume');

      // 恢复播放（如果有保存的歌曲）
      if (_queueManager.currentTrack != null) {
        logDebug('Restoring saved track: ${_queueManager.currentTrack!.title}');
        // 不自动播放，只设置 URL
        await _prepareCurrentTrack(autoPlay: false);
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
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _queueManager.dispose();
    _audioService.dispose();
    super.dispose();
  }

  // ========== 播放控制 ==========

  /// 播放
  Future<void> play() async {
    await _audioService.play();
  }

  /// 暂停
  Future<void> pause() async {
    await _audioService.pause();
  }

  /// 切换播放/暂停
  /// 如果当前歌曲有错误状态，尝试重新播放当前歌曲
  Future<void> togglePlayPause() async {
    // 如果当前有错误状态，尝试重新播放当前歌曲
    if (state.error != null && state.currentTrack != null) {
      logDebug('Retrying playback for track with error: ${state.currentTrack!.title}');
      await _playTrack(state.currentTrack!);
      return;
    }
    await _audioService.togglePlayPause();
  }

  /// 停止
  Future<void> stop() async {
    await _audioService.stop();
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    await _audioService.seekTo(position);
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
  Future<void> seekForward([Duration duration = const Duration(seconds: 10)]) async {
    await _audioService.seekForward(duration);
  }

  /// 快退
  Future<void> seekBackward([Duration duration = const Duration(seconds: 10)]) async {
    await _audioService.seekBackward(duration);
  }

  // ========== 队列控制 ==========

  /// 播放单首歌曲
  Future<void> playSingle(Track track) async {
    await _ensureInitialized();
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

  /// 播放队列中指定索引的歌曲
  Future<void> playAt(int index) async {
    await _ensureInitialized();
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
    logDebug('next() called');
    final nextIdx = _queueManager.moveToNext();
    if (nextIdx != null) {
      final track = _queueManager.currentTrack;
      if (track != null) {
        await _playTrack(track);
      }
    }
  }

  /// 上一首
  Future<void> previous() async {
    await _ensureInitialized();
    logDebug('previous() called');
    // 如果播放超过3秒，重新开始当前歌曲
    if (_audioService.position.inSeconds > 3) {
      await _audioService.seekTo(Duration.zero);
    } else {
      final prevIdx = _queueManager.moveToPrevious();
      if (prevIdx != null) {
        final track = _queueManager.currentTrack;
        if (track != null) {
          await _playTrack(track);
        }
      }
    }
  }

  /// 添加到队列
  Future<void> addToQueue(Track track) async {
    await _ensureInitialized();
    logInfo('Adding to queue: ${track.title}');
    try {
      await _queueManager.add(track);
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to add track to queue', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 添加到下一首
  Future<void> addNext(Track track) async {
    await _ensureInitialized();
    logInfo('Adding next: ${track.title}');
    try {
      await _queueManager.addNext(track);
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to add track as next', e, stack);
      state = state.copyWith(error: e.toString());
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
      await _audioService.stop();
      await _queueManager.clear();
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
    logDebug('Toggling shuffle');
    await _queueManager.toggleShuffle();
    state = state.copyWith(isShuffleEnabled: _queueManager.isShuffleEnabled);
  }

  /// 设置循环模式
  Future<void> setLoopMode(LoopMode mode) async {
    logDebug('Setting loop mode: $mode');
    await _queueManager.setLoopMode(mode);
    state = state.copyWith(loopMode: mode);
  }

  /// 循环切换循环模式
  Future<void> cycleLoopMode() async {
    await _queueManager.cycleLoopMode();
    state = state.copyWith(loopMode: _queueManager.loopMode);
  }

  // ========== 音量 ==========

  /// 设置音量
  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 保存音量设置
    await _queueManager.saveVolume(volume);
  }

  // ========== 私有方法 ==========

  /// 获取播放音频所需的 HTTP 请求头
  /// Bilibili 需要 Referer 头才能正常播放
  Map<String, String>? _getHeadersForTrack(Track track) {
    switch (track.sourceType) {
      case SourceType.bilibili:
        return {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        };
      case SourceType.youtube:
        return null;
    }
  }

  /// 播放指定歌曲
  Future<void> _playTrack(Track track) async {
    // 获取当前请求ID，用于检测是否被新请求取代
    final requestId = ++_playRequestId;
    logDebug('_playTrack started for: ${track.title} (requestId: $requestId)');

    // 等待之前的播放操作完成
    if (_playLock != null && !_playLock!.isCompleted) {
      logDebug('Waiting for previous play operation to complete...');
      await _playLock!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logWarning('Previous play operation timed out, proceeding anyway');
        },
      );
    }

    // 检查是否已被新请求取代
    if (requestId != _playRequestId) {
      logDebug('Play request $requestId superseded by $requestId, aborting');
      return;
    }

    // 创建新的锁
    _playLock = Completer<void>();

    state = state.copyWith(isLoading: true, error: null);
    _updateQueueState();

    try {
      // 确保有音频 URL
      logDebug('Fetching audio URL for: ${track.title}');
      final trackWithUrl = await _queueManager.ensureAudioUrl(track);

      // 再次检查是否被取代
      if (requestId != _playRequestId) {
        logDebug('Play request $requestId superseded after URL fetch, aborting');
        return;
      }

      // 获取播放地址
      final url = trackWithUrl.downloadedPath ??
                  trackWithUrl.cachedPath ??
                  trackWithUrl.audioUrl;

      if (url == null) {
        throw Exception('No audio URL available for: ${track.title}');
      }

      final urlType = trackWithUrl.downloadedPath != null ? "downloaded" : trackWithUrl.cachedPath != null ? "cached" : "stream";
      logDebug('Playing track: ${track.title}, URL type: $urlType, source: ${track.sourceType}');

      // 播放
      if (trackWithUrl.downloadedPath != null || trackWithUrl.cachedPath != null) {
        await _audioService.playFile(url);
      } else {
        // 获取该音源所需的 HTTP 请求头
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.playUrl(url, headers: headers);
      }

      // 再次检查是否被取代
      if (requestId != _playRequestId) {
        logDebug('Play request $requestId superseded after playUrl, stopping');
        await _audioService.stop();
        return;
      }

      // 等待一小段时间确保播放状态稳定
      await Future.delayed(const Duration(milliseconds: 100));

      // 如果还没播放，再次尝试
      if (!_audioService.isPlaying &&
          _audioService.processingState == just_audio.ProcessingState.ready) {
        logWarning('Player ready but not playing, calling play() again');
        await _audioService.play();
      }

      // 预取下一首
      _queueManager.prefetchNext();

      state = state.copyWith(isLoading: false);
      logDebug('_playTrack completed successfully for: ${track.title}');
    } on just_audio.PlayerInterruptedException catch (e) {
      // 播放被中断（通常是因为新的播放请求），不作为错误处理
      logDebug('Playback interrupted for ${track.title}: ${e.message}');
      state = state.copyWith(isLoading: false);
    } on BilibiliApiException catch (e) {
      // Bilibili API 错误（如视频不可用、版权限制等）
      logWarning('Bilibili API error for ${track.title}: ${e.message}');
      
      // 如果视频不可用，尝试跳到下一首
      if (e.isUnavailable || e.isGeoRestricted) {
        logInfo('Track unavailable: ${track.title}');
        // 检查是否有下一首可播放
        final nextIdx = _queueManager.getNextIndex();
        if (nextIdx != null) {
          // 有下一首，显示提示并跳过
          state = state.copyWith(isLoading: false);
          _toastService.showWarning('无法播放「${track.title}」，已跳过');
          Future.delayed(const Duration(milliseconds: 300), () {
            next();
          });
        } else {
          // 没有下一首，停止当前播放并显示提示
          await _audioService.stop();
          state = state.copyWith(
            error: '无法播放: ${e.message}',
            isLoading: false,
          );
          _toastService.showError('无法播放「${track.title}」');
        }
      } else {
        state = state.copyWith(
          error: '无法播放: ${e.message}',
          isLoading: false,
        );
      }
    } catch (e, stack) {
      logError('Failed to play track: ${track.title}', e, stack);
      await _audioService.stop();
      state = state.copyWith(error: e.toString(), isLoading: false);
      _toastService.showError('播放失败: ${track.title}');
    } finally {
      // 释放锁
      if (!_playLock!.isCompleted) {
        _playLock!.complete();
      }
    }
  }

  /// 准备当前歌曲（不自动播放）
  Future<void> _prepareCurrentTrack({bool autoPlay = false}) async {
    final track = _queueManager.currentTrack;
    if (track == null) return;

    try {
      final trackWithUrl = await _queueManager.ensureAudioUrl(track);

      final url = trackWithUrl.downloadedPath ??
                  trackWithUrl.cachedPath ??
                  trackWithUrl.audioUrl;

      if (url == null) return;

      if (trackWithUrl.downloadedPath != null || trackWithUrl.cachedPath != null) {
        await _audioService.setFile(url);
      } else {
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.setUrl(url, headers: headers);
      }

      // 恢复播放位置
      final savedPosition = _queueManager.savedPosition;
      if (savedPosition > Duration.zero) {
        await _audioService.seekTo(savedPosition);
      }

      if (autoPlay) {
        await _audioService.play();
      }
    } catch (e) {
      logError('Failed to prepare track: ${track.title}', e);
    }
  }

  void _onPlayerStateChanged(just_audio.PlayerState playerState) {
    logDebug('PlayerState changed: playing=${playerState.playing}, processingState=${playerState.processingState}');
    state = state.copyWith(
      isPlaying: playerState.playing,
      isBuffering: playerState.processingState == just_audio.ProcessingState.buffering,
      isLoading: playerState.processingState == just_audio.ProcessingState.loading,
      processingState: playerState.processingState,
    );
  }

  void _onPositionChanged(Duration position) {
    state = state.copyWith(position: position);
    // 更新 QueueManager 的位置（用于恢复播放）
    _queueManager.updatePosition(position);
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

  void _onTrackCompleted(void _) {
    // 防止重复处理
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    logDebug('Track completed, loopMode: ${_queueManager.loopMode}, shuffle: ${_queueManager.isShuffleEnabled}');

    // 使用 Future.microtask 来避免在流监听器中直接操作
    Future.microtask(() async {
      try {
        if (_queueManager.loopMode == LoopMode.one) {
          // 单曲循环：seek 到开头并重新播放
          logDebug('LoopOne mode: seeking to start and playing');
          await _audioService.seekTo(Duration.zero);
          await _audioService.play();
        } else {
          // 移动到下一首
          final nextIdx = _queueManager.moveToNext();
          if (nextIdx != null) {
            final track = _queueManager.currentTrack;
            if (track != null) {
              await _playTrack(track);
            }
          } else {
            logDebug('No next track available');
          }
        }
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
    final currentTrack = _queueManager.currentTrack;
    logDebug('Updating queue state: ${queue.length} tracks, index: $currentIndex, track: ${currentTrack?.title ?? "null"}');
    state = state.copyWith(
      queue: queue,
      currentIndex: currentIndex,
      currentTrack: currentTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: _queueManager.hasPrevious,
      canPlayNext: _queueManager.hasNext,
    );
  }
}

// ========== Providers ==========

/// AudioService Provider
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// QueueManager Provider
final queueManagerProvider = Provider<QueueManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final sourceManager = ref.watch(sourceManagerProvider);

  final queueRepository = QueueRepository(db);
  final trackRepository = TrackRepository(db);

  final manager = QueueManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
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

  final controller = AudioController(
    audioService: audioService,
    queueManager: queueManager,
    toastService: toastService,
  );

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
