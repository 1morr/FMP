import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/recovery_policy.dart';

RecoveryAction decide(
  PlaybackFailure failure, {
  int retries = 0,
  bool candidateSwitched = false,
  bool hasOtherCandidate = false,
  int consecutiveSkips = 0,
  int queueLength = 20,
}) => decideRecovery(
  failure,
  retries: retries,
  candidateSwitched: candidateSwitched,
  hasOtherCandidate: hasOtherCandidate,
  consecutiveSkips: consecutiveSkips,
  queueLength: queueLength,
);

Matcher retryAfter(int seconds, int attempt) => isA<RetryAfter>()
    .having((a) => a.delay, 'delay', Duration(seconds: seconds))
    .having((a) => a.attempt, 'attempt', attempt);

void main() {
  group('network and rate limit errors', () {
    for (final error in [NetworkError(), RateLimited()]) {
      test(
        '${error.typeName} retries after 1, 3 and 9 seconds, then skips',
        () {
          final failure = ResolveFailed(error);
          expect(decide(failure), retryAfter(1, 1));
          expect(decide(failure, retries: 1), retryAfter(3, 2));
          expect(decide(failure, retries: 2), retryAfter(9, 3));
          expect(decide(failure, retries: 3), isA<SkipTrack>());
        },
      );
    }

    test('an interrupted stream retries like a network error', () {
      const failure = StreamInterrupted();
      expect(decide(failure), retryAfter(1, 1));
      expect(decide(failure, retries: 3), isA<SkipTrack>());
    });
  });

  group('errors that retrying does not fix are skipped at once', () {
    for (final error in <AppError>[
      Unavailable(reason: UnavailableReason.copyright),
      Unavailable(reason: UnavailableReason.previewOnly),
      NotFound(),
      AuthRequired(),
      CredentialInvalid(),
      VerificationRequired(),
      Unsupported(),
      ParseError(),
      UnexpectedError(),
    ]) {
      test(error.toString(), () {
        expect(decide(ResolveFailed(error)), isA<SkipTrack>());
      });
    }
  });

  group('a stream that cannot be opened', () {
    test('tries the next candidate once', () {
      expect(
        decide(const StreamUnopenable(), hasOtherCandidate: true),
        isA<TryNextCandidate>(),
      );
      expect(
        decide(
          const StreamUnopenable(),
          hasOtherCandidate: true,
          candidateSwitched: true,
        ),
        isA<SkipTrack>(),
      );
    });

    test('skips without another candidate', () {
      expect(decide(const StreamUnopenable()), isA<SkipTrack>());
    });
  });

  group('consecutive skips', () {
    test('stop when this skip reaches the queue length', () {
      final failure = ResolveFailed(NotFound());
      expect(
        decide(failure, consecutiveSkips: 1, queueLength: 3),
        isA<SkipTrack>(),
      );
      expect(
        decide(failure, consecutiveSkips: 2, queueLength: 3),
        isA<StopPlayback>(),
      );
      expect(decide(failure, queueLength: 1), isA<StopPlayback>());
    });

    test('stop at ten in a longer queue', () {
      final failure = ResolveFailed(NotFound());
      expect(
        decide(failure, consecutiveSkips: 8, queueLength: 100),
        isA<SkipTrack>(),
      );
      expect(
        decide(failure, consecutiveSkips: 9, queueLength: 100),
        isA<StopPlayback>(),
      );
    });

    test('also apply after the retries run out', () {
      expect(
        decide(
          ResolveFailed(NetworkError()),
          retries: 3,
          consecutiveSkips: 1,
          queueLength: 2,
        ),
        isA<StopPlayback>(),
      );
    });
  });
}
