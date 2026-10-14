import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fmp/core/redaction/redactor.dart';

/// 診斷包裡的 `diagnostics.txt` 與 `diagnostics.json`（ADR 0011 §決定 6、ADR 0025 §決定 10）。
/// 兩者來自同一份 [data]：整份先經 [Redactor.redactValue]（逐個字串遮蔽），再各自輸出；純文字
/// 輸出前再遮一次整段。JSON 不再對編碼後的整段文字遮蔽：header 名單的值遮到行尾，會連 JSON 的
/// 結尾引號與逗號一起吃掉，輸出就不是合法的 JSON；編碼只會把字元跳脫，逐個字串遮過的內容不會
/// 因此多出需要遮的東西。
///
/// [data] 只放 JSON 能表示的值，內容由 `DiagnosticsService` 決定；這裡不認得任何設定或插件。
@immutable
final class DiagnosticsReport {
  const DiagnosticsReport._({
    required this.data,
    required this.text,
    required this.json,
  });

  factory DiagnosticsReport.build(
    Map<String, Object?> data,
    Redactor redactor,
  ) {
    final redacted = redactor.redactValue(data)! as Map<String, Object?>;
    return DiagnosticsReport._(
      data: redacted,
      text: redactor.redact(_render(redacted)),
      json: const JsonEncoder.withIndent('  ').convert(redacted),
    );
  }

  /// 已遮蔽的資料。
  final Map<String, Object?> data;

  /// 人讀的純文字（`diagnostics.txt`，也是「複製」的內容）。
  final String text;

  /// `diagnostics.json`。
  final String json;

  /// 純文字：一層一層縮排的 `鍵: 值`；物件清單每項一行。
  static String _render(Map<String, Object?> data) {
    final buffer = StringBuffer();
    void write(Map<String, Object?> map, int depth) {
      final indent = '  ' * depth;
      for (final MapEntry(:key, :value) in map.entries) {
        switch (value) {
          case Map<String, Object?>():
            buffer.writeln('$indent$key:');
            write(value, depth + 1);
          case List<Object?>():
            buffer.writeln('$indent$key:');
            for (final item in value) {
              buffer.writeln('$indent  - ${_inline(item)}');
            }
          default:
            buffer.writeln('$indent$key: ${_scalar(value)}');
        }
      }
    }

    write(data, 0);
    return buffer.toString();
  }

  static String _inline(Object? item) => switch (item) {
    Map<String, Object?>() =>
      item.entries.map((e) => '${e.key}=${_scalar(e.value)}').join(', '),
    _ => _scalar(item),
  };

  static String _scalar(Object? value) => switch (value) {
    null => '-',
    true => 'yes',
    false => 'no',
    List<Object?>() => value.map(_scalar).join(', '),
    Map<String, Object?>() => _inline(value),
    _ => '$value',
  };
}
