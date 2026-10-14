import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fmp/core/redaction/redactor.dart';

/// log 層級（ADR 0011 §決定 2）。順序即嚴重程度。
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// 寫進 log 檔的字串。持久化格式：與 [name] 分開寫死，改名不會改到檔案。
  String get wireName => switch (this) {
    debug => 'debug',
    info => 'info',
    warning => 'warning',
    error => 'error',
  };

  static LogLevel? _fromWireName(Object? name) => switch (name) {
    'debug' => debug,
    'info' => info,
    'warning' => warning,
    'error' => error,
    _ => null,
  };
}

/// 一筆已遮蔽的 log（ADR 0025 §決定 3）。記憶體歷史與 log 檔都存這個形狀。
///
/// error 與 stackTrace 在進門面時就轉成遮蔽過的字串，原始物件不會留下來。
@immutable
final class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.fields = const {},
  });

  /// UTC。
  final DateTime time;
  final LogLevel level;

  /// 模組或音源 id。
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  /// 結構化欄位，只含 JSON 能表示的值（`Redactor.redactValue` 的結果）。
  final Map<String, Object?> fields;

  /// log 檔的一行（JSON Lines）。欄位名稱是持久化格式；空的 error、
  /// stackTrace、fields 不寫。
  String toJsonLine() => jsonEncode({
    'time': time.toUtc().toIso8601String(),
    'level': level.wireName,
    'tag': tag,
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (fields.isNotEmpty) 'fields': fields,
  });

  /// 解析 [toJsonLine] 寫出的一行；格式不對時回傳 `null`。
  static LogRecord? tryParseJsonLine(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (json case {
      'time': final String time,
      'level': final Object level,
      'tag': final String tag,
      'message': final String message,
    }) {
      final parsedTime = DateTime.tryParse(time);
      final parsedLevel = LogLevel._fromWireName(level);
      final error = json['error'];
      final stackTrace = json['stackTrace'];
      final fields = json['fields'];
      if (parsedTime == null ||
          parsedLevel == null ||
          error is! String? ||
          stackTrace is! String? ||
          fields is! Map<String, Object?>?) {
        return null;
      }
      return LogRecord(
        time: parsedTime.toUtc(),
        level: parsedLevel,
        tag: tag,
        message: message,
        error: error,
        stackTrace: stackTrace,
        fields: fields ?? const {},
      );
    }
    return null;
  }

  /// 以 [redactor] 再遮一次每個欄位（與門面寫入時同一套：文字欄位 [Redactor.redact]、
  /// [fields] [Redactor.redactValue]）。已遮過的內容再遮一次不變；用在寫入之後才登記的
  /// 家目錄或憑證值（[redactLogLines]）。
  LogRecord redactedWith(Redactor redactor) {
    final redactedFields = redactor.redactValue(fields);
    return LogRecord(
      time: time,
      level: level,
      tag: redactor.redact(tag),
      message: redactor.redact(message),
      error: error == null ? null : redactor.redact(error!),
      stackTrace: stackTrace == null ? null : redactor.redact(stackTrace!),
      fields: redactedFields is Map<String, Object?>
          ? redactedFields
          : const {},
    );
  }

  @override
  String toString() => 'LogRecord(${toJsonLine()})';
}

/// 解析 log 檔的內容（JSON Lines）。空行與壞行略過，不中止（ADR 0025
/// §如何確認）：檔案可能在寫到一半時被截斷，或被人手動改過。
List<LogRecord> parseLogLines(String content) => [
  for (final line in const LineSplitter().convert(content))
    if (line.trim().isNotEmpty) ?LogRecord.tryParseJsonLine(line),
];

/// 以目前的 [redactor] 再遮一次 log 檔的內容，輸出仍是 JSON Lines（一行一筆、換行結尾）。
///
/// log 檔寫入時已經遮蔽，但遮蔽函式只認得「寫入當時」登記的東西：家目錄登記之前（更早的版本）、
/// 憑證值登記之前寫的行仍帶原值。診斷包與「匯出 log 檔」送出裝置前一律經這裡（ADR 0025
/// §決定 10）。解析得出的行逐欄位重遮再編碼（不對整行遮：header 名單的值遮到行尾，會吃掉 JSON
/// 的結尾引號）；解析不出的壞行整行經 [Redactor.redact]，照樣留著（它不是 JSON，遮到行尾也
/// 不會更壞）；空行略過。
String redactLogLines(String content, Redactor redactor) {
  final buffer = StringBuffer();
  for (final line in const LineSplitter().convert(content)) {
    if (line.trim().isEmpty) continue;
    final record = LogRecord.tryParseJsonLine(line);
    buffer
      ..write(
        record == null
            ? redactor.redact(line)
            : record.redactedWith(redactor).toJsonLine(),
      )
      ..write('\n');
  }
  return buffer.toString();
}
