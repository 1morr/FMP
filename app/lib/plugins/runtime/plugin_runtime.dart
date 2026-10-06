import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/plugin_worker.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/plugins/runtime/worker_protocol.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 每次呼叫插件函式（含載入）的上限（ADR 0014；PRD 9a）。
const defaultPluginCallTimeout = Duration(seconds: 30);

/// 逾時後等背景 isolate 回應探測多久；等不到就判定它卡住。
const defaultLivenessGrace = Duration(seconds: 2);

/// 背景 isolate 的進入點；測試換掉它來模擬背景 isolate 當掉。
typedef PluginWorkerEntry = void Function(PluginWorkerStart start);

/// 插件停止回應或背景 isolate 意外結束。只當 [AppError] 的 cause（進 log）。
final class PluginUnresponsive implements Exception {
  const PluginUnresponsive(this.reason);

  final String reason;

  @override
  String toString() => 'PluginUnresponsive: $reason';
}

/// 一個插件的 JS 執行環境的主 isolate 端（ADR 0014 §決定 2、5；prd 擁有者
/// 決定 7）。
///
/// - QuickJS 在這個插件自己的背景 isolate（`plugin_worker.dart`）；腳本同步
///   跑不停時卡住的是那個 isolate，UI 照常。
/// - 宿主 API 的網路、storage、憑證、log 在這裡（主 isolate）執行，背景
///   isolate 以訊息請求（`worker_protocol.dart`）；網域與插件 id 的檢查都在
///   這一邊。`crypto` 在背景 isolate 算。
/// - 看門狗：每次呼叫（含載入）有 [callTimeout]。到期時送 [Ping] 探測，
///   [livenessGrace] 內有回應就是「在等東西」（例如慢的網路），這次呼叫以
///   [NetworkError] 失敗，插件照常；沒有回應就判定卡住：插件轉成
///   [PluginHealth.unresponsive]、進行中與之後的呼叫都以 [UnexpectedError]
///   失敗、呼叫 `Isolate.kill`。
/// - **卡住的執行緒回收不了**：`Isolate.kill` 要等 isolate 回到 Dart 的事件
///   迴圈才生效，停在 QuickJS 原生碼裡的執行緒會一直忙到 App 結束。
final class PluginRuntime {
  PluginRuntime._({
    required this.pluginId,
    required this._host,
    required this._log,
    required this.callTimeout,
    required this.livenessGrace,
  });

  /// 在新的背景 isolate 載入 [script]，回傳時已知道它匯出的函式
  /// （[exports]）。
  ///
  /// 腳本語法錯誤是 [ParseError]；載入時拋出的其他錯誤照 [invoke] 的規則轉換；
  /// 逾時照看門狗的規則；背景 isolate 起不來是 [UnexpectedError]。失敗時
  /// runtime 已釋放。
  static Future<PluginRuntime> start({
    required String pluginId,
    required String script,
    required PluginHost host,
    required Log log,
    Duration callTimeout = defaultPluginCallTimeout,
    Duration livenessGrace = defaultLivenessGrace,
    PluginWorkerEntry entryPoint = pluginWorkerMain,
  }) async {
    final runtime = PluginRuntime._(
      pluginId: pluginId,
      host: host,
      log: log,
      callTimeout: callTimeout,
      livenessGrace: livenessGrace,
    );
    try {
      await runtime._spawn(script, entryPoint);
      return runtime;
    } on AppError {
      runtime.dispose();
      rethrow;
    } on Object catch (error, stackTrace) {
      // 例如 Isolate.spawn 失敗：插件邊界以上只看得到 AppError。
      runtime.dispose();
      throw AppError.wrap(error, stackTrace, pluginId: pluginId);
    }
  }

  final String pluginId;

  /// 每次呼叫的上限。
  final Duration callTimeout;

  /// 逾時後等探測回應的時間。
  final Duration livenessGrace;

  /// 腳本匯出的函式名稱。
  late final Set<String> exports;

  final PluginHost _host;
  final Log _log;
  final _fromWorker = ReceivePort();
  Isolate? _isolate;
  SendPort? _toWorker;
  bool _disposed = false;

  PluginHealth _health = PluginHealth.ready;
  final _unresponsive = Completer<void>();

  /// 等結果的呼叫；id 0 是載入。
  final _pending = <int, _Pending>{};
  int _lastCallId = 0;

  /// 進行中的探測。
  Future<bool>? _probe;
  (int, Completer<bool>)? _pong;
  int _lastPingId = 0;

  /// 宿主函式丟出的 [AppError]，腳本以 `hostErrorId` 帶回來時原樣拋出（保留
  /// 網路紀錄 id 與原因）。沒有呼叫在進行時清空。
  final _hostErrors = <int, AppError>{};
  int _lastHostErrorId = 0;

  PluginHealth get health => _health;

  /// 變成 [PluginHealth.unresponsive] 時完成。
  Future<void> get whenUnresponsive => _unresponsive.future;

  /// 呼叫匯出的函式 [function]，參數與回傳值都是 JSON。
  ///
  /// 腳本拋出的錯誤：結構化錯誤轉成對應的 [AppError]（`script_errors.dart`），
  /// 宿主函式的錯誤原樣拋出，其他值包成 [UnexpectedError]；回傳值無法轉成 JSON
  /// 是 [ParseError]；逾時照看門狗的規則；插件已沒有回應是 [UnexpectedError]。
  Future<Object?> invoke(String function, Object? argument) async {
    _checkUsable();
    if (!exports.contains(function)) {
      throw ArgumentError.value(function, 'function', 'is not exported');
    }
    // 先編碼再登記：編碼失敗時不留下等結果的呼叫。
    final argumentJson = jsonEncode(argument);
    final id = ++_lastCallId;
    final reply = _wait(id, function);
    _toWorker!.send(CallRequest(id, function, argumentJson));
    try {
      return _unwrap(await reply, loading: false);
    } finally {
      _forgetHostErrors();
    }
  }

  /// 釋放：請背景 isolate 釋放 QuickJS 後結束，等待中的呼叫以
  /// [UnexpectedError] 結束。重複呼叫無作用。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _toWorker?.send(const Shutdown());
    _failPending(
      (label) => UnexpectedError(
        pluginId: pluginId,
        cause: StateError('The plugin runtime was disposed during $label'),
        stackTrace: StackTrace.current,
      ),
    );
    _stop();
  }

  Future<void> _spawn(String script, PluginWorkerEntry entryPoint) async {
    _fromWorker.listen(_onMessage);
    // 先登記才收得到結果；計時從 isolate 起來之後算，spawn 本身不算腳本的時間。
    final loaded = _wait(0, 'load', startDeadline: false);
    try {
      _isolate = await Isolate.spawn(
        entryPoint,
        PluginWorkerStart(
          toMain: _fromWorker.sendPort,
          pluginId: pluginId,
          script: script,
        ),
        onError: _fromWorker.sendPort,
        onExit: _fromWorker.sendPort,
        debugName: 'plugin $pluginId',
      );
    } on Object {
      // 沒有人會等 loaded 了：拿掉，dispose 才不會讓它以沒人接的錯誤結束。
      _pending.remove(0);
      rethrow;
    }
    _pending[0]?.startDeadline(callTimeout, () => _onDeadline(0));
    try {
      final value = _unwrap(await loaded, loading: true);
      exports = Set.unmodifiable((value! as List).cast<String>());
    } finally {
      _forgetHostErrors();
    }
  }

  void _checkUsable() {
    if (_health == PluginHealth.unresponsive) {
      throw _unresponsiveError('the plugin stopped responding earlier');
    }
    if (_disposed) {
      throw UnexpectedError(
        pluginId: pluginId,
        cause: StateError('The plugin runtime was disposed'),
        stackTrace: StackTrace.current,
      );
    }
  }

  /// 登記一個等結果的呼叫並開始計時；結果到了就移除。
  Future<String> _wait(int id, String label, {bool startDeadline = true}) {
    final pending = _Pending(label);
    if (startDeadline) {
      pending.startDeadline(callTimeout, () => _onDeadline(id));
    }
    _pending[id] = pending;
    return pending.completer.future;
  }

  /// 沒有呼叫在進行時清空 [_hostErrors]（[_unwrap] 讀過之後才呼叫）。
  void _forgetHostErrors() {
    if (_pending.isEmpty) _hostErrors.clear();
  }

  void _complete(int id, String reply) {
    final pending = _pending.remove(id);
    pending?.deadline?.cancel();
    pending?.completer.complete(reply);
  }

  void _failPending(AppError Function(String label) error) {
    final pending = [..._pending.values];
    _pending.clear();
    for (final call in pending) {
      call.deadline?.cancel();
      call.completer.completeError(error(call.label), StackTrace.current);
    }
  }

  Future<void> _onDeadline(int id) async {
    if (!_pending.containsKey(id)) return;
    final alive = await _isAlive();
    final pending = _pending[id];
    if (pending == null) return;
    if (alive) {
      _pending.remove(id);
      pending.completer.completeError(
        NetworkError(
          pluginId: pluginId,
          cause: TimeoutException(
            'Plugin call ${pending.label} did not finish',
            callTimeout,
          ),
          stackTrace: StackTrace.current,
        ),
      );
      return;
    }
    _markUnresponsive(
      '${pending.label} did not finish within $callTimeout and the worker '
      'did not answer a ping within $livenessGrace',
    );
  }

  /// 背景 isolate 的事件迴圈還在轉嗎：送 [Ping]，[livenessGrace] 內等 [Pong]。
  Future<bool> _isAlive() => _probe ??= () async {
    final toWorker = _toWorker;
    if (toWorker == null) return false;
    final pong = Completer<bool>();
    final id = ++_lastPingId;
    _pong = (id, pong);
    toWorker.send(Ping(id));
    final timer = Timer(livenessGrace, () {
      if (!pong.isCompleted) pong.complete(false);
    });
    final alive = await pong.future;
    timer.cancel();
    _probe = null;
    return alive;
  }();

  void _markUnresponsive(String reason) {
    if (_disposed || _health == PluginHealth.unresponsive) return;
    _health = PluginHealth.unresponsive;
    _log.report(
      'Plugin stopped responding',
      _unresponsiveError(reason),
      tag: pluginId,
    );
    // 卡在 QuickJS 原生碼裡的 isolate 不會真的停：kill 要等它回到事件迴圈。
    _isolate?.kill(priority: Isolate.immediate);
    _failPending((label) => _unresponsiveError('$label: $reason'));
    _stop();
    _unresponsive.complete();
  }

  /// 插件卡住或背景 isolate 死掉：插件本身的 bug，所以是 [UnexpectedError]
  /// （不可重試、視為 bug 的通用訊息）；狀態在 [health] 與清單上。
  AppError _unresponsiveError(String reason) => UnexpectedError(
    pluginId: pluginId,
    cause: PluginUnresponsive(reason),
    stackTrace: StackTrace.current,
  );

  /// 不再收背景 isolate 的訊息、取消進行中的請求。
  void _stop() {
    _host.close();
    _fromWorker.close();
  }

  void _onMessage(Object? message) {
    switch (message) {
      case WorkerReady(:final toWorker):
        _toWorker = toWorker;
      case LoadResult(:final replyJson):
        _complete(0, replyJson);
      case CallResult(:final id, :final replyJson):
        _complete(id, replyJson);
      case HostRequest(:final id, :final op, :final argumentsJson):
        _reply(() => _host.callAsync(op, jsonDecode(argumentsJson)))
            .then((reply) {
              if (!_disposed && _health == PluginHealth.ready) {
                _toWorker?.send(HostReply(id, reply));
              }
            });
      case LogRequest(:final level, :final message, :final fieldsJson):
        _host.writeLog(
          level,
          message,
          (jsonDecode(fieldsJson) as Map).cast<String, Object?>(),
        );
      case RejectionReport(:final reason):
        // QuickJS 在 Promise 被拒絕、當下還沒有處理者時就回報，之後接上
        // 處理者也不收回：async 函式拋錯而呼叫端隨後才 await 也會報。所以
        // 只記 debug，措辭照實寫；真正的錯誤經呼叫的結果拋出。
        _log.debug(
          'Promise rejected before a handler was attached',
          tag: pluginId,
          error: reason,
        );
      case Pong(:final id):
        if (_pong case (final expected, final pong) when expected == id) {
          if (!pong.isCompleted) pong.complete(true);
        }
      // onError：[錯誤, stack]（字串）。errorsAreFatal 預設為真，isolate 隨後
      // 結束。
      case [final Object? error, final Object? stack]:
        _markUnresponsive('the worker failed: $error\n$stack');
      // onExit。
      case null:
        _markUnresponsive('the worker exited');
    }
  }

  Future<String> _reply(Future<Object?> Function() call) async {
    try {
      return jsonEncode({'ok': true, 'value': await call()});
    } on ArgumentError catch (error) {
      return _argumentError(error.toString());
    } on FormatException catch (error) {
      return _argumentError(error.message);
    } on Object catch (error, stackTrace) {
      return _appError(AppError.wrap(error, stackTrace, pluginId: pluginId));
    }
  }

  static String _argumentError(String message) => jsonEncode({
    'ok': false,
    'error': {'kind': 'argument', 'message': message},
  });

  /// 腳本只看到類別名與重試資訊；原因（可能含網址、伺服器訊息）留在主
  /// isolate。
  String _appError(AppError error) {
    final id = ++_lastHostErrorId;
    _hostErrors[id] = error;
    return jsonEncode({
      'ok': false,
      'error': {
        'kind': 'host',
        'fmpError': error.typeName,
        'hostErrorId': id,
        'retryAfterSeconds': switch (error.retryAfter) {
          null => null,
          final delay => delay.inMilliseconds / 1000,
        },
        'reason': switch (error) {
          Unavailable(:final reason?) => unavailableReasonWireName(reason),
          _ => null,
        },
      },
    });
  }

  Object? _unwrap(String reply, {required bool loading}) {
    final json = jsonDecode(reply) as Map<String, Object?>;
    if (json['ok'] == true) return json['value'];
    final error = json['error']! as Map<String, Object?>;
    final stackTrace = StackTrace.current;
    switch (error) {
      case {'kind': 'structured', 'fmpError': final String name}:
        final hostError = switch (error['hostErrorId']) {
          final int id => _hostErrors[id],
          _ => null,
        };
        if (hostError != null && hostError.typeName == name) throw hostError;
        throw structuredScriptError(
          pluginId: pluginId,
          fmpError: name,
          retryAfterSeconds: error['retryAfterSeconds'] as num?,
          reason: error['reason'] as String?,
          message: error['message'] as String?,
        );
      case {'kind': 'unserializable', 'message': final String? message}:
        throw ParseError(
          pluginId: pluginId,
          cause: PluginScriptError('Unserializable', message ?? ''),
          stackTrace: stackTrace,
        );
      case {
        'kind': 'thrown',
        'name': final String name,
        'message': final String message,
        'stack': final String jsStack,
      }:
        final cause = PluginScriptError(name, message, jsStack);
        // 載入時的語法錯誤：腳本本身讀不懂。
        if (loading && name == 'SyntaxError') {
          throw ParseError(
            pluginId: pluginId,
            cause: cause,
            stackTrace: stackTrace,
          );
        }
        throw UnexpectedError(
          pluginId: pluginId,
          cause: cause,
          stackTrace: stackTrace,
        );
    }
    throw UnexpectedError(
      pluginId: pluginId,
      cause: FormatException('Unexpected reply from the worker: $reply'),
      stackTrace: stackTrace,
    );
  }
}

final class _Pending {
  _Pending(this.label);

  /// 函式名稱，或 `load`。只進 log。
  final String label;
  final completer = Completer<String>();
  Timer? deadline;

  void startDeadline(Duration timeout, void Function() onDeadline) {
    deadline = Timer(timeout, onDeadline);
  }
}
