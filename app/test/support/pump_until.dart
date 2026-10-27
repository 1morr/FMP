import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// 讓事件佇列跑到 [condition] 成立為止；跑了 [maxRounds] 輪仍不成立就失敗。
///
/// 測試裡等非同步進度只用這裡的助手（lint `fmp_test_waits`），不直接呼叫
/// `pumpEventQueue`，也不用實際時間的 `Future.delayed`。
///
/// 只等主 isolate 自己的工作（假的 adapter、microtask、`Future`）：輪數上限只量得到
/// 主 isolate 跑了幾輪，量不到別的執行緒。條件要靠事件迴圈以外的進度（drift 的背景
/// isolate、`dart:io` 的檔案操作、插件的背景 isolate）才成立時，負載下 20 輪只有幾毫秒，
/// 會在那邊做完之前就失敗：有事件可等就等事件（例如 `FakeHttpAdapter.received`），
/// 沒有就用 [pollUntil]。
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

/// 等 [condition] 成立，上限是實際時間 [timeout]。
///
/// 給要靠事件迴圈以外的進度才成立、又沒有事件可等的條件（例如 flutter_cache_manager 沒等的
/// 索引寫入、dio 開出來的暫存檔）：那些進度的快慢由別的執行緒與 I/O 決定，和主 isolate 跑了
/// 幾輪無關，所以不數輪數。每次檢查之間讓出幾毫秒的實際時間，不空轉搶 CPU。
/// 只在 `test()`（實際時間）裡用；`testWidgets` 的假時間 zone 裡要包在 `tester.runAsync`。
Future<void> pollUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final elapsed = Stopwatch()..start();
  while (!await condition()) {
    if (elapsed.elapsed > timeout) {
      fail(reason ?? 'condition never became true within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// 讓事件佇列跑完目前排著的工作（斷言「什麼都沒發生」之前用）。
Future<void> settle() => pumpEventQueue();
