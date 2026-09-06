import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/legacy.dart';
// AudioDevice replaced by FmpAudioDevice from audio_types.dart
import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_exception.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/play_history_repository.dart';
import '../lyrics/lyrics_auto_match_service.dart';
import '../../core/services/toast_service.dart';
import 'audio_types.dart';
import 'buffer_starvation_watchdog.dart';
import 'effective_playback_state.dart';
import 'audio_service.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'audio_stream_manager.dart';
import 'playback_recovery_coordinator.dart';
import 'playback_request_session.dart';
import 'playback_capabilities.dart';
import 'playback_error_presenter.dart';
import 'playback_handoff_gate.dart';
import 'now_playing_publisher.dart';
import 'queue_commands.dart';
import 'queue_manager.dart';
import 'queue_persistence_manager.dart';
import 'queue_state.dart';
import 'player_state.dart';
import 'audio_playback_types.dart';
import 'mix_session_coordinator.dart';
import 'lyrics_auto_match_coordinator.dart';
import 'play_history_recorder.dart';
import 'mix_playlist_types.dart';
import 'temporary_play_handler.dart';

export 'player_state.dart';

/// 內部異常：表示重試已被安排，呼叫者不應再次安排重試
class _RetryScheduledException implements Exception {
  const _RetryScheduledException();
}

/// 音訊控制器 - 管理所有播放相關的狀態和操作
/// 協調 AudioService（單曲播放）和 QueueManager（佇列管理）
class AudioController extends StateNotifier<PlayerState>
    with Logging
    implements PlaybackRetryExecutor {
  /// 失敗分類與文案。無狀態，所以 const 一份就夠。
  static const _errorPresenter = PlaybackErrorPresenter();

  final FmpAudioService _audioService;
  final QueueManager _queueManager;
  late final QueueCommands _queueCommands;
  final AudioStreamManager _audioStreamManager;
  final ToastService _toastService;
  final NowPlayingPublisher _publisher;
  late final PlayHistoryRecorder _playHistory;
  late final LyricsAutoMatchCoordinator _lyricsAutoMatch;
  final SettingsRepository? _settingsRepository;
  final QueuePersistenceManager? _queuePersistenceManager;

  final List<StreamSubscription> _subscriptions = [];
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isDisposed = false;

  // 防止重複處理完成事件
  bool _isHandlingCompletion = false;
  String? _terminalMediaOpenErrorTrackKey;

  // 導航請求ID - 防止快速點擊 next/previous 時的競態條件
  int _navRequestId = 0;

  // 統一的播放上下文（管理所有播放狀態，包括臨時播放、加載狀態等）
  /// 目前的播放模式。臨時播放、Mix、脫離佇列的分支都讀它。
  PlayMode _mode = PlayMode.queue;

  /// 控制器正在投影哪一次播放請求的交接，0 代表不在交接中。
  ///
  /// 這是 `PlaybackRequestSession` 那個單調遞增請求 id 的**閂存副本**
  /// （`_enterLoading()` → `onLoadingStarted` 原樣傳過來），交接結束就歸零。
  /// 它不是第二個計數器。
  late final PlaybackHandoffGate _handoff;

  bool get _isTemporaryMode => _mode == PlayMode.temporary;
  bool get _isMixMode => _mode == PlayMode.mix;
  bool get _isLoadingPlayback => _handoff.isLoading;

  // 基於位置檢測的備選切歌定時器（解決後台播放 completed 事件丟失問題）
  Timer? _positionCheckTimer;

  late final PlaybackRequestSession _playbackRequestSession;
  late final PlaybackRecoveryCoordinator _recoveryCoordinator;
  late final TemporaryPlayHandler _temporaryPlayHandler;
  late final MixSessionCoordinator _mixSession;
  int _mixStartRequestId = 0;

  // 通知欄/SMTC 更新節流：上次更新的位置
  Duration _lastNotificationPosition = Duration.zero;

  // 當前正在播放的歌曲（獨立於佇列，確保 UI 顯示與實際播放一致）
  Track? _playingTrack;

  /// 播放開始前的回呼（用於互斥機制，如停止電台播放）
  Future<void> Function()? onPlaybackStarting;

  /// 檢查電台是否正在播放（由 RadioController 設定，用於避免電台斷流時誤觸發佇列播放）
  bool Function()? isRadioPlaying;

  /// 歌詞自動比對狀態回呼（UI 用來顯示載入動畫）。
  ///
  /// 轉發給 `LyricsAutoMatchCoordinator` —— 接線點留在 controller 上，provider
  /// 那頭不需要知道這件事已經搬家了。
  set onLyricsAutoMatchStateChanged(void Function(bool isMatching)? callback) {
    _lyricsAutoMatch.onStateChanged = callback;
  }

  void Function(QueueState queueState)? onQueueStateChanged;

  /// 佇列面向 UI 的投影，唯一一份。
  ///
  /// `PlayerState` 只描述「正在播的那一首」；佇列的形狀（內容、索引、隨機／
  /// 迴圈、Mix 身分）一律住在這裡。兩邊曾經各存一份同樣的 12 個欄位，靠
  /// `_updateQueueState` 每次逐欄位抄過去維持一致 —— 抄漏一個就是一個看不見的
  /// bug，而消費端會因為問了不同的 provider 拿到不同的答案。
  QueueState _queueState = const QueueState();

  /// 目前的佇列投影。與 `state` 平行的第二個唯讀出口，生產環境的訂閱者走
  /// `onQueueStateChanged` → `queueStateProvider`，這個 getter 是給不架
  /// container 的呼叫端直接讀的。
  QueueState get queueState => _queueState;

  /// 改一次佇列投影並推給訂閱者。所有佇列欄位的寫入都要走這裡。
  void _emitQueueState(QueueState next) {
    _queueState = next;
    onQueueStateChanged?.call(next);
  }

  // ========== 網路重試相關 ==========
  /// 網路恢復監聽訂閱
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
        _settingsRepository = settingsRepository,
        _queuePersistenceManager = queuePersistenceManager,
        super(const PlayerState()) {
    _playHistory = PlayHistoryRecorder(repository: playHistoryRepository);
    _lyricsAutoMatch = LyricsAutoMatchCoordinator(
      service: lyricsAutoMatchService,
      settingsRepository: settingsRepository,
    );
    _queueCommands = QueueCommands(
      queueManager: _queueManager,
      toastService: _toastService,
    );
    _handoff = PlaybackHandoffGate(
      currentTrackKey: () => _playingTrack?.uniqueKey,
      performSeek: _performSeek,
      isRequestSuperseded: (requestId) =>
          _playbackRequestSession.isSuperseded(requestId),
    );
    _playbackRequestSession = PlaybackRequestSession(
      budget: _budget,
      audioService: _audioService,
      audioStreamManager: _audioStreamManager,
      getNextTrack: _nextTrackForPrefetch,
      onLoadingStarted: _startSessionLoadingState,
      onLoadingFinished: (requestId, result) {
        if (!result.isSuperseded) return;
        _handoff.discardPending(
          requestId: requestId,
          reason: 'playback request was superseded',
        );
        // 閂存還停在這一次請求上時才收投影：被取代的請求如果早就不是控制器
        // 手上那一次，收 loading 會把新請求的轉圈關掉。
        if (_handoff.isCurrent(requestId)) {
          state = state.copyWith(isLoading: false);
          _handoff.endRequest();
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
      isRetryableError: _errorPresenter.isRetryable,
    );
    _bufferWatchdog = BufferStarvationWatchdog(
      onStarved: _onBufferStarvation,
      budget: _budget,
    );
    _temporaryPlayHandler = TemporaryPlayHandler();
    _mixSession = MixSessionCoordinator(
      queueManager: _queueManager,
      toastService: _toastService,
      fetcher: mixTracksFetcher,
      onLoadingChanged: _onMixLoadingChanged,
      onQueueChanged: _updateQueueState,
    );
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

      // 儲存需要恢復的位置（在設定監聽器之前，避免被位置流覆蓋）
      final positionToRestore = _queueManager.savedPosition;
      logDebug('Position to restore: $positionToRestore');

      // 註冊 audio service 串流訂閱（統一加入 _subscriptions 以便 dispose 取消）。
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

      // 啟動基於位置檢測的備選切歌機制（解決後台播放 completed 事件丟失問題）
      _startPositionCheckTimer();

      // 監聽佇列狀態變化
      subscribe(_queueManager.stateStream, _onQueueStateChanged);

      // 接管系統媒體控制（通知欄 / SMTC），平台分流由 publisher 負責
      _claimMediaControls();

      // 更新初始狀態
      _updateQueueState();

      // 恢復 Mix 播放模式（如果之前有持久化的 Mix metadata）
      final restoredMix = _mixSession.restoreFrom(
        _queuePersistenceManager == null
            ? null
            : await _queuePersistenceManager.restoreState(),
      );
      if (restoredMix != null) {
        // Mix 模式不支持隨機播放，確保關閉
        if (_queueManager.isShuffleEnabled) {
          await _queueManager.setShuffle(false);
          if (_isDisposed) return;
          _emitQueueState(_queueState.copyWith(isShuffleEnabled: false));
        }

        _mode = PlayMode.mix;
        _emitQueueState(_queueState.copyWith(
          isMixMode: true,
          mixTitle: restoredMix.title,
        ));
        _mixSession.onTrackStarted(PlayMode.mix);
      }

      // 恢復音量
      final savedVolume = _queueManager.savedVolume;
      await _audioService.setVolume(savedVolume);
      if (_isDisposed) return;
      state = state.copyWith(volume: savedVolume);
      logDebug('Restored volume: $savedVolume');

      // 恢復播放（如果有儲存的歌曲）
      if (_queueManager.currentTrack != null) {
        logDebug('Restoring saved track: ${_queueManager.currentTrack!.title}');
        // 不自動播放，只設定 URL，傳入儲存的位置
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

  /// 確保已初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      logWarning('AudioController not initialized, initializing now...');
      await initialize();
    }
  }

  /// 釋放資源
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _handoff.dispose();
    _lyricsAutoMatch.dispose();
    _stopPositionCheckTimer();
    _cancelRetryTimer();
    _bufferWatchdog.dispose();
    _recoveryCoordinator.dispose();
    _playbackRequestSession.dispose();
    _networkRecoverySubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _mixSession.exit();
    _queueManager.dispose();
    // 交還系統媒體控制。刻意**不** dispose 原生控制代碼：需要跟著 controller
    // 一起消失的是回呼繫結，不是 SMTC 本身 —— 原生 session 只在 main.dart
    // 建立一次，dispose 掉之後沒有任何程式碼會重建它。按鈕訂閱留著，解綁後
    // 它派發到 null，正是 app 啟動時的狀態。
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
      // 如果當前歌曲的 URL 已過期（如暫停過夜），重新獲取 URL 並從當前位置恢復
      if (await _resumeWithFreshUrlIfNeeded()) return;
      await _audioService.play();
    } catch (e, stack) {
      logError('Failed to play', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 暫停
  Future<void> pause() async {
    try {
      await _audioService.pause();
    } catch (e, stack) {
      logError('Failed to pause', e, stack);
    }
  }

  /// 切換播放/暫停
  /// 如果當前歌曲有錯誤狀態，嘗試重新播放當前歌曲
  Future<void> togglePlayPause() async {
    try {
      // 如果當前有網路錯誤狀態，觸發手動重試
      if (state.isNetworkError && state.currentTrack != null) {
        logDebug(
            'Manual retry for network error: ${state.currentTrack!.title}');
        await retryManually();
        return;
      }
      // 如果當前有錯誤狀態，嘗試重新播放當前歌曲
      if (state.error != null && state.currentTrack != null) {
        logDebug(
            'Retrying playback for track with error: ${state.currentTrack!.title}');
        await _playTrack(state.currentTrack!);
        return;
      }
      // 如果當前是暫停狀態且 URL 已過期（如暫停過夜），重新獲取 URL 並從當前位置恢復
      if (!state.isPlaying && await _resumeWithFreshUrlIfNeeded()) return;
      await _audioService.togglePlayPause();
    } catch (e, stack) {
      logError('Failed to togglePlayPause', e, stack);
      state = state.copyWith(error: e.toString());
    }
  }

  /// 停止
  Future<void> stop() async {
    _handoff.cancelDeferredSeeks(reason: 'playback stopped');
    await _audioService.stop();
    _clearPlayingTrack();
  }

  // ========== 進度控制 ==========

  /// 跳轉到指定位置
  Future<void> seekTo(Duration position) async {
    try {
      final deferredSeek = _handoff.deferSeek(position);
      if (deferredSeek != null) {
        await deferredSeek;
        return;
      }
      await _performSeek(position);
    } catch (e, stack) {
      logError('Failed to seekTo $position', e, stack);
    }
  }

  /// 跳轉到百分比位置
  Future<void> seekToProgress(double progress) async {
    final duration = state.duration;
    if (duration != null) {
      final position = Duration(
        milliseconds: (duration.inMilliseconds * progress).round(),
      );
      await seekTo(position);
    }
  }

  /// 開一次新的播放請求之前，把上一次交接整個收乾淨。
  ///
  /// 順序有意義：先讓 session 作廢舊的請求 id，再清掉綁在那個 id 上的延後 seek。
  void _cancelActivePlaybackRequest({required String reason}) {
    _playbackRequestSession.cancelActive();
    _handoff.cancel(reason: reason);
  }

  Future<void> _performSeek(Duration position) async {
    // seek 之後重新緩衝是理所當然的，該給它完整的一份預算重新起算。
    _bufferWatchdog.cancel();
    await _audioService.seekTo(position);
    // 立即儲存位置，避免 seek 後馬上關閉應用導致進度丟失
    await _queueManager.savePositionNow();
  }

  // ========== 佇列控制 ==========

  /// 播放單首歌曲
  Future<void> playSingle(Track track) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置網路重試狀態
    _cancelActivePlaybackRequest(reason: 'single-track playback started');
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

  /// 播放單首歌曲 (別名方法)
  Future<void> playTrack(Track track) => playSingle(track);

  /// 臨時播放單首歌曲（播放完成後恢復原佇列位置）
  /// 用於搜尋頁面和歌單頁面點擊歌曲時的行為
  Future<void> playTemporary(Track track) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置網路重試狀態
    _cancelActivePlaybackRequest(reason: 'temporary playback started');

    logInfo('Playing temporary track: ${track.title}');

    _temporaryPlayHandler.enterTemporary(
      currentMode: _mode,
      hasQueueTrack: _queueManager.currentTrack != null,
      currentIndex: _queueManager.currentIndex,
      currentPosition: _audioService.position,
      currentWasPlaying: _audioService.isPlaying,
    );
    _mode = PlayMode.temporary;

    try {
      await _executePlayRequest(
        track: track,
        mode: PlayMode.temporary,
        persist: false,
        countsAsNewPlay: true,
        prefetchNext: false,
      );
    } on SourceApiException catch (e) {
      // 音源 API 錯誤：嘗試恢復原佇列
      logWarning(
          '${e.sourceType} API error for temporary track ${track.title}: ${e.message}');
      if (_errorPresenter.shouldSkipTrack(e)) {
        _toastService.showWarning(_errorPresenter.cannotPlay(track, e));
      } else {
        _toastService
            .showError(_errorPresenter.playbackFailed(e));
      }
      if (_temporaryPlayHandler.hasSavedState) {
        await _restoreSavedState();
      } else {
        _mode = PlayMode.queue;
        _temporaryPlayHandler.clear();
      }
    } catch (e, stack) {
      logError('Failed to play temporary track: ${track.title}', e, stack);
      _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
      if (_temporaryPlayHandler.hasSavedState) {
        await _restoreSavedState();
      } else {
        _mode = PlayMode.queue;
        _temporaryPlayHandler.clear();
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
          _mode = targetMode;
          _temporaryPlayHandler.clear();
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
        _temporaryPlayHandler.clear();
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
        _temporaryPlayHandler.clear();
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
        _temporaryPlayHandler.clear();
      }
      // 還原逾時要說出來。finally 會把轉圈停掉，但停掉而不說任何話，使用者只會
      // 看到播放鍵自己不轉了、歌也沒播 —— 與起播路徑同一句文案。
      if (e is PlaybackTimeoutException) {
        final track = _queueManager.currentTrack;
        if (track != null) {
          _toastService.showError(t.audio.cannotPlayReason(
            title: track.title,
            reason: t.audio.sourceErrorTimeout,
          ));
        }
      }
    } finally {
      if (requestId != null) {
        _resetLoadingState(requestId: requestId);
      }
    }
  }

  /// 恢復儲存的播放狀態
  /// 注意：直接使用當前佇列，不恢復佇列內容（使用者可能在臨時播放期間修改了佇列）
  Future<void> _restoreSavedState() async {
    if (!_temporaryPlayHandler.hasSavedState) {
      logDebug('No saved state to restore');
      _mode = PlayMode.queue;
      _temporaryPlayHandler.clear();
      return;
    }

    final positionSettings = await _queueManager.getPositionRestoreSettings();
    final restorePlan = _temporaryPlayHandler.buildRestorePlan(
      rememberPosition: positionSettings.enabled,
      rewindSeconds: positionSettings.tempPlayRewindSeconds,
    );

    if (restorePlan == null) {
      logDebug('No restore plan available');
      _mode = PlayMode.queue;
      _temporaryPlayHandler.clear();
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

    if (_isTemporaryMode && _temporaryPlayHandler.hasSavedState) {
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
    _cancelActivePlaybackRequest(reason: 'queue playback started');
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

  /// 播放歌單 (別名方法)
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

    if (!_mixSession.canFetch) {
      throw StateError(t.library.main.cannotLoadMix);
    }

    _cancelActivePlaybackRequest(reason: 'Mix playback started');
    final mixStartRequestId = ++_mixStartRequestId;
    final playRequestGeneration = _playbackRequestSession.activeRequestId;
    final result = await _mixSession.fetch(
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
    state = state.copyWith(isLoading: true, error: null);
    _emitQueueState(_queueState.copyWith(isLoadingMoreMix: false));
    logInfo('Playing Mix playlist: $title with ${tracks.length} tracks');

    try {
      // 清空當前隊列並設置 Mix 模式
      await _queueManager.clear();

      // Mix 模式不支持隨機播放，強制關閉
      if (_queueManager.isShuffleEnabled) {
        await _queueManager.setShuffle(false);
        _emitQueueState(_queueState.copyWith(isShuffleEnabled: false));
      }

      // 初始化 Mix 狀態
      final mixState = _mixSession.start(
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

      // 先設置，因為 _executePlayRequest 會重置 isLoading
      _emitQueueState(_queueState.copyWith(
        isMixMode: true,
        mixTitle: title,
      ));

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
    final mixState = _mixSession.current;
    if (mixState != null) {
      logDebug('Exiting Mix mode');
      _mixSession.exit();
      _mode = PlayMode.queue;
      _emitQueueState(_queueState.copyWith(
        isMixMode: false,
        clearMixTitle: true,
        isLoadingMoreMix: false,
      ));
      // 清除持久化的 Mix 狀態
      _queueManager.clearMixMode();
    }
  }

  /// 播放佇列中指定索引的歌曲
  Future<void> playAt(int index) async {
    await _ensureInitialized();
    _resetRetryState(); // 重置網路重試狀態
    logDebug('Playing at index: $index');
    try {
      _queueManager.setCurrentIndex(index);
      final currentTrack = _queueManager.currentTrack;
      if (currentTrack != null) {
        _handoff.requestStabilizationForNextRequest();
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
    _resetRetryState(); // 重置網路重試狀態

    // 獲取導航請求 ID，防止快速點擊導致競態條件
    final navId = ++_navRequestId;
    logDebug(
        'next() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 檢測是否脫離佇列播放
    if (_isPlayingOutOfQueue) {
      logDebug('Playing out of queue: returning to queue');
      await _returnToQueue();
      return;
    }

    final nextIdx = _queueManager.moveToNext();
    if (nextIdx != null) {
      // 檢查是否被更新的導航請求取代
      if (navId != _navRequestId) {
        logDebug('next() navId $navId superseded by $_navRequestId, aborting');
        return;
      }
      final track = _queueManager.currentTrack;
      if (track != null) {
        _handoff.requestStabilizationForNextRequest();
        await _playTrack(track);
      }
    }
  }

  /// 上一首
  Future<void> previous() async {
    await _ensureInitialized();
    _resetRetryState(); // 重置網路重試狀態

    // 獲取導航請求 ID，防止快速點擊導致競態條件
    final navId = ++_navRequestId;
    logDebug(
        'previous() called, navId: $navId, isPlayingOutOfQueue: $_isPlayingOutOfQueue');

    // 檢測是否脫離佇列播放
    if (_isPlayingOutOfQueue) {
      logDebug('Playing out of queue: returning to queue');
      await _returnToQueue();
      return;
    }

    // 如果播放超過3秒，重新開始當前歌曲
    if (_audioService.position.inSeconds >
        AppConstants.previousTrackThresholdSeconds) {
      await _audioService.seekTo(Duration.zero);
    } else {
      final prevIdx = _queueManager.moveToPrevious();
      if (prevIdx != null) {
        // 檢查是否被更新的導航請求取代
        if (navId != _navRequestId) {
          logDebug(
              'previous() navId $navId superseded by $_navRequestId, aborting');
          return;
        }
        final track = _queueManager.currentTrack;
        if (track != null) {
          _handoff.requestStabilizationForNextRequest();
          await _playTrack(track);
        }
      }
    }
  }

  /// 新增到佇列
  ///
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addToQueue(Track track) async {
    await _ensureInitialized();
    return _applyQueueMutation(
        await _queueCommands.add(track, isMixMode: _isMixMode));
  }

  /// 批次新增到佇列
  ///
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addAllToQueue(List<Track> tracks) async {
    await _ensureInitialized();
    return _applyQueueMutation(
        await _queueCommands.addAll(tracks, isMixMode: _isMixMode));
  }

  /// 添加到下一首
  ///
  /// 返回 true 表示添加成功，false 表示被阻止（例如 Mix 模式）
  Future<bool> addNext(Track track) async {
    await _ensureInitialized();
    return _applyQueueMutation(
        await _queueCommands.addNext(track, isMixMode: _isMixMode));
  }

  /// 從佇列移除
  Future<void> removeFromQueue(int index) async {
    await _ensureInitialized();
    _applyQueueMutation(await _queueCommands.removeAt(index));
  }

  /// 移動佇列中的歌曲
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    await _ensureInitialized();
    _applyQueueMutation(await _queueCommands.move(oldIndex, newIndex));
  }

  /// 隨機打亂佇列（破壞性）
  Future<void> shuffleQueue() async {
    await _ensureInitialized();
    _applyQueueMutation(
        await _queueCommands.shuffle(isMixMode: _isMixMode));
  }

  /// 清空佇列
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

    if (_isMixMode) {
      _exitMixMode();
    }
    if (_playingTrack != null && !_isTemporaryMode) {
      _mode = PlayMode.detached;
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

  /// 設定播放速度
  Future<void> setSpeed(double speed) async {
    await _audioService.setSpeed(speed);
  }

  /// 重置播放速度
  Future<void> resetSpeed() async {
    await _audioService.resetSpeed();
  }

  // ========== 播放模式 ==========

  /// 切換隨機播放
  Future<void> toggleShuffle() async {
    // Mix 模式下禁止隨機播放（UI 應該已禁用按鈕，這是額外保護）
    if (_isMixMode) return;

    logDebug('Toggling shuffle');
    await _queueManager.toggleShuffle();
    _emitQueueState(
        _queueState.copyWith(isShuffleEnabled: _queueManager.isShuffleEnabled));
    _publishPlayModes();
  }

  /// 設定迴圈模式
  Future<void> setLoopMode(LoopMode mode) async {
    logDebug('Setting loop mode: $mode');
    await _queueManager.setLoopMode(mode);
    _emitQueueState(_queueState.copyWith(loopMode: mode));
    _publishPlayModes();
  }

  /// 迴圈切換迴圈模式
  Future<void> cycleLoopMode() async {
    await _queueManager.cycleLoopMode();
    _emitQueueState(_queueState.copyWith(loopMode: _queueManager.loopMode));
    _publishPlayModes();
  }

  // ========== 音量 ==========

  // 靜音前的音量（用於恢復）
  double _volumeBeforeMute = 1.0;

  /// 設定音量
  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 儲存音量設定
    await _queueManager.saveVolume(volume);
  }

  /// 靜音切換
  Future<void> toggleMute() async {
    if (state.volume > 0) {
      // 儲存靜音前的音量
      _volumeBeforeMute = state.volume;
      await setVolume(0);
    } else {
      // 恢復靜音前的音量
      await setVolume(_volumeBeforeMute);
    }
  }

  /// 調整音量
  ///
  /// [delta] - 音量變化量，正數增加，負數減少
  Future<void> adjustVolume(double delta) async {
    final newVolume = (state.volume + delta).clamp(0.0, 1.0);
    await setVolume(newVolume);
  }

  // ========== 音訊輸出裝置 ========== //

  /// 設定音訊輸出裝置
  Future<void> setAudioDevice(FmpAudioDevice device) async {
    await _audioService.setAudioDevice(device);
    await _settingsRepository?.update((s) {
      s.preferredAudioDeviceId = device.name;
      s.preferredAudioDeviceName = device.description;
    });
  }

  /// 設定為自動選擇音訊裝置（跟隨系統預設）
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

  // ========== 基於位置檢測的備選切歌機制（解決後台播放 completed 事件丟失問題）========== //

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

  /// `MixSessionCoordinator` 回報預取的載入中狀態。
  void _onMixLoadingChanged(bool isLoading) {
    if (_isDisposed) return;
    _emitQueueState(_queueState.copyWith(isLoadingMoreMix: isLoading));
  }

  /// 接管系統媒體控制。
  ///
  /// 通知欄與 SMTC 的差異、以及哪些按鈕該出現，全部由 [NowPlayingPublisher]
  /// 依 [PlaybackCapabilities] 決定 —— 這裡只負責說「音樂這個模式支援什麼」。
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

  /// 更新正在播放的歌曲（UI 顯示用）
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

    // 更新系統媒體控制的媒體資訊（通知欄 / SMTC）
    _publisher.publishTrack(NowPlayingOwner.music, track);

    // 一次播放請求裡這個方法會被呼叫兩次（先更新 UI，拿到 URL 後再補記），
    // 靠旗標避免記兩筆。這不是「聽滿幾秒才算」的門檻。
    if (countsAsNewPlay) {
      _playHistory.record(track);
    }

    logDebug('Updated playing track: ${track.title}');
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

    // 系統媒體控制轉為停止狀態
    _publisher.publishStopped(NowPlayingOwner.music);

    logDebug('Cleared playing track');
  }

  // ========== 統一播放入口 ========== //

  /// 進入 session 加載狀態（統一的 UI 更新邏輯）
  void _startSessionLoadingState(int requestId) {
    _terminalMediaOpenErrorTrackKey = null;
    _handoff.prepareForRequest(reason: 'new playback request started');
    _bufferWatchdog.cancel();
    state = state.copyWith(
      isLoading: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      error: null,
      clearDuration: true,
      replaceCurrentStreamMetadata: true,
    );
    _handoff.beginRequest(requestId);
    _publishLoadingState();
  }

  void _publishLoadingState() {
    _publishPlaybackState(
      isPlaying: false,
      position: Duration.zero,
      processingState: FmpAudioProcessingState.loading,
    );
  }

  /// 速度與緩衝位置在這裡讀好再傳出去 —— [NowPlayingPublisher] 刻意不認識
  /// [FmpAudioService]，維持成純 sink。
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
  /// [mode] - 播放模式；為 null 代表保持現有模式不變
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
    _handoff.endRequest();
    // mode 為 null 時刻意保持原模式 —— 重試與啟動還原不該把臨時播放或
    // Mix 打回 queue。原本靠 copyWith 的 `??` 預設達成，拆開後要寫出來。
    if (mode != null) _mode = mode;

    if (trackWithUrl != null) {
      _updatePlayingTrack(trackWithUrl, countsAsNewPlay: countsAsNewPlay);
      if (stabilizeSeekAfterReady) {
        _handoff.startStabilizationWindow(requestId, trackWithUrl.uniqueKey);
      }
    }
    _handoff.applyPendingIfCurrent(requestId);
  }

  /// 重置加載狀態（在請求被取代或失敗時使用）
  void _resetLoadingState({int? requestId}) {
    if (_isDisposed) return;
    if (requestId != null && _isSessionSuperseded(requestId)) {
      return;
    }
    if (requestId != null) {
      _handoff.discardPending(
        requestId: requestId,
        reason: 'playback loading state reset',
      );
    } else {
      _handoff.discardPending(reason: 'playback loading state reset');
    }
    state = state.copyWith(isLoading: false);
    _handoff.endRequest();
    _publishCurrentPlaybackState();
  }

  void _resetSourceErrorLoadingState(int requestId) {
    if (_isDisposed || _isSessionSuperseded(requestId)) return;
    _handoff.discardPending(
      requestId: requestId,
      reason: 'source error reset playback loading state',
    );
    _handoff.endRequest();
    _publishCurrentPlaybackState();
  }

  void _clearMatchingSessionLoadingContext(int requestId) {
    if (_isDisposed || !_handoff.isCurrent(requestId)) return;
    _handoff.discardPending(
      requestId: requestId,
      reason: 'playback loading context cleared',
    );
    _handoff.endRequest();
    _publishCurrentPlaybackState();
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
        _handoff.consumeStabilizationForNextRequest();

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

      // 自動匹配歌詞（後台執行，不阻塞播放）
      if (countsAsNewPlay) {
        _lyricsAutoMatch.onTrackStarted(track);
      }

      // Mix 模式：接近尾端時提前加載更多歌曲
      _mixSession.onTrackStarted(mode);

      logDebug(
          '_executePlayRequest completed successfully for: ${track.title}');
    } on SourceApiException catch (e) {
      logWarning(
          '${e.sourceType} API error for ${track.title}: ${e.message}');
      // 網路錯誤和超時：走重試邏輯，而非通用錯誤處理
      if (_errorPresenter.shouldRetrySource(e)) {
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
      if (_errorPresenter.isRetryable(e)) {
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
    final cannotPlayMessage = _errorPresenter.cannotPlay(track, e);
    if (_errorPresenter.shouldSkipTrack(e)) {
      logInfo('Track unavailable (${e.sourceType}): ${track.title}');
      final nextIdx = _queueManager.getNextIndex();
      if (nextIdx != null && mode == PlayMode.queue) {
        _resetLoadingState(requestId: requestId);
        _toastService.showWarning(
          _errorPresenter.cannotPlay(track, e, skipped: true),
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
        );
        _emitQueueState(
            _queueState.copyWith(queueTrack: _queueManager.currentTrack));
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
      final message = _errorPresenter.playbackFailed(e);
      state = state.copyWith(
        error: message,
        isLoading: false,
      );
      _resetSourceErrorLoadingState(requestId);
      _toastService.showError(message);
    }
  }

  // ========== 網路重試邏輯 ========== //

  PlayMode get _currentRecoveryMode =>
      _isMixMode ? PlayMode.mix : PlayMode.queue;

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

  /// 安排重試（漸進式延遲）
  void _scheduleRetry(Track track, Duration? position, PlayMode mode) {
    final event = _recoveryCoordinator.scheduleRetry(
      track: track,
      position: position,
      mode: mode,
    );
    _applyRecoveryEvent(event);
  }

  /// 網路恢復時自動恢復播放
  Future<void> _onNetworkRecovered() async {
    logInfo(
        '_onNetworkRecovered called, recoveryTrack: ${_recoveryCoordinator.recoveryTrack?.title}');
    final event = await _recoveryCoordinator.onNetworkRecovered(
      mode: _currentRecoveryMode,
    );
    _applyRecoveryEvent(event, showNonRetryableToast: true);
  }

  /// 重置重試狀態
  void _resetRetryState() {
    _applyRecoveryEvent(_recoveryCoordinator.reset());
  }

  /// 取消待處理的重試
  void _cancelRetryTimer() {
    _recoveryCoordinator.reset();
  }

  /// 設定網路恢復監聽（需要在初始化時從外部傳入 Ref）
  void setupNetworkRecoveryListener(Stream<void> networkRecoveredStream) {
    logDebug('Setting up network recovery listener');
    _networkRecoverySubscription?.cancel();
    _networkRecoverySubscription = networkRecoveredStream.listen((_) {
      logDebug('Network recovery event received from stream');
      _onNetworkRecovered();
    });
    logDebug('Network recovery listener set up successfully');
  }

  /// 手動觸發重試（使用者點擊重試按鈕）
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

    return _mode == PlayMode.temporary ||
        _mode == PlayMode.detached ||
        (_playingTrack != null &&
            queueTrack != null &&
            _playingTrack!.id != queueTrack.id) ||
        (_playingTrack != null && queueTrack == null && queue.isNotEmpty);
  }

  /// 統一「返回隊列」邏輯
  /// 如果有保存的臨時播放狀態，恢復到該位置
  /// 否則播放隊列第一首
  Future<void> _returnToQueue() async {
    if (_isTemporaryMode && _temporaryPlayHandler.hasSavedState) {
      await _restoreSavedState();
    } else {
      await _playFirstInQueue();
    }
  }

  /// 播放隊列第一首歌曲
  Future<void> _playFirstInQueue() async {
    // 清除臨時播放狀態
    _mode = PlayMode.queue;
    _temporaryPlayHandler.clear();

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

  /// 檢查當前歌曲的 URL 是否已過期，如果過期則重新獲取 URL 並從當前位置恢復播放。
  /// 返回 true 表示已處理（呼叫方應 return），false 表示無需處理。
  ///
  /// 典型場景：使用者暫停後長時間不操作（如過夜），音訊 URL 已過期，
  /// 直接呼叫 player.play() 會導致 "Error decoding audio"。
  Future<bool> _resumeWithFreshUrlIfNeeded() async {
    final track = state.currentTrack;
    if (track == null) return false;

    // 只在 URL 確實過期時觸發（有 URL 但已過期）
    if (track.audioUrl == null || track.hasValidAudioUrl) return false;

    // 排除已下載的本地檔案（本地檔案不會過期）
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

    // 播放成功後恢復到之前的位置
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
    final currentMode = _isMixMode ? PlayMode.mix : PlayMode.queue;
    await _executePlayRequest(
      track: track,
      mode: currentMode,
      persist: true,
      countsAsNewPlay: true,
      prefetchNext: true,
    );
  }

  /// 準備當前歌曲（不自動播放）
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

      final mode = _isMixMode ? PlayMode.mix : PlayMode.queue;
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

    final effective = EffectivePlaybackState.from(
      backend: playerState,
      controllerIsLoading: _isLoadingPlayback,
      backendPosition: _audioService.position,
    );

    logDebug(
        'PlayerState changed: playing=${playerState.playing}, processingState=${playerState.processingState}');
    state = state.copyWith(
      isPlaying: effective.isPlaying,
      isBuffering: effective.isBuffering,
      isLoading: effective.isLoading,
      processingState: effective.processingState,
      error: state.error,
    );

    // 重新緩衝屬於 playing 的子狀態：這裡只餵資料，升不升級成失敗由 watchdog 判斷。
    _bufferWatchdog.onPlayerStateChanged(
      isBuffering: effective.isBuffering,
      isPlaying: effective.isPlaying,
      isSuppressed: _isLoadingPlayback ||
          state.isRetrying ||
          state.isNetworkError ||
          _isWithinOutputDeviceFailureGuard,
    );

    // 更新系統媒體控制的播放狀態（通知欄 / SMTC）
    //
    // 兩個表面統一送 effective 值。過去 SMTC 收的是後端原始值，所以
    // AGENTS.md 那條「控制器擁有的載入階段，後端 idle 事件不得覆蓋
    // loading 狀態」只在 Android 通知欄成立 —— 沒有理由只保護一個平台。
    _publishPlaybackState(
      isPlaying: effective.isPlaying,
      position: effective.position,
      processingState: effective.processingState,
    );
  }

  void _onPositionChanged(Duration position) {
    if (_isDisposed) return;
    // 電台播放中的位置變化與音樂播放器無關
    if (isRadioPlaying?.call() == true) return;
    // 載入期間忽略位置更新（防止舊歌曲的位置覆蓋已重置的進度條）
    if (_isLoadingPlayback) return;

    state = state.copyWith(position: position, error: state.error);
    // 更新 QueueManager 的位置（用於恢復播放）
    _queueManager.updatePosition(position);

    // 節流通知欄/SMTC 更新：每 500ms 最多更新一次，減少 IPC 開銷
    final shouldUpdateNotification =
        (position.inMilliseconds - _lastNotificationPosition.inMilliseconds)
                .abs() >=
            500;
    if (!shouldUpdateNotification) return;
    _lastNotificationPosition = position;

    // 更新系統媒體控制的進度（通知欄 / SMTC）
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
    if (_isLoadingPlayback || state.isRetrying || state.isNetworkError) {
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

    // 獲取當前播放的歌曲
    final track = state.playingTrack;
    if (track == null) {
      logDebug('No playing track, ignoring error');
      return;
    }

    logWarning('Network error detected during playback: ${track.title}');

    // URL 沒過期不等於 URL 還能用。失敗過的那一個必須從可重用的解析結果裡拿掉，
    // 否則重試會一次又一次拿到同一個死 URL。
    _audioStreamManager.invalidateResolvedStream(track);

    final activeRetryRequestId = state.isRetrying && _isLoadingPlayback
        ? _handoff.activeRequestId
        : null;
    if (activeRetryRequestId != null) {
      _playbackRequestSession.cancelActive();
      _handoff.discardPending(reason: 'active retry handoff cancelled');
    }
    final retryRequestGeneration = _playbackRequestSession.activeRequestId;

    // 保存當前位置，stop() 可能會透過 positionStream 將 position 重置為 zero
    final positionBeforeStop = state.position;

    // 停止播放並觸發重試
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
      // stop() 失敗時仍需觸發重試，否則播放器會卡在錯誤狀態
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
    final track = _playingTrack;
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
    if (!_isMixMode) return false;

    final pendingLoad = _mixSession.pendingLoad;
    if (pendingLoad == null) return false;

    logDebug('Mix queue end reached while load-more is pending; waiting...');
    await pendingLoad;
    if (_isDisposed || !_isMixMode) return false;

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
    if (_isLoadingPlayback || state.isRetrying || state.isNetworkError) {
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
    // 防止重複處理
    if (_isHandlingCompletion) return;

    if (!_canHandlePlaybackEnd()) return;

    _isHandlingCompletion = true;

    // 使用 Future.microtask 來避免在流監聽器中直接操作
    Future.microtask(() async {
      try {
        logDebug(
            'Track completed, loopMode: ${_queueManager.loopMode}, shuffle: ${_queueManager.isShuffleEnabled}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');
        // 單曲迴圈優先：即使在臨時播放模式下也繼續迴圈播放
        if (_queueManager.loopMode == LoopMode.one) {
          // 單曲迴圈：重新播放當前歌曲
          logDebug('LoopOne mode: replaying current track');
          final track = _playingTrack;
          if (track != null) {
            await _playTrack(track);
          }
          return;
        }

        // 檢測是否脫離佇列播放
        if (_isPlayingOutOfQueue) {
          logDebug('Track completed while playing out of queue');
          await _returnToQueue();
          return;
        }

        // 正常佇列播放：移動到下一首
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

    // 佇列中當前位置的歌曲（注意：這與 playingTrack 可能不同）
    final queueTrack = _queueManager.currentTrack;

    // 計算 upcomingTracks 和導航按鈕狀態
    List<Track> upcomingTracks;
    bool canPlayPrevious;
    bool canPlayNext;

    // 檢測是否脫離佇列播放
    if (_isPlayingOutOfQueue) {
      // 當前播放的歌曲脫離佇列：點擊"下一首"會去到佇列中儲存的索引位置
      if (_isTemporaryMode && _temporaryPlayHandler.hasSavedState && queue.isNotEmpty) {
        // 臨時播放模式：顯示當前佇列中從儲存位置開始的歌曲
        final targetIndex =
            _temporaryPlayHandler.savedQueueIndex!.clamp(0, queue.length - 1);
        if (_queueManager.isShuffleEnabled) {
          // Shuffle 模式：從當前 shuffle 索引獲取後續歌曲
          upcomingTracks =
              _queueManager.getUpcomingTracksFromIndex(targetIndex, count: 5);
        } else {
          // 順序模式：顯示當前佇列中從儲存位置開始的歌曲（最多5首）
          final endIndex = (targetIndex + 5).clamp(0, queue.length);
          upcomingTracks = queue.sublist(targetIndex, endIndex);
        }
      } else {
        // 沒有儲存的狀態，或非臨時播放但脫離佇列：顯示當前佇列從索引 0 開始的歌曲
        final endIdx = 5.clamp(0, queue.length);
        upcomingTracks = queue.sublist(0, endIdx);
      }

      // 脫離佇列模式下，上一首/下一首都會去到佇列，所以只要佇列不為空就可用
      canPlayPrevious = queue.isNotEmpty;
      canPlayNext = queue.isNotEmpty;
    } else {
      upcomingTracks = _queueManager.getUpcomingTracks(count: 5);
      canPlayPrevious = _queueManager.hasPrevious;
      canPlayNext = _queueManager.hasNext;
    }

    logDebug(
        'Updating queue state: ${queue.length} tracks, index: $currentIndex, queueTrack: ${queueTrack?.title ?? "null"}, playingTrack: ${_playingTrack?.title ?? "null"}, isPlayingOutOfQueue: $_isPlayingOutOfQueue');
    _emitQueueState(_queueState.copyWith(
      queue: queue,
      upcomingTracks: upcomingTracks,
      currentIndex: currentIndex,
      queueTrack: queueTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: canPlayPrevious,
      canPlayNext: canPlayNext,
      queueVersion: _queueState.queueVersion + 1,
    ));
  }
}
