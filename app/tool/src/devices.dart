/// 完整閘門與實跑（`tool/real_run.dart`）共用的裝置操作：挑模擬器、在 `winpc`
/// 建置與跑 integration_test（docs/development.md〈平台〉）。呼叫的人自己持有共用
/// 裝置鎖。
library;

import 'dart:convert';
import 'dart:io';

import 'steps.dart';

/// 開著的 iPhone 模擬器的 udid（也是 `flutter test -d` 的裝置 id）。
///
/// 從 `xcrun simctl list devices --json` 挑：它只列模擬器，不會挑到連著的
/// 實體 iPhone；只挑 iPhone，iPad 開著也不用。沒有開著的 iPhone 時，開最近用過
/// （`lastUsedAt`）的那台可用的 iPhone，在 [out] 印出原因，用
/// `simctl bootstatus -b` 開機並等到開好（事實 T5）。模擬器會在閘門之外被
/// 關掉，例如 Orca 的模擬器面板換裝置時會關掉前一台（docs/development.md
/// 〈其他已知怪癖〉）。
Future<String> ensureBootedIPhone(
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
Future<String> androidEmulator(Shell shell, Directory app) async {
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
class Winpc {
  Winpc(this.app, this.shell, this.out, this.logs);

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

  /// [extra] 接在 `test.ps1` 的參數後面，例如實跑的 `-RealRunDir`。log 存成
  /// [logs] 底下的 `test-<檔名>.log`。
  Future<bool> integrationTest(String file, {List<String> extra = const []}) {
    final name = file.split('/').last.replaceAll('.dart', '');
    return _task(
      'fmptest',
      'test.ps1',
      ['-File', file, ...extra],
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
