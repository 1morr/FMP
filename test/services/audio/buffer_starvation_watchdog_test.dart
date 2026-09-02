import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/services/audio/buffer_starvation_watchdog.dart';
import 'package:fmp/services/audio/playback_recovery_coordinator.dart';

void main() {
  group('BufferStarvationWatchdog', () {
    late int starvedCount;
    late _FakeTimer? armed;
    late BufferStarvationWatchdog watchdog;

    setUp(() {
      starvedCount = 0;
      armed = null;
      watchdog = BufferStarvationWatchdog(
        onStarved: () => starvedCount++,
        budget: const PlaybackTimeoutBudget(
          bufferStarvation: Duration(seconds: 15),
        ),
        timerFactory: (delay, callback) {
          expect(delay, const Duration(seconds: 15));
          return armed = _FakeTimer(callback);
        },
      );
    });

    void buffering() => watchdog.onPlayerStateChanged(
          isBuffering: true,
          isPlaying: true,
          isSuppressed: false,
        );

    test('does not report starvation while the budget has not elapsed', () {
      buffering();

      expect(armed, isNotNull);
      expect(starvedCount, 0);
    });

    test('reports starvation once the budget elapses', () {
      buffering();
      armed!.fire();

      expect(starvedCount, 1);
    });

    test('repeated buffering events do not restart the countdown', () {
      buffering();
      final first = armed;
      for (var i = 0; i < 5; i++) {
        buffering();
      }

      // 「連續 15 秒」是從進入 buffering 那一刻起算。每個事件都重置的話，
      // 一條穩定回報 buffering 的串流會讓這隻狗永遠不叫。
      expect(armed, same(first));
      expect(first!.cancelled, isFalse);
    });

    test('leaving buffering cancels the countdown', () {
      buffering();
      watchdog.onPlayerStateChanged(
        isBuffering: false,
        isPlaying: true,
        isSuppressed: false,
      );

      expect(armed!.cancelled, isTrue);
    });

    test('a suppressed player never arms the countdown', () {
      watchdog.onPlayerStateChanged(
        isBuffering: true,
        isPlaying: true,
        isSuppressed: true,
      );

      expect(armed, isNull);
    });

    test('a paused player never arms the countdown', () {
      watchdog.onPlayerStateChanged(
        isBuffering: true,
        isPlaying: false,
        isSuppressed: false,
      );

      expect(armed, isNull);
    });

    test('dispose cancels a running countdown', () {
      buffering();
      watchdog.dispose();

      expect(armed!.cancelled, isTrue);
    });
  });
}

class _FakeTimer implements PlaybackRecoveryTimer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool cancelled = false;

  void fire() => _callback();

  @override
  void cancel() => cancelled = true;
}
