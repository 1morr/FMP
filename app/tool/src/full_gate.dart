import 'dart:convert';
import 'dart:io';

import 'device_lock.dart';
import 'steps.dart';

/// 完整版閘門在 quick 之後的平台步驟（plan §2、§4）：先建置四個平台，再在
/// 四個平台跑 [integrationTests]。步驟名稱帶平台，失敗時看得出是哪個平台、
/// 哪一步。
///
/// - 碰共用裝置的步驟（`winpc` 的同步與建置、四平台的 integration_test）
///   夾在 `lock shared devices` 與 `unlock shared devices` 之間，持有
///   [deviceLock] 時才跑；沒拿到鎖就判失敗、不執行。Mac 上的三個建置只寫
///   這個 worktree 的 `build/`，在鎖外先做，縮短持鎖時間。
/// - 一次只給 `flutter test` 一個 integration_test 檔（plan §2 的怪癖）。
/// - iOS、Android 只挑模擬器，不碰連著的實機；加 `--no-uninstall`，跑完
///   不刪模擬器上的 App 與資料。Android 先 `adb start-server`。
/// - Windows 經 SSH 在 `winpc` 的桌面工作階段跑（plan §2〈Windows〉），
///   log 取回 [winpcLogs] 並印到 [out]。
List<CheckStep> platformSteps({
  required Directory app,
  required Shell shell,
  required List<String> integrationTests,
  required StringSink out,
  required Directory winpcLogs,
  required DeviceLock deviceLock,
}) {
  CheckStep flutter(String name, List<String> args) =>
      commandStep(name, shell, 'flutter', args, workingDirectory: app);

  CheckStep locked(CheckStep step) => CheckStep(step.name, () async {
    if (!deviceLock.isHeld) {
      out.writeln('Skipped: the shared-device lock is not held.');
      return false;
    }
    return step.run();
  });

  final windows = _Winpc(app, shell, out, winpcLogs);
  final sharedDeviceSteps = [
    CheckStep('build windows', windows.build),
    for (final file in integrationTests)
      flutter('integration_test macos: $file', ['test', file, '-d', 'macos']),
    for (final (platform, isTarget) in _emulators)
      for (final file in integrationTests)
        CheckStep('integration_test $platform: $file', () async {
          if (platform == 'android') {
            // adb server 不在時以 ADB_MDNS=0 叫起來（brief 事實 K15），在跑時
            // 什麼都不做；先叫起來，`flutter devices` 才看得到模擬器。
            await shell.run('adb', ['start-server'], workingDirectory: app);
          }
          final device = await _findEmulator(shell, app, platform, isTarget);
          final args = ['test', file, '-d', device, '--no-uninstall'];
          return await shell.run('flutter', args, workingDirectory: app) == 0;
        }),
    for (final file in integrationTests)
      CheckStep(
        'integration_test windows: $file',
        () => windows.integrationTest(file),
      ),
  ];

  return [
    flutter('build macos', ['build', 'macos', '--debug']),
    flutter('build ios', ['build', 'ios', '--simulator', '--debug']),
    flutter('build android', ['build', 'apk', '--debug']),
    CheckStep('lock shared devices', () async {
      await deviceLock.acquire(out);
      return true;
    }),
    ...sharedDeviceSteps.map(locked),
    CheckStep('unlock shared devices', () async {
      await deviceLock.release();
      return true;
    }),
  ];
}

const _emulators = [('ios', _isIos), ('android', _isAndroid)];

bool _isIos(String targetPlatform) => targetPlatform == 'ios';
bool _isAndroid(String targetPlatform) => targetPlatform.startsWith('android');

Future<String> _findEmulator(
  Shell shell,
  Directory app,
  String platform,
  bool Function(String targetPlatform) isTarget,
) async {
  final json = await shell.capture('flutter', [
    'devices',
    '--machine',
  ], workingDirectory: app);
  for (final device in jsonDecode(json) as List<dynamic>) {
    final {'id': String id, 'targetPlatform': String target} =
        device as Map<String, dynamic>;
    if (device['emulator'] == true && isTarget(target)) return id;
  }
  throw StateError(
    'No running $platform simulator/emulator found by `flutter devices`; '
    'boot one first (plan §2).',
  );
}

/// `winpc` 上的建置與 integration_test：同步工作樹、以排程工作執行
/// `tool/winpc/*.ps1`、取回 log。
class _Winpc {
  _Winpc(this.app, this.shell, this.out, this.logs);

  final Directory app;
  final Shell shell;
  final StringSink out;
  final Directory logs;

  Future<bool> build() async {
    if (await shell.run('tool/winpc/sync.sh', [], workingDirectory: app) != 0) {
      return false;
    }
    return _task(
      'fmpbuild',
      'build.ps1',
      ['-Mode', 'debug'],
      'build.log',
      'build.log',
    );
  }

  Future<bool> integrationTest(String file) {
    final name = file.split('/').last.replaceAll('.dart', '');
    return _task(
      'fmptest',
      'test.ps1',
      ['-File', file],
      'test.log',
      'test-$name.log',
    );
  }

  /// 以排程工作 [task] 跑 `C:/fmp-wt/<script>`。[remoteLog] 是腳本寫的 log
  /// （`C:\fmp-wt\` 底下），取回後存成 [localLog]。遠端 log 先刪掉，工作沒跑
  /// 起來時不會讀到上一次的結果。
  Future<bool> _task(
    String task,
    String script,
    List<String> args,
    String remoteLog,
    String localLog,
  ) async {
    await shell.run('ssh', [
      'winpc',
      'Remove-Item C:\\fmp-wt\\$remoteLog -EA SilentlyContinue',
    ], workingDirectory: app);
    final started = await shell.run('tool/winpc/run_task.sh', [
      task,
      'C:/fmp-wt/$script',
      ...args,
    ], workingDirectory: app);
    if (started != 0) return false;

    final log = await shell.capture('ssh', [
      'winpc',
      'Get-Content -Raw C:\\fmp-wt\\$remoteLog',
    ], workingDirectory: app);
    File('${logs.path}/$localLog')
      ..createSync(recursive: true)
      ..writeAsStringSync(log);
    out.writeln(log);
    return remoteLogPassed(log);
  }
}

/// `tool/winpc/*.ps1` 的 log 每個階段寫一行 `exit <階段>=<退出碼>`，跑完寫
/// `=== done`。全部階段為 0 且有 `=== done` 才算通過；工作中途死掉時沒有
/// `=== done`。
bool remoteLogPassed(String log) {
  final exits = RegExp(
    r'^exit [\w-]+=(-?\d+)\s*$',
    multiLine: true,
  ).allMatches(log).map((m) => m.group(1)).toList();
  return exits.isNotEmpty &&
      exits.every((code) => code == '0') &&
      RegExp(r'^=== done', multiLine: true).hasMatch(log);
}

/// `integration_test/` 底下的 `*_test.dart`（含子目錄），相對於 [app]、排序。
List<String> integrationTestFiles(Directory app) {
  final dir = Directory('${app.path}/integration_test');
  if (!dir.existsSync()) return [];
  return [
    for (final file in dir.listSync(recursive: true))
      if (file is File && file.path.endsWith('_test.dart'))
        file.path.substring(app.path.length + 1).replaceAll(r'\', '/'),
  ]..sort();
}
