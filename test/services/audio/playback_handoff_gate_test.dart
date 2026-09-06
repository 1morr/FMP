import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/playback_handoff_gate.dart';

/// `PlaybackHandoffGate` 是 Phase 4 步驟 C 抽出來的協作者，擁有「控制器正在交接
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

    setUp(() {
      seeks = [];
      trackKey = 'track-a';
      supersededRequests = {};
      gate = PlaybackHandoffGate(
        currentTrackKey: () => trackKey,
        performSeek: (position) async => seeks.add(position),
        isRequestSuperseded: supersededRequests.contains,
        stabilizationDelay: stabilization,
      );
    });

    /// future 完成了沒。作廢路徑漏掉 `complete()` 的話這裡會是 false。
    Future<bool> settled(Future<void> future) async {
      var done = false;
      unawaited(future.then((_) => done = true));
      await pumpEventQueue(times: 10);
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

    test('a seek right after navigation waits out the stabilization window',
        () async {
      gate.startStabilizationWindow(7, 'track-a');
      final deferred = gate.deferSeek(const Duration(seconds: 120))!;

      expect(await settled(deferred), isFalse);
      expect(seeks, isEmpty);

      await deferred;

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

    test('discardPending scoped to a request ignores another request',
        () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      gate.discardPending(requestId: 8, reason: 'wrong request');
      expect(await settled(deferred), isFalse);

      gate.discardPending(requestId: 7, reason: 'right request');
      expect(await settled(deferred), isTrue);
      expect(seeks, isEmpty);
    });

    test('isCurrent tracks the latch, not the session generation', () {
      gate.beginRequest(7);
      expect(gate.isCurrent(7), isTrue);
      expect(gate.isCurrent(8), isFalse);

      gate.endRequest();
      // 交接結束後閂存歸零，即使 session 那邊 7 仍是最新的一次請求。
      expect(gate.isCurrent(7), isFalse);
      expect(supersededRequests.contains(7), isFalse);
    });

    test('dispose completes an outstanding seek instead of stranding it',
        () async {
      gate.beginRequest(7);
      final deferred = gate.deferSeek(const Duration(seconds: 30))!;

      gate.dispose();

      expect(await settled(deferred), isTrue);
      expect(seeks, isEmpty);
    });
  });
}
