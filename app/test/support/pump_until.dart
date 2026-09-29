import 'package:flutter_test/flutter_test.dart';

/// 讓事件佇列跑到 [condition] 成立為止；跑了 [maxRounds] 輪仍不成立就失敗。
///
/// 測試裡等非同步進度只用這裡的助手（lint `fmp_test_waits`），不直接呼叫
/// `pumpEventQueue`，也不用實際時間的 `Future.delayed`。
Future<void> pumpUntil(
  bool Function() condition, {
  int maxRounds = 20,
  String? reason,
}) async {
  for (var round = 0; round < maxRounds; round++) {
    if (condition()) return;
    await pumpEventQueue();
  }
  expect(condition(), isTrue, reason: reason ?? 'condition never became true');
}

/// 讓事件佇列跑完目前排著的工作（斷言「什麼都沒發生」之前用）。
Future<void> settle() => pumpEventQueue();
