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
///   就放掉鎖，退出碼是指令的退出碼。別人持有時印出持有者並等待。祖先行程
///   已持有這把鎖（例如完整閘門或外層的包裝指令）時直接執行，不會卡死。
///   收到 SIGINT、SIGTERM 時轉給指令，等它結束才放鎖。指令帶
///   [sharedDeviceEnvironment]（`ADB_MDNS=0`）。
/// - 第二種（`--held`）：祖先行程持有這把鎖時退出碼 0，否則 1。給
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
    exit(await lock.heldByAncestor() ? 0 : 1);
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
  final reentrant = await lock.heldByAncestor();
  if (!reentrant) await lock.acquire(stderr);

  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    environment: sharedDeviceEnvironment,
  );
  final forwarded = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen(process.kill),
  ];
  final code = await process.exitCode;
  for (final subscription in forwarded) {
    await subscription.cancel();
  }
  await lock.release();
  exit(code);
}
