// 實驗用（可丟棄）：flutter_js 對 probe_common 測項的實作。
//
// 一律用 QuickJsRuntime2，不用 getJavascriptRuntime()（它在 iOS／macOS 回 JavaScriptCore）。
// Android、Windows 用套件附的 QuickJS 二進位；iOS、macOS 用 packages/fmp_quickjs 自編的
// 同一份原始碼（android-js-runtimes 0.3.6）。
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';
import 'package:probe_common/probe_common.dart';
import 'package:probe_common/probe_common.dart' as js show asyncHostCall;

const flutterJsVersion = '0.8.7';

JavascriptRuntime? _keepDefault;

Object? _eval(QuickJsRuntime2 rt, String code) {
  final r = rt.evaluate(code);
  if (r.isError) throw StateError('js error: ${r.stringResult}');
  return r.rawResult;
}

/// QuickJsRuntime2 不會自己推進 Promise 的 job queue：輪詢 executePendingJob 直到 [f] 完成。
Future<T> _pump<T>(QuickJsRuntime2 rt, Future<T> f) async {
  rt.executePendingJob();
  final t = Timer.periodic(
    const Duration(milliseconds: 2),
    (_) => rt.executePendingJob(),
  );
  try {
    return await f;
  } finally {
    t.cancel();
  }
}

/// 背景 isolate：用套件的 timeout 選項跑無窮迴圈，回來就回報。
void _loopWithTimeout(SendPort reply) {
  final rt = QuickJsRuntime2(timeout: interruptAfter.inMilliseconds);
  final r = rt.evaluate(infiniteLoop);
  reply.send('evaluate returned (isError=${r.isError}): ${r.stringResult}');
}

void _spin(Object? _) => QuickJsRuntime2().evaluate(infiniteLoop);

String _cpuWorkInFreshRuntime() {
  final rt = QuickJsRuntime2();
  final v = rt.evaluate(cpuWork).stringResult;
  rt.dispose();
  return v;
}

class FlutterJsProbe implements Probe {
  @override
  String get candidate => 'flutter_js $flutterJsVersion';

  @override
  Future<Check> engineIdentity() async {
    final rt = QuickJsRuntime2();
    final fp = _eval(rt, jsFingerprint);
    final surface = _eval(rt, sandboxSurface);
    rt.dispose();
    // 套件預設的 runtime 是什麼（只記錄，不算分）。
    String defaultRuntime;
    try {
      // 不 dispose：在 macOS 上 dispose 後，套件 enableHandlePromises 的輪詢 timer 還會對已釋放的
      // JavaScriptCore context evaluate，行程 SIGSEGV（JSC::JSLockHolder，2026-11-11 實測）。
      _keepDefault = getJavascriptRuntime();
      defaultRuntime =
          '${_keepDefault.runtimeType}: ${_keepDefault!.evaluate(jsFingerprint).stringResult}';
    } catch (e) {
      defaultRuntime = 'threw $e';
    }
    return Check(
      'engine_identity',
      pass: '$fp'.startsWith('quickjs-like'),
      detail:
          'QuickJsRuntime2: $fp; globals: $surface; package default getJavascriptRuntime() = $defaultRuntime',
    );
  }

  @override
  Future<Check> interruptInfiniteLoop() async {
    // evaluate 是同步 FFI 呼叫，會卡住所在的 isolate：只能放背景 isolate。
    final reply = ReceivePort();
    final exited = ReceivePort();
    final replied = Completer<String>();
    final exitedC = Completer<void>();
    reply.listen((m) => replied.isCompleted ? null : replied.complete('$m'));
    exited.listen((_) => exitedC.isCompleted ? null : exitedC.complete());
    final sw = Stopwatch()..start();
    final iso = await Isolate.spawn(
      _loopWithTimeout,
      reply.sendPort,
      onExit: exited.sendPort,
    );

    final notes = <String>[];
    var pass = false;
    try {
      final m = await replied.future.timeout(interruptAfter + interruptBudget);
      final cpuAfter = await cpuMsDuring(cpuWindow);
      notes.add(
        'timeout option worked after ${sw.elapsedMilliseconds}ms: $m; CPU ${cpuAfter}ms in the next second',
      );
      pass = cpuAfter < cpuWindow.inMilliseconds ~/ 2;
    } on TimeoutException {
      notes.add(
        'timeout option (${interruptAfter.inMilliseconds}ms) did not interrupt: still running after '
        '${sw.elapsedMilliseconds}ms',
      );
      // 退路：殺掉 isolate。
      final cpuDuring = await cpuMsDuring(cpuWindow);
      iso.kill(priority: Isolate.immediate);
      var didExit = true;
      try {
        await exitedC.future.timeout(interruptBudget);
      } on TimeoutException {
        didExit = false;
      }
      final cpuAfter = await cpuMsDuring(cpuWindow);
      notes.add(
        'Isolate.kill(immediate): isolate ${didExit ? 'exited' : 'did not exit within ${interruptBudget.inSeconds}s'}; '
        'process CPU per ${cpuWindow.inMilliseconds}ms window: ${cpuDuring}ms while looping, ${cpuAfter}ms after kill',
      );
      pass = didExit && loopStopped(cpuDuring, cpuAfter);
      if (!pass) {
        notes.add(
          'the native thread keeps spinning for the rest of the process; '
          'loops after await or in timers were not measured because the '
          'top-level loop already cannot be stopped',
        );
      }
    } finally {
      reply.close();
      exited.close();
    }
    return Check(
      'interrupt_infinite_loop',
      pass: pass,
      ms: sw.elapsedMilliseconds,
      detail: notes.join('; '),
    );
  }

  @override
  Future<Check> memoryLimit() async {
    QuickJsRuntime2? rt;
    try {
      rt = QuickJsRuntime2(memoryLimit: memoryLimitBytes);
      // 上限在第一次 evaluate 時才設（_ensureEngine 查 jsSetMemoryLimit 符號）。
      final r = rt.evaluate(memoryHog);
      final outcome = r.isError
          ? 'threw: ${r.stringResult}'
          : 'returned: ${r.stringResult}';
      final after = rt.evaluate(sanity).stringResult;
      return Check(
        'memory_limit',
        pass: memoryLimited(outcome, after),
        detail:
            'limit ${memoryLimitBytes ~/ (1024 * 1024)} MiB; $outcome; same runtime afterwards 1+2=$after',
      );
    } catch (e) {
      return Check(
        'memory_limit',
        pass: false,
        detail: 'QuickJsRuntime2(memoryLimit:) threw: $e',
      );
    } finally {
      try {
        rt?.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<Check> awaitJsPromise() async {
    final rt = QuickJsRuntime2();
    try {
      final raw = _eval(rt, asyncReturn);
      if (raw is! Future) {
        return Check(
          'await_js_promise',
          pass: false,
          detail: 'rawResult is ${raw.runtimeType}, not Future',
        );
      }
      final v = await _pump(rt, raw);
      return Check(
        'await_js_promise',
        pass: v == 42,
        detail:
            'rawResult is a Dart Future (flutter_qjs wrapper); awaited with executePendingJob polling: $v',
      );
    } finally {
      rt.dispose();
    }
  }

  @override
  Future<Check> asyncHostCall() async {
    final rt = QuickJsRuntime2();
    try {
      // 沒有註冊 host function 的 API：拿一個 JS 函式回來，把 Dart 函式當參數傳進去。
      // wrapper 會把 Dart 回傳的 Future 轉成 JS Promise。
      final dynamic setter = _eval(rt, '(f) => { globalThis.hostDelay = f; }');
      // ignore: avoid_dynamic_calls -- JSInvokable 沒有從套件匯出
      setter.invoke([
        (dynamic ms, dynamic value) => Future<Object?>.delayed(
          Duration(milliseconds: (ms as num).toInt()),
          () => value,
        ),
      ]);
      // ignore: avoid_dynamic_calls -- 同上
      setter.free();
      final raw = _eval(rt, js.asyncHostCall);
      if (raw is! Future) {
        return Check(
          'async_host_call',
          pass: false,
          detail: 'rawResult is ${raw.runtimeType}',
        );
      }
      final (v, stall) = await measureStall(() => _pump(rt, raw));
      return Check(
        'async_host_call',
        pass: v == 'pong!',
        detail:
            'Dart function passed into JS, its Future became a JS Promise: $v; '
            'needs executePendingJob polling; caller isolate worst stall ${stall}ms',
      );
    } finally {
      rt.dispose();
    }
  }

  @override
  Future<Check> stuckEngineIsolation() async {
    // 每個 runtime 在自己的 isolate：卡住的只有那條原生執行緒。這幾條殺不掉，會空轉到行程結束。
    for (var i = 0; i < stuckEngines; i++) {
      await Isolate.spawn(_spin, null);
    }
    await Future<void>.delayed(interruptAfter);
    final sw = Stopwatch()..start();
    try {
      final v = await Isolate.run(
        () => QuickJsRuntime2().evaluate(sanity).stringResult,
      ).timeout(stuckBudget);
      return Check(
        'stuck_engine_isolation',
        pass: v == '3',
        detail:
            'while $stuckEngines isolates spin in while(true): a runtime in another '
            'isolate evaluated 1+2=$v in ${sw.elapsedMilliseconds}ms '
            '(the spinning threads cannot be stopped)',
      );
    } on TimeoutException {
      return Check(
        'stuck_engine_isolation',
        pass: false,
        detail:
            'another isolate did not answer within ${stuckBudget.inSeconds}s',
      );
    }
  }

  @override
  Future<Check> isolateLayout() async {
    final notes = <String>[];
    var pass = true;

    final createSw = Stopwatch()..start();
    final rt = QuickJsRuntime2();
    _eval(rt, sanity);
    notes.add('create + first eval: ${createSw.elapsedMilliseconds}ms');
    final (soloMs, mainStall) = await measureStall(() async {
      final sw = Stopwatch()..start();
      _eval(rt, cpuWork);
      return sw.elapsedMilliseconds;
    });
    rt.dispose();
    notes.add(
      'cpu work on the caller isolate: ${soloMs}ms, caller stalled ${mainStall}ms (evaluate is synchronous)',
    );

    try {
      final oneSw = Stopwatch()..start();
      await Isolate.run(_cpuWorkInFreshRuntime);
      final oneMs = oneSw.elapsedMilliseconds;
      final (_, stall) = await measureStall(() async {
        final sw = Stopwatch()..start();
        await Future.wait(
          List.generate(4, (_) => Isolate.run(_cpuWorkInFreshRuntime)),
        );
        notes.add(
          'background isolates: 1 runtime ${oneMs}ms, 4 runtimes in 4 isolates ${sw.elapsedMilliseconds}ms',
        );
      });
      notes.add('main isolate worst stall during 4-isolate work: ${stall}ms');
    } catch (e) {
      pass = false;
      notes.add('background isolate failed: $e');
    }
    return Check('isolate_layout', pass: pass, detail: notes.join('; '));
  }
}
