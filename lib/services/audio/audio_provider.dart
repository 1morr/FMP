import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_provider.dart';
import '../../providers/database_provider.dart';
import '../../core/services/toast_service.dart';
import '../../main.dart' show audioHandler, windowsSmtcHandler;
import 'audio_handler.dart';
import 'windows_smtc_handler.dart';
import 'audio_service.dart' as audio;
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
  /// 实际正在播放的歌曲（可能是临时播放的歌曲，也可能是队列中的歌曲）
  /// UI 应使用此字段显示当前播放的歌曲
  final Track? playingTrack;
  /// 队列中当前位置的歌曲（可能与 playingTrack 不同，例如临时播放时）
  final Track? queueTrack;
  final List<Track> queue;
  final List<Track> upcomingTracks;
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
    this.playingTrack,
    this.queueTrack,
    this.queue = const [],
    this.upcomingTracks = const [],
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.error,
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
    just_audio.ProcessingState? processingState,
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
      playingTrack: playingTrack ?? this.playingTrack,
      queueTrack: queueTrack ?? this.queueTrack,
      queue: queue ?? this.queue,
      upcomingTracks: upcomingTracks ?? this.upcomingTracks,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      error: error,
    );
  }
}

/// 临时播放保存的状态
class _TemporaryPlayState {
  final List<Track> queue;
  final int index;
  final Duration position;
  final bool isPlaying;
  final List<int> shuffleOrder;
  final int shuffleIndex;

  const _TemporaryPlayState({
    required this.queue,
    required this.index,
    required this.position,
    required this.isPlaying,
    required this.shuffleOrder,
    required this.shuffleIndex,
  });
}

/// 音频控制器 - 管理所有播放相关的状态和操作
/// 协调 AudioService（单曲播放）和 QueueManager（队列管理）
class AudioController extends StateNotifier<PlayerState> with Logging {
  final audio.AudioService _audioService;
  final QueueManager _queueManager;
  final ToastService _toastService;
  final FmpAudioHandler _audioHandler;
  final WindowsSmtcHandler _windowsSmtcHandler;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;

  // 防止重复处理完成事件
  bool _isHandlingCompletion = false;

  // 播放锁 - 防止快速切歌时的竞态条件
  Completer<void>? _playLock;
  int _playRequestId = 0;

  // 导航请求ID - 防止快速点击 next/previous 时的竞态条件
  int _navRequestId = 0;

  // 临时播放状态（封装为一个类会更好，但这里保持简单）
  bool _isTemporaryPlay = false;
  _TemporaryPlayState? _temporaryState;

  // 基于位置检测的备选切歌定时器（解决后台播放 completed 事件丢失问题）
  Timer? _positionCheckTimer;
  static const Duration _positionCheckInterval = Duration(seconds: 1);
  static const Duration _positionThreshold = Duration(milliseconds: 500);

  // 当前正在播放的歌曲（独立于队列，确保 UI 显示与实际播放一致）
  Track? _playingTrack;

  AudioController({
    required audio.AudioService audioService,
    required QueueManager queueManager,
    required ToastService toastService,
    required FmpAudioHandler audioHandler,
    required WindowsSmtcHandler windowsSmtcHandler,
  })  : _audioService = audioService,
        _queueManager = queueManager,
        _toastService = toastService,
        _audioHandler = audioHandler,
        _windowsSmtcHandler = windowsSmtcHandler,
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
    _clearPlayingTrack();
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    await _audioService.seekTo(position);
    // 立即保存位置，避免 seek 后马上关闭应用导致进度丢失
    await _queueManager.savePositionNow();
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
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    await _audioService.seekForward(seekDuration);
    // 立即保存位置
    await _queueManager.savePositionNow();
  }

  /// 快退
  Future<void> seekBackward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    await _audioService.seekBackward(seekDuration);
    // 立即保存位置
    await _queueManager.savePositionNow();
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

  /// 临时播放单首歌曲（播放完成后恢复原队列位置）
  /// 用于搜索页面和歌单页面点击歌曲时的行为
  Future<void> playTemporary(Track track) async {
    await _ensureInitialized();
    state = state.copyWith(isLoading: true, error: null);
    logInfo('Playing temporary track: ${track.title}');

    try {
      // 只在第一次进入临时播放时保存状态（避免连续临时播放时覆盖原始状态）
      if (!_isTemporaryPlay && _queueManager.currentTrack != null) {
        _temporaryState = _TemporaryPlayState(
          queue: List.from(_queueManager.tracks),
          index: _queueManager.currentIndex,
          position: _audioService.position,
          isPlaying: _audioService.isPlaying,
          shuffleOrder: List.from(_queueManager.shuffleOrder),
          shuffleIndex: _queueManager.shuffleIndex,
        );
        logDebug('Saved queue state: ${_temporaryState!.queue.length} tracks, index: ${_temporaryState!.index}, shuffleOrder: ${_temporaryState!.shuffleOrder.length}');
      }

      _isTemporaryPlay = true;

      // 获取音频 URL 并播放（不修改队列，不保存到数据库）
      final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(track, persist: false);
      final url = localPath ?? trackWithUrl.audioUrl;

      if (url == null) {
        throw Exception('No audio URL available for: ${track.title}');
      }

      // 先更新正在播放的歌曲（在播放操作之前更新，避免 Android 上 UI 刷新延迟问题）
      // 播放操作会触发 playerStateStream 事件，导致 UI 重建，此时 playingTrack 必须已经更新
      _updatePlayingTrack(trackWithUrl);

      // 播放（传递 Track 信息用于后台播放通知）
      if (localPath != null) {
        await _audioService.playFile(url, track: trackWithUrl);
      } else {
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
      }
      state = state.copyWith(isLoading: false);

      // 更新队列状态以显示正确的 upcomingTracks（原队列中的当前歌曲）
      _updateQueueState();

      logDebug('Temporary playback started for: ${track.title}');
    } on just_audio.PlayerInterruptedException catch (e) {
      // 播放被中断（通常是因为新的播放请求），不作为错误处理
      logDebug('Temporary playback interrupted for ${track.title}: ${e.message}');
      state = state.copyWith(isLoading: false);
    } on BilibiliApiException catch (e) {
      // Bilibili API 错误（如视频不可用、版权限制等）
      logWarning('Bilibili API error for temporary track ${track.title}: ${e.message}');

      // 临时播放失败，尝试恢复原队列
      state = state.copyWith(isLoading: false);

      if (e.isUnavailable || e.isGeoRestricted) {
        _toastService.showWarning('无法播放「${track.title}」');
      } else {
        _toastService.showError('播放失败: ${e.message}');
      }

      // 如果有保存的状态，尝试恢复
      if (_temporaryState != null) {
        await _restoreSavedState();
      } else {
        _isTemporaryPlay = false;
      }
    } catch (e, stack) {
      logError('Failed to play temporary track: ${track.title}', e, stack);
      state = state.copyWith(error: e.toString(), isLoading: false);
      _toastService.showError('播放失败: ${track.title}');

      // 如果有保存的状态，尝试恢复
      if (_temporaryState != null) {
        await _restoreSavedState();
      } else {
        _isTemporaryPlay = false;
        _temporaryState = null;
      }
    }
  }

  /// 清除保存的队列状态
  void _clearSavedState() {
    _temporaryState = null;
  }

  /// 恢复保存的队列状态
  Future<void> _restoreSavedState() async {
    final saved = _temporaryState;
    if (saved == null) {
      logDebug('No saved state to restore');
      _isTemporaryPlay = false;
      return;
    }

    logDebug('Restoring queue state: ${saved.queue.length} tracks, index: ${saved.index}, shuffleOrder: ${saved.shuffleOrder.length}');

    try {
      // 恢复 shuffle 状态（必须在 restoreQueue 之前设置）
      if (saved.shuffleOrder.isNotEmpty) {
        _queueManager.setShuffleState(saved.shuffleOrder, saved.shuffleIndex);
      }

      // 恢复队列（不会重新生成 shuffle order）
      await _queueManager.restoreQueue(saved.queue, startIndex: saved.index);

      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        // 【重要】立即更新 UI，避免 Android 上明显的延迟
        _updatePlayingTrack(currentTrack);
        _updateQueueState();

        // 准备歌曲
        final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(currentTrack);
        final url = localPath ?? trackWithUrl.audioUrl;

        if (url != null) {
          if (localPath != null) {
            await _audioService.setFile(url);
          } else {
            final headers = _getHeadersForTrack(trackWithUrl);
            await _audioService.setUrl(url, headers: headers);
          }

          // 更新正在播放的歌曲（可能有 URL 更新）
          _updatePlayingTrack(trackWithUrl);

          // 恢复播放位置（回退10秒，方便用户回忆上下文）
          if (saved.position > Duration.zero) {
            final restorePosition = saved.position - const Duration(seconds: AppConstants.temporaryPlayRestoreOffsetSeconds);
            await _audioService.seekTo(restorePosition.isNegative ? Duration.zero : restorePosition);
          }

          // 如果之前正在播放，恢复播放
          if (saved.isPlaying) {
            await _audioService.play();
            logDebug('Resumed playback after restore');
          }
        }
      }

      // 先清除临时播放状态，再更新 UI
      _isTemporaryPlay = false;
      _clearSavedState();

      _updateQueueState();
      logInfo('Queue state restored successfully');
    } catch (e, stack) {
      logError('Failed to restore queue state', e, stack);
      _isTemporaryPlay = false;
      _clearSavedState();
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
    
    // 获取导航请求 ID，防止快速点击导致竞态条件
    final navId = ++_navRequestId;
    logDebug('next() called, navId: $navId, isTemporaryPlay: $_isTemporaryPlay');

    // 只在明确的临时播放模式下才认为是"脱离队列"
    // 注意：不能用 _playingTrack != queueTrack 来检测，因为快速切歌时这两个值可能暂时不一致
    if (_isTemporaryPlay) {
      logDebug('Temporary play mode: restoring saved state');
      
      if (_temporaryState != null) {
        // 有保存的状态：恢复到保存的位置
        await _restoreSavedState();
      } else {
        // 没有保存的状态，退出临时播放模式并播放队列第一首
        _isTemporaryPlay = false;
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
    
    // 获取导航请求 ID，防止快速点击导致竞态条件
    final navId = ++_navRequestId;
    logDebug('previous() called, navId: $navId, isTemporaryPlay: $_isTemporaryPlay');

    // 只在明确的临时播放模式下才认为是"脱离队列"
    if (_isTemporaryPlay) {
      logDebug('Temporary play mode: restoring saved state');
      
      if (_temporaryState != null) {
        // 有保存的状态：恢复到保存的位置
        await _restoreSavedState();
      } else {
        // 没有保存的状态，退出临时播放模式并播放队列第一首
        _isTemporaryPlay = false;
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

  /// 批量添加到队列
  Future<void> addAllToQueue(List<Track> tracks) async {
    await _ensureInitialized();
    logInfo('Adding ${tracks.length} tracks to queue');
    try {
      await _queueManager.addAll(tracks);
      _updateQueueState();
    } catch (e, stack) {
      logError('Failed to add tracks to queue', e, stack);
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
  void _updatePlayingTrack(Track track) {
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

    logDebug('Updated playing track: ${track.title}');
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

    // 【重要】立即更新 UI，让用户看到切换效果
    // 必须在任何 await 之前执行，否则 Android 上 stop() 可能导致明显延迟
    _updatePlayingTrack(track);
    _updateQueueState();

    state = state.copyWith(isLoading: true, error: null);
    
    // 停止当前播放，避免在获取新 URL 期间继续播放上一首
    await _audioService.stop();

    try {
      // 确保有音频 URL
      logDebug('Fetching audio URL for: ${track.title}');
      final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(track);

      // 再次检查是否被取代
      if (requestId != _playRequestId) {
        logDebug('Play request $requestId superseded after URL fetch, aborting');
        return;
      }

      // 获取播放地址
      final url = localPath ?? trackWithUrl.audioUrl;

      if (url == null) {
        throw Exception('No audio URL available for: ${track.title}');
      }

      final urlType = localPath != null ? "downloaded" : "stream";
      logDebug('Playing track: ${track.title}, URL type: $urlType, source: ${track.sourceType}');

      // 播放（传递 Track 信息用于后台播放通知）
      if (localPath != null) {
        await _audioService.playFile(url, track: trackWithUrl);
      } else {
        // 获取该音源所需的 HTTP 请求头
        final headers = _getHeadersForTrack(trackWithUrl);
        await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
      }

      // 再次检查是否被取代
      if (requestId != _playRequestId) {
        logDebug('Play request $requestId superseded after playUrl, stopping');
        await _audioService.stop();
        return;
      }

      // 预取下一首
      _queueManager.prefetchNext();

      // 更新正在播放的歌曲
      _updatePlayingTrack(trackWithUrl);

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
        logDebug('Seeking to saved position: $positionToSeek');
        await _audioService.seekTo(positionToSeek);
        logDebug('Seek completed');
      } else {
        logDebug('No saved position to restore (position is zero)');
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

  void _onTrackCompleted(void _) {
    // 防止重复处理
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;

    logDebug('Track completed, loopMode: ${_queueManager.loopMode}, shuffle: ${_queueManager.isShuffleEnabled}, temporaryPlay: $_isTemporaryPlay');

    // 使用 Future.microtask 来避免在流监听器中直接操作
    Future.microtask(() async {
      try {
        // 单曲循环优先：即使在临时播放模式下也继续循环播放
        if (_queueManager.loopMode == LoopMode.one) {
          // 单曲循环：重新播放当前歌曲
          // 注意：不能使用 seekTo + play，因为在 completed 状态下 seekTo 可能无法正确重置状态
          logDebug('LoopOne mode: replaying current track (temporaryPlay: $_isTemporaryPlay)');
          final track = _playingTrack;
          if (track != null) {
            await _playTrack(track);
          }
          return;
        }

        // 检查是否是临时播放模式（非单曲循环时才恢复队列）
        if (_isTemporaryPlay) {
          logDebug('Temporary play completed, restoring saved state');
          await _restoreSavedState();
          return;
        }
        
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
    final saved = _temporaryState;

    // 队列中当前位置的歌曲（注意：这与 playingTrack 可能不同）
    final queueTrack = _queueManager.currentTrack;

    // 计算 upcomingTracks 和导航按钮状态
    List<Track> upcomingTracks;
    bool canPlayPrevious;
    bool canPlayNext;

    // 检测当前播放的歌曲是否"脱离"了队列
    // 情况1：临时播放模式
    // 情况2：清空队列后继续播放的歌曲（_playingTrack 存在但与 queueTrack 不同）
    final bool isPlayingOutOfQueue = _isTemporaryPlay ||
        (_playingTrack != null && queueTrack != null && _playingTrack!.id != queueTrack.id) ||
        (_playingTrack != null && queueTrack == null && queue.isNotEmpty);

    if (isPlayingOutOfQueue) {
      // 当前播放的歌曲脱离队列：点击"下一首"会去到队列的第一首
      if (_isTemporaryPlay && saved != null && saved.index < saved.queue.length) {
        // 临时播放模式且有保存的状态：显示原队列中从保存位置开始的歌曲
        if (_queueManager.isShuffleEnabled && saved.shuffleOrder.isNotEmpty) {
          // Shuffle 模式：按 shuffle order 获取后续歌曲
          upcomingTracks = [];
          for (var i = saved.shuffleIndex; i < saved.shuffleOrder.length && upcomingTracks.length < 5; i++) {
            final trackIndex = saved.shuffleOrder[i];
            if (trackIndex >= 0 && trackIndex < saved.queue.length) {
              upcomingTracks.add(saved.queue[trackIndex]);
            }
          }
        } else {
          // 顺序模式：显示原队列中从保存位置开始的歌曲（最多5首）
          final endIndex = (saved.index + 5).clamp(0, saved.queue.length);
          upcomingTracks = saved.queue.sublist(saved.index, endIndex);
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

    logDebug('Updating queue state: ${queue.length} tracks, index: $currentIndex, queueTrack: ${queueTrack?.title ?? "null"}, playingTrack: ${_playingTrack?.title ?? "null"}, isTemporaryPlay: $_isTemporaryPlay');
    state = state.copyWith(
      queue: queue,
      upcomingTracks: upcomingTracks,
      currentIndex: currentIndex,
      queueTrack: queueTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: canPlayPrevious,
      canPlayNext: canPlayNext,
    );
  }
}

// ========== Providers ==========

/// AudioService Provider
final audioServiceProvider = Provider<audio.AudioService>((ref) {
  final service = audio.AudioService();
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

  final controller = AudioController(
    audioService: audioService,
    queueManager: queueManager,
    toastService: toastService,
    audioHandler: audioHandler,
    windowsSmtcHandler: windowsSmtcHandler,
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
