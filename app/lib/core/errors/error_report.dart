import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';

/// 對應到這次錯誤的那一筆請求的摘要（網路紀錄的欄位，已遮蔽）。
@immutable
final class ErrorReportRequest {
  const ErrorReportRequest({
    required this.method,
    required this.url,
    this.status,
    this.ms,
    this.error,
  });

  final String method;

  /// 主機＋路徑＋遮過的 query；網路紀錄不存 scheme。
  final String url;
  final int? status;
  final int? ms;

  /// 網路紀錄的 `error` 欄位（錯誤類型名稱）。
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is ErrorReportRequest &&
      other.method == method &&
      other.url == url &&
      other.status == status &&
      other.ms == ms &&
      other.error == error;

  @override
  int get hashCode => Object.hash(method, url, status, ms, error);
}

/// 一則錯誤的報告（ADR 0023 §決定 4）：詳細頁顯示、「複製」與「在 GitHub 回報」都用同一份。
///
/// 由 `Log.report` 寫進錯誤歷史的那筆 [LogRecord]（已遮蔽）組成，所以不會有第二條路拿到
/// 原始的 error 或 stackTrace。組成時每個文字欄位（含版本字串等外來欄位）再過一次 [Redactor]：
/// 紀錄是寫入當時遮的，之後才登記的憑證值要在這裡擋，而且頁面顯示的欄位與 Markdown 是同一份
/// （ADR 0023 §決定 4）；整份 Markdown 輸出前再遮一次。純 Dart，不認得平台或介面。
@immutable
final class ErrorReport {
  const ErrorReport._({
    required this.time,
    required this.operation,
    required this.tag,
    required this.type,
    required this.reason,
    required this.cause,
    required this.pluginId,
    required this.pluginVersion,
    required this.request,
    required this.stackTrace,
    required this.appVersion,
    required this.flavor,
    required this.platform,
    required this.osVersion,
    required this._redactor,
  });

  /// 從 [record] 組報告。
  ///
  /// [networkHistory] 是這次執行的記憶體歷史，用 `fields.networkRecordId` 找對應的網路紀錄；
  /// 前幾次執行的紀錄（log 檔讀回）傳空清單：id 只在同一次執行裡唯一，對到的會是別的請求。
  /// 找得到的還要音源相同、時間不晚於這筆錯誤，擋掉剛好撞號的。
  factory ErrorReport.fromRecord(
    LogRecord record, {
    required Redactor redactor,
    required String appVersion,
    required String flavor,
    required String platform,
    required String osVersion,
    String? pluginVersion,
    List<LogRecord> networkHistory = const [],
  }) {
    final fields = record.fields;
    final pluginId = fields['pluginId'] as String?;
    String? redactOrNull(String? text) =>
        text == null ? null : redactor.redact(text);
    return ErrorReport._(
      time: record.time,
      operation: redactor.redact(record.message),
      tag: redactor.redact(record.tag),
      type: redactOrNull(fields['type'] as String?),
      reason: redactOrNull(fields['reason'] as String?),
      cause: redactOrNull(record.error),
      pluginId: redactOrNull(pluginId),
      pluginVersion: redactOrNull(pluginVersion),
      request: _requestOf(
        fields['networkRecordId'],
        pluginId: pluginId,
        before: record.time,
        history: networkHistory,
        redactor: redactor,
      ),
      stackTrace: redactOrNull(record.stackTrace),
      appVersion: redactor.redact(appVersion),
      flavor: redactor.redact(flavor),
      platform: redactor.redact(platform),
      osVersion: redactor.redact(osVersion),
      redactor: redactor,
    );
  }

  static ErrorReportRequest? _requestOf(
    Object? id, {
    required String? pluginId,
    required DateTime before,
    required List<LogRecord> history,
    required Redactor redactor,
  }) {
    if (id is! int) return null;
    for (final record in history.reversed) {
      final fields = record.fields;
      if (record.tag != networkLogTag || fields['id'] != id) continue;
      if (record.time.isAfter(before)) continue;
      final source = fields['pluginId'];
      if (pluginId != null && source is String && source != pluginId) continue;
      final method = fields['method'];
      final host = fields['host'];
      final path = fields['path'];
      if (method is! String || host is! String || path is! String) continue;
      final query = fields['query'];
      final error = fields['error'];
      return ErrorReportRequest(
        method: redactor.redact(method),
        url: redactor.redact(
          '$host$path${query is String && query.isNotEmpty ? '?$query' : ''}',
        ),
        status: fields['status'] as int?,
        ms: fields['ms'] as int?,
        error: error is String ? redactor.redact(error) : null,
      );
    }
    return null;
  }

  final Redactor _redactor;

  /// UTC。
  final DateTime time;

  /// 使用者動作：`report` 的 operation（英文，例如 `Search failed`）。
  final String operation;

  /// 模組或音源 id。
  final String tag;

  /// 錯誤類型名稱（`AppError.typeName`）；不是 `report` 寫的紀錄時為 `null`。
  final String? type;

  /// [Unavailable] 的原因名稱。
  final String? reason;

  /// 原因：原始 error 遮蔽後的字串。
  final String? cause;
  final String? pluginId;
  final String? pluginVersion;
  final ErrorReportRequest? request;
  final String? stackTrace;
  final String appVersion;
  final String flavor;
  final String platform;
  final String osVersion;

  /// ISO 8601（UTC）。
  String get timestamp => time.toUtc().toIso8601String();

  /// GitHub issue 與「複製」用的 Markdown：標題、欄位清單、stack trace 放 code block。
  /// 整份在輸出前再過一次 [Redactor]。
  String toMarkdown() {
    final buffer = StringBuffer('## ${type ?? 'Error'}: $operation\n\n');
    void item(String label, Object? value) {
      if (value != null) buffer.writeln('- **$label**: $value');
    }

    item('Time', timestamp);
    item('Type', type);
    item('Reason', reason);
    item('Source', _source);
    item('Action', operation);
    item('Module', tag);
    if (request case final request?) {
      item('Request', '${request.method} ${request.url}');
      item('Status', request.status);
      item('Duration', request.ms == null ? null : '${request.ms} ms');
      item('Request error', request.error);
    }
    item('App', '$appVersion ($flavor)');
    item('System', '$platform, $osVersion');
    if (cause != null) buffer.write('\n### Cause\n\n${_fenced(cause!)}\n');
    if (stackTrace != null) {
      buffer.write('\n### Stack trace\n\n${_fenced(stackTrace!)}\n');
    }
    return _redactor.redact(buffer.toString());
  }

  String? get _source => pluginId == null
      ? null
      : pluginVersion == null
      ? pluginId
      : '$pluginId $pluginVersion';

  /// code block 用 `~` 的 fence：GitHub 的 issue 範本以 `render: markdown` 把整個欄位包進
  /// 反引號的 code block，裡面再出現反引號的 fence 會提早結束外層（CommonMark：反引號的
  /// fence 只被反引號關掉）。內容裡的 `~~~` 也不能提早結束它：fence 比內容裡最長的一串
  /// `~` 多一個。
  static String _fenced(String text) {
    var longest = 0;
    for (final run in RegExp('~+').allMatches(text)) {
      if (run.end - run.start > longest) longest = run.end - run.start;
    }
    final fence = '~' * (longest < 3 ? 3 : longest + 1);
    return '$fence\n$text\n$fence';
  }
}
