import 'dart:async';

/// 「呼叫次數達到 N」的等待清單。
///
/// 假物件用它讓測試等到「呼叫真的發生了」，而不是猜幾圈事件迴圈夠不夠
/// （見 `test/support/pump_until.dart` 與 issue #43）。次數只增不減，所以等待
/// 不會錯過某個瞬間 —— 這是它比條件式輪詢更適合「呼叫次數」的地方。
class CountWaiters {
  CountWaiters(this._count);

  /// 目前的呼叫次數。
  final int Function() _count;

  final List<_Waiter> _waiters = [];

  /// 等到呼叫次數達到 [target]。已經達到就立刻返回。
  Future<void> waitFor(int target) {
    if (_count() >= target) return Future.value();
    final completer = Completer<void>();
    _waiters.add(_Waiter(target, completer));
    return completer.future;
  }

  /// 記錄完一次呼叫之後叫它。
  void notify() {
    for (final waiter in List<_Waiter>.from(_waiters)) {
      if (_count() >= waiter.target && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
  }
}

class _Waiter {
  _Waiter(this.target, this.completer);

  final int target;
  final Completer<void> completer;
}
