import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_js/flutter_js.dart';

import 'package:fmp/plugins/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/js_prelude.dart';
import 'package:fmp/plugins/runtime/worker_protocol.dart';

/// 插件腳本載入成 ES module 時的名稱。module loader 只對這個名稱回傳腳本，
/// 其他 `import` 一律失敗。
const pluginModuleName = 'fmp-plugin';

/// 插件背景 isolate 的進入點（`Isolate.spawn`）：建立 QuickJS、執行 prelude、
/// 載入腳本，之後處理主 isolate 的呼叫。
///
/// 這個 isolate 只跑 JS 與不碰外界的宿主函式（`crypto`、log 參數的形狀檢查）；
/// 網路、storage、憑證都以 [HostRequest] 交給主 isolate，安全檢查在那裡。
/// 腳本同步跑不停時卡住的是這個 isolate，主 isolate 照常。
void pluginWorkerMain(PluginWorkerStart start) {
  final commands = ReceivePort();
  // 先交出 port：之後即使載入卡住，主 isolate 的看門狗也送得到 Ping。
  start.toMain.send(WorkerReady(commands.sendPort));
  final worker = _Worker(start, commands);
  commands.listen((message) => worker.handle(message as ToWorker));
  worker.load();
}

final class _Worker {
  _Worker(this._start, this._commands)
    : _engine = _QuickJs(
        moduleHandler: (name) => name == pluginModuleName
            ? _start.script
            : throw ArgumentError.value(name, 'module', 'cannot be imported'),
        hostPromiseRejectionHandler: (reason) =>
            _start.toMain.send(RejectionReport('$reason')),
      ) {
    final prelude = _engine.evaluate(jsPrelude, name: '<fmp-prelude>');
    if (prelude.isError) {
      throw StateError('The plugin prelude failed: ${prelude.stringResult}');
    }
    final factory = prelude.rawResult as JSInvokable;
    final api = factory.invoke([_hostAsync, _hostSync, hostApiVersion]) as Map;
    factory.free();
    _load = api['load'] as JSInvokable;
    _call = api['call'] as JSInvokable;
  }

  final PluginWorkerStart _start;
  final ReceivePort _commands;
  final _QuickJs _engine;
  late final JSInvokable _load;
  late final JSInvokable _call;
  bool _closed = false;

  /// 等主 isolate 回覆的宿主呼叫。
  final _hostCalls = <int, Completer<String>>{};
  int _lastHostCallId = 0;

  void load() {
    final promise = _load.invoke([pluginModuleName]) as Future<Object?>;
    _pump();
    promise.then(
      (reply) => _start.toMain.send(LoadResult(reply! as String)),
      onError: (Object _) => _start.toMain.send(const LoadResult(_noReply)),
    );
  }

  void handle(ToWorker message) {
    if (_closed) return;
    switch (message) {
      case CallRequest(:final id, :final function, :final argumentJson):
        final promise =
            _call.invoke([function, argumentJson]) as Future<Object?>;
        _pump();
        promise.then(
          (reply) => _start.toMain.send(CallResult(id, reply! as String)),
          onError: (Object _) => _start.toMain.send(CallResult(id, _noReply)),
        );
      case HostReply(:final id, :final replyJson):
        _hostCalls.remove(id)?.complete(replyJson);
        // complete 先排了一個 microtask 把結果交給 listener（flutter_js 在
        // 那裡呼叫 JS 的 resolve），這個排在它之後，Promise 工作才會有東西
        // 跑。不用 Timer.run：在 Android 的 UI isolate 上實測它要等下一輪訊息
        // 迴圈，每次宿主呼叫多約一個 frame（PR 9a 的 research/notes.md §4）。
        scheduleMicrotask(_pump);
      case Ping(:final id):
        _start.toMain.send(Pong(id));
      case Shutdown():
        _closed = true;
        _load.free();
        _call.free();
        _engine.dispose();
        _commands.close();
    }
  }

  /// 執行排著的 Promise 工作，直到沒有為止。
  void _pump() {
    if (!_closed) _engine.executePendingJob();
  }

  /// JS 的 `hostAsync(op, argsJson)`：交給主 isolate，回覆到了才 resolve。
  Future<String> _hostAsync(String op, String args) {
    final id = ++_lastHostCallId;
    final completer = Completer<String>();
    _hostCalls[id] = completer;
    _start.toMain.send(HostRequest(id, op, args));
    return completer.future;
  }

  /// JS 的 `hostSync(op, argsJson)`：不碰外界，在這裡算完。
  String _hostSync(String op, String args) {
    try {
      final arguments = jsonDecode(args);
      return jsonEncode({'ok': true, 'value': _sync(op, arguments)});
    } on ArgumentError catch (error) {
      return _argumentError(error.toString());
    } on FormatException catch (error) {
      return _argumentError(error.message);
    }
  }

  Object? _sync(String op, Object? args) => switch (op) {
    'crypto.md5' => crypto.md5.convert(utf8.encode(_text(args))).toString(),
    'crypto.sha256' =>
      crypto.sha256.convert(utf8.encode(_text(args))).toString(),
    'log' => _log(args),
    _ => throw ArgumentError.value(op, 'op', 'unknown host function'),
  };

  /// 檢查 log 參數的形狀後交給主 isolate；層級名稱在那裡再對一次。
  Object? _log(Object? args) {
    final fields = JsonFields(args, const {
      'level': true,
      'message': true,
      'fields': false,
    }, path: 'fmp.log');
    final level = fields.string('level');
    if (!const {'debug', 'info', 'warn', 'error'}.contains(level)) {
      throw ArgumentError.value(level, 'level');
    }
    _start.toMain.send(
      LogRequest(
        level,
        fields.string('message'),
        jsonEncode(fields.optionalObject('fields') ?? const {}),
      ),
    );
    return null;
  }

  static String _text(Object? args) => switch (args) {
    {'text': final String text} => text,
    _ => throw ArgumentError('crypto input must be a string'),
  };

  /// prelude 的 `load`／`call` 本來永遠 resolve；腳本弄壞了 JSON（例如讓
  /// `Object.prototype.toJSON` 拋錯）時它連錯誤都回不了。改回這個，不讓它成為
  /// 背景 isolate 未捕捉的錯誤：那會被當成當掉，插件停用到重啟。
  static const _noReply =
      '{"ok":false,"error":{"kind":"thrown","name":"NoReply",'
      '"message":"the plugin could not encode its reply","stack":""}}';

  static String _argumentError(String message) => jsonEncode({
    'ok': false,
    'error': {'kind': 'argument', 'message': message},
  });
}

/// 不裝 flutter_js 預設全域的 QuickJS runtime。
///
/// [QuickJsRuntime2] 的建構子呼叫 [init]，預設會加上 `console`（寫到
/// `print`）、`setTimeout`（Timer 到期時呼叫 `evaluate`，runtime 已釋放也會
/// 重建引擎）與 `sendMessage`；宿主 API 只有 `fmp`，所以都不要。也不用
/// `getJavascriptRuntime()`：它會裝走 `package:http` 的 `fetch`，繞過宿主的
/// 網路層。
final class _QuickJs extends QuickJsRuntime2 {
  _QuickJs({
    required super.moduleHandler,
    required super.hostPromiseRejectionHandler,
  });

  @override
  JavascriptRuntime init() => this;
}
