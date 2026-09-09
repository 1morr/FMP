import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/playback_handoff_gate.dart';

import '../../support/pump_until.dart';

/// `PlaybackHandoffGate` 擁有「控制器正在交接
/// 一次播放請求」這段期間的狀態：載入閂存、延後中的 seek、切歌後的穩定化視窗。
///
/// 這裡大半的測試在守同一件事：**任何一條作廢路徑都必須 `complete()`**。
/// `AudioController.seekTo` 會 await 這個 future，漏掉一條就是使用者拖進度條之後
/// 那個 await 永遠回不來。
void main() {
  group('PlaybackHandoffGate', () {
    late List<Duration> seeks;
    late String? trackKey;
    late Set<int> supersededRequests;
    late PlaybackHandoffGate gate;

    const stabilization = Duration(milliseconds: 40);

    void buildGate({Duration stabilizationDelay = stabilization}) {
      gate = PlaybackHandoffGate(
        currentTrackKey: () => trackKey,
        performSeek: (position) async => seeks.add(position),
        isRequestSuperseded: supersededRequests.contains,
        stabilizationDelay: stabilizationDelay,
      );
    }

    setUp(() {
      seeks = [];
      trackKey = 'track-a';
      supersededRequests = {};
      buildGate();
    });

    /// future 完成了沒。作廢路徑漏掉 `complete()` 的話這裡會是 false。
    ///
    /// 「還沒完成」等不到，只能推完在途工作再看 —— 所以這裡是刻意的固定圈數。
    /// 呼叫端有責任確保「完成」不是靠一個真計時器：圈數耗掉的牆鐘時間在滿載的
    /// 機器上會超過那個計時器，那正是 issue #55。
    Future<bool> settled(Future<void> future) async {
      var done = false;
      unawaited(future.then((_) => done = true));
      await drainEventQueue(
        reason: 'let any completion of the deferred seek land',
      );
      return done;
    }

    test('an idle gate sends the seek straight through', () {
      expect(gate.deferSeek(const Duration(seconds: 30)), isNull);
      expect(gate.isLoading, isFalse);
      expect(seeks, isEmpty); // 呼叫端自己送，gate 只說「不用延後」
    });

    test('a seek during a handoff waits for the request to be ready', () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30));

      expect(deferred, isNotNull);
      expect(gate.isLoading, isTrue);
      expect(await settled(deferred!), isFalse);
      expect(seeks, isEmpty);

      gate.endRequest();
      gate.applyPendingIfCurrent(7);
      await deferred;

      expect(seeks, [const Duration(seconds: 30)]);
    });

    test('a newer seek replaces the older one without stranding it', () async {
      gate.beginRequest(7);
      final first = gate.deferSeek(const Duration(seconds: 30))!;
      final second = gate.deferSeek(const Duration(seconds: 90))!;

      // 舊的那次被作廢，但呼叫端仍然等得到它。
      expect(await settled(first), isTrue);

      gate.applyPendingIfCurrent(7);
      await second;

      expect(seeks, [const Duration(seconds: 90)]);
    });

    test('a seek left over from a superseded handoff is dropped', () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      supersededRequests.add(7);
      gate.applyPendingIfCurrent(7);
      await deferred;

      expect(seeks, isEmpty);
    });

    test('a seek is dropped when the track changed underneath it', () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      trackKey = 'track-b';
      gate.applyPendingIfCurrent(7);
      await deferred;

      expect(seeks, isEmpty);
    });

    // 這裡本來是一條測試，同時守「視窗內延後」與「視窗過後送出」，而它用固定
    // 圈數的 pump 去斷言前者 —— 圈數耗掉的時間一超過 40ms 視窗，seek 就已經送出
    // 去了（issue #55）。拆成兩條之後，兩邊各自不再跟時間賽跑。
    test('a seek inside the stabilization window stays deferred', () async {
      // 視窗長到任何 pump 預算都追不上，「還沒送出」因此不是時序的巧合。
      buildGate(stabilizationDelay: const Duration(seconds: 30));
      gate.startStabilizationWindow(7, 'track-a');
      final deferred = gate.deferSeek(const Duration(seconds: 120))!;

      expect(await settled(deferred), isFalse);
      expect(seeks, isEmpty);

      // 別讓延後中的 seek 掛在那裡跨過測試邊界。
      gate.cancel(reason: 'test finished');
      await deferred;
    });

    test('a seek is sent once the stabilization window passes', () async {
      // 500ms 不是「夠快」而是「夠慢」：`deferSeek` 只要在視窗還開著的時候被呼叫
      // 到就行，而它就在下一行。壓到 1ms 反而讓視窗可能先關掉、`deferSeek` 回 null
      // —— 本輪的壓力跑 20 次抓到 1 次，是同一種競態換了個方向。
      buildGate(stabilizationDelay: const Duration(milliseconds: 500));
      gate.startStabilizationWindow(7, 'track-a');
      final deferred = gate.deferSeek(const Duration(seconds: 120))!;

      await deferred;
      await pumpUntil(
        () => seeks.isNotEmpty,
        reason: 'the deferred seek should be sent after the window',
      );

      expect(seeks, [const Duration(seconds: 120)]);
      // 視窗過了之後就不再延後。
      expect(gate.deferSeek(const Duration(seconds: 5)), isNull);
    });

    test('the stabilize-next flag survives beginRequest but not cancel', () {
      // next()/previous()/playAt() 設下旗標，_executePlayRequest 才取用 ——
      // 中間會經過 beginRequest，它刻意不能把旗標吃掉。
      gate.requestStabilizationForNextRequest();
      gate.prepareForRequest(reason: 'new playback request started');
      gate.beginRequest(7);
      expect(gate.consumeStabilizationForNextRequest(), isTrue);
      expect(gate.consumeStabilizationForNextRequest(), isFalse);

      gate.requestStabilizationForNextRequest();
      gate.cancel(reason: 'queue playback started');
      expect(gate.consumeStabilizationForNextRequest(), isFalse);
    });

    test('cancel clears the latch, the pending seek and the window', () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      gate.cancel(reason: 'queue playback started');

      expect(gate.isLoading, isFalse);
      expect(gate.activeRequestId, 0);
      expect(await settled(deferred), isTrue);
      expect(seeks, isEmpty);
    });

    test('cancelDeferredSeeks leaves the latch alone', () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      // stop() 走這條：丟掉 seek，但不假裝交接結束了。
      gate.cancelDeferredSeeks(reason: 'playback stopped');

      expect(gate.isLoading, isTrue);
      expect(gate.isCurrent(7), isTrue);
      expect(await settled(deferred), isTrue);
      expect(seeks, isEmpty);
    });

    test(
      'discardPending scoped to a request ignores another request',
      () async {
        gate.beginRequest(7);
        final deferred = gate.deferSeek(const Duration(seconds: 30))!;

        gate.discardPending(requestId: 8, reason: 'wrong request');
        expect(await settled(deferred), isFalse);

        gate.discardPending(requestId: 7, reason: 'right request');
        expect(await settled(deferred), isTrue);
        expect(seeks, isEmpty);
      },
    );

    test('isCurrent tracks the latch, not the session generation', () {
      gate.beginRequest(7);
      expect(gate.isCurrent(7), isTrue);
      expect(gate.isCurrent(8), isFalse);

      gate.endRequest();
      // 交接結束後閂存歸零，即使 session 那邊 7 仍是最新的一次請求。
      expect(gate.isCurrent(7), isFalse);
      expect(supersededRequests.contains(7), isFalse);
    });

    test(
      'dispose completes an outstanding seek instead of stranding it',
      () async {
        gate.beginRequest(7);
        final deferred = gate.deferSeek(const Duration(seconds: 30))!;

        gate.dispose();

        expect(await settled(deferred), isTrue);
        expect(seeks, isEmpty);
      },
    );
  });
}
