import 'dart:io';

import 'device_lock.dart';
import 'full_gate.dart';
import 'plugin_bundle_gate.dart';
import 'schema_gate.dart';
import 'steps.dart';

/// `tool/check.dart` 的步驟（docs/app-development.md〈開發環境與閘門〉）。[quick] 時只有 quick 的步驟；完整版
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
    // 文件檢查是 Python 腳本（規則寫在它的 docstring），在 repo 根目錄跑。
    commandStep('doc gate', shell, 'python3', [
      'scripts/check_docs.py',
    ], workingDirectory: app.parent),
    commandStep('doc gate tests', shell, 'python3', [
      '-m',
      'unittest',
      'discover',
      '-s',
      'scripts/tests',
    ], workingDirectory: app.parent),
    if (!quick) ...[
      ...platformSteps(
        app: app,
        shell: shell,
        integrationTests: integrationTestFiles(app),
        out: out,
        winpcLogs: Directory('${app.path}/build/winpc'),
        deviceLock: DeviceLock.forRepo(app),
      ),
      pluginBundleStep(app: app, shell: shell, out: out),
    ],
  ];
}

/// `tool/check.dart` 跑外部指令用的 [Shell]：帶 [sharedDeviceEnvironment]。
Shell gateShell() => const ProcessShell(environment: sharedDeviceEnvironment);

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
