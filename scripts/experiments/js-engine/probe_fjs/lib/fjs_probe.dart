// 實驗用（可丟棄）：fjs 對 probe_common 測項的實作。
import 'dart:async';
import 'dart:isolate';

import 'package:fjs/fjs.dart';
import 'package:probe_common/probe_common.dart';
import 'package:probe_common/probe_common.dart' as js show asyncHostCall;

const fjsVersion = '3.3.2';

// 插件只拿到宿主 API：不開 fs、net、fetch、child_process 這類 llrt 內建模組。
// timers 要開，Promise 與 setTimeout 才有 driver。
const _builtins = JsBuiltinOptions(timers: true, console: true);

Future<JsEngine> _engine({int? memoryLimit, bool bridge = false}) async {
  final engine = await JsEngine.create(
    builtins: _builtins,
    runtimeOptions: JsEngineRuntimeOptions(
      memoryLimit: memoryLimit == null ? null : BigInt.from(memoryLimit),
    ),
  );
  if (bridge) {
    // fjs 只有單一 bridge：JS 端 `fjs.bridge_call(value)`，Dart 端自己分派。
    await engine.init(
      bridge: (v) async {
        final m = v.value as Map;
        if (m['fn'] == 'hostDelay') {
          final args = m['args'] as List;
          await Future<void>.delayed(
            Duration(milliseconds: (args[0] as num).toInt()),
          );
          return JsResult.ok(JsValue.from(args[1]));
        }
        return JsResult.err(JsError.bridge('unknown host fn ${m['fn']}'));
      },
    );
    await engine.eval(
      source: const JsCode.code(
        "globalThis.hostDelay = (ms, value) => fjs.bridge_call({ fn: 'hostDelay', args: [ms, value] });",
      ),
    );
  } else {
    await engine.initWithoutBridge();
  }
  return engine;
}

void _note(List<String> notes, String s) {
  notes.add(s);
  // ignore: avoid_print -- 實驗輸出就是 log
  print('PROBE_NOTE $s');
}

Future<Object?> _eval(JsEngine e, String code) async =>
    (await e.eval(source: JsCode.code(code))).value;

class FjsProbe implements Probe {
  @override
  String get candidate => 'fjs $fjsVersion';

  @override
  Future<Check> engineIdentity() async {
    final e = await _engine();
    try {
      final fp = await _eval(e, jsFingerprint);
      final surface = await _eval(e, sandboxSurface);
      // fjs 只有一個 Rust crate（rquickjs → QuickJS-NG），沒有依平台換引擎的分支。
      return Check(
        'engine_identity',
        pass: '$fp'.startsWith('quickjs-like'),
        detail:
            'package engine: rquickjs (QuickJS-NG) on every platform; js: $fp; '
            'globals with builtins(timers, console): $surface',
      );
    } finally {
      await e.close();
    }
  }

  @override
  Future<Check> interruptInfiniteLoop() async {
    final sw = Stopwatch()..start();
    final cases = [
      await _interruptCase('top-level loop', infiniteLoop),
      await _interruptCase('loop after await', loopAfterAwait),
      await _interruptCase('loop in setTimeout callback', loopInTimer),
    ];
    // 引擎關了就報廢；確認重建的新引擎可用（插件的做法：停掉、重建）。
    final fresh = await _engine();
    final after = await _eval(fresh, sanity);
    await fresh.close();
    return Check(
      'interrupt_infinite_loop',
      pass: cases.every((c) => c.$1) && after == 3,
      ms: sw.elapsedMilliseconds,
      detail:
          '${cases.map((c) => c.$2).join(' | ')} | '
          'engine is dead after close, a new engine evaluates 1+2=$after',
    );
  }

  /// 跑 [code]，[interruptAfter] 後 close；迴圈在跑時與 close 後各量一個 [cpuWindow] 的行程 CPU。
  Future<(bool, String)> _interruptCase(String label, String code) async {
    final e = await _engine();
    final run = e.eval(source: JsCode.code(code));
    var settled = false;
    String evalOutcome = 'still running';
    String? closeError;
    unawaited(
      run
          .then(
            (v) => evalOutcome = 'returned ${v.value}',
            onError: (Object err) => evalOutcome =
                'failed with ${err is JsError ? err.code() : err}',
          )
          .whenComplete(() => settled = true),
    );
    final (
      (closeMs, cpuDuring, cpuAfter, beforeClose),
      stall,
    ) = await measureStall(() async {
      await Future<void>.delayed(interruptAfter);
      final beforeClose = evalOutcome;
      final cpuDuring = await cpuMsDuring(cpuWindow);
      final c = Stopwatch()..start();
      try {
        await e.close().timeout(interruptBudget);
      } on TimeoutException {
        closeError =
            'close() did not return within ${interruptBudget.inSeconds}s';
      } catch (err) {
        // 中斷 timer 裡的迴圈時，被中斷的回呼變成「未處理的背景錯誤」，close() 會把它拋出來。
        closeError = 'close() threw: ${'$err'.split('\n').first}';
      }
      final closeMs = c.elapsedMilliseconds;
      final deadline = DateTime.now().add(interruptBudget);
      while (!settled && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final cpuAfter = await cpuMsDuring(cpuWindow);
      return (closeMs, cpuDuring, cpuAfter, beforeClose);
    });
    final pass =
        settled &&
        closeMs < interruptBudget.inMilliseconds &&
        loopStopped(cpuDuring, cpuAfter);
    return (
      pass,
      '$label: eval before close: $beforeClose, after close: $evalOutcome; '
          '${closeError == null ? '' : '$closeError; '}'
          'close() ${closeMs}ms; process CPU per ${cpuWindow.inMilliseconds}ms '
          'window ${cpuDuring}ms while looping, ${cpuAfter}ms after close; '
          'caller worst stall ${stall}ms',
    );
  }

  @override
  Future<Check> stuckEngineIsolation() async {
    final notes = <String>[];
    var pass = true;
    // fjs 全行程只有 2 條 JS 執行緒（libfjs/src/runtime/executor.rs 的 worker_threads(2)），
    // 所以量 1、2、4 個卡住的情況。
    for (final n in {1, 2, stuckEngines}) {
      pass = await _stuckCase(n, notes) && pass;
    }
    return Check(
      'stuck_engine_isolation',
      pass: pass,
      detail: notes.join('; '),
    );
  }

  /// [n] 個引擎卡在無窮迴圈時，另建一個引擎算 1+2；每一步都有 [stuckBudget] 的上限並記下結果。
  Future<bool> _stuckCase(int n, List<String> notes) async {
    final stuck = <JsEngine>[];
    for (var i = 0; i < n; i++) {
      stuck.add(await _engine());
    }
    for (final e in stuck) {
      unawaited(
        e
            .eval(source: const JsCode.code(infiniteLoop))
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    await Future<void>.delayed(interruptAfter);
    var ok = false;
    final sw = Stopwatch()..start();
    try {
      final other = await _engine().timeout(stuckBudget);
      final createdMs = sw.elapsedMilliseconds;
      final v = await _eval(other, sanity).timeout(stuckBudget);
      _note(
        notes,
        '$n stuck: another engine created in ${createdMs}ms, 1+2=$v after ${sw.elapsedMilliseconds}ms',
      );
      ok = v == 3;
      await other.close().timeout(stuckBudget);
    } on TimeoutException {
      _note(
        notes,
        '$n stuck: another engine did not answer within ${stuckBudget.inSeconds}s (${sw.elapsedMilliseconds}ms)',
      );
    }
    final closeSw = Stopwatch()..start();
    final closes = await Future.wait(
      stuck.map(
        (e) => e
            .close()
            .timeout(stuckBudget)
            .then<String?>(
              (_) => null,
              onError: (Object err) => '$err'.split('\n').first,
            ),
      ),
    );
    final failed = closes.whereType<String>().toList();
    final closed = n - failed.length;
    _note(
      notes,
      '$n stuck: closed $closed/$n concurrently in ${closeSw.elapsedMilliseconds}ms'
      '${failed.isEmpty ? '' : ' (failures: ${failed.toSet().join(', ')})'}',
    );
    // 關完之後，新引擎能不能在上限內回來（行程是否恢復）。
    final recoverSw = Stopwatch()..start();
    try {
      final fresh = await _engine().timeout(stuckBudget);
      final v = await _eval(fresh, sanity).timeout(stuckBudget);
      await fresh.close().timeout(stuckBudget);
      _note(
        notes,
        '$n stuck: after closing, a new engine evaluates 1+2=$v in ${recoverSw.elapsedMilliseconds}ms',
      );
    } on TimeoutException {
      _note(
        notes,
        '$n stuck: after closing, a new engine still did not answer within ${stuckBudget.inSeconds}s',
      );
      return false;
    }
    return ok && closed == n;
  }

  @override
  Future<Check> memoryLimit() async {
    final e = await _engine(memoryLimit: memoryLimitBytes);
    try {
      String outcome;
      try {
        outcome = 'returned: ${await _eval(e, memoryHog)}';
      } on JsError catch (err) {
        outcome = 'threw ${err.code()}: $err';
      }
      Object? after;
      try {
        after = await _eval(e, sanity);
      } on JsError catch (err) {
        after = 'threw ${err.code()}';
      }
      final usage = await e.memoryUsage();
      return Check(
        'memory_limit',
        pass: memoryLimited(outcome, after),
        detail:
            'limit ${memoryLimitBytes ~/ (1024 * 1024)} MiB; $outcome; '
            'same engine afterwards 1+2=$after; memoryUsedSize after: '
            '${usage.memoryUsedSize} bytes, mallocLimit: ${usage.mallocLimit}',
      );
    } finally {
      await e.close();
    }
  }

  @override
  Future<Check> awaitJsPromise() async {
    final e = await _engine();
    try {
      final r = await _eval(e, asyncReturn);
      return Check(
        'await_js_promise',
        pass: r == 42,
        detail: 'eval awaited the promise: $r',
      );
    } finally {
      await e.close();
    }
  }

  @override
  Future<Check> asyncHostCall() async {
    final e = await _engine(bridge: true);
    try {
      final (r, stall) = await measureStall(() => _eval(e, js.asyncHostCall));
      return Check(
        'async_host_call',
        pass: r == 'pong!',
        detail:
            'JS awaited Dart Future via fjs.bridge_call: $r; caller isolate worst stall ${stall}ms',
      );
    } finally {
      await e.close();
    }
  }

  @override
  Future<Check> isolateLayout() async {
    final notes = <String>[];
    var pass = true;

    final createSw = Stopwatch()..start();
    final e = await _engine();
    final createMs = createSw.elapsedMilliseconds;
    await e.close();
    _note(notes, 'create+close one engine: ${createMs}ms');

    // 四個插件各一個引擎，同時跑一段 CPU 工作：看是否真的並行、是否卡住呼叫端。
    const work = cpuWork;
    final one = await _engine();
    final soloSw = Stopwatch()..start();
    await _eval(one, work);
    final soloMs = soloSw.elapsedMilliseconds;
    await one.close();
    final engines = await Future.wait(List.generate(4, (_) => _engine()));
    final (_, stall) = await measureStall(() async {
      final sw = Stopwatch()..start();
      await Future.wait(engines.map((x) => _eval(x, work)));
      _note(
        notes,
        'cpu work: 1 engine ${soloMs}ms, 4 engines in parallel ${sw.elapsedMilliseconds}ms',
      );
    });
    _note(notes, 'main isolate worst stall during 4-engine work: ${stall}ms');
    for (final x in engines) {
      await x.close();
    }

    // 背景 isolate 裡也能用嗎（要各自 LibFjs.init）？
    _note(notes, 'starting background isolate');
    try {
      final r = await Isolate.run(() async {
        await LibFjs.init();
        final b = await JsEngine.create(builtins: _builtins);
        await b.initWithoutBridge();
        final v = (await b.eval(source: const JsCode.code(sanity))).value;
        await b.close();
        return v;
      }).timeout(const Duration(seconds: 15));
      _note(notes, 'background isolate (own LibFjs.init): 1+2=$r');
    } catch (err) {
      pass = false;
      _note(notes, 'background isolate failed: $err');
    }
    return Check('isolate_layout', pass: pass, detail: notes.join('; '));
  }
}
