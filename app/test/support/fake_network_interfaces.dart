import 'dart:async';

import 'package:fmp/platform/connectivity/connectivity.dart';

/// 測試用的網路介面：預設有介面，[change] 模擬系統回報介面改變。
final class FakeNetworkInterfaces implements NetworkInterfaces {
  FakeNetworkInterfaces({this.available = true});

  /// [check] 回答的值。
  bool available;

  /// [check] 被呼叫的次數。
  int checks = 0;

  final _changes = StreamController<bool>.broadcast(sync: true);

  @override
  Future<bool> check() async {
    checks++;
    return available;
  }

  @override
  Stream<bool> get changes => _changes.stream;

  /// 系統回報介面改變成 [available]。同步送出。
  void change({required bool available}) {
    this.available = available;
    _changes.add(available);
  }
}
