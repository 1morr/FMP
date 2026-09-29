import 'dart:isolate';

// 主 isolate 與插件背景 isolate 之間的訊息（prd 擁有者決定 7、ADR 0014
// 2026-09-30 補充）。兩邊在同一個 isolate group（Isolate.spawn），所以直接傳
// 這些物件；內容只有字串、數字與 SendPort。
//
// 參數與結果一律是 JSON 字串：與 prelude 的 `{ok, value}`／`{ok, error}`
// 回覆同一個格式，兩邊都不必轉換 Dart 物件。

/// Isolate.spawn 的起始訊息。
final class PluginWorkerStart {
  const PluginWorkerStart({
    required this.toMain,
    required this.pluginId,
    required this.script,
  });

  final SendPort toMain;
  final String pluginId;
  final String script;
}

/// 主 isolate → 背景 isolate。
sealed class ToWorker {
  const ToWorker();
}

/// 呼叫匯出的函式。
final class CallRequest extends ToWorker {
  const CallRequest(this.id, this.function, this.argumentJson);

  final int id;
  final String function;
  final String argumentJson;
}

/// 宿主非同步函式的回覆（[HostRequest] 的結果）。
final class HostReply extends ToWorker {
  const HostReply(this.id, this.replyJson);

  final int id;
  final String replyJson;
}

/// 看門狗的探測：背景 isolate 的事件迴圈還在轉就回 [Pong]。
final class Ping extends ToWorker {
  const Ping(this.id);

  final int id;
}

/// 釋放 QuickJS 並結束 isolate。
final class Shutdown extends ToWorker {
  const Shutdown();
}

/// 背景 isolate → 主 isolate。
sealed class ToMain {
  const ToMain();
}

/// 背景 isolate 一開始就送：之後的訊息往這個 port 送。
final class WorkerReady extends ToMain {
  const WorkerReady(this.toWorker);

  final SendPort toWorker;
}

/// 載入完成（或失敗）。[replyJson] 成功時的值是匯出的函式名稱。
final class LoadResult extends ToMain {
  const LoadResult(this.replyJson);

  final String replyJson;
}

/// [CallRequest] 的結果。
final class CallResult extends ToMain {
  const CallResult(this.id, this.replyJson);

  final int id;
  final String replyJson;
}

/// 腳本呼叫宿主的非同步函式（網路、storage、憑證），在主 isolate 執行。
final class HostRequest extends ToMain {
  const HostRequest(this.id, this.op, this.argumentsJson);

  final int id;
  final String op;
  final String argumentsJson;
}

/// 腳本寫的 log（`fmp.log`、`console`）。背景 isolate 只檢查形狀，tag 由主
/// isolate 填成插件 id。
final class LogRequest extends ToMain {
  const LogRequest(this.level, this.message, this.fieldsJson);

  /// `debug`、`info`、`warn`、`error`。
  final String level;
  final String message;
  final String fieldsJson;
}

/// Promise 被拒絕時還沒有處理者（只記 debug，見 `plugin_worker.dart`）。
final class RejectionReport extends ToMain {
  const RejectionReport(this.reason);

  final String reason;
}

/// [Ping] 的回覆。
final class Pong extends ToMain {
  const Pong(this.id);

  final int id;
}
