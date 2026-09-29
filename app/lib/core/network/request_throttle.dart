import 'dart:async';
import 'dart:collection';

import 'package:fmp/core/errors/retry_policy.dart';

/// 一個插件的請求排程：同時進行中的請求不超過
/// [RateLimitPolicy.maxConcurrentRequests]，兩次開始之間至少隔
/// [RateLimitPolicy.minRequestInterval]（ADR 0013 §決定 4：事先避開限流）。
///
/// 先來先開始。時鐘與等待由外面注入，測試才能固定。
final class RequestThrottle {
  RequestThrottle(this.policy, {required this._now, required this._wait}) {
    if (policy.maxConcurrentRequests < 1) {
      throw RangeError.value(
        policy.maxConcurrentRequests,
        'maxConcurrentRequests',
        'must be at least 1',
      );
    }
  }

  final RateLimitPolicy policy;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  final _queue = Queue<ThrottleSlot>();
  int _active = 0;
  DateTime? _lastStart;
  bool _waitingForInterval = false;

  /// 排進佇列。拿到的 [ThrottleSlot] 在 [ThrottleSlot.granted] 完成時可以
  /// 開始；請求結束（成功、失敗或取消）時一定要 [ThrottleSlot.release]。
  ThrottleSlot enqueue() {
    final slot = ThrottleSlot._(this);
    _queue.add(slot);
    _pump();
    return slot;
  }

  void _pump() {
    if (_waitingForInterval) return;
    while (_queue.isNotEmpty && _active < policy.maxConcurrentRequests) {
      final now = _now();
      // 時鐘往回撥（使用者改時間、NTP 校正）時上次開始會在未來，照算要等到
      // 時鐘追上；改從現在起算，最多等一個間隔，不讓整個插件卡住。
      if (_lastStart case final last? when now.isBefore(last)) {
        _lastStart = now;
      }
      if (_lastStart?.add(policy.minRequestInterval) case final ready?
          when now.isBefore(ready)) {
        _waitingForInterval = true;
        unawaited(
          _wait(ready.difference(now)).whenComplete(() {
            _waitingForInterval = false;
            _pump();
          }),
        );
        return;
      }
      final slot = _queue.removeFirst();
      _active++;
      _lastStart = now;
      slot._state = _SlotState.granted;
      slot._granted.complete();
    }
  }

  void _release(ThrottleSlot slot) {
    switch (slot._state) {
      case _SlotState.queued:
        // 還在排隊就結束了（被取消）：移出佇列，[ThrottleSlot.granted]
        // 永遠不會完成，等它的人已經不在了。
        _queue.remove(slot);
      case _SlotState.granted:
        _active--;
        _pump();
      case _SlotState.released:
        return;
    }
    slot._state = _SlotState.released;
  }
}

enum _SlotState { queued, granted, released }

/// [RequestThrottle] 裡的一個位置。
final class ThrottleSlot {
  ThrottleSlot._(this._throttle);

  final RequestThrottle _throttle;
  final _granted = Completer<void>();
  _SlotState _state = _SlotState.queued;

  /// 輪到這個請求時完成。
  Future<void> get granted => _granted.future;

  /// 請求結束：還在排隊就移出佇列，已經開始就讓出位置。重複呼叫沒有作用。
  void release() => _throttle._release(this);
}
