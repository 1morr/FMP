import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  @override
  String toString() => 'LogRecord(${toJsonLine()})';
}

/// 解析 log 檔的內容（JSON Lines）。空行與壞行略過，不中止（ADR 0025
/// §如何確認）：檔案可能在寫到一半時被截斷，或被人手動改過。
List<LogRecord> parseLogLines(String content) => [
  for (final line in const LineSplitter().convert(content))
    if (line.trim().isNotEmpty) ?LogRecord.tryParseJsonLine(line),
];
