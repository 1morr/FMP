import 'dart:async';
import 'dart:io';

import 'src/device_lock.dart';

/// 拿共用裝置鎖再執行一個指令（plan §2、§4）。照 util-linux `flock(1)`
/// 「包住一個指令」的慣例：
///
///     dart run tool/device_lock.dart [--repo <目錄>] -- <指令> [參數...]
///     dart run tool/device_lock.dart [--repo <目錄>] --held
///
/// - 第一種：拿 <目錄>（預設是目前目錄）所在 repo 的鎖，執行指令，指令結束
///   就放掉鎖，退出碼是指令的退出碼（被訊號結束時是 128 + 訊號編號）。別的
///   worktree 持有時印出持有者並等待；同一個 worktree 已持有（完整閘門、
///   外層或背景的包裝指令）時直接執行，不會等自己。收到 SIGINT、SIGTERM、
///   SIGHUP 時轉給指令，等它結束才放鎖。拿到鎖後先跑一次
///   `adb start-server`（server 在跑時什麼都不做），指令與它都帶
///   [sharedDeviceEnvironment]（`ADB_MDNS=0`）。
/// - 第二種（`--held`）：這個 worktree 持有這把鎖時退出碼 0，否則 1。給
///   `tool/winpc/lock_guard.sh` 用。
///
/// 訊息都印到 stderr，指令的輸出原樣留在 stdout。
Future<void> main(List<String> args) async {
  var rest = args;
  var repo = Directory.current;
  if (rest.length >= 2 && rest.first == '--repo') {
    repo = Directory(rest[1]);
    rest = rest.sublist(2);
  }
  final lock = DeviceLock.forRepo(repo);

  if (rest.length == 1 && rest.single == '--held') {
    exit(await lock.heldByThisWorktree() ? 0 : 1);
  }
  if (rest.length < 2 || rest.first != '--') {
    stderr.writeln(
      'usage: dart run tool/device_lock.dart [--repo <dir>] -- <command> '
      '[args...]\n'
      '       dart run tool/device_lock.dart [--repo <dir>] --held',
    );
    exit(64);
  }

  final [executable, ...arguments] = rest.sublist(1);
  if (!await lock.heldByThisWorktree()) {
    await lock.acquire(stderr);
    await _startAdbServer();
  }

  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    environment: sharedDeviceEnvironment,
  );
  final forwarded = [
    for (final signal in [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
    ])
      signal.watch().listen(process.kill),
  ];
  final code = await process.exitCode;
  for (final subscription in forwarded) {
    await subscription.cancel();
  }
  await lock.release();
  // 被訊號結束時 Dart 給負的訊號編號；照 shell 的慣例換成 128 + n。
  exit(code < 0 ? 128 - code : code);
}

/// 讓 adb server 以 `ADB_MDNS=0` 跑起來（brief 事實 K15）：server 不在時
/// 啟動它，在跑時什麼都不做，不會打斷別的 session。Orca 等閘門外的工具叫起來
/// 的 server 不帶這個變數，所以拿到鎖就先叫一次。沒裝 adb 時略過。
Future<void> _startAdbServer() async {
  try {
    await Process.run('adb', [
      'start-server',
    ], environment: sharedDeviceEnvironment);
  } on ProcessException {
    // 這台機器沒有 adb：用不到 Android 模擬器。
  }
}
