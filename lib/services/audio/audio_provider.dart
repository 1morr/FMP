import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../providers/database_provider.dart';
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
  final PlayMode playMode;
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
    this.playMode = PlayMode.sequential,
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
    PlayMode? playMode,
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
      playMode: playMode ?? this.playMode,
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
class AudioController extends StateNotifier<PlayerState> with Logging {
  final AudioService _audioService;
  final QueueManager _queueManager;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;

  AudioController({
    required AudioService audioService,
    required QueueManager queueManager,
  })  : _audioService = audioService,
        _queueManager = queueManager,
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

      // 监听当前索引
      _subscriptions.add(
        _audioService.currentIndexStream.listen(_onCurrentIndexChanged),
      );

      // 监听速度
      _subscriptions.add(
        _audioService.speedStream.listen(_onSpeedChanged),
      );

      // 更新初始状态
      _updateQueueState();
      
      // 恢复保存的播放模式
      final savedPlayMode = _queueManager.playMode;
      if (savedPlayMode != PlayMode.sequential) {
        logDebug('Restoring saved play mode: $savedPlayMode');
        await _audioService.setPlayMode(savedPlayMode);
        // 如果是 shuffle 模式，需要生成 shuffle order
        if (savedPlayMode == PlayMode.shuffle) {
          _queueManager.restoreShuffleMode();
        }
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
  Future<void> togglePlayPause() async {
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
      await _queueManager.playSingle(track);
      _updateQueueState();
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
      _updateQueueState();
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
      await _queueManager.playAt(index);
    } catch (e, stack) {
      logError('Failed to play at index $index', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 下一首
  Future<void> next() async {
    await _ensureInitialized();
    logDebug('next() called');
    await _queueManager.skipToNext();
  }

  /// 上一首
  Future<void> previous() async {
    await _ensureInitialized();
    logDebug('previous() called');
    // 如果播放超过3秒，重新开始当前歌曲
    if (_audioService.position.inSeconds > 3) {
      await _audioService.seekTo(Duration.zero);
    } else {
      await _queueManager.skipToPrevious();
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

  /// 随机打乱队列
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

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    await _audioService.setPlayMode(mode);
    await _queueManager.setPlayMode(mode);
    state = state.copyWith(playMode: mode);
  }

  /// 切换播放模式
  Future<void> cyclePlayMode() async {
    await _audioService.cyclePlayMode();
    await _queueManager.setPlayMode(_audioService.playMode);
    state = state.copyWith(playMode: _audioService.playMode);
  }

  // ========== 音量 ==========

  /// 设置音量
  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  // ========== 私有方法 ==========

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
  }

  void _onDurationChanged(Duration? duration) {
    state = state.copyWith(duration: duration);
  }

  void _onBufferedPositionChanged(Duration bufferedPosition) {
    state = state.copyWith(bufferedPosition: bufferedPosition);
  }

  void _onCurrentIndexChanged(int? index) {
    final track = _queueManager.currentTrack;
    logDebug('CurrentIndex changed: $index, track: ${track?.title ?? "null"}');
    state = state.copyWith(
      currentIndex: index,
      currentTrack: track,
      canPlayPrevious: _queueManager.hasPrevious,
      canPlayNext: _queueManager.hasNext,
    );
  }

  void _onSpeedChanged(double speed) {
    state = state.copyWith(speed: speed);
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
      playMode: _queueManager.playMode,
      canPlayPrevious: _queueManager.hasPrevious,
      canPlayNext: _queueManager.hasNext,
      isLoading: false,
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
  final audioService = ref.watch(audioServiceProvider);
  final db = ref.watch(databaseProvider).requireValue;
  final sourceManager = ref.watch(sourceManagerProvider);

  final queueRepository = QueueRepository(db);
  final trackRepository = TrackRepository(db);

  return QueueManager(
    player: audioService.player,
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    sourceManager: sourceManager,
  );
});

/// AudioController Provider
final audioControllerProvider =
    StateNotifierProvider<AudioController, PlayerState>((ref) {
  final audioService = ref.watch(audioServiceProvider);
  final queueManager = ref.watch(queueManagerProvider);

  final controller = AudioController(
    audioService: audioService,
    queueManager: queueManager,
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

/// 播放模式
final playModeProvider = Provider<PlayMode>((ref) {
  return ref.watch(audioControllerProvider).playMode;
});
