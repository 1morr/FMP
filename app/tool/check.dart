import 'dart:io';

import 'src/doc_gate.dart';
import 'src/steps.dart';

/// 新版的閘門（plan §4）。在 `app/` 裡跑：
///
///     dart run tool/check.dart --quick
///
/// `--quick`：產生 i18n、format、analyze、單元測試、文件閘門。完整版（四平台
/// 建置與 integration_test、插件打包產物）由 M0 票 02 接上。
Future<void> main(List<String> args) async {
  if (!args.contains('--quick')) {
    stderr.writeln(
      'The full gate lands in M0 ticket 02; only --quick exists for now.',
    );
    exit(64);
  }

  final app = File.fromUri(Platform.script).parent.parent;
  final repo = app.parent;

  final code = await runSteps([
    // *.g.dart 不進 git；先產生，analyze 與測試才看得到最新的字串。
    commandStep('i18n (slang)', 'dart', [
      'run',
      'slang',
    ], workingDirectory: app),
    commandStep('format', 'dart', [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ..._handwrittenDartFiles(app),
    ], workingDirectory: app),
    commandStep('analyze', 'flutter', ['analyze'], workingDirectory: app),
    commandStep('test', 'flutter', ['test'], workingDirectory: app),
    CheckStep('doc gate', () async {
      final problems = checkAcceptanceTickets(repo);
      problems.forEach(stdout.writeln);
      return problems.isEmpty;
    }),
  ], stdout);
  exit(code);
}

/// slang 的產物不照 dart format，所以 format 只看手寫的檔。
List<String> _handwrittenDartFiles(Directory app) {
  return [
    for (final dir in ['lib', 'test', 'tool', 'integration_test'])
      if (Directory('${app.path}/$dir').existsSync())
        for (final file in Directory(
          '${app.path}/$dir',
        ).listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              !file.path.endsWith('.g.dart'))
            file.path.substring(app.path.length + 1),
  ]..sort();
}
