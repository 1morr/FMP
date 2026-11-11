/// 實驗用（可丟棄）：JS 引擎實驗兩個候選共用的測項與回報格式。
///
/// 每個候選的 probe app 各自實作 [Probe]，交給 [runProbe] 跑。結果由 `probe_app.dart`
/// 寫成 JSON 檔並印出 `PROBE_FILE <路徑>`，`run.sh` 依路徑取回存到 `results/`。
library;

import 'dart:async';
import 'dart:convert';

export 'cpu_time.dart';

/// 一項檢查的結果。
class Check {
  Check(this.id, {required this.pass, required this.detail, this.ms});

  final String id;
  final bool pass;
  final String detail;
  final int? ms;

  Map<String, Object?> toJson() => {
    'id': id,
    'pass': pass,
    'detail': detail,
    if (ms != null) 'ms': ms,
  };
}

/// 每個候選要回答的問題。全部在呼叫端的 isolate 裡跑；要不要另開 isolate 是候選自己的事，
/// 要寫在 [Check.detail] 裡。
abstract interface class Probe {
  /// 候選名稱與版本，例如 `fjs 2.0.0`。`summarize.py` 會和 pubspec.lock 對照。
  String get candidate;

  /// 標準 1：這個平台實際用的引擎。回報套件的 runtime 型別與 JS 端的指紋（[jsFingerprint]）。
  Future<Check> engineIdentity();

  /// 標準 2：[infiniteLoop]（以及 [loopAfterAwait]、[loopInTimer]）在 [interruptAfter] 後被中斷，
  /// 原生執行緒真的停了（[loopStopped]），之後同一個或重建的引擎還能用。
  Future<Check> interruptInfiniteLoop();

  /// 標準 3：設 [memoryLimitBytes] 上限後跑 [memoryHog]，拿到可捕捉的錯誤而不是行程崩潰。
  Future<Check> memoryLimit();

  /// 標準 4a：Dart 端 await JS 回傳的 Promise（[asyncReturn] 應得 42）。
  Future<Check> awaitJsPromise();

  /// 標準 4b：JS await Dart 提供的 async 函式 `hostDelay(ms, value)`，[asyncHostCall] 應得 `"pong!"`。
  Future<Check> asyncHostCall();

  /// isolate 配置的量測：建立一個引擎要多久、能不能在背景 isolate 用、能不能同時開多個。
  Future<Check> isolateLayout();

  /// isolate 配置的量測：[stuckEngines] 個引擎卡在無窮迴圈時，另一個引擎還能在
  /// [stuckBudget] 內算出 [sanity]（一個插件卡住不能拖垮其他插件）。
  Future<Check> stuckEngineIsolation();
}

/// QuickJS 的 stack 一行是 `    at f (<eval>:1)`，JavaScriptCore 是 `f@`。
const jsFingerprint = '''
(function () {
  function probeFrame() { return new Error('x').stack || ''; }
  var s = String(probeFrame()).split('\\n')[0];
  var engine = /^\\s*at /.test(s) ? 'quickjs-like (V8/QuickJS stack format)'
             : /@/.test(s) ? 'jsc-like (JavaScriptCore stack format)'
             : 'unknown';
  return engine + ' | first frame: ' + s.trim();
})()
''';

const infiniteLoop = 'while (true) {}';

/// 插件的迴圈多半在 await 之後（等完網路回應才開始算）。
const loopAfterAwait =
    '(async () => { await Promise.resolve(); while (true) {} })()';

/// 迴圈在 timer 回呼裡：eval 本身已經回來，迴圈在背景跑。
const loopInTimer = "setTimeout(() => { while (true) {} }, 0); 'scheduled'";

/// 卡住的引擎數（第一版有四個插件）與另一個引擎的回應上限。
const stuckEngines = 4;
const stuckBudget = Duration(seconds: 5);
const interruptAfter = Duration(milliseconds: 500);

/// 中斷超過這個時間才回來就算失敗（含引擎回收）。
const interruptBudget = Duration(seconds: 3);

const memoryLimitBytes = 32 * 1024 * 1024;

/// 不斷配置，直到被上限擋下，結果是錯誤訊息。總量封頂在約 160 塊（QuickJS 一個值 16 bytes，
/// 一塊約 1.6 MB，共約 256 MB）：沒被擋住時回 `not limited`，而不是讓行程被系統殺掉、拿不到結果。
const memoryHog = '''
(function () {
  var keep = [];
  try {
    for (var i = 0; i < 160; i++) keep.push(new Array(1e5).fill(i));
    return 'not limited: allocated ' + keep.length + ' chunks';
  } catch (e) {
    keep = null;
    return 'caught: ' + e;
  }
})()
''';

const asyncReturn =
    '(async () => { await null; await Promise.resolve(); return 42; })()';

const asyncHostCall = '''
(async () => {
  const r = await hostDelay(50, 'pong');
  return r + '!';
})()
''';

/// 插件不該看得到的全域：任意聯網、模組載入、行程資訊。回報每個的 typeof。
const sandboxSurface = '''
['fetch', 'XMLHttpRequest', 'WebSocket', 'require', 'process', 'Deno', 'std', 'os']
  .map(function (n) { return n + ':' + typeof globalThis[n]; }).join(' ')
''';

/// isolate_layout 的 CPU 工作。
const cpuWork = 'let s = 0; for (let i = 0; i < 1e7; i++) s += i; s';

/// 中斷後用來確認引擎還能用。
const sanity = '1 + 2';

/// 記憶體上限有效：JS 拿到 out of memory（不是別的錯誤），而且同一個引擎之後還能算 [sanity]。
bool memoryLimited(String outcome, Object? sanityAfter) =>
    outcome.toLowerCase().contains('out of memory') &&
    '$sanityAfter' == '3';

/// 以 10 ms 的 timer 量呼叫端 isolate 有沒有被卡住：回傳 [action] 期間最長的 tick 間隔。
Future<(T, int)> measureStall<T>(Future<T> Function() action) async {
  var last = DateTime.now();
  var worst = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final now = DateTime.now();
    final gap = now.difference(last).inMilliseconds;
    if (gap > worst) worst = gap;
    last = now;
  });
  try {
    final result = await action();
    final gap = DateTime.now().difference(last).inMilliseconds;
    if (gap > worst) worst = gap;
    return (result, worst);
  } finally {
    timer.cancel();
  }
}

/// 跑完全部檢查，每項有自己的逾時；印出 `PROBE_RESULT` 並回傳同一份 JSON。
Future<Map<String, Object?>> runProbe(
  Probe probe, {
  required String platform,
  Duration perCheckTimeout = const Duration(seconds: 120),
}) async {
  final checks = <String, Future<Check> Function()>{
    'engine_identity': probe.engineIdentity,
    'memory_limit': probe.memoryLimit,
    'await_js_promise': probe.awaitJsPromise,
    'async_host_call': probe.asyncHostCall,
    'isolate_layout': probe.isolateLayout,
    // 下面兩項中斷不了的候選會留下空轉的原生執行緒，放最後才不會污染前面的計時。
    'interrupt_infinite_loop': probe.interruptInfiniteLoop,
    'stuck_engine_isolation': probe.stuckEngineIsolation,
  };
  final results = <Map<String, Object?>>[];
  for (final MapEntry(key: id, value: run) in checks.entries) {
    final sw = Stopwatch()..start();
    Check check;
    try {
      check = await run().timeout(perCheckTimeout);
    } on TimeoutException {
      check = Check(
        id,
        pass: false,
        detail: 'harness timeout after $perCheckTimeout',
      );
    } catch (e, st) {
      check = Check(id, pass: false, detail: 'threw: $e\n$st');
    }
    final json = check.toJson()
      ..putIfAbsent('ms', () => sw.elapsedMilliseconds);
    results.add(json);
    // ignore: avoid_print -- 實驗輸出就是 log
    print('PROBE_CHECK ${jsonEncode(json)}');
  }
  final report = {
    'candidate': probe.candidate,
    'platform': platform,
    'at': DateTime.now().toUtc().toIso8601String(),
    'checks': results,
  };
  // ignore: avoid_print -- 實驗輸出就是 log
  print('PROBE_RESULT ${jsonEncode(report)}');
  return report;
}

/// 中斷後量 CPU 的時間窗。迴圈在跑時這段約等於 1000 ms，停了應該接近 0。
const cpuWindow = Duration(seconds: 1);

/// 迴圈真的停了：中斷後一個 [cpuWindow] 的行程 CPU 比迴圈在跑時少了至少半顆核心。
/// 用相對值是因為模擬器的 CPU 很吵，絕對門檻在桌面與模擬器上不能共用。
bool loopStopped(int cpuWhileLooping, int cpuAfterInterrupt) =>
    cpuWhileLooping >= 0 &&
    cpuAfterInterrupt >= 0 &&
    cpuWhileLooping - cpuAfterInterrupt >= cpuWindow.inMilliseconds ~/ 2;
