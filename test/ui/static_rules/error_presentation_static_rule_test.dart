import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

/// 三條「錯誤要讓使用者看得到、而且看得懂」的機械規則。
///
/// 掃的是整個 `lib/ui` 目錄而不是一份檔案清單，所以新增的頁面自動被涵蓋。
void main() {
  group('Error presentation static rules', () {
    test('an async error branch never renders as nothing', () {
      // 區塊靜靜消失時，使用者讀到的是「我沒有資料」而不是「載入失敗」。
      // 封面／頭像退回 placeholder 是允許的 —— 那看起來就是「沒有封面」。
      final offenders = <String>[];

      for (final file in _uiDartFiles()) {
        if (silentErrorBranches(file.readAsStringSync()).isNotEmpty) {
          offenders.add(file.path);
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

      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.contains('i18n')) continue;
        for (final call in rawExceptionInTemplates(file.readAsStringSync())) {
          offenders.add('${file.path}: $call');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'pass userMessageFor(e) into the template, not the exception',
      );
    });

    test('no raw exception text is handed to a user-facing widget', () {
      // `Exception: <伺服器原文>` 不該出現在畫面上。原文走 AppLogger，
      // 畫面走 userMessageFor。
      final offenders = <String>[];

      for (final file in _uiDartFiles()) {
        for (final call in rawExceptionInUserFacingCalls(
          file.readAsStringSync(),
        )) {
          offenders.add('${file.path}: $call');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'wrap the exception in userMessageFor / ToastService.failure',
      );
    });
  });

  group('the error presentation detectors', () {
    test('a synthesised violation is caught', () {
      const silent = '''
value.when(
  data: (items) => ItemList(items),
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => const SizedBox.shrink(),
)
''';
      const template = '''
ToastService.error(t.library.loadFailed(error: e.toString()));
''';
      const rawCall = '''
ToastService.error('Failed: \${e}');
''';

      expect(silentErrorBranches(silent), hasLength(1));
      expect(rawExceptionInTemplates(template), hasLength(1));
      expect(rawExceptionInUserFacingCalls(rawCall), hasLength(1));
    });

    test('a violation written in a comment does not count', () {
      const silent = '''
// error: (e, _) => const SizedBox.shrink() 會讓區塊靜靜消失。
value.when(
  data: (items) => ItemList(items),
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => const ErrorDisplay(compact: true),
)
''';
      const template = '''
/// 不要寫成 t.library.loadFailed(error: e.toString())。
ToastService.error(t.library.loadFailed(error: userMessageFor(e)));
''';
      const rawCall = '''
// ToastService.error('Failed: \${e}') 會把伺服器原文貼到畫面上。
ToastService.error(userMessageFor(e));
''';

      expect(silentErrorBranches(silent), isEmpty);
      expect(rawExceptionInTemplates(template), isEmpty);
      expect(rawExceptionInUserFacingCalls(rawCall), isEmpty);
    });
  });
}

/// `error:` / `orElse:` 分支直接畫一個空盒子。
final _silentBranchPatterns = <RegExp>[
  RegExp(r'error:\s*\([^)]*\)\s*=>\s*(const\s+)?SizedBox\.shrink\(\)'),
  RegExp(
    r'error:\s*\([^)]*\)\s*\{[^{}]*return\s+(const\s+)?SizedBox\.shrink\(\);',
  ),
  RegExp(r'orElse:\s*\(\)\s*=>\s*(const\s+)?SizedBox\.shrink\(\)'),
];

/// 例外原文 —— `e.toString()` 或直接插值進字串。
final _rawExceptionPattern = RegExp(
  r"\b(e|err|error|exception)\.toString\(\)"
  r"|\$\{?(e|error)\}?(?![A-Za-z0-9_])",
);

/// i18n 模板的 `error:` 參數。
final _i18nTemplatePattern = RegExp(r't\.[A-Za-z0-9_.]+\(\s*error:[^)]*\)');

/// 使用者看得到的呼叫入口。
final _userFacingCallPatterns = <RegExp>[
  RegExp(r'ToastService\.\w+\('),
  RegExp(r'ErrorDisplay[.\w]*\('),
];

List<String> silentErrorBranches(String source) {
  final code = stripDartComments(source);
  return [
    for (final pattern in _silentBranchPatterns)
      for (final match in pattern.allMatches(code)) match.group(0)!,
  ];
}

List<String> rawExceptionInTemplates(String source) {
  final code = stripDartComments(source);
  return [
    for (final call in _i18nTemplatePattern.allMatches(code))
      if (_rawExceptionPattern.hasMatch(call.group(0)!)) call.group(0)!,
  ];
}

List<String> rawExceptionInUserFacingCalls(String source) {
  final code = stripDartComments(source);
  final raw = RegExp(
    r"""\b(e|err|error|exception|snapshot\.error|state\.error)\.toString\(\)"""
    r"""|\$\{?(e|error)\}?['"]""",
  );

  return [
    for (final pattern in _userFacingCallPatterns)
      for (final call in _callArguments(code, pattern))
        if (raw.hasMatch(call)) call,
  ];
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
