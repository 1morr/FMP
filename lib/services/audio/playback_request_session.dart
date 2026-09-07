import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import 'audio_playback_types.dart';
import 'audio_service.dart';
import 'audio_stream_manager.dart';
import 'audio_types.dart';
import 'playback_media.dart';

enum PlaybackSessionResultKind {
  completed,
  superseded,
  terminalMediaOpenError,
  failed,
}

class PlaybackSessionCommand {
  const PlaybackSessionCommand({
    required this.track,
    required this.mode,
    required this.positionBeforeLoad,
    this.persist = true,
    this.prefetchNext = true,
    this.onPlaybackStarting,
  });

  final Track track;
  final PlayMode mode;
  final Duration positionBeforeLoad;
  final bool persist;
  final bool prefetchNext;
  final Future<void> Function()? onPlaybackStarting;
}

class PlaybackRestoreCommand {
  const PlaybackRestoreCommand({
    required this.track,
    required this.mode,
    required this.position,
    required this.shouldResume,
  });

  final Track track;
  final PlayMode mode;
  final Duration position;
  final bool shouldResume;
}

class PlaybackSessionResult {
  const PlaybackSessionResult._({
    required this.requestId,
    required this.kind,
    this.track,
    this.attemptedUrl,
    this.streamResult,
    this.message,
    this.error,
    this.stackTrace,
  });

  factory PlaybackSessionResult.completed({
    required int requestId,
    required Track track,
    required String attemptedUrl,
    required AudioStreamResult? streamResult,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.completed,
      track: track,
      attemptedUrl: attemptedUrl,
      streamResult: streamResult,
    );
  }

  factory PlaybackSessionResult.superseded({required int requestId}) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.superseded,
    );
  }

  factory PlaybackSessionResult.terminalMediaOpenError({
    required int requestId,
    required Track track,
    required String message,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.terminalMediaOpenError,
      track: track,
      message: message,
    );
  }

  factory PlaybackSessionResult.failed({
    required int requestId,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  final int requestId;
  final PlaybackSessionResultKind kind;
  final Track? track;
  final String? attemptedUrl;
  final AudioStreamResult? streamResult;
  final String? message;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isCompleted => kind == PlaybackSessionResultKind.completed;
  bool get isSuperseded => kind == PlaybackSessionResultKind.superseded;
  bool get isTerminalMediaOpenError =>
      kind == PlaybackSessionResultKind.terminalMediaOpenError;
  bool get isFailed => kind == PlaybackSessionResultKind.failed;
}

typedef PlaybackSessionLoadingStarted = void Function(int requestId);
typedef PlaybackSessionLoadingFinished =
    void Function(int requestId, PlaybackSessionResult result);
typedef PlaybackSessionCurrentTrack = Track? Function();
typedef PlaybackSessionTerminalMessage = String Function(Track track);
typedef PlaybackSessionTerminalMediaOpen =
    void Function({required Track track, required String message});
typedef PlaybackSessionPosition = Duration Function();
typedef PlaybackSessionIsPlaying = bool Function();
typedef PlaybackSessionDelay = Future<void> Function(Duration duration);

/// 下一首的串流已經預取好了。回傳的 future 完成之前不會有第二次通知。
typedef PlaybackSessionNextPrefetched = Future<void> Function(Track nextTrack);

class PlaybackRequestSession with Logging {
  PlaybackRequestSession({
    required FmpAudioService audioService,
    required PlaybackRequestStreamAccess audioStreamManager,
    required Track? Function() getNextTrack,
    required PlaybackSessionLoadingStarted onLoadingStarted,
    required PlaybackSessionLoadingFinished onLoadingFinished,
    required PlaybackSessionTerminalMessage terminalMediaOpenMessage,
    PlaybackSessionTerminalMediaOpen? onTerminalMediaOpenError,
    PlaybackSessionNextPrefetched? onNextTrackPrefetched,
    PlaybackSessionDelay? delay,
    PlaybackTimeoutBudget budget = const PlaybackTimeoutBudget(),
  }) : _budget = budget,
       _audioService = audioService,
       _audioStreamManager = audioStreamManager,
       _getNextTrack = getNextTrack,
       _onLoadingStarted = onLoadingStarted,
       _onLoadingFinished = onLoadingFinished,
       _terminalMediaOpenMessage = terminalMediaOpenMessage,
       _onTerminalMediaOpenError = onTerminalMediaOpenError,
       _onNextTrackPrefetched = onNextTrackPrefetched,
       _delay = delay ?? Future<void>.delayed;

  static const _mediaOpenRecoveryDelay = Duration(seconds: 2);
  static const _mediaOpenRecoveryAdvance = Duration(milliseconds: 500);

  final FmpAudioService _audioService;
  final PlaybackRequestStreamAccess _audioStreamManager;
  final Track? Function() _getNextTrack;
  final PlaybackSessionLoadingStarted _onLoadingStarted;
  final PlaybackSessionLoadingFinished _onLoadingFinished;
  final PlaybackSessionTerminalMessage _terminalMediaOpenMessage;
  final PlaybackSessionTerminalMediaOpen? _onTerminalMediaOpenError;
  final PlaybackSessionNextPrefetched? _onNextTrackPrefetched;
  final PlaybackSessionDelay _delay;
  final PlaybackTimeoutBudget _budget;

  /// 目前這次請求的總期限。每次 `_execute` / `_executeQueueRestore` 進來時重設。
  DateTime? _requestDeadline;

  int _requestId = 0;
  _SessionLock? _playLock;
  final Map<int, _PendingMediaOpenError> _pendingMediaOpenErrors = {};
  _PendingPostHandoffMediaOpenError? _pendingPostHandoffMediaOpenError;
  bool _isDisposed = false;

  int get activeRequestId => _requestId;
  bool get isInLoadingState => _playLock != null;

  void dispose() {
    _isDisposed = true;
    _requestId++;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = null;
    for (final pending in _pendingMediaOpenErrors.values) {
      pending.complete(recovered: true);
    }
    _pendingMediaOpenErrors.clear();
    _pendingPostHandoffMediaOpenError?.complete();
    _pendingPostHandoffMediaOpenError = null;
  }

  bool isSuperseded(int requestId) => _isDisposed || requestId != _requestId;

  void cancelActive() {
    if (_isDisposed) return;
    _cancelPostHandoffMediaOpenError();
    _requestId++;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = null;
  }

  Future<PlaybackSessionResult> start(PlaybackSessionCommand command) async {
    final requestId = _enterLoading();
    late PlaybackSessionResult result;
    try {
      await command.onPlaybackStarting?.call();
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      await _stopForRequest(requestId);
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      final execution = await _execute(
        requestId: requestId,
        track: command.track,
        persist: command.persist,
        prefetchNext: command.prefetchNext,
      );
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (execution == null) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      result = PlaybackSessionResult.completed(
        requestId: requestId,
        track: execution.track,
        attemptedUrl: execution.attemptedUrl,
        streamResult: execution.streamResult,
      );
      final completedMediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (completedMediaOpenResult != null) {
        result = completedMediaOpenResult;
      }
      return result;
    } catch (error, stackTrace) {
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      result = PlaybackSessionResult.failed(
        requestId: requestId,
        error: error,
        stackTrace: stackTrace,
      );
      return result;
    } finally {
      _finishLoading(requestId, result);
    }
  }

  Future<PlaybackSessionResult> restore(PlaybackRestoreCommand command) async {
    final requestId = _enterLoading();
    late PlaybackSessionResult result;
    try {
      await _stopForRequest(requestId);
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      final execution = await _executeQueueRestore(
        requestId: requestId,
        track: command.track,
        position: command.position,
        shouldResume: command.shouldResume,
      );
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (execution == null) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      result = PlaybackSessionResult.completed(
        requestId: requestId,
        track: execution.track,
        attemptedUrl: execution.attemptedUrl,
        streamResult: execution.streamResult,
      );
      final completedMediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (completedMediaOpenResult != null) {
        result = completedMediaOpenResult;
      }
      return result;
    } catch (error, stackTrace) {
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      result = PlaybackSessionResult.failed(
        requestId: requestId,
        error: error,
        stackTrace: stackTrace,
      );
      return result;
    } finally {
      _finishLoading(requestId, result);
    }
  }

  Future<void> onMediaOpenError({
    required String error,
    required Track track,
    required Duration positionAtError,
  }) async {
    if (_isDisposed) return;
    final requestId = _playLock?.requestId;
    if (requestId == null) {
      await _handlePostHandoffMediaOpenError(
        error: error,
        track: track,
        positionAtError: positionAtError,
      );
      return;
    }

    final existing = _pendingMediaOpenErrors[requestId];
    if (existing != null) {
      logDebug('Media open error already pending for request $requestId');
      await existing.recovered.future;
      return;
    }

    final pending = _PendingMediaOpenError(track);
    _pendingMediaOpenErrors[requestId] = pending;

    await _delay(_mediaOpenRecoveryDelay);
    if (_isDisposed ||
        _pendingMediaOpenErrors[requestId] != pending ||
        isSuperseded(requestId)) {
      pending.complete(recovered: true);
      return;
    }

    final currentPosition = _audioService.position;
    final hasAdvanced =
        currentPosition - positionAtError > _mediaOpenRecoveryAdvance;
    if (_audioService.isPlaying && hasAdvanced) {
      logDebug('Media open error recovered by backend: $error');
      pending.complete(recovered: true);
      return;
    }

    logWarning('Media open error did not recover: $error');
    cancelActive();
    final terminalGeneration = _requestId;
    try {
      await _audioService.stop();
    } catch (stopError, stackTrace) {
      logError(
        'Failed to stop player after media open error',
        stopError,
        stackTrace,
      );
    }

    if (_isDisposed ||
        _pendingMediaOpenErrors[requestId] != pending ||
        _requestId != terminalGeneration) {
      pending.complete(recovered: true);
      return;
    }

    pending.terminalMessage = _terminalMediaOpenMessage(track);
    pending.complete(recovered: false);
  }

  Future<void> _handlePostHandoffMediaOpenError({
    required String error,
    required Track track,
    required Duration positionAtError,
  }) async {
    final existing = _pendingPostHandoffMediaOpenError;
    if (existing != null) {
      if (existing.track.uniqueKey == track.uniqueKey) {
        logDebug('Post-handoff media open error already pending');
        await existing.completer.future;
      }
      return;
    }

    final pending = _PendingPostHandoffMediaOpenError(track);
    _pendingPostHandoffMediaOpenError = pending;
    try {
      await _delay(_mediaOpenRecoveryDelay);
      if (_isDisposed || _pendingPostHandoffMediaOpenError != pending) {
        pending.complete();
        return;
      }

      final currentPosition = _audioService.position;
      final hasAdvanced =
          currentPosition - positionAtError > _mediaOpenRecoveryAdvance;
      if (_audioService.isPlaying && hasAdvanced) {
        logDebug('Post-handoff media open error recovered by backend: $error');
        pending.complete();
        return;
      }

      logWarning('Post-handoff media open error did not recover: $error');
      try {
        await _audioService.stop();
      } catch (stopError, stackTrace) {
        logError(
          'Failed to stop player after media open error',
          stopError,
          stackTrace,
        );
      }

      if (_isDisposed || _pendingPostHandoffMediaOpenError != pending) {
        pending.complete();
        return;
      }

      final message = _terminalMediaOpenMessage(track);
      _onTerminalMediaOpenError?.call(track: track, message: message);
      pending.complete();
    } finally {
      if (_pendingPostHandoffMediaOpenError == pending) {
        _pendingPostHandoffMediaOpenError = null;
      }
    }
  }

  int _enterLoading() {
    _cancelPostHandoffMediaOpenError();
    final requestId = ++_requestId;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = _SessionLock(requestId);
    _onLoadingStarted(requestId);
    return requestId;
  }

  void _cancelPostHandoffMediaOpenError() {
    _pendingPostHandoffMediaOpenError?.complete();
    _pendingPostHandoffMediaOpenError = null;
  }

  void _finishLoading(int requestId, PlaybackSessionResult result) {
    if (_isDisposed) return;
    _playLock?.completeIf(requestId);
    if (_playLock?.requestId == requestId) {
      _playLock = null;
    }
    _onLoadingFinished(requestId, result);
  }

  Future<PlaybackSessionResult?> _consumeMediaOpenResult(int requestId) async {
    final pending = _pendingMediaOpenErrors[requestId];
    if (pending == null) return null;
    try {
      final recovered = await pending.recovered.future;
      if (recovered) return null;
      return PlaybackSessionResult.terminalMediaOpenError(
        requestId: requestId,
        track: pending.track,
        message:
            pending.terminalMessage ?? _terminalMediaOpenMessage(pending.track),
      );
    } finally {
      if (_pendingMediaOpenErrors[requestId] == pending) {
        _pendingMediaOpenErrors.remove(requestId);
      }
    }
  }

  Future<void> _stopForRequest(int requestId) async {
    if (isSuperseded(requestId)) return;
    await _audioService.stop();
  }

  Future<_PlaybackRequestExecution?> _execute({
    required int requestId,
    required Track track,
    required bool persist,
    required bool prefetchNext,
  }) async {
    if (isSuperseded(requestId)) {
      logDebug('Play request $requestId superseded by newer request, aborting');
      return null;
    }

    _requestDeadline = DateTime.now().add(_budget.total);
    logDebug('Selecting playback for: ${track.title}');
    final selection = await _withBudget(
      _audioStreamManager.selectPlayback(track, persist: persist),
      PlaybackTimeoutPhase.streamResolution,
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback selection, aborting',
      );
      return null;
    }

    try {
      await _playSelection(requestId, selection);
    } catch (error, stackTrace) {
      if (!isSuperseded(requestId)) {
        try {
          logInfo(
            'Attempting manager-selected fallback playback for: ${track.title} (failed URL: ${selection.media.debugUrl})',
          );
          final fallbackSelection = await _withBudget(
            _audioStreamManager.selectFallbackPlayback(
              selection.media.track,
              failedUrl: selection.media.debugUrl,
            ),
            PlaybackTimeoutPhase.streamResolution,
          );

          if (fallbackSelection != null) {
            if (isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback selection, aborting',
              );
              return null;
            }

            await _playSelection(requestId, fallbackSelection);

            if (isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback handoff, aborting',
              );
              return null;
            }

            _prefetchNextIfRequested(prefetchNext);

            return _PlaybackRequestExecution(
              track: fallbackSelection.media.track,
              attemptedUrl: fallbackSelection.media.debugUrl,
              streamResult: fallbackSelection.streamResult,
            );
          }
        } catch (fallbackError, fallbackStackTrace) {
          logError(
            'Manager-selected fallback playback failed for: ${track.title}',
            fallbackError,
            fallbackStackTrace,
          );
        }
      }

      Error.throwWithStackTrace(error, stackTrace);
    }

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    _prefetchNextIfRequested(prefetchNext);

    return _PlaybackRequestExecution(
      track: selection.media.track,
      attemptedUrl: selection.media.debugUrl,
      streamResult: selection.streamResult,
    );
  }

  Future<_PlaybackRequestExecution?> _executeQueueRestore({
    required int requestId,
    required Track track,
    required Duration position,
    required bool shouldResume,
  }) async {
    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded by newer request, aborting',
      );
      return null;
    }

    _requestDeadline = DateTime.now().add(_budget.total);
    logDebug('Restoring queue track: ${track.title}');
    // 底下三個交接等待點都要帶 phase。沒有 phase 的 _waitForRequestOperation 完全
    // 不設限，後端只要有一個 future 不回來，restore() 就永遠不返回 —— 呼叫端的
    // requestId 停在 null、finally 的 _resetLoadingState 不執行、載入中轉圈到天荒
    // 地老。issue #54 就是這樣來的。
    final selection = await _withBudget(
      _audioStreamManager.selectPlayback(track, persist: true),
      PlaybackTimeoutPhase.streamResolution,
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after playback selection, aborting',
      );
      return null;
    }

    final attemptedUrl = selection.media.debugUrl;
    await _waitForRequestOperation<void>(
      requestId: requestId,
      operation: _audioService.setMedia(selection.media),
      description: 'setMedia',
      phase: PlaybackTimeoutPhase.mediaOpen,
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    if (position > Duration.zero) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.seekTo(position),
        description: 'seekTo',
        phase: PlaybackTimeoutPhase.mediaOpen,
      );
      if (isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after seek, aborting',
        );
        return null;
      }
    }

    if (shouldResume) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.play(),
        description: 'play',
        phase: PlaybackTimeoutPhase.mediaOpen,
      );
      if (isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after resume, aborting',
        );
        return null;
      }
    }

    // 佇列恢復之後幾乎一定會往下一首走，而恢復是啟動路徑上最慢的一段。
    _prefetchNextIfRequested(true);

    return _PlaybackRequestExecution(
      track: selection.media.track,
      attemptedUrl: attemptedUrl,
      streamResult: selection.streamResult,
    );
  }

  Future<void> _playSelection(
    int requestId,
    PlaybackSelection selection,
  ) async {
    final media = selection.media;
    final urlType = media is LocalPlaybackMedia ? 'downloaded' : 'stream';
    logDebug(
      'Playing track: ${media.track.title}, URL type: $urlType, source: ${media.track.sourceType}',
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded before playback handoff, aborting',
      );
      return;
    }

    await _waitForRequestOperation<void>(
      requestId: requestId,
      operation: _audioService.playMedia(media),
      description: 'playMedia',
      phase: PlaybackTimeoutPhase.mediaOpen,
    );
  }

  /// 給一個沒有時鐘的等待加上上界。
  ///
  /// 逾時拋 [PlaybackTimeoutException] 而不是 [TimeoutException]：前者是
  /// 「FMP 決定不再等」，走 fallback 一次就停下；後者是 adapter 的網路抖動，
  /// 走退避階梯。見 audio_types.dart 的說明。
  ///
  /// 每個階段除了自己的預算，還受這次請求的總期限拘束 —— 否則 fallback 那一輪
  /// 會再拿一份完整的 T1+T2，最壞等待直接翻倍。
  Future<T> _withBudget<T>(Future<T> operation, PlaybackTimeoutPhase phase) {
    final phaseBudget = switch (phase) {
      PlaybackTimeoutPhase.streamResolution => _budget.streamResolution,
      PlaybackTimeoutPhase.mediaOpen => _budget.mediaOpen,
      PlaybackTimeoutPhase.bufferStarvation => _budget.bufferStarvation,
    };
    final budget = _remainingBudget(phaseBudget);
    if (budget <= Duration.zero) {
      logWarning('${phase.name} started with no budget left');
      return Future.error(PlaybackTimeoutException(phase, Duration.zero));
    }
    return operation.timeout(
      budget,
      onTimeout: () {
        logWarning(
          '${phase.name} exceeded its ${budget.inMilliseconds}ms budget',
        );
        throw PlaybackTimeoutException(phase, budget);
      },
    );
  }

  /// 這次請求還剩多少時間，上限是該階段自己的預算。
  Duration _remainingBudget(Duration phaseBudget) {
    final deadline = _requestDeadline;
    if (deadline == null) return phaseBudget;
    final remaining = deadline.difference(DateTime.now());
    return remaining < phaseBudget ? remaining : phaseBudget;
  }

  Future<T?> _waitForRequestOperation<T>({
    required int requestId,
    required Future<T> operation,
    required String description,
    PlaybackTimeoutPhase? phase,
  }) async {
    final operationCompleter = Completer<T?>();
    unawaited(
      operation
          .then((value) {
            if (!operationCompleter.isCompleted) {
              operationCompleter.complete(value);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (isSuperseded(requestId)) {
              logError(
                '$description failed after request $requestId was superseded',
                error,
                stackTrace,
              );
              if (!operationCompleter.isCompleted) {
                operationCompleter.complete(null);
              }
              return;
            }
            if (!operationCompleter.isCompleted) {
              operationCompleter.completeError(error, stackTrace);
            }
          }),
    );

    final lock = _playLock;
    final waited = (lock == null || lock.requestId != requestId)
        ? operationCompleter.future
        : Future.any([
            operationCompleter.future,
            lock.completer.future.then<T?>((_) => null),
          ]);

    if (phase == null) return waited;
    // 被新請求取代要先於逾時解決：那不是失敗，只是這一次不再重要了。
    return _withBudget(waited, phase).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (error is PlaybackTimeoutException && isSuperseded(requestId)) {
        return null;
      }
      throw error;
    });
  }

  /// 預取下一首的串流 URL。
  ///
  /// 傳的是佇列裡**那個**實例，不是 copy()。解析會就地把 URL 寫進 track，寫進
  /// 一個 copy() 等於解析完就丟掉 —— 網路照打、風控額度照燒、下次播放照樣重解析。
  void _prefetchNextIfRequested(bool prefetchNext) {
    if (!prefetchNext) return;
    final nextTrack = _getNextTrack();
    if (nextTrack != null) {
      unawaited(_prefetchAndAnnounce(nextTrack));
    }
  }

  /// 預取本身仍然是 fire-and-forget，完成之後多通知一次擁有者。
  ///
  /// 「要不要把這一首交給後端」是控制器的決定（loop-one、脫離佇列、電台占用
  /// 後端……都在那一層），所以這裡只負責說「下一首的串流準備好了」。
  Future<void> _prefetchAndAnnounce(Track nextTrack) async {
    await _audioStreamManager.prefetchTrack(nextTrack);
    if (_isDisposed) return;
    await _onNextTrackPrefetched?.call(nextTrack);
  }
}

class _PlaybackRequestExecution {
  const _PlaybackRequestExecution({
    required this.track,
    required this.attemptedUrl,
    required this.streamResult,
  });

  final Track track;
  final String attemptedUrl;
  final AudioStreamResult? streamResult;
}

class _SessionLock {
  _SessionLock(this.requestId);

  final int requestId;
  final Completer<void> completer = Completer<void>();

  void completeIf(int id) {
    if (id == requestId && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _PendingMediaOpenError {
  _PendingMediaOpenError(this.track);

  final Track track;
  final Completer<bool> recovered = Completer<bool>();
  String? terminalMessage;

  void complete({required bool recovered}) {
    if (!this.recovered.isCompleted) {
      this.recovered.complete(recovered);
    }
  }
}

class _PendingPostHandoffMediaOpenError {
  _PendingPostHandoffMediaOpenError(this.track);

  final Track track;
  final Completer<void> completer = Completer<void>();

  void complete() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}
