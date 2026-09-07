import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 兩條把 5a③／5g 的結果鎖住的機械規則。
///
/// 掃的是整個 `lib/ui` 目錄而不是一份檔案清單，所以新增的頁面自動被涵蓋
/// （形狀照 `list_tile_leading_static_rule_test.dart`）。
void main() {
  group('Error presentation static rules', () {
    test('an async error branch never renders as nothing', () {
      // 區塊靜靜消失時，使用者讀到的是「我沒有資料」而不是「載入失敗」。
      // 封面／頭像退回 placeholder 是允許的 —— 那看起來就是「沒有封面」。
      final offenders = <String>[];
      final inline = RegExp(
        r'error:\s*\([^)]*\)\s*=>\s*(const\s+)?SizedBox\.shrink\(\)',
      );
      final block = RegExp(
        r'error:\s*\([^)]*\)\s*\{[^{}]*return\s+(const\s+)?SizedBox\.shrink\(\);',
      );
      final orElse = RegExp(
        r'orElse:\s*\(\)\s*=>\s*(const\s+)?SizedBox\.shrink\(\)',
      );

      for (final file in _uiDartFiles()) {
        final source = file.readAsStringSync();
        for (final pattern in [inline, block, orElse]) {
          if (pattern.hasMatch(source)) {
            offenders.add(file.path);
            break;
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'use ErrorDisplay(compact: true) with a retry instead',
      );
    });

    test('no i18n error template is filled with raw exception text', () {
      // `t.x.loadFailed(error: ...)` 翻譯的是外面那幾個字，`error:` 收到什麼就
      // 原樣顯示什麼。這條掃整個 `lib/`，不只 `lib/ui` —— 實機驗收時搜尋頁
      // 顯示了一整條含 URL 的 ClientException，來源在 `lib/services` 裡，
      // 只掃 UI 的規則看不到它。
      final offenders = <String>[];
      final template = RegExp(r't\.[A-Za-z0-9_.]+\(\s*error:[^)]*\)');
      final raw = RegExp(
        r"\b(e|err|error|exception)\.toString\(\)"
        r"|\$\{?(e|error)\}?(?![A-Za-z0-9_])",
      );

      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.contains('i18n')) continue;
        final source = file.readAsStringSync();
        for (final call in template.allMatches(source)) {
          if (raw.hasMatch(call.group(0)!)) {
            offenders.add('${file.path}: ${call.group(0)}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'pass userMessageFor(e) into the template, not the exception',
      );
    });

    test('no raw exception text is handed to a user-facing widget', () {
      // P1-7：`Exception: <伺服器原文>` 不該出現在畫面上。原文走 AppLogger，
      // 畫面走 userMessageFor。
      final offenders = <String>[];
      final raw = RegExp(
        r"""\b(e|err|error|exception|snapshot\.error|state\.error)\.toString\(\)"""
        r"""|\$\{?(e|error)\}?['"]""",
      );

      for (final file in _uiDartFiles()) {
        final source = file.readAsStringSync();
        for (final call in _callArguments(
          source,
          RegExp(r'ToastService\.\w+\('),
        ).followedBy(_callArguments(source, RegExp(r'ErrorDisplay[.\w]*\(')))) {
          if (raw.hasMatch(call)) {
            offenders.add('${file.path}: $call');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'wrap the exception in userMessageFor / ToastService.failure',
      );
    });
  });
}

Iterable<File> _uiDartFiles() => Directory('lib/ui')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// 取出每一個符合 [opening] 的呼叫的引數字串（括號平衡，忽略字串內的括號）。
List<String> _callArguments(String source, RegExp opening) {
  final calls = <String>[];
  for (final match in opening.allMatches(source)) {
    var depth = 0;
    String? quote;
    for (var i = match.end - 1; i < source.length; i++) {
      final ch = source[i];
      if (quote != null) {
        if (ch == r'\') {
          i++;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) {
          calls.add(source.substring(match.end, i));
          break;
        }
      }
    }
  }
  return calls;
}
