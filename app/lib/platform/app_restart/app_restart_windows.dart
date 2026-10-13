import 'dart:io' as io;

import 'package:fmp/platform/app_restart/app_restart.dart';

/// 新行程的命令列參數前綴，值是舊行程的 pid。`windows/runner/main.cpp` 看到它會先等那個行程
/// 結束（最多 10 秒）再建立單一實例的 mutex，否則新行程會被「已有實例」擋掉。Dart 端的
/// 命令列解析（`devPluginPath`）只認自己的參數，會忽略它。
const restartedFromArgumentPrefix = '--fmp-restarted-from=';

/// 啟動 [executable] 並讓它脫離目前的行程。
typedef ProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// Windows：以同一個執行檔啟動新行程（不沿用原本的命令列參數，只帶舊 pid），再結束自己。
final class WindowsAppRestarter implements AppRestarter {
  WindowsAppRestarter({
    required this.executable,
    required this.pid,
    required this.launch,
    required this.exitProcess,
  });

  /// 以目前的行程組出來：`Platform.resolvedExecutable`、`pid`、脫離式的 `Process.start`、`exit`。
  factory WindowsAppRestarter.system() => WindowsAppRestarter(
    executable: io.Platform.resolvedExecutable,
    pid: io.pid,
    launch: (executable, arguments) async {
      await io.Process.start(
        executable,
        arguments,
        mode: io.ProcessStartMode.detached,
      );
    },
    exitProcess: io.exit,
  );

  final String executable;
  final int pid;
  final ProcessLauncher launch;
  final void Function(int code) exitProcess;

  @override
  Future<void> restart() async {
    // 啟動失敗就不結束、把錯誤丟給呼叫端顯示：自己結束的話使用者看不到原因。這時資料庫
    // 已經關閉，App 不能再用，要使用者自己關掉重開。
    await launch(executable, ['$restartedFromArgumentPrefix$pid']);
    exitProcess(0);
  }
}
