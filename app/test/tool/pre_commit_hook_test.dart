import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.githooks/pre-commit`：staged 檔案含 `app/` 時跑
/// `dart run tool/check.dart --quick`；沒有 `app/`、但有文件或票時跑
/// `python3 scripts/check_docs.py`；只改舊版時都不跑。在暫存 repo 裡用真的
/// `git commit` 驗證，兩支檢查都換成留下記號的替身。
void main() {
  final hook = File('../.githooks/pre-commit');
  late Directory repo;

  // 這支測試可能在 pre-commit 裡被跑到；那時 git 會設 GIT_DIR、
  // GIT_INDEX_FILE 等變數，繼承下去就會改到真正的 repo。
  final env = {
    for (final MapEntry(:key, :value) in Platform.environment.entries)
      if (!key.startsWith('GIT_')) key: value,
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': '/dev/null',
  };

  ProcessResult git(List<String> args) => Process.runSync(
    'git',
    ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args],
    workingDirectory: repo.path,
    environment: env,
    includeParentEnvironment: false,
  );

  void write(String path, String content) => File('${repo.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  File marker() => File('${repo.path}/check-ran');

  setUp(() {
    repo = Directory.systemTemp.createTempSync('fmp_hook_');
    git(['init', '-q']);
    write('.githooks/pre-commit', hook.readAsStringSync());
    Process.runSync('chmod', ['+x', '${repo.path}/.githooks/pre-commit']);
    git(['config', 'core.hooksPath', '.githooks']);
    write('app/tool/check.dart', '''
import 'dart:io';
void main(List<String> args) {
  // git 給 hook 的 GIT_DIR 等變數會讓 flutter 讀錯自己的 SDK 版本。
  final leaked = Platform.environment.keys.where((k) => k.startsWith('GIT_'));
  File('../check-ran').writeAsStringSync([...args, ...leaked].join(' '));
  exit(Platform.environment['CHECK_FAILS'] == '1' ? 1 : 0);
}
''');
    write('README.md', 'x\n');
    git(['add', '-A']);
    git(['commit', '-q', '--no-verify', '-m', 'init']);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  test('a commit touching app/ runs the quick gate', () {
    write('app/lib/main.dart', 'void main() {}\n');
    git(['add', 'app/lib/main.dart']);
    final result = git(['commit', '-q', '-m', 'app change']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(marker().readAsStringSync(), '--quick');
  });

  test('a failing quick gate blocks the commit', () {
    env['CHECK_FAILS'] = '1';
    addTearDown(() => env.remove('CHECK_FAILS'));
    write('app/lib/main.dart', 'void main() {}\n');
    git(['add', 'app/lib/main.dart']);
    expect(git(['commit', '-q', '-m', 'app change']).exitCode, isNot(0));
    expect(
      git(['log', '--oneline']).stdout.toString().trim().split('\n'),
      hasLength(1),
    );
  });

  test('moving a file out of app/ also runs it', () {
    write('app/lib/moved.dart', 'void main() {}\n' * 20);
    git(['add', '-A']);
    git(['commit', '-q', '--no-verify', '-m', 'add']);
    git(['mv', 'app/lib/moved.dart', 'moved.dart']);
    final result = git(['commit', '-q', '-m', 'move out of app']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(marker().existsSync(), isTrue);
  });

  File docsMarker() => File('${repo.path}/docs-check-ran');

  /// 文件檢查的替身：留下記號，`DOCS_FAIL` 存在時失敗。
  void fakeDocsCheck() {
    write('scripts/check_docs.py', '''
import os, sys
open("docs-check-ran", "w").write(" ".join(k for k in os.environ if k.startswith("GIT_")))
sys.exit(1 if os.path.exists("DOCS_FAIL") else 0)
''');
    git(['add', '-A']);
    git(['commit', '-q', '--no-verify', '-m', 'add the docs check']);
  }

  test('a commit touching only the legacy app skips both checks', () {
    fakeDocsCheck();
    write('lib/main.dart', 'void main() {}\n');
    write('application/notes.md', 'not app/\n');
    write('documents/notes.md', 'not docs/\n');
    git(['add', '-A']);
    final result = git(['commit', '-q', '-m', 'legacy change']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(marker().existsSync(), isFalse);
    expect(docsMarker().existsSync(), isFalse);
  });

  for (final path in [
    'docs/progress.md',
    '.scratch/m1/issues/01-x.md',
    'AGENTS.md',
    'ARCHITECTURE.md',
  ]) {
    test('a commit touching $path runs only the docs check', () {
      fakeDocsCheck();
      write(path, '# x\n');
      git(['add', '-A']);
      final result = git(['commit', '-q', '-m', 'docs change']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(marker().existsSync(), isFalse);
      // 檢查裡的 git 指令不能繼承 hook 的 GIT_* 變數。
      expect(docsMarker().readAsStringSync(), isEmpty);
    });
  }

  test('a failing docs check blocks the commit', () {
    fakeDocsCheck();
    write('DOCS_FAIL', '');
    write('docs/progress.md', '# 進度\n');
    git(['add', 'docs/progress.md']);
    expect(git(['commit', '-q', '-m', 'docs change']).exitCode, isNot(0));
    expect(
      git(['log', '--oneline']).stdout.toString().trim().split('\n'),
      hasLength(2),
    );
  });
}
