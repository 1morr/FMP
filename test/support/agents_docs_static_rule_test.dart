/// `AGENTS.md` 裡的引用還指得到東西嗎。
///
/// **這條測試只擋 BROKEN 類：名字不存在。** 它擋不住 STALE 類 —— 敘述本身是假
/// 的，而每個名字都還在。兩者裡 STALE 那類比較多也比較傷（一條「已完成」的假狀態
/// 會把人導向重做，而一條壞掉的路徑會當場失敗），所以**綠燈不是文檔正確的證明**。
/// 這一輪修掉的四條斷言錯誤裡只有一條是這裡抓得到的。
///
/// 只認反引號裡的**路徑**：`lib/` `test/` `docs/` `.github/` 開頭，或裸的
/// `*.dart` 檔名。原本還認「小寫開頭 + `()`」的方法呼叫，但那些引用全在已刪除
/// 的巢狀 `AGENTS.md` 裡，根檔一個也沒有 —— 對著零個消費點的閘門就一起刪了。
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

/// 佔位符，不是真的路徑。
bool _isPlaceholder(String token) =>
    token.contains('*') ||
    token.contains('<') ||
    token.contains('…') ||
    token.contains(' ');

/// 具名例外，value 是理由。
///
/// 例外必須是「這個名字**故意**不存在」，不是「還沒修」。
const _knownAbsent = <String, String>{
  'CLAUDE.md': '根 AGENTS.md 明文禁止新增的檔名',
  'CLAUDE.local.md': '根 AGENTS.md 明文禁止新增的檔名',
};

/// 文件裡引用、實際卻不存在的路徑，以及總共檢查了幾個。
///
/// 帶斜線的 token 用 [pathExists] 判斷；裸檔名只查它在不在 [basenames] 裡
/// （樹裡有同名檔就算數），不去猜它指哪一個 —— 會被停用的閘門不如沒有。
({List<String> broken, int scanned}) brokenRefs(
  String doc, {
  required bool Function(String path) pathExists,
  required Set<String> basenames,
}) {
  var scanned = 0;
  final broken = <String>[];
  for (final match in _pathPattern.allMatches(doc)) {
    final token = match.group(1)!;
    if (_isPlaceholder(token)) continue;
    if (_knownAbsent.containsKey(token)) continue;
    scanned++;
    final exists = token.contains('/')
        ? pathExists(token)
        : basenames.contains(token);
    if (!exists) broken.add(token);
  }
  return (broken: broken, scanned: scanned);
}

void main() {
  group('agent instruction references', () {
    test('every cited path exists', () {
      final basenames = {for (final f in _trackedFiles()) f.split('/').last};

      var scanned = 0;
      final broken = <String>[];
      for (final doc in _agentDocs()) {
        final result = brokenRefs(
          File(doc).readAsStringSync(),
          pathExists: (p) => File(p).existsSync() || Directory(p).existsSync(),
          basenames: basenames,
        );
        scanned += result.scanned;
        broken.addAll(result.broken.map((token) => '$doc -> $token'));
      }

      expect(scanned, greaterThan(20), reason: 'extractor matched nothing');
      expect(broken, isEmpty);
    });

    test('a missing path turns the check red, prose around it does not', () {
      const existing = {'lib/core/logger.dart', 'docs'};
      bool exists(String p) => existing.contains(p);
      const names = {'analysis_options.yaml'};

      const cited = '''
See `lib/core/logger.dart`, `docs` and `analysis_options.yaml`.
''';
      const withGone = '''
See `lib/core/logger.dart`, `docs` and `analysis_options.yaml`.
The old helper lived in `lib/core/gone.dart`, next to `gone_options.yaml`.
''';
      const rearranged = '''
- `analysis_options.yaml`

Moved to another section: `docs`, then `lib/core/logger.dart`, then a
placeholder `lib/**/*.dart` and prose like `flutter test`.
''';

      expect(
        brokenRefs(cited, pathExists: exists, basenames: names).broken,
        isEmpty,
      );
      expect(
        brokenRefs(withGone, pathExists: exists, basenames: names).broken,
        ['lib/core/gone.dart', 'gone_options.yaml'],
      );
      expect(
        brokenRefs(rearranged, pathExists: exists, basenames: names).broken,
        isEmpty,
      );
    });

    test('every named exception is still absent', () {
      for (final entry in _knownAbsent.entries) {
        final token = entry.key;
        expect(
          File(token).existsSync() || Directory(token).existsSync(),
          isFalse,
          reason: 'exception "$token" now exists; drop it (${entry.value})',
        );
      }
    });

    test('every instruction file is the root one', () {
      final found = _instructionFiles(_repoFiles());
      expect(
        found,
        {'AGENTS.md'},
        reason:
            'Claude Code stops reading AGENTS.md once a CLAUDE.md or '
            'CLAUDE.local.md exists; put the reason next to the code instead '
            'of adding a scoped instruction file',
      );
    });

    test(
      'the instruction-file filter catches scoped files and nothing else',
      () {
        // 違規：巢狀 AGENTS.md、任何位置的 CLAUDE.md / CLAUDE.local.md 都要被抓到。
        expect(
          _instructionFiles(const [
            'AGENTS.md',
            'lib/ui/AGENTS.md',
            'CLAUDE.md',
            '.claude/CLAUDE.md',
            'CLAUDE.local.md',
          ]),
          {
            'AGENTS.md',
            'lib/ui/AGENTS.md',
            'CLAUDE.md',
            '.claude/CLAUDE.md',
            'CLAUDE.local.md',
          },
        );
        // 無關：名字裡剛好有 agents / claude 的檔、以及順序不同，都不影響結果。
        expect(
          _instructionFiles(const [
            'docs/agents/domain.md',
            'lib/agents_md_notes.dart',
            '.claude/skills/verify-on-device/SKILL.md',
            'AGENTS.md',
          ]),
          {'AGENTS.md'},
        );
      },
    );

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
  });
}

/// 只有根目錄一份：巢狀的 `AGENTS.md` 與 `CLAUDE.md` 已刪除，理由搬進了程式碼
/// 旁的 dartdoc 與測試。見 `every instruction file is the root one`。
List<String> _agentDocs() => const ['AGENTS.md'];

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

/// 指令檔：任何名為 `AGENTS.md`、`CLAUDE.md` 或 `CLAUDE.local.md` 的檔案。
Set<String> _instructionFiles(Iterable<String> paths) => {
  for (final p in paths)
    if (const {
      'AGENTS.md',
      'CLAUDE.md',
      'CLAUDE.local.md',
    }.contains(p.split('/').last))
      p,
};

/// 倉庫裡會被 agent 讀到的位置：根目錄的檔案加上各個原始碼樹。
///
/// 不掃 `build/`、`.dart_tool/` 這類建置產物；`.claude/` 要掃，因為
/// `.claude/CLAUDE.md` 同樣會讓 Claude Code 停止讀 `AGENTS.md`。
List<String> _repoFiles() => [
  ..._trackedFiles(),
  ...['tool', 'assets']
      .where((r) => Directory(r).existsSync())
      .expand(
        (r) => Directory(r)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => _posix(f.path)),
      ),
];
