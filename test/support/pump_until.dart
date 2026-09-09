import 'package:flutter_test/flutter_test.dart';

/// 開頭「只推事件迴圈、不睡」的輪數上限。
///
/// 沿用被它取代的那些區域 helper 的 `maxPumps = 50`；一輪是
/// `pumpEventQueue()` 的 20 圈，所以是 1000 圈事件迴圈。
const _busyRounds = 50;

/// 等到 [condition] 成立為止，最多等 [timeout]。
///
/// 取代 `await pumpEventQueue(times: N)` 之後緊接斷言的寫法。`times` 數的是事件
/// 迴圈的圈數 —— `pumpEventQueue` 每一圈只是排一個零延遲的 `Timer`，而圈數換不到
/// 「進度」：背景 I/O、Isar 交易與真計時器什麼時候完成跟圈數無關。機器滿載時
/// 同樣的圈數換到的進度更少，正向斷言就落在還沒收斂的狀態上（issue #43）；反過來
/// 同樣的圈數耗掉的牆鐘時間更多，「還沒發生」的斷言就會提早成立（issue #55）。
/// 兩個方向壞在相反的地方，所以把圈數調大不是修，只是把競態換一邊 —— 這裡改用
/// 牆鐘期限。
///
/// **[condition] 必須是「進入時還不成立」的東西。** 一進來就成立的條件會讓這個
/// 函式立刻返回、一圈都沒推，比它取代掉的固定圈數**更少**推進；那不是等待。
///
/// 等的方式分兩段，兩段都是量出來的，不是選出來的：
///
/// - 前 [_busyRounds] 輪用 `pumpEventQueue()`，**不耗牆鐘時間**。睡覺會讓真計時器
///   提早到期，本身就會改變被測程式的行為，而且會整段錯過只存在幾圈的瞬間狀態。
/// - 一輪是完整的 `pumpEventQueue()`（20 圈），不是一圈。改成一圈一檢查會讓等待
///   在更早的時點返回，而呼叫端的下一步就落在不同的交錯上 ——
///   `audio_controller_handoff_and_errors_test` 的「superseded source error」那條會因此卡死。
///   20 圈是套件裡既有區域 helper 一直在用的粒度。
/// - 之後改成睡 10ms。走到這裡通常是在等一個真計時器，熱迴圈只會讓滿載的機器
///   更慢，而這正是本來要修的病。
///
/// [reason] 是必填的：逾時訊息是這個 helper 唯一的產出，寫「在等什麼」而不是
/// 「等待失敗了」。
///
/// 條件一成立就返回，所以放寬 [timeout] 不會讓任何原本會過的測試變慢。預設的
/// 5 秒遠低於 `test` 的 30 秒預設逾時，逾時訊息因此留得下來。
Future<void> pumpUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  var round = 0;
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    if (round++ < _busyRounds) {
      await pumpEventQueue();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
  if (!condition()) fail('timed out after $timeout waiting: $reason');
}

/// 推進事件佇列固定圈數，給「某件事**不該**發生」的斷言用。
///
/// 條件式等待對這種斷言沒有意義 —— 條件在第 0 圈就成立，[pumpUntil] 會立刻返回，
/// 什麼都沒等到。首選是先用 [pumpUntil] 等一個**排在它之後**的里程碑，再斷言那件事
/// 沒發生；真的找不到里程碑時才用這個，並在 [reason] 寫下它替代的是什麼。
///
/// [reason] 只有人會讀。它的作用是讓 `rg drainEventQueue` 一次列出全部「我們知道
/// 自己在斷言缺席」的地方 —— 註解做不到這件事。
Future<void> drainEventQueue({required String reason, int times = 20}) {
  assert(reason.isNotEmpty, 'drainEventQueue needs a reason');
  return pumpEventQueue(times: times);
}
