import 'dart:io';

import 'doc_gate.dart';
import 'full_gate.dart';
import 'schema_gate.dart';
import 'steps.dart';

/// `tool/check.dart` 的步驟（plan §4）。[quick] 時只有 quick 的步驟；完整版
/// 再接上四平台的建置與 integration_test（[platformSteps]）。
List<CheckStep> gateSteps({
  required bool quick,
  required Directory app,
  required Shell shell,
  required StringSink out,
}) {
  CheckStep command(String name, String executable, List<String> args) =>
      commandStep(name, shell, executable, args, workingDirectory: app);

  return [
    // *.g.dart 不進 git；先產生，analyze 與測試才看得到最新的字串。
    command('i18n (slang)', 'dart', ['run', 'slang']),
    // drift 的 database.g.dart 同理。
    command('codegen (build_runner)', 'dart', ['run', 'build_runner', 'build']),
    command('format', 'dart', [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ..._handwrittenDartFiles(app),
    ]),
    command('analyze', 'flutter', ['analyze']),
    command('test', 'flutter', ['test']),
    schemaSnapshotStep(app: app, shell: shell, out: out),
    CheckStep('doc gate', () async {
      final problems = checkAcceptanceTickets(app.parent);
      problems.forEach(out.writeln);
      return problems.isEmpty;
    }),
    if (!quick) ...[
      ...platformSteps(
        app: app,
        shell: shell,
        integrationTests: integrationTestFiles(app),
        out: out,
        winpcLogs: Directory('${app.path}/build/winpc'),
      ),
      // M0 票 08：「插件打包產物是否最新」（plan §4）接在這裡。
    ],
  ];
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
