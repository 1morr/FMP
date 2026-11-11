import 'dart:io';

/// 文件閘門：`docs/progress.md` 里程碑表裡還沒驗收的里程碑，它的票目錄
/// 要有一張 `*-acceptance.md`（`AGENTS.md`〈Skills〉里程碑開工第 2 步）。
///
/// 已驗收的里程碑（備註換成 `docs/archive/` 的連結）不查，驗收後補的票
/// 不影響。回傳問題清單，空的代表通過。
List<String> checkAcceptanceTickets(Directory repoRoot) {
  final progress = File('${repoRoot.path}/docs/progress.md');
  if (!progress.existsSync()) return ['docs/progress.md not found'];

  final table = _milestoneTable(progress.readAsLinesSync());
  if (table == null) {
    return [
      'docs/progress.md: no table with 里程碑, 票目錄 and 備註 columns '
          'under "## 里程碑與閱讀指引"',
    ];
  }

  final problems = <String>[];
  for (final row in table) {
    if (row == null) {
      problems.add(
        'docs/progress.md: a milestone row has the wrong cell count',
      );
      continue;
    }
    final dir = RegExp(r'`([^`]*/issues/?)`').firstMatch(row['票目錄']!)?[1];
    if (dir == null) continue;
    if (RegExp(r'archive/[\w.-]+\.md').hasMatch(row['備註']!)) continue;

    final milestone = row['里程碑'];
    final issues = Directory('${repoRoot.path}/$dir');
    if (!issues.existsSync()) {
      problems.add('$milestone: ticket directory $dir does not exist');
      continue;
    }
    final hasAcceptance = issues.listSync().any(
      (e) => e is File && e.path.endsWith('-acceptance.md'),
    );
    if (!hasAcceptance) {
      problems.add(
        '$milestone: $dir has no *-acceptance.md ticket; every milestone '
        'in progress ends with one (AGENTS.md, Skills)',
      );
    }
  }
  return problems;
}

/// 「## 里程碑與閱讀指引」底下第一張表，每列以欄名為 key；欄數不對的列是
/// null。
List<Map<String, String>?>? _milestoneTable(List<String> lines) {
  final start = lines.indexWhere((l) => l.trim() == '## 里程碑與閱讀指引');
  if (start < 0) return null;

  List<String> cells(String line) {
    final parts = line.trim().split('|');
    return [for (final p in parts.sublist(1, parts.length - 1)) p.trim()];
  }

  final rows = <List<String>>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('#')) break;
    if (line.trim().startsWith('|')) {
      rows.add(cells(line));
    } else if (rows.isNotEmpty) {
      break;
    }
  }
  if (rows.length < 2) return null;

  final header = rows.first;
  const required = ['里程碑', '票目錄', '備註'];
  if (!required.every(header.contains)) return null;

  return [
    for (final row in rows.skip(2))
      row.length == header.length
          ? {for (var i = 0; i < header.length; i++) header[i]: row[i]}
          : null,
  ];
}
