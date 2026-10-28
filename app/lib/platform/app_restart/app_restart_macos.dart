import 'dart:io' as io;

import 'package:path/path.dart' as p;

import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

/// 等舊行程（`$0`）結束再用 `open` 開 `.app`（`$1`）。pid 與路徑以位置參數傳入，不拼進
/// 腳本字串：路徑含空白或引號也不會被當成指令。
const macosRestartScript =
    r'while kill -0 "$0" 2>/dev/null; do sleep 0.2; done; '
    r'exec /usr/bin/open "$1"';

/// macOS：先收掉系統媒體控制，由脫離的 shell 等本行程結束後用 `open` 重開同一個
/// `.app`，再結束自己。
///
/// 為什麼要等：舊行程還在時 `open` 只會把舊視窗帶到前景，不會開新行程；原生端的單一
/// 實例檢查也會擋掉太早起來的新行程。
final class MacosAppRestarter implements AppRestarter {
  MacosAppRestarter({
    required this.executable,
    required this.pid,
    required this.launch,
    required this.exitProcess,
    this.mediaControls,
  });

  /// 以目前的行程組出來：`Platform.resolvedExecutable`、`pid`、脫離式的
  /// `Process.start`、`exit`。[mediaControls] 沒有系統媒體控制時為 `null`。
  factory MacosAppRestarter.system(SystemMediaControls? mediaControls) =>
      MacosAppRestarter(
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
        mediaControls: mediaControls,
      );

  /// 目前行程的執行檔：`<名稱>.app/Contents/MacOS/<執行檔>`，往上三層是 `.app`。
  final String executable;
  final int pid;

  /// 啟動 `executable` 並讓它脫離目前的行程。
  final Future<void> Function(String executable, List<String> arguments) launch;
  final void Function(int code) exitProcess;
  final SystemMediaControls? mediaControls;

  @override
  Future<void> restart() async {
    final bundle = p.dirname(p.dirname(p.dirname(executable)));
    await mediaControls?.dispose();
    // 啟動失敗就不結束、把錯誤丟給呼叫端顯示（同 Windows）。
    await launch('/bin/sh', ['-c', macosRestartScript, '$pid', bundle]);
    exitProcess(0);
  }
}
