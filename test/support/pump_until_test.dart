import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

void main() {
  group('pumpUntil', () {
    test('a fixed pump count is not a synchronisation point', () async {
      var late = false;
      final timer = Timer(const Duration(seconds: 3), () => late = true);
      addTearDown(timer.cancel);

      // 10 圈事件迴圈就是 10 個零延遲的 Timer，跑完是微秒等級的事 —— 不可能等到
      // 一個 3 秒後才到期的計時器。這條斷言的方向是確定的（事件迴圈不會自己耗掉
      // 3 秒），而它守的正是 issue #43 / #55 那個形狀。
      await pumpEventQueue(times: 10);

      expect(late, isFalse);
    });

    test('waits for a real timer', () async {
      var fired = false;
      Timer(const Duration(milliseconds: 50), () => fired = true);

      await pumpUntil(() => fired, reason: 'the 50ms timer should fire');

      expect(fired, isTrue);
    });

    test('returns without waiting when the condition already holds', () async {
      // timeout 是 0，所以迴圈一圈都跑不到；能過就代表它沒有先等再檢查。
      await pumpUntil(
        () => true,
        reason: 'an already-true condition',
        timeout: Duration.zero,
      );
    });

    test('fails with the reason when the condition never holds', () async {
      await expectLater(
        pumpUntil(
          () => false,
          reason: 'a condition that never holds',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('a condition that never holds'),
          ),
        ),
      );
    });
  });

  group('drainEventQueue', () {
    test('lets already-queued work run', () async {
      var ran = false;
      unawaited(Future<void>.microtask(() => ran = true));

      await drainEventQueue(reason: 'queued microtasks should have run');

      expect(ran, isTrue);
    });
  });
}
