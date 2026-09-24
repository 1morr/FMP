import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/playback_event_router.dart';

/// 後端事件的路由決定，一條規則一條斷言。
///
/// 這些規則以前只存在於 `AudioController` 的處理函式裡，要驗其中任何一條都得
/// 架一整個控制器、一個假後端與一個 Isar，再從 toast 與日誌反推走了哪一條。
/// 這個檔就是「結束原因 → 控制器動作」那張表：每一列一條斷言。
void main() {
  group('routeEnd — the end reason table', () {
    test('a natural end enters the completion path', () {
      expect(
        PlaybackEventRouter.routeEnd(const EndedNaturally(), _context()),
        isA<HandleTrackCompletion>(),
      );
    });

    test('a premature end retries the current track from where it stopped', () {
      final action = PlaybackEventRouter.routeEnd(
        const EndedPrematurely(
          at: Duration(seconds: 13),
          expected: Duration(minutes: 4),
        ),
        _context(),
      );

      expect(action, isA<RetryPrematureEnd>());
      expect((action as RetryPrematureEnd).at, const Duration(seconds: 13));
      expect(action.expected, const Duration(minutes: 4));
    });

    test('a premature end with no reported duration is still a retry', () {
      // 「開了流但一個位元組都沒有」就是這個形狀。後端決定它算 premature，
      // 路由的責任只是別把它當成播完。
      final action = PlaybackEventRouter.routeEnd(
        const EndedPrematurely(at: Duration.zero),
        _context(),
      );

      expect(action, isA<RetryPrematureEnd>());
      expect((action as RetryPrematureEnd).expected, isNull);
    });

    test('a transport failure recovers instead of advancing', () {
      const failure = TransportFailed(
        kind: TransportFailureKind.reset,
        raw: 'tcp: connection reset',
      );

      final action = PlaybackEventRouter.routeEnd(failure, _context());

      expect(action, isA<RecoverTransportFailure>());
      expect((action as RecoverTransportFailure).failure, same(failure));
    });

    test('a transport failure while paused waits for play', () {
      // 實機：還原後暫停著，CDN 關掉連線。重試會真的開始播放。
      const failure = TransportFailed(
        kind: TransportFailureKind.unknown,
        raw: 'tcp: ffurl_read returned 0xdfb9b0bb',
      );

      final action = PlaybackEventRouter.routeEnd(
        failure,
        _context(backendIsPlaying: false),
      );

      expect(action, isA<DeferTransportFailureUntilPlay>());
      expect((action as DeferTransportFailureUntilPlay).failure, same(failure));
    });

    test('a transport failure while opening or retrying still recovers', () {
      // 這兩段後端也沒在播，但使用者要的是播放。
      const failure = TransportFailed(
        kind: TransportFailureKind.timeout,
        raw: 'tcp: timed out',
      );

      for (final context in [
        _context(backendIsPlaying: false, isLoadingPlayback: true),
        _context(backendIsPlaying: false, isRetrying: true),
      ]) {
        expect(
          PlaybackEventRouter.routeEnd(failure, context),
          isA<RecoverTransportFailure>(),
        );
      }
    });

    test('a transport failure with no playing track is ignored', () {
      expect(
        PlaybackEventRouter.routeEnd(
          const TransportFailed(
            kind: TransportFailureKind.dns,
            raw: 'Failed host lookup',
          ),
          _context(playingTrackKey: null),
        ),
        isA<IgnoreEvent>(),
      );
    });

    test('an output device failure never blames the track', () {
      final action = PlaybackEventRouter.routeEnd(
        const OutputDeviceFailed(raw: 'ao: wasapi'),
        _context(),
      );

      expect(action, isA<ReportOutputDeviceFailure>());
      expect((action as ReportOutputDeviceFailure).raw, 'ao: wasapi');
      expect(action.showToast, isTrue);
    });

    test('an unopenable medium and a failed decoder share one path', () {
      expect(
        PlaybackEventRouter.routeEnd(
          const MediaUnopenable(raw: 'Failed to open https://example.com'),
          _context(),
        ),
        isA<ReopenAfterMediaFailure>(),
      );
      expect(
        PlaybackEventRouter.routeEnd(
          const DecoderFailed(raw: 'could not decode'),
          _context(),
        ),
        isA<ReopenAfterMediaFailure>(),
      );
    });

    test('a media failure with no playing track is ignored', () {
      expect(
        PlaybackEventRouter.routeEnd(
          const MediaUnopenable(raw: 'Failed to open https://example.com'),
          _context(playingTrackKey: null),
        ),
        isA<IgnoreEvent>(),
      );
    });

    test('an unclassified failure is dropped visibly, not silently', () {
      final action = PlaybackEventRouter.routeEnd(
        const UnclassifiedFailure(raw: 'something new from the engine'),
        _context(),
      );

      expect(action, isA<ReportUnclassifiedFailure>());
      expect(
        (action as ReportUnclassifiedFailure).raw,
        'something new from the engine',
      );
    });
  });

  group('routeEnd — radio owns the backend', () {
    test('only the output device failure gets through', () {
      expect(
        PlaybackEventRouter.routeEnd(
          const OutputDeviceFailed(raw: 'ao: wasapi'),
          _context(radioOwnsPlayback: true),
        ),
        isA<ReportOutputDeviceFailure>(),
      );
    });

    test('every other end reason is ignored', () {
      const reasons = <PlaybackEndReason>[
        EndedNaturally(),
        EndedPrematurely(at: Duration(seconds: 3)),
        TransportFailed(
          kind: TransportFailureKind.reset,
          raw: 'tcp: connection reset',
        ),
        MediaUnopenable(raw: 'Failed to open https://example.com'),
        DecoderFailed(raw: 'could not decode'),
        UnclassifiedFailure(raw: 'something new'),
      ];

      for (final reason in reasons) {
        expect(
          PlaybackEventRouter.routeEnd(
            reason,
            _context(radioOwnsPlayback: true),
          ),
          isA<IgnoreEvent>(),
          reason: '$reason must stay with RadioController',
        );
      }
    });
  });

  group('routeEnd — loading, retrying and network errors', () {
    test('a premature end is ignored in every one of the three states', () {
      const premature = EndedPrematurely(at: Duration(seconds: 13));

      for (final context in [
        _context(isLoadingPlayback: true),
        _context(isRetrying: true),
        _context(isNetworkError: true),
      ]) {
        expect(
          PlaybackEventRouter.routeEnd(premature, context),
          isA<IgnoreEvent>(),
        );
      }
    });

    test('a disposed controller does nothing at all', () {
      expect(
        PlaybackEventRouter.routeEnd(
          const EndedNaturally(),
          _context(isDisposed: true),
        ),
        isA<IgnoreEvent>(),
      );
    });
  });

  group('routeEnd — issue #106, the output device and the retry', () {
    const premature = EndedPrematurely(
      at: Duration(seconds: 13),
      expected: Duration(minutes: 4),
    );

    test('a device failure in this generation cancels the retry', () {
      final action = PlaybackEventRouter.routeEnd(
        premature,
        _context(outputDeviceFailureMark: (generation: 7, trackKey: 'a')),
      );

      expect(action, isA<SkipPrematureEndRetry>());
      expect((action as SkipPrematureEndRetry).at, const Duration(seconds: 13));
    });

    test('a device failure in an older generation does not', () {
      // 使用者修好裝置後重按播放 —— 換一個請求世代，抑制就該失效。
      expect(
        PlaybackEventRouter.routeEnd(
          premature,
          _context(outputDeviceFailureMark: (generation: 6, trackKey: 'a')),
        ),
        isA<RetryPrematureEnd>(),
      );
    });

    test('a device failure on another track does not either', () {
      expect(
        PlaybackEventRouter.routeEnd(
          premature,
          _context(outputDeviceFailureMark: (generation: 7, trackKey: 'b')),
        ),
        isA<RetryPrematureEnd>(),
      );
    });
  });

  group('routeOutputDeviceFailure', () {
    test('the first message of a failure shows the toast', () {
      final action = _outputDeviceFailure(_context());

      expect(action.showToast, isTrue);
      expect(action.at, _now);
    });

    test('a second message inside the suppress window does not', () {
      // 實測 mpv 一次裝置失敗吐三條訊息。
      final action = _outputDeviceFailure(
        _context(
          lastOutputDeviceFailureAt: _now.subtract(
            const Duration(milliseconds: 500),
          ),
        ),
      );

      expect(action.showToast, isFalse);
    });

    test('a new failure after the window shows the toast again', () {
      final action = _outputDeviceFailure(
        _context(
          lastOutputDeviceFailureAt: _now.subtract(const Duration(seconds: 4)),
        ),
      );

      expect(action.showToast, isTrue);
    });

    test('a retry already scheduled for this generation is taken back', () {
      // 實機順序：mpv 先宣告 completed、4ms 後才吐 ao 錯誤，所以重試那時已經
      // 排好了（issue #106）。
      final action = _outputDeviceFailure(
        _context(prematureEndRetryMark: (generation: 7, trackKey: 'a')),
      );

      expect(action.cancelScheduledRetry, isTrue);
    });

    test('nothing is taken back when no retry is pending', () {
      expect(_outputDeviceFailure(_context()).cancelScheduledRetry, isFalse);
    });

    test('a retry from another generation is left alone', () {
      final action = _outputDeviceFailure(
        _context(prematureEndRetryMark: (generation: 6, trackKey: 'a')),
      );

      expect(action.cancelScheduledRetry, isFalse);
    });

    test('a suppressed message still takes the scheduled retry back', () {
      // 兩個決定互相獨立：第二、三條訊息不出 toast，但照樣要收回重試。
      final action = _outputDeviceFailure(
        _context(
          lastOutputDeviceFailureAt: _now.subtract(
            const Duration(milliseconds: 500),
          ),
          prematureEndRetryMark: (generation: 7, trackKey: 'a'),
        ),
      );

      expect(action.showToast, isFalse);
      expect(action.cancelScheduledRetry, isTrue);
    });
  });

  group('routePlayerState', () {
    const playing = FmpPlayerState(
      playing: true,
      processingState: FmpAudioProcessingState.ready,
    );

    test('radio only gets the buffer watchdog cancelled', () {
      expect(
        PlaybackEventRouter.routePlayerState(
          playing,
          _context(radioOwnsPlayback: true),
        ),
        isA<CancelBufferWatchdog>(),
      );
    });

    test('a track that cannot be opened stops projecting backend state', () {
      expect(
        PlaybackEventRouter.routePlayerState(
          playing,
          _context(terminalMediaOpenErrorTrackKey: 'a', hasError: true),
        ),
        isA<IgnoreEvent>(),
      );
    });

    test('a terminal error on a different track does not stop it', () {
      expect(
        PlaybackEventRouter.routePlayerState(
          playing,
          _context(terminalMediaOpenErrorTrackKey: 'b', hasError: true),
        ),
        isA<ProjectPlayerState>(),
      );
    });

    test('playing inside the device guard is taken back', () {
      // mpv 沒有輸出裝置也會把 playing 翻真；不收回的話 UI 停在「正在播放」
      // 卻完全沒有聲音。
      expect(
        PlaybackEventRouter.routePlayerState(
          playing,
          _context(
            lastOutputDeviceFailureAt: _now.subtract(
              const Duration(seconds: 2),
            ),
          ),
        ),
        isA<PauseBackend>(),
      );
    });

    test('not playing inside the device guard is projected as usual', () {
      expect(
        PlaybackEventRouter.routePlayerState(
          const FmpPlayerState(
            playing: false,
            processingState: FmpAudioProcessingState.idle,
          ),
          _context(
            lastOutputDeviceFailureAt: _now.subtract(
              const Duration(seconds: 2),
            ),
          ),
        ),
        isA<ProjectPlayerState>(),
      );
    });

    test('playing after the guard has closed is projected again', () {
      expect(
        PlaybackEventRouter.routePlayerState(
          playing,
          _context(
            lastOutputDeviceFailureAt: _now.subtract(
              const Duration(seconds: 6),
            ),
          ),
        ),
        isA<ProjectPlayerState>(),
      );
    });

    test('the projection carries the effective state, not the raw one', () {
      final action =
          PlaybackEventRouter.routePlayerState(
                const FmpPlayerState(
                  playing: true,
                  processingState: FmpAudioProcessingState.idle,
                ),
                _context(isLoadingPlayback: true, position: _somePosition),
              )
              as ProjectPlayerState;

      // 控制器自己造成的 idle 不是「播放結束了」。
      expect(action.effective.isPlaying, isFalse);
      expect(action.effective.isLoading, isTrue);
      expect(action.effective.position, Duration.zero);
      expect(action.backend.playing, isTrue);
    });

    test(
      'the watchdog is suppressed in each state that is not real playing',
      () {
        for (final context in [
          _context(isLoadingPlayback: true),
          _context(isRetrying: true),
          _context(isNetworkError: true),
          _context(
            lastOutputDeviceFailureAt: _now.subtract(
              const Duration(seconds: 2),
            ),
          ),
        ]) {
          final action =
              PlaybackEventRouter.routePlayerState(
                    const FmpPlayerState(
                      playing: false,
                      processingState: FmpAudioProcessingState.buffering,
                    ),
                    context,
                  )
                  as ProjectPlayerState;
          expect(action.suppressWatchdog, isTrue);
        }

        final healthy =
            PlaybackEventRouter.routePlayerState(playing, _context())
                as ProjectPlayerState;
        expect(healthy.suppressWatchdog, isFalse);
      },
    );
  });

  group('routeCompletion', () {
    test('loop-one wins over everything else', () {
      expect(
        PlaybackEventRouter.routeCompletion(
          _context(
            loopMode: LoopMode.one,
            isPlayingOutOfQueue: true,
            hasNextInQueue: true,
          ),
        ),
        isA<ReplayCurrentTrack>(),
      );
    });

    test('playing out of the queue returns to it', () {
      expect(
        PlaybackEventRouter.routeCompletion(
          _context(isPlayingOutOfQueue: true, hasNextInQueue: true),
        ),
        isA<ReturnToQueue>(),
      );
    });

    test('a next track in the queue is played', () {
      expect(
        PlaybackEventRouter.routeCompletion(_context(hasNextInQueue: true)),
        isA<AdvanceQueue>(),
      );
    });

    test('the mix end waits for the pending load-more', () {
      expect(
        PlaybackEventRouter.routeCompletion(_context(mixLoadMorePending: true)),
        isA<WaitForMixLoadMore>(),
      );
    });

    test('a next track wins over a pending mix load-more', () {
      expect(
        PlaybackEventRouter.routeCompletion(
          _context(hasNextInQueue: true, mixLoadMorePending: true),
        ),
        isA<AdvanceQueue>(),
      );
    });

    test('the end of the queue pauses the backend', () {
      expect(
        PlaybackEventRouter.routeCompletion(_context()),
        isA<PauseAtQueueEnd>(),
      );
    });

    test('loading, retrying and network errors swallow the completion', () {
      for (final context in [
        _context(isLoadingPlayback: true, hasNextInQueue: true),
        _context(isRetrying: true, hasNextInQueue: true),
        _context(isNetworkError: true, hasNextInQueue: true),
        _context(isDisposed: true, hasNextInQueue: true),
      ]) {
        expect(
          PlaybackEventRouter.routeCompletion(context),
          isA<IgnoreEvent>(),
        );
      }
    });
  });

  group('routePositionCheck', () {
    const trackLength = Duration(minutes: 3, seconds: 4);
    // 容忍窗是 `AppConstants.positionCheckThreshold`（500ms），這裡剩 200ms。
    const nearTheEnd = Duration(minutes: 3, seconds: 3, milliseconds: 800);

    // 這一組刻意斷言 `NothingToDo` 而不是 `IgnoreEvent`：位置檢查一秒一格，
    // 給每一格記一行「事件被忽略」一天就是八萬多行，而日誌只留三個檔。
    test('a paused backend is not checked at all, and not logged either', () {
      expect(
        PlaybackEventRouter.routePositionCheck(
          _context(
            backendIsPlaying: false,
            position: nearTheEnd,
            duration: trackLength,
          ),
        ),
        isA<NothingToDo>(),
      );
    });

    test('a stream with no usable duration is not checked either', () {
      for (final duration in const [null, Duration.zero]) {
        expect(
          PlaybackEventRouter.routePositionCheck(
            _context(position: nearTheEnd, duration: duration),
          ),
          isA<NothingToDo>(),
        );
      }
    });

    test('a disposed controller polls nothing', () {
      expect(
        PlaybackEventRouter.routePositionCheck(
          _context(
            isDisposed: true,
            position: nearTheEnd,
            duration: trackLength,
          ),
        ),
        isA<NothingToDo>(),
      );
    });

    test('far from the end the armed tick count is reset', () {
      expect(
        PlaybackEventRouter.routePositionCheck(
          _context(
            position: const Duration(minutes: 1),
            duration: trackLength,
            armedNextTrackKey: 'beta|',
            armedEndTicks: 2,
          ),
        ),
        isA<ResetArmedEndTicks>(),
      );
    });

    test('near the end with nothing armed synthesizes the completion', () {
      final action = PlaybackEventRouter.routePositionCheck(
        _context(position: nearTheEnd, duration: trackLength),
      );

      expect(action, isA<SynthesizeCompletion>());
      expect((action as SynthesizeCompletion).position, nearTheEnd);
      expect(action.duration, trackLength);
    });

    test('the first two ticks give the advance back to the backend', () {
      for (final ticks in const [0, 1]) {
        expect(
          PlaybackEventRouter.routePositionCheck(
            _context(
              position: nearTheEnd,
              duration: trackLength,
              armedNextTrackKey: 'beta|',
              armedEndTicks: ticks,
            ),
          ),
          isA<IncrementArmedEndTicks>(),
          reason: 'tick $ticks is still inside the grace window',
        );
      }
    });

    test('the third tick takes the advance back', () {
      // 1 秒一格，所以讓了 3 秒。備援本來就是為了「後台 completed 事件丟失」
      // 而存在的，不是無限期讓路。
      expect(PlaybackEventRouter.armedAdvanceGraceTicks, 3);

      final action = PlaybackEventRouter.routePositionCheck(
        _context(
          position: nearTheEnd,
          duration: trackLength,
          armedNextTrackKey: 'beta|',
          armedEndTicks: 2,
        ),
      );

      expect(action, isA<TakeBackAdvanceAndComplete>());
      expect((action as TakeBackAdvanceAndComplete).position, nearTheEnd);
      expect(action.duration, trackLength);
    });
  });

  group('routeBufferStarvation', () {
    test('the first starvation on a track re-issues the request', () {
      expect(
        PlaybackEventRouter.routeBufferStarvation(_context()),
        isA<RetryStalledStream>(),
      );
    });

    test('the second one on the same track gives up', () {
      // 同一首只救一次，否則就變成無限重載。
      expect(
        PlaybackEventRouter.routeBufferStarvation(
          _context(bufferStarvationTrackKey: 'a'),
        ),
        isA<FailStalledPlayback>(),
      );
    });

    test('a rescue spent on another track does not count', () {
      expect(
        PlaybackEventRouter.routeBufferStarvation(
          _context(bufferStarvationTrackKey: 'b'),
        ),
        isA<RetryStalledStream>(),
      );
    });

    test('nothing is rescued without a playing track', () {
      expect(
        PlaybackEventRouter.routeBufferStarvation(
          _context(playingTrackKey: null),
        ),
        isA<IgnoreEvent>(),
      );
    });

    test('loading, retrying and network errors are not starvation', () {
      for (final context in [
        _context(isLoadingPlayback: true),
        _context(isRetrying: true),
        _context(isNetworkError: true),
        _context(isDisposed: true),
      ]) {
        expect(
          PlaybackEventRouter.routeBufferStarvation(context),
          isA<IgnoreEvent>(),
        );
      }
    });
  });
}

final _now = DateTime(2026, 9, 16, 23, 20, 56);
const _somePosition = Duration(seconds: 42);

ReportOutputDeviceFailure _outputDeviceFailure(PlaybackEventContext context) =>
    PlaybackEventRouter.routeOutputDeviceFailure('ao: wasapi', context)
        as ReportOutputDeviceFailure;

/// 一張「一切正常、佇列尾端、什麼都沒 arm」的快照，逐條測試只改它關心的欄位。
PlaybackEventContext _context({
  bool isDisposed = false,
  bool radioOwnsPlayback = false,
  bool isLoadingPlayback = false,
  bool isRetrying = false,
  bool isNetworkError = false,
  String? playingTrackKey = 'a',
  bool hasError = false,
  String? terminalMediaOpenErrorTrackKey,
  ({int generation, String? trackKey}) generationMark = (
    generation: 7,
    trackKey: 'a',
  ),
  ({int generation, String? trackKey})? outputDeviceFailureMark,
  ({int generation, String? trackKey})? prematureEndRetryMark,
  DateTime? lastOutputDeviceFailureAt,
  LoopMode loopMode = LoopMode.none,
  bool isPlayingOutOfQueue = false,
  bool hasNextInQueue = false,
  bool mixLoadMorePending = false,
  String? armedNextTrackKey,
  int armedEndTicks = 0,
  String? bufferStarvationTrackKey,
  bool backendIsPlaying = true,
  Duration position = Duration.zero,
  Duration? duration,
}) => PlaybackEventContext(
  isDisposed: isDisposed,
  radioOwnsPlayback: radioOwnsPlayback,
  isLoadingPlayback: isLoadingPlayback,
  isRetrying: isRetrying,
  isNetworkError: isNetworkError,
  playingTrackKey: playingTrackKey,
  hasError: hasError,
  terminalMediaOpenErrorTrackKey: terminalMediaOpenErrorTrackKey,
  generationMark: generationMark,
  outputDeviceFailureMark: outputDeviceFailureMark,
  prematureEndRetryMark: prematureEndRetryMark,
  lastOutputDeviceFailureAt: lastOutputDeviceFailureAt,
  now: _now,
  loopMode: loopMode,
  isPlayingOutOfQueue: isPlayingOutOfQueue,
  hasNextInQueue: hasNextInQueue,
  mixLoadMorePending: mixLoadMorePending,
  armedNextTrackKey: armedNextTrackKey,
  armedEndTicks: armedEndTicks,
  bufferStarvationTrackKey: bufferStarvationTrackKey,
  backendIsPlaying: backendIsPlaying,
  position: position,
  duration: duration,
);
