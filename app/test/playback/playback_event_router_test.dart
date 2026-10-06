import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/recovery_policy.dart';

const _generation = 3;
const _resumeAt = Duration(seconds: 7);
const _lastPosition = Duration(seconds: 42);

PlaybackSnapshot snapshot({
  bool playWhenReady = true,
  bool hasNext = true,
  bool repeatsTrack = false,
}) => PlaybackSnapshot(
  generation: _generation,
  playWhenReady: playWhenReady,
  hasNext: hasNext,
  repeatsTrack: repeatsTrack,
  resumeAt: _resumeAt,
);

Matcher recovers<F extends PlaybackFailure, E extends AppError>({
  required Duration position,
  bool endedEarly = false,
}) => isA<Recover>()
    .having((a) => a.failure, 'failure', isA<F>())
    .having((a) => a.error, 'error', isA<E>())
    .having((a) => a.error.pluginId, 'error.pluginId', 'fmp-test')
    .having((a) => a.position, 'position', position)
    .having((a) => a.endedEarly, 'endedEarly', endedEarly);

void main() {
  group('an event from an older generation is ignored', () {
    for (final event in <SessionEvent>[
      const SourceBuffering(generation: _generation - 1, wasReady: true),
      const SourceReady(
        generation: _generation - 1,
        playing: true,
        wasReady: false,
      ),
      const LookAheadTookOver(
        generation: _generation - 1,
        end: TrackEndReason.completed,
      ),
      const SourceFinished(
        generation: _generation - 1,
        pluginId: 'fmp-test',
        end: TrackEndReason.completed,
        lastPosition: _lastPosition,
      ),
      const SourceUnopenable(generation: _generation - 1, pluginId: 'fmp-test'),
      const SourceInterrupted(
        generation: _generation - 1,
        pluginId: 'fmp-test',
        lastPosition: _lastPosition,
      ),
    ]) {
      test('${event.runtimeType}', () {
        expect(routePlaybackEvent(event, snapshot()), isA<IgnoreEvent>());
      });
    }
  });

  group('buffering', () {
    test('before the source was ready is Loading', () {
      final action = routePlaybackEvent(
        const SourceBuffering(generation: _generation, wasReady: false),
        snapshot(),
      );
      expect(
        action,
        isA<ShowState>().having((a) => a.state, 'state', isA<Loading>()),
      );
    });

    test('after the source was ready is Buffering', () {
      final action = routePlaybackEvent(
        const SourceBuffering(generation: _generation, wasReady: true),
        snapshot(),
      );
      expect(
        action,
        isA<ShowState>().having((a) => a.state, 'state', isA<Buffering>()),
      );
    });
  });

  group('ready', () {
    test('the first time, playing, prepares the look-ahead', () {
      final action = routePlaybackEvent(
        const SourceReady(
          generation: _generation,
          playing: true,
          wasReady: false,
        ),
        snapshot(),
      );
      expect(
        action,
        isA<MarkReady>()
            .having((a) => a.playing, 'playing', isTrue)
            .having((a) => a.first, 'first', isTrue),
      );
    });

    test(
      'the first time, silent while the user wants sound, waits for play',
      () {
        final action = routePlaybackEvent(
          const SourceReady(
            generation: _generation,
            playing: false,
            wasReady: false,
          ),
          snapshot(),
        );
        expect(action, isA<IgnoreEvent>());
      },
    );

    test('the first time, silent while paused, is Paused', () {
      final action = routePlaybackEvent(
        const SourceReady(
          generation: _generation,
          playing: false,
          wasReady: false,
        ),
        snapshot(playWhenReady: false),
      );
      expect(
        action,
        isA<MarkReady>()
            .having((a) => a.playing, 'playing', isFalse)
            .having((a) => a.first, 'first', isTrue),
      );
    });

    test('again, silent, is a pause and not a first time', () {
      final action = routePlaybackEvent(
        const SourceReady(
          generation: _generation,
          playing: false,
          wasReady: true,
        ),
        snapshot(),
      );
      expect(
        action,
        isA<MarkReady>()
            .having((a) => a.playing, 'playing', isFalse)
            .having((a) => a.first, 'first', isFalse),
      );
    });
  });

  group('look-ahead handover', () {
    test('a completed track is adopted', () {
      final action = routePlaybackEvent(
        const LookAheadTookOver(
          generation: _generation,
          end: TrackEndReason.completed,
        ),
        snapshot(),
      );
      expect(
        action,
        isA<AdoptLookAhead>().having(
          (a) => a.previousEndedEarly,
          'previousEndedEarly',
          isFalse,
        ),
      );
    });

    test('a track that ended early is adopted too, and marked', () {
      final action = routePlaybackEvent(
        const LookAheadTookOver(
          generation: _generation,
          end: TrackEndReason.endedEarly,
        ),
        snapshot(),
      );
      expect(
        action,
        isA<AdoptLookAhead>().having(
          (a) => a.previousEndedEarly,
          'previousEndedEarly',
          isTrue,
        ),
      );
    });
  });

  group('end of a track', () {
    SourceFinished finished(TrackEndReason end, {Duration? lastPosition}) =>
        SourceFinished(
          generation: _generation,
          pluginId: 'fmp-test',
          end: end,
          lastPosition: lastPosition,
        );

    test('completed with a next track plays it', () {
      expect(
        routePlaybackEvent(finished(TrackEndReason.completed), snapshot()),
        isA<PlayNextTrack>(),
      );
    });

    test('completed at the end of the queue finishes', () {
      expect(
        routePlaybackEvent(
          finished(TrackEndReason.completed),
          snapshot(hasNext: false),
        ),
        isA<FinishQueue>(),
      );
    });

    // 單曲循環：前瞻（同一份解析結果）沒來得及接上時，播完就重播，不管後面
    // 有沒有歌。
    for (final hasNext in [true, false]) {
      test(
        'completed under loop one repeats the track (hasNext: $hasNext)',
        () {
          expect(
            routePlaybackEvent(
              finished(TrackEndReason.completed),
              snapshot(hasNext: hasNext, repeatsTrack: true),
            ),
            isA<RepeatTrack>(),
          );
        },
      );
    }

    test('ended early under loop one is still an interruption', () {
      expect(
        routePlaybackEvent(
          finished(TrackEndReason.endedEarly, lastPosition: _lastPosition),
          snapshot(repeatsTrack: true),
        ),
        recovers<StreamInterrupted, NetworkError>(
          position: _lastPosition,
          endedEarly: true,
        ),
      );
    });

    test('ended early is an interruption from the last position', () {
      expect(
        routePlaybackEvent(
          finished(TrackEndReason.endedEarly, lastPosition: _lastPosition),
          snapshot(hasNext: false),
        ),
        recovers<StreamInterrupted, NetworkError>(
          position: _lastPosition,
          endedEarly: true,
        ),
      );
    });

    test('ended early without a position resumes where it started', () {
      expect(
        routePlaybackEvent(finished(TrackEndReason.endedEarly), snapshot()),
        recovers<StreamInterrupted, NetworkError>(
          position: _resumeAt,
          endedEarly: true,
        ),
      );
    });
  });

  group('failures', () {
    test('a source that cannot be opened is Unsupported from the start', () {
      expect(
        routePlaybackEvent(
          const SourceUnopenable(generation: _generation, pluginId: 'fmp-test'),
          snapshot(),
        ),
        recovers<StreamUnopenable, Unsupported>(position: _resumeAt),
      );
    });

    // design §7.5：跳過時給使用者的原因依狀態碼。
    for (final (status, matcher) in [
      (404, isA<NotFound>()),
      (410, isA<NotFound>()),
      (403, isA<Unavailable>().having((e) => e.reason, 'reason', isNull)),
      (500, isA<Unsupported>()),
    ]) {
      test(
        'a source refused with $status carries the status and its error',
        () {
          final action = routePlaybackEvent(
            SourceUnopenable(
              generation: _generation,
              pluginId: 'fmp-test',
              httpStatus: status,
            ),
            snapshot(),
          );
          expect(
            action,
            isA<Recover>()
                .having(
                  (a) => a.failure,
                  'failure',
                  isA<StreamUnopenable>().having(
                    (f) => f.httpStatus,
                    'httpStatus',
                    status,
                  ),
                )
                .having((a) => a.error, 'error', matcher)
                .having((a) => a.error.pluginId, 'pluginId', 'fmp-test'),
          );
        },
      );
    }

    test('an interrupted source is a network error from its position', () {
      expect(
        routePlaybackEvent(
          const SourceInterrupted(
            generation: _generation,
            pluginId: 'fmp-test',
            lastPosition: _lastPosition,
          ),
          snapshot(),
        ),
        recovers<StreamInterrupted, NetworkError>(position: _lastPosition),
      );
    });

    test('an interrupted source without a position resumes where it '
        'started', () {
      expect(
        routePlaybackEvent(
          const SourceInterrupted(
            generation: _generation,
            pluginId: 'fmp-test',
            lastPosition: null,
          ),
          snapshot(),
        ),
        recovers<StreamInterrupted, NetworkError>(position: _resumeAt),
      );
    });
  });
}
