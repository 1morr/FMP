import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/network/request_throttle.dart';

import '../../support/pump_until.dart';

void main() {
  late DateTime now;
  late List<Duration> waits;

  setUp(() {
    now = DateTime.utc(2026, 9, 29, 12);
    waits = [];
  });

  /// 假時鐘：等待立刻完成，並把時鐘往前撥。
  RequestThrottle throttle({
    int maxConcurrentRequests = 1,
    Duration minRequestInterval = Duration.zero,
  }) => RequestThrottle(
    RateLimitPolicy(
      maxConcurrentRequests: maxConcurrentRequests,
      minRequestInterval: minRequestInterval,
    ),
    now: () => now,
    wait: (duration) async {
      waits.add(duration);
      now = now.add(duration);
    },
  );

  test(
    'never more than the concurrency limit at once, first come first',
    () async {
      final subject = throttle(maxConcurrentRequests: 2);
      final slots = [for (var i = 0; i < 4; i++) subject.enqueue()];
      final granted = <int>[];
      for (final (index, slot) in slots.indexed) {
        slot.granted.then((_) => granted.add(index));
      }

      await settle();
      expect(granted, [0, 1]);

      slots[1].release();
      await pumpUntil(() => granted.length == 3);
      expect(granted, [0, 1, 2]);

      // 重複 release 不會多讓出一個位置。
      slots[1].release();
      await settle();
      expect(granted, [0, 1, 2]);

      slots[0].release();
      await pumpUntil(() => granted.length == 4);
      expect(granted, [0, 1, 2, 3]);
      expect(waits, isEmpty);
    },
  );

  test('starts are spaced by the minimum interval (fake clock)', () async {
    final start = now;
    final subject = throttle(
      maxConcurrentRequests: 5,
      minRequestInterval: const Duration(milliseconds: 400),
    );
    var granted = 0;
    for (var i = 0; i < 3; i++) {
      subject.enqueue().granted.then((_) => granted++);
    }

    await pumpUntil(() => granted == 3);
    // 第一個立刻開始，之後每個都等滿間隔；位置還夠，所以只受間隔限制。
    expect(waits, [
      const Duration(milliseconds: 400),
      const Duration(milliseconds: 400),
    ]);
    expect(now.difference(start), const Duration(milliseconds: 800));
  });

  test('no wait when the interval has already passed', () async {
    final subject = throttle(
      maxConcurrentRequests: 5,
      minRequestInterval: const Duration(seconds: 1),
    );
    subject.enqueue();
    now = now.add(const Duration(seconds: 2));
    var granted = false;
    subject.enqueue().granted.then((_) => granted = true);

    await pumpUntil(() => granted);
    expect(waits, isEmpty);
  });

  test('a clock set back waits at most one interval', () async {
    final subject = throttle(
      maxConcurrentRequests: 5,
      minRequestInterval: const Duration(seconds: 1),
    );
    subject.enqueue();
    now = now.subtract(const Duration(hours: 1));
    var granted = false;
    subject.enqueue().granted.then((_) => granted = true);

    await pumpUntil(() => granted);
    // 照原本的算法要等一小時一秒。
    expect(waits, [const Duration(seconds: 1)]);
  });

  test('releasing a queued slot removes it without taking a place', () async {
    final subject = throttle();
    final first = subject.enqueue();
    final cancelled = subject.enqueue();
    final third = subject.enqueue();
    var cancelledGranted = false;
    var thirdGranted = false;
    cancelled.granted.then((_) => cancelledGranted = true);
    third.granted.then((_) => thirdGranted = true);

    cancelled.release();
    first.release();
    await pumpUntil(() => thirdGranted);
    expect(cancelledGranted, isFalse);
  });

  test('a limit below one is rejected', () {
    expect(() => throttle(maxConcurrentRequests: 0), throwsRangeError);
  });
}
