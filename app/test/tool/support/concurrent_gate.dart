import 'dart:convert';
import 'dart:io';

import '../../../tool/src/device_lock.dart';
import '../../../tool/src/full_gate.dart';
import '../../../tool/src/steps.dart';

/// 模擬一個 worktree 跑完整版的平台步驟，給 `device_lock_test.dart` 當子行程。
///
///     dart test/tool/support/concurrent_gate.dart <共用目錄> <worktree 名稱>
///
/// [_SharedDeviceShell] 把 `winpc` 的 `C:\fmp-wt` 與各模擬器換成 <共用目錄>
/// 裡的檔：同步、安裝時寫入自己的名稱，建置、測試途中再讀回來；被別的
/// worktree 蓋掉時那一步失敗。印出 `ready` 後等 stdin 一行才開跑，讓兩個
/// 子行程同時開始。退出碼就是閘門的退出碼。
Future<void> main(List<String> args) async {
  final [path, worktree] = args;
  final shared = Directory(path);
  final shell = _SharedDeviceShell(shared, worktree);
  final logs = Directory.systemTemp.createTempSync('fmp_gate_logs_');

  stdout.writeln('ready');
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;

  final code = await runSteps(
    platformSteps(
      app: Directory.current,
      shell: shell,
      integrationTests: const ['integration_test/app_test.dart'],
      out: stdout,
      winpcLogs: logs,
      deviceLock: DeviceLock(
        File('${shared.path}/${DeviceLock.fileName}'),
        worktree: worktree,
      ),
    ),
    stdout,
  );
  logs.deleteSync(recursive: true);
  exit(code);
}

class _SharedDeviceShell implements Shell {
  _SharedDeviceShell(this.shared, this.worktree);

  final Directory shared;
  final String worktree;
  String _remoteLog = '';

  /// 一個共用裝置；內容是最後放上去的 worktree。
  File _device(String name) => File('${shared.path}/$name');

  /// 放上自己的程式碼，做一段事，再確認裝置上還是自己的。
  Future<bool> _useDevice(String name) async {
    _device(name).writeAsStringSync(worktree);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final now = _device(name).readAsStringSync();
    if (now == worktree) return true;
    stdout.writeln('$name was overwritten by $now');
    return false;
  }

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    if (executable == 'tool/winpc/sync.sh') {
      _device('winpc').writeAsStringSync(worktree);
      return 0;
    }
    if (executable == 'tool/winpc/run_task.sh') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final ok = _device('winpc').readAsStringSync() == worktree;
      if (!ok) stdout.writeln('winpc was overwritten');
      _remoteLog = 'exit task=${ok ? 0 : 1}\n=== done\n';
      return 0;
    }
    if (executable == 'flutter' && arguments.first == 'test') {
      final device = arguments[arguments.indexOf('-d') + 1];
      return await _useDevice(device) ? 0 : 1;
    }
    return 0; // 本機建置與 ssh 刪 log：不碰共用裝置。
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    if (executable == 'flutter') {
      return jsonEncode([
        {'id': 'sim', 'targetPlatform': 'ios', 'emulator': true},
        {'id': 'emu', 'targetPlatform': 'android-arm64', 'emulator': true},
      ]);
    }
    return _remoteLog; // ssh winpc Get-Content
  }
}
