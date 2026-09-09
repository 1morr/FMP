/// `AGENTS.md` 裡的引用還指得到東西嗎。
///
/// **這條測試只擋 BROKEN 類：名字不存在。** 它擋不住 STALE 類 —— 敘述本身是假
/// 的，而每個名字都還在。兩者裡 STALE 那類比較多也比較傷（一條「已完成」的假狀態
/// 會把人導向重做，而一條壞掉的路徑會當場失敗），所以**綠燈不是文檔正確的證明**。
/// 這一輪修掉的四條斷言錯誤裡只有一條是這裡抓得到的。
///
/// 只認兩種形狀，都在反引號裡：
///
/// - **路徑**：`lib/` `test/` `docs/` `.github/` 開頭，或裸的 `*.dart` 檔名。
/// - **方法**：小寫開頭 + `()`。
///
/// **刻意不認裸識別符。** 在這棵樹上實測 191 個候選、10 個零命中，而那 10 個
/// 全部是文檔**刻意**提到不存在的東西：被明文禁止的名字（`isDesktop`）、明說
/// 「沒有這個東西」的 API（`supportsQueue`）、以及歷史沿革（`_PlaybackContext`
/// 「以前住在這裡」）。要它們存在會直接牴觸根 `AGENTS.md` 的「Preserve comments
/// that explain … historical rationale」。那不是調參問題，是類別問題。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 反引號裡看起來像倉庫路徑的 token。
final _pathPattern = RegExp(
  r'`((?:lib|test|docs|android|ios|windows|macos|linux|web|assets|licenses|screenshots|\.github|\.claude)/[^`]+|[A-Za-z0-9_.-]+\.(?:dart|yaml|yml|json|md))`',
);

/// 反引號裡的方法呼叫：小寫或底線開頭，後面接一對空括號。
final _methodPattern = RegExp(r'`(_?[a-z][A-Za-z0-9_]*)\(\)`');

/// 佔位符，不是真的路徑。
bool _isPlaceholder(String token) =>
    token.contains('*') ||
    token.contains('<') ||
    token.contains('…') ||
    token.contains(' ');

/// 本檔自己的路徑。
///
/// 它必須被排除在被掃描的語料之外：下面 parser 自測裡的合成樣本含有真實的識別
/// 符字面值，留在語料裡會讓「這個名字存在嗎」永遠答 yes —— 第一次寫的時候就是
/// 這樣，`_migrateDatabase()` 的變異驗證因此靜靜地通過了。
const _selfPath = 'test/support/agents_docs_static_rule_test.dart';

/// 具名例外，value 是理由。
///
/// 例外必須是「這個名字**故意**不存在」，不是「還沒修」。
const _knownAbsent = <String, String>{};

void main() {
  group('agent instruction references', () {
    test('every cited path exists', () {
      final basenames = <String, int>{};
      for (final file in _trackedFiles()) {
        final name = file.split('/').last;
        basenames[name] = (basenames[name] ?? 0) + 1;
      }

      var scanned = 0;
      final broken = <String>[];
      for (final doc in _agentDocs()) {
        final source = File(doc).readAsStringSync();
        for (final match in _pathPattern.allMatches(source)) {
          final token = match.group(1)!;
          if (_isPlaceholder(token)) continue;
          if (_knownAbsent.containsKey(token)) continue;
          scanned++;
          if (token.contains('/')) {
            if (!File(token).existsSync() && !Directory(token).existsSync()) {
              broken.add('$doc -> $token');
            }
            continue;
          }
          // 裸檔名：只在剛好有一個同名檔時才判斷，否則跳過。
          // 抄 chrishayuk/larql 的降噪法 —— 會被停用的閘門不如沒有。
          if (basenames[token] == null) broken.add('$doc -> $token');
        }
      }

      expect(scanned, greaterThan(100), reason: 'extractor matched nothing');
      expect(broken, isEmpty);
    });

    test('every cited method exists', () {
      final sources = [..._dartFilesUnder('lib'), ..._dartFilesUnder('test')]
          .where((p) => p != _selfPath)
          .map(File.new)
          .map((f) => f.readAsStringSync())
          .toList();

      var scanned = 0;
      final broken = <String>[];
      for (final doc in _agentDocs()) {
        final source = File(doc).readAsStringSync();
        for (final match in _methodPattern.allMatches(source)) {
          final name = match.group(1)!;
          if (_knownAbsent.containsKey('$name()')) continue;
          scanned++;
          final word = RegExp('\\b${RegExp.escape(name)}\\b');
          if (!sources.any(word.hasMatch)) broken.add('$doc -> $name()');
        }
      }

      expect(scanned, greaterThan(20), reason: 'extractor matched nothing');
      expect(broken, isEmpty);
    });

    test('every named exception is still absent', () {
      for (final entry in _knownAbsent.entries) {
        final token = entry.key;
        if (token.endsWith('()')) continue;
        expect(
          File(token).existsSync() || Directory(token).existsSync(),
          isFalse,
          reason: 'exception "$token" now exists; drop it (${entry.value})',
        );
      }
    });

    // 01-決策-2 選過「進 repo 但禁止程式碼引用」，然後那條規則從來沒有被寫進任何
    // 地方，也從來沒有被遵守 —— 清掉的時候有 22 處引用要改，其中兩處指向一個幾個
    // 月前就刪掉的檔案。這條測試就是那個決定第一次真的有閘門。
    //
    // 根 AGENTS.md 與本檔不算：規則本身總得叫得出它禁止的那個名字。
    test('code does not cite the execution log', () {
      final offenders = <String>[];
      for (final path in [
        ..._dartFilesUnder('lib'),
        ..._dartFilesUnder('test'),
        ..._agentDocs().where((p) => p != 'AGENTS.md'),
      ]) {
        if (path == _selfPath) continue;
        if (File(path).readAsStringSync().contains('docs/review')) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'docs/review/execution-log.md is history. Put the fact in the file '
            'it describes instead.',
      );
    });

    test('the path extractor reads paths, not prose or placeholders', () {
      const doc = '''
Real: `lib/core/logger.dart` and `docs/README.md` and `analysis_options.yaml`.
Placeholders: `lib/**/*.dart`, `docs/adr/NNNN-<slug>.md`, `test/**`.
Prose: run `flutter test` and read `AudioController`.
''';
      final found = _pathPattern
          .allMatches(doc)
          .map((m) => m.group(1)!)
          .where((t) => !_isPlaceholder(t))
          .toList();
      expect(found, [
        'lib/core/logger.dart',
        'docs/README.md',
        'analysis_options.yaml',
      ]);
    });

    test('the method extractor ignores types and bare identifiers', () {
      const doc = '''
Calls: `openFmpDatabase()` and `_migrateDatabase()`.
Not calls: `SourceManager`, `isDesktop`, `AudioController.playMedia`.
''';
      expect(_methodPattern.allMatches(doc).map((m) => m.group(1)).toList(), [
        'openFmpDatabase',
        '_migrateDatabase',
      ]);
    });
  });
}

List<String> _agentDocs() => [
  'AGENTS.md',
  ...Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => _posix(f.path))
      .where((p) => p.endsWith('/AGENTS.md')),
];

List<String> _dartFilesUnder(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => _posix(f.path))
    .where((p) => p.endsWith('.dart') && !p.endsWith('.g.dart'))
    .toList();

/// 判斷裸檔名用的候選集合：整棵樹的檔案，排除建置產物。
List<String> _trackedFiles() {
  final out = <String>[];
  for (final root in const [
    'lib',
    'test',
    'docs',
    'android',
    'windows',
    '.github',
    '.claude',
  ]) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    out.addAll(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => _posix(f.path))
          .where((p) => !p.contains('/build/')),
    );
  }
  out.addAll(
    Directory('.').listSync().whereType<File>().map(
      (f) => _posix(f.path).replaceFirst('./', ''),
    ),
  );
  return out;
}

String _posix(String path) => path.replaceAll(r'\', '/');
