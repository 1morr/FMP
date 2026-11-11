import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.githooks/pre-commit`：只有 staged 檔案含 `app/` 時才跑
/// `dart run tool/check.dart --quick`。在暫存 repo 裡用真的 `git commit`
/// 驗證，`app/tool/check.dart` 換成留下記號的替身。
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

  test('a commit touching only the legacy app or docs skips it', () {
    write('lib/main.dart', 'void main() {}\n');
    write('docs/progress.md', '# 進度\n');
    write('application/notes.md', 'not app/\n');
    git(['add', '-A']);
    final result = git(['commit', '-q', '-m', 'legacy change']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(marker().existsSync(), isFalse);
  });
}
