import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/playback/recovery_policy.dart';

// design §7.5 的表：每一列至少一例。

RecoveryAction decide(
  PlaybackFailure failure, {
  NetworkStatus network = NetworkStatus.online,
  bool skipPreviewClips = true,
  int retries = 0,
  int reResolves = 0,
  bool candidateSwitched = false,
  bool hasOtherCandidate = false,
  int consecutiveSkips = 0,
  int queueLength = 20,
}) => decideRecovery(
  failure,
  network: network,
  skipPreviewClips: skipPreviewClips,
  retries: retries,
  reResolves: reResolves,
  candidateSwitched: candidateSwitched,
  hasOtherCandidate: hasOtherCandidate,
  consecutiveSkips: consecutiveSkips,
  queueLength: queueLength,
);

Matcher retryAfter(int seconds, int attempt) => isA<RetryAfter>()
    .having((a) => a.delay, 'delay', Duration(seconds: seconds))
    .having((a) => a.attempt, 'attempt', attempt);

const _offline = [NetworkStatus.noInterface, NetworkStatus.unreachable];

void main() {
  group('network and rate limit errors, interruptions', () {
    for (final (name, failure) in <(String, PlaybackFailure)>[
      ('NetworkError', ResolveFailed(NetworkError())),
      ('RateLimited', ResolveFailed(RateLimited())),
      ('an interruption', const StreamInterrupted()),
    ]) {
      test('$name online: retries after 1, 3 and 9 seconds, then skips', () {
        expect(decide(failure), retryAfter(1, 1));
        expect(decide(failure, retries: 1), retryAfter(3, 2));
        expect(decide(failure, retries: 2), retryAfter(9, 3));
        expect(decide(failure, retries: 3), isA<SkipTrack>());
      });

      for (final network in _offline) {
        test('$name ${network.name}: waits for the network, whatever the '
            'count', () {
          expect(decide(failure, network: network), isA<WaitForNetwork>());
          // 重試用完了也一樣：離線時不計次數、不跳過。
          expect(
            decide(failure, network: network, retries: 3),
            isA<WaitForNetwork>(),
          );
        });
      }
    }
  });

  group('errors that retrying does not fix are skipped at once', () {
    for (final error in <AppError>[
      Unavailable(reason: UnavailableReason.copyright),
      Unavailable(reason: UnavailableReason.previewOnly),
      Unavailable(),
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
        // 離線也不等：插件已經回答了。
        expect(
          decide(ResolveFailed(error), network: NetworkStatus.noInterface),
          isA<SkipTrack>(),
        );
      });
    }
  });

  group('a preview-only result', () {
    test('is skipped while "skip preview clips" is on', () {
      expect(decide(const PreviewOnly()), isA<SkipTrack>());
    });

    test('plays as a preview while it is off', () {
      expect(
        decide(const PreviewOnly(), skipPreviewClips: false),
        isA<PlayAsPreview>(),
      );
    });

    test('counts towards consecutive skips', () {
      expect(
        decide(const PreviewOnly(), consecutiveSkips: 1, queueLength: 2),
        isA<StopPlayback>(),
      );
    });
  });

  group('a stream that cannot be opened (decoding, unknown status)', () {
    for (final status in [500, 401]) {
      test('HTTP $status: tries the next candidate once, then skips', () {
        final failure = StreamUnopenable(httpStatus: status);
        expect(
          decide(failure, hasOtherCandidate: true),
          isA<TryNextCandidate>(),
        );
        expect(
          decide(failure, hasOtherCandidate: true, candidateSwitched: true),
          isA<SkipTrack>(),
        );
        expect(decide(failure), isA<SkipTrack>());
      });
    }
  });

  group('a stream refused with 403, 404 or 410', () {
    for (final status in [403, 404, 410]) {
      test('$status: resolves again once, then the next candidate, then '
          'skips', () {
        final failure = StreamUnopenable(httpStatus: status);
        expect(decide(failure, hasOtherCandidate: true), isA<ReResolve>());
        expect(
          decide(failure, reResolves: 1, hasOtherCandidate: true),
          isA<TryNextCandidate>(),
        );
        expect(
          decide(
            failure,
            reResolves: 1,
            hasOtherCandidate: true,
            candidateSwitched: true,
          ),
          isA<SkipTrack>(),
        );
        expect(decide(failure, reResolves: 1), isA<SkipTrack>());
      });
    }

    test('the refusal is an answer: offline does not make it wait', () {
      expect(
        decide(
          const StreamUnopenable(httpStatus: 403),
          network: NetworkStatus.unreachable,
        ),
        isA<ReResolve>(),
      );
    });
  });

  // Android 拿不到狀態碼（just_audio 只給 `Source error`），網址過期也要救得
  // 回來（擁有者 2026-10-06）。
  group('a stream that failed to open without a status', () {
    test('resolves again once, then the next candidate, then skips', () {
      const failure = StreamUnopenable();
      expect(decide(failure), isA<ReResolve>());
      expect(
        decide(failure, reResolves: 1, hasOtherCandidate: true),
        isA<TryNextCandidate>(),
      );
      expect(
        decide(
          failure,
          reResolves: 1,
          hasOtherCandidate: true,
          candidateSwitched: true,
        ),
        isA<SkipTrack>(),
      );
    });

    for (final network in _offline) {
      test('${network.name}: waits for the network first', () {
        expect(
          decide(const StreamUnopenable(), network: network),
          isA<WaitForNetwork>(),
        );
      });
    }
  });

  group('buffering stalled for 15 seconds', () {
    test('resolves again the first time; skips the second time', () {
      expect(decide(const BufferingStalled()), isA<ReResolve>());
      expect(decide(const BufferingStalled(), reResolves: 1), isA<SkipTrack>());
    });

    test('waits for the network while offline', () {
      expect(
        decide(const BufferingStalled(), network: NetworkStatus.noInterface),
        isA<WaitForNetwork>(),
      );
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
