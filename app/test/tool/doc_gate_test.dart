import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/doc_gate.dart';

/// 雙向變異：拿掉驗收票要紅；改票的內文、標題或編號不能紅。
void main() {
  test('the repo passes the doc gate', () {
    final problems = checkAcceptanceTickets(Directory('..'));
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('fmp_doc_gate_');
    _write(repo, 'docs/progress.md', _progress());
    _write(repo, '.scratch/m0/issues/01-skeleton.md', '# 01: 骨架\n');
    _write(repo, '.scratch/m0/issues/12-m0-acceptance.md', '# 12: M0 驗收\n');
  });

  tearDown(() => repo.deleteSync(recursive: true));

  test('a milestone in progress with an acceptance ticket passes', () {
    expect(checkAcceptanceTickets(repo), isEmpty);
  });

  group('turns red when', () {
    test('the acceptance ticket is removed', () {
      File('${repo.path}/.scratch/m0/issues/12-m0-acceptance.md').deleteSync();
      expect(checkAcceptanceTickets(repo), [contains('M0')]);
    });

    test('the ticket directory is missing', () {
      Directory('${repo.path}/.scratch/m0').deleteSync(recursive: true);
      expect(checkAcceptanceTickets(repo), [contains('.scratch/m0/issues/')]);
    });

    test('a second milestone in progress has no acceptance ticket', () {
      _write(repo, 'docs/progress.md', _progress(extraRows: [_m1Row]));
      _write(repo, '.scratch/m1/issues/01-sources.md', '# 01\n');
      expect(checkAcceptanceTickets(repo), [contains('M1')]);
    });

    test('a milestone row is malformed', () {
      _write(
        repo,
        'docs/progress.md',
        _progress(extraRows: ['| M1 | `.scratch/m1/issues/` |']),
      );
      expect(checkAcceptanceTickets(repo), [contains('cell count')]);
    });

    test('the milestone table cannot be found', () {
      _write(repo, 'docs/progress.md', '# 進度\n\n沒有表。\n');
      expect(checkAcceptanceTickets(repo), isNotEmpty);
    });
  });

  group('stays green when', () {
    test('the acceptance ticket is renumbered', () {
      File('${repo.path}/.scratch/m0/issues/12-m0-acceptance.md')
          .renameSync('${repo.path}/.scratch/m0/issues/14-m0-acceptance.md');
      expect(checkAcceptanceTickets(repo), isEmpty);
    });

    test('the acceptance ticket body and title change', () {
      _write(
        repo,
        '.scratch/m0/issues/12-m0-acceptance.md',
        '# 12: 驗收與封存\n\n**Status:** done\n',
      );
      expect(checkAcceptanceTickets(repo), isEmpty);
    });

    test('an archived milestone has no acceptance ticket', () {
      _write(repo, 'docs/progress.md', _progress(extraRows: [_archivedRow]));
      _write(repo, '.scratch/mx/issues/01-late-fix.md', '# 01\n');
      expect(checkAcceptanceTickets(repo), isEmpty);
    });

    test('a row has no ticket directory', () {
      _write(repo, 'docs/progress.md', _progress(extraRows: [_designRow]));
      expect(checkAcceptanceTickets(repo), isEmpty);
    });

    test('the table columns are reordered', () {
      _write(repo, 'docs/progress.md', '''
# 進度

## 里程碑與閱讀指引

| 備註 | 里程碑 | 票目錄 |
| --- | --- | --- |
| 進行中 | M0 | `.scratch/m0/issues/` |
''');
      expect(checkAcceptanceTickets(repo), isEmpty);
    });
  });
}

const _m1Row =
    '| M1 | `.scratch/m1/issues/` | `.scratch/m1/spec.md` | 已拆 1 張票 |';
const _archivedRow =
    '| MX | `.scratch/mx/issues/` | 無 | [封存](archive/mx.md)，見 `docs/archive/mx.md` |';
const _designRow = '| D | 無 | brief §11 | 和 M0 並行 |';

String _progress({List<String> extraRows = const []}) =>
    '''
# 進度

## 里程碑與閱讀指引

| 里程碑 | 票目錄 | 拆票前讀 | 備註 |
| --- | --- | --- | --- |
| M0 | `.scratch/m0/issues/` | `.scratch/m0/spec.md` | 已拆 2 張票 |
${extraRows.join('\n')}

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-11 | 01 | `.scratch/m9/issues/` 只是被提到 | 無 |
''';

void _write(Directory root, String path, String content) {
  File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
