import 'dart:convert';
import 'dart:io';

import 'device_lock.dart';
import 'steps.dart';

/// 完整版閘門在 quick 之後的平台步驟（docs/development.md〈平台〉〈開發環境與閘門〉）：先建置四個平台，再在
/// 四個平台跑 [integrationTests]。步驟名稱帶平台，失敗時看得出是哪個平台、
/// 哪一步。
///
/// - 碰共用裝置的步驟（`winpc` 的同步與建置、macOS 的原生測試、四平台的
///   integration_test）夾在 `lock shared devices` 與 `unlock shared devices` 之間，持有
///   [deviceLock] 時才跑；沒拿到鎖就判失敗、不執行。Mac 上的建置（三個平台與 macOS 的原生
///   測試）只寫這個 worktree 的 `build/`，在鎖外先做，縮短持鎖時間。
/// - 一次只給 `flutter test` 一個 integration_test 檔（docs/development.md〈平台〉 的怪癖）。
/// - iOS、Android 只挑模擬器，不碰連著的實機；加 `--no-uninstall`，跑完
///   不刪模擬器上的 App 與資料。iOS 只用 iPhone，沒開著就開一台
///   （[_ensureBootedIPhone]）；Android 先 `adb start-server`。
/// - Windows 經 SSH 在 `winpc` 的桌面工作階段跑（docs/development.md〈平台〉〈Windows〉），
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

  // 模擬器上的 integration_test：跑完不刪 App 與資料（docs/development.md〈平台〉）。
  Future<bool> testOnEmulator(String file, String device) async =>
      await shell.run('flutter', [
        'test',
        file,
        '-d',
        device,
        '--no-uninstall',
      ], workingDirectory: app) ==
      0;

  CheckStep locked(CheckStep step) => CheckStep(step.name, () async {
    if (!deviceLock.isHeld) {
      out.writeln('Skipped: the shared-device lock is not held.');
      return false;
    }
    return step.run();
  });

  // 和 `flutter build macos` 共用 build/macos，build-for-testing 只補建測試目標。
  const macosNativeTests = [
    '-workspace',
    'macos/Runner.xcworkspace',
    '-scheme',
    'Runner',
    '-destination',
    'platform=macOS',
    '-derivedDataPath',
    'build/macos',
  ];
  final windows = _Winpc(app, shell, out, winpcLogs);
  final sharedDeviceSteps = [
    CheckStep('build windows', windows.build),
    // macos/RunnerTests 跑在 Mac 的 App 裡，讀真的視窗（紅綠燈的位置，事實 M13）；
    // 建置在鎖外（[macosNativeTests] 的 build-for-testing）。
    commandStep('native tests macos', shell, 'xcodebuild', [
      'test-without-building',
      ...macosNativeTests,
      '-only-testing:RunnerTests',
    ], workingDirectory: app),
    for (final file in integrationTests)
      flutter('integration_test macos: $file', ['test', file, '-d', 'macos']),
    for (final file in integrationTests)
      CheckStep('integration_test ios: $file', () async {
        // 每個檔都重查：模擬器可能在兩個檔之間被關掉。
        final device = await _ensureBootedIPhone(shell, app, out);
        return testOnEmulator(file, device);
      }),
    for (final file in integrationTests)
      CheckStep('integration_test android: $file', () async {
        // adb server 不在時以 ADB_MDNS=0 叫起來（brief 事實 K15），在跑時
        // 什麼都不做；先叫起來，`flutter devices` 才看得到模擬器。
        await shell.run('adb', ['start-server'], workingDirectory: app);
        return testOnEmulator(file, await _androidEmulator(shell, app));
      }),
    for (final file in integrationTests)
      CheckStep(
        'integration_test windows: $file',
        () => windows.integrationTest(file),
      ),
  ];

  return [
    flutter('build macos', ['build', 'macos', '--debug']),
    commandStep('build macos native tests', shell, 'xcodebuild', [
      'build-for-testing',
      ...macosNativeTests,
    ], workingDirectory: app),
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

/// 開著的 iPhone 模擬器的 udid（也是 `flutter test -d` 的裝置 id）。
///
/// 從 `xcrun simctl list devices --json` 挑：它只列模擬器，不會挑到連著的
/// 實體 iPhone；只挑 iPhone，iPad 開著也不用。沒有開著的 iPhone 時，開最近用過
/// （`lastUsedAt`）的那台可用的 iPhone，在 [out] 印出原因，用
/// `simctl bootstatus -b` 開機並等到開好（事實 T5）。模擬器會在閘門之外被
/// 關掉，例如 Orca 的模擬器面板換裝置時會關掉前一台（docs/development.md
/// 〈其他已知怪癖〉）。
Future<String> _ensureBootedIPhone(
  Shell shell,
  Directory app,
  StringSink out,
) async {
  final json = await shell.capture('xcrun', [
    'simctl',
    'list',
    'devices',
    '--json',
  ], workingDirectory: app);
  final {'devices': Map<String, dynamic> runtimes} =
      jsonDecode(json) as Map<String, dynamic>;
  final iPhones = [
    for (final devices in runtimes.values)
      for (final device in devices as List<dynamic>)
        if (device
            case {
              'udid': String udid,
              'name': String name,
              'state': String state,
              'isAvailable': true,
              'deviceTypeIdentifier': String type,
            }
            when type.startsWith(
              'com.apple.CoreSimulator.SimDeviceType.iPhone',
            ))
          (
            udid: udid,
            name: name,
            booted: state == 'Booted',
            lastUsedAt: switch ((device
                as Map<String, dynamic>)['lastUsedAt']) {
              final String at => DateTime.tryParse(at),
              _ => null,
            },
          ),
  ];
  for (final iPhone in iPhones) {
    if (iPhone.booted) return iPhone.udid;
  }
  if (iPhones.isEmpty) {
    throw StateError(
      'No available iPhone simulator in `xcrun simctl list devices`; '
      'create one in Xcode (docs/development.md〈iOS 模擬器〉).',
    );
  }
  // 沒用過的（沒有 lastUsedAt）排最後。
  final never = DateTime.utc(0);
  final recent = iPhones.reduce(
    (a, b) => (b.lastUsedAt ?? never).isAfter(a.lastUsedAt ?? never) ? b : a,
  );
  out.writeln(
    'No booted iPhone simulator (it may have been shut down outside the gate, '
    "e.g. by Orca's emulator pane switching devices; docs/development.md"
    '〈iOS 模擬器〉); booting ${recent.name} (${recent.udid}).',
  );
  final booted = await shell.run('xcrun', [
    'simctl',
    'bootstatus',
    recent.udid,
    '-b',
  ], workingDirectory: app);
  if (booted != 0) {
    throw StateError('`xcrun simctl bootstatus ${recent.udid} -b` failed.');
  }
  return recent.udid;
}

/// `flutter devices --machine` 裡第一台 Android 模擬器的 id，不挑實機。
Future<String> _androidEmulator(Shell shell, Directory app) async {
  final json = await shell.capture('flutter', [
    'devices',
    '--machine',
  ], workingDirectory: app);
  for (final device in jsonDecode(json) as List<dynamic>) {
    final {'id': String id, 'targetPlatform': String target} =
        device as Map<String, dynamic>;
    if (device['emulator'] == true && target.startsWith('android')) return id;
  }
  throw StateError(
    'No running android simulator/emulator found by `flutter devices`; '
    'boot one first (docs/development.md〈平台〉).',
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
