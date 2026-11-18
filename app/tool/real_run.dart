import 'dart:io';

import 'src/blank_screenshot.dart';
import 'src/device_lock.dart';
import 'src/devices.dart';
import 'src/real_run_host.dart';
import 'src/steps.dart';

/// 實跑一個情境（docs/development.md〈實跑驅動〉）。在 `app/` 裡跑：
///
///     dart run tool/real_run.dart -d <macos|ios|android|windows> [--out <目錄>] <情境檔>
///
/// 情境檔是 `integration_test/real_run/*_run.dart`。截圖、讀回的文字與
/// `flutter test` 的輸出存到 `<目錄>/<平台>/`（預設 `build/real_run/`，不進
/// git）。
///
/// - 整段持有共用裝置鎖：這個 worktree 已持有時直接用，否則自己拿、跑完放。
///   別包在 `tool/device_lock.dart` 裡，也別在背景持鎖時跑：外層一結束鎖就
///   沒人持有，這支卻還在用裝置。
/// - macOS、iOS、Android：在 127.0.0.1 開截圖服務（[RealRunCaptureServer]），
///   驅動每一步來要截圖，用系統的截圖工具截：`screencapture -l`、
///   `simctl io screenshot`、`adb exec-out screencap`（Android 經
///   `adb reverse` 連回 Mac）。
/// - Windows：同步、建置，再以排程工作跑 `test.ps1 -RealRunDir`；驅動在
///   `winpc` 上用 `shot.ps1 -AppPid` 截自己的視窗，跑完 scp 回來。
///
/// 退出碼是 `flutter test` 的（Windows 是 log 判定的）。
Future<void> main(List<String> args) async {
  final app = File.fromUri(Platform.script).parent.parent;
  final parsed = _parse(args);
  if (parsed == null) {
    stderr.writeln(
      'usage: dart run tool/real_run.dart -d <macos|ios|android|windows> '
      '[--out <dir>] integration_test/real_run/<scenario>_run.dart',
    );
    exit(64);
  }
  final (:platform, :file, :out) = parsed;
  final dir = Directory('${out ?? '${app.path}/build/real_run'}/$platform');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  final lock = DeviceLock.forRepo(app);
  final alreadyHeld = await lock.heldByThisWorktree();
  if (!alreadyHeld) {
    await lock.acquire(stderr);
    await startAdbServer();
  }
  int code;
  try {
    code = platform == 'windows'
        ? await _windows(app, file, dir)
        : await _local(app, platform, file, dir);
  } finally {
    if (!alreadyHeld) await lock.release();
  }

  // 測試綠、截圖白不算通過（票 06b：winpc 螢幕睡著時截到白圖）。
  final blank = blankScreenshots(dir);
  if (blank.isNotEmpty) {
    stderr.writeln(
      '\nBlank screenshots, the run does not count:\n'
      '${blank.map((b) => '  $b').join('\n')}',
    );
    if (code == 0) code = 1;
  }

  stdout.writeln('\nReal run ($platform) saved to ${dir.path}:');
  for (final entry
      in dir.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
    stdout.writeln('  ${entry.path.split('/').last}');
  }
  exit(code);
}

const _platforms = {'macos', 'ios', 'android', 'windows'};

({String platform, String file, String? out})? _parse(List<String> args) {
  String? platform;
  String? out;
  String? file;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-d' when i + 1 < args.length:
        platform = args[++i];
      case '--out' when i + 1 < args.length:
        out = args[++i];
      case final arg when !arg.startsWith('-') && file == null:
        file = arg;
      default:
        return null;
    }
  }
  if (platform == null || !_platforms.contains(platform) || file == null) {
    return null;
  }
  if (!file.startsWith('integration_test/real_run/') ||
      !file.endsWith('_run.dart')) {
    stderr.writeln(
      'Not a real-run scenario: $file (integration_test/real_run/*_run.dart)',
    );
    return null;
  }
  return (platform: platform, file: file, out: out);
}

const _shell = ProcessShell(environment: sharedDeviceEnvironment);

/// 在 Mac 上跑情境的一個平台：`flutter test -d` 的裝置、截圖的方式；模擬器
/// 跑完不刪 App 與資料（docs/development.md〈平台〉），Android 模擬器裡的
/// 127.0.0.1 是它自己，要 `adb reverse` 把截圖服務的埠接回 Mac。
typedef _Target = ({
  String device,
  CaptureWindow capture,
  bool emulator,
  bool reversePort,
});

Future<_Target> _target(Directory app, String platform) async {
  switch (platform) {
    case 'macos':
      return (
        device: 'macos',
        capture: _captureMacWindow,
        emulator: false,
        reversePort: false,
      );
    case 'ios':
      final udid = await ensureBootedIPhone(_shell, app, stdout);
      return (
        device: udid,
        capture: (File file, int _) =>
            _capture('xcrun', ['simctl', 'io', udid, 'screenshot', file.path]),
        emulator: true,
        reversePort: false,
      );
    default:
      final id = await androidEmulator(_shell, app);
      return (
        device: id,
        capture: (File file, int _) async {
          final result = await Process.run(
            'adb',
            ['-s', id, 'exec-out', 'screencap', '-p'],
            stdoutEncoding: null,
            environment: sharedDeviceEnvironment,
          );
          if (result.exitCode != 0) {
            throw ProcessException('adb', ['screencap'], '${result.stderr}');
          }
          file.writeAsBytesSync(result.stdout as List<int>);
        },
        emulator: true,
        reversePort: true,
      );
  }
}

/// macOS、iOS、Android：Mac 上的截圖服務加 `flutter test -d`。
Future<int> _local(
  Directory app,
  String platform,
  String file,
  Directory dir,
) async {
  final target = await _target(app, platform);
  final server = await RealRunCaptureServer.start(
    out: dir,
    capture: target.capture,
    system: (action, args, pid, shot) =>
        _system(app, platform, target.device, action, args, pid, shot),
  );
  final port = 'tcp:${server.url.port}';
  try {
    if (target.reversePort) {
      await _capture('adb', ['-s', target.device, 'reverse', port, port]);
    }
    final process = await Process.start(
      'flutter',
      [
        'test',
        file,
        '-d',
        target.device,
        if (target.emulator) '--no-uninstall',
        '--dart-define=FMP_REAL_RUN_HOST=${server.url}',
        '--dart-define=FMP_SCRATCH_DATA=$scratchData',
      ],
      workingDirectory: app.path,
      environment: sharedDeviceEnvironment,
    );
    final log = File('${dir.path}/output.log').openWrite();
    await Future.wait([
      process.stdout.forEach((bytes) {
        stdout.add(bytes);
        log.add(bytes);
      }),
      process.stderr.forEach((bytes) {
        stderr.add(bytes);
        log.add(bytes);
      }),
    ]);
    await log.close();
    return await process.exitCode;
  } finally {
    await server.close();
    if (target.reversePort) {
      await _shell.run('adb', [
        '-s',
        target.device,
        'reverse',
        '--remove',
        port,
      ], workingDirectory: app);
    }
  }
}

/// `screencapture -l <視窗 id>`：截那個視窗本身（被蓋住也截得到），連同系統畫的
/// 標題列與紅綠燈，不動游標也不搶前景。視窗 id 由 pid 經 CoreGraphics 的視窗清單
/// 查：畫面上、一般層級（layer 0）、最前面那一個。
/// 情境向宿主要做的系統動作（`RealRun.system`）：交給
/// `tool/real_run_system.sh`，它依平台用 osascript、simctl、adb 做，不動
/// Mac 的游標。回傳它印出的文字；失敗就丟例外。
Future<String> _system(
  Directory app,
  String platform,
  String device,
  String action,
  List<String> args,
  int pid,
  File shot,
) async {
  final result = await Process.run(
    '${app.path}/tool/real_run_system.sh',
    [platform, device, '$pid', shot.path, action, ...args],
    workingDirectory: app.path,
    environment: sharedDeviceEnvironment,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'real_run_system.sh',
      [action, ...args],
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return '${result.stdout}';
}

Future<void> _captureMacWindow(File file, int pid) async {
  const findWindow = r'''
ObjC.import('CoreGraphics');
function run(argv) {
  const list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo(
      $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0));
  for (let i = 0; i < list.count; i++) {
    const w = list.objectAtIndex(i);
    if (ObjC.unwrap(w.objectForKey('kCGWindowOwnerPID')) === parseInt(argv[0]) &&
        ObjC.unwrap(w.objectForKey('kCGWindowLayer')) === 0) {
      return String(ObjC.unwrap(w.objectForKey('kCGWindowNumber')));
    }
  }
  return '';
}''';
  final id = await _shell.capture('osascript', [
    '-l',
    'JavaScript',
    '-e',
    findWindow,
    '$pid',
  ], workingDirectory: Directory.current);
  if (id.trim().isEmpty) {
    throw StateError('No on-screen window for pid $pid');
  }
  await _capture('screencapture', ['-x', '-o', '-l', id.trim(), file.path]);
}

/// Windows：同步、建置，再跑情境；截圖與文字在 `winpc` 的 [_winpcDir]，
/// 跑完取回。
Future<int> _windows(Directory app, String file, Directory dir) async {
  final winpc = Winpc(app, _shell, stdout, dir);
  if (!await winpc.build()) return 1;
  await _shell.run('ssh', [
    'winpc',
    'Remove-Item -Recurse -Force $_winpcDir -EA SilentlyContinue',
  ], workingDirectory: app);
  final passed = await winpc.integrationTest(
    file,
    extra: [
      '-RealRunDir',
      _winpcDir.replaceAll(r'\', '/'),
      '-ScratchData',
      scratchData,
    ],
  );
  final copied = await _shell.run('scp', [
    'winpc:${_winpcDir.replaceAll(r'\', '/')}/*',
    dir.path,
  ], workingDirectory: app);
  return passed && copied == 0 ? 0 : 1;
}

const _winpcDir = r'C:\fmp-wt\real_run';

/// App 在實跑時用的隔離資料目錄名（`FMP_SCRATCH_DATA`）：放在裝置的系統暫存
/// 目錄底下，驅動每次開 App 前清空，不碰 dev 版的資料。Windows 經
/// `test.ps1 -ScratchData` 帶過去。
const scratchData = 'fmp-real-run';

/// 跑指令，退出碼非零時丟 [ProcessException]（含 stderr）。
Future<void> _capture(String executable, List<String> arguments) =>
    _shell.capture(executable, arguments, workingDirectory: Directory.current);
