import 'dart:convert';
import 'dart:io';

import '../../../tool/src/device_lock.dart';

/// 模擬另一個 worktree 的閘門持有共用裝置鎖，給 `device_lock_test.dart` 與
/// `device_lock_cli_test.dart` 當子行程。
///
///     dart test/tool/support/hold_device_lock.dart <鎖檔> <worktree 名稱>
///
/// 拿到鎖後印 `held`，stdin 收到一行就放掉鎖、印 `released` 並結束。
Future<void> main(List<String> args) async {
  final [path, worktree] = args;
  final lock = DeviceLock(File(path), worktree: worktree);
  await lock.acquire(stdout);
  stdout.writeln('held');
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await lock.release();
  stdout.writeln('released');
}
