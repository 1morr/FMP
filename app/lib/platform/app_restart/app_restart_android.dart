import 'dart:io';

import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

/// Android：沒有正規的「重啟自己」，先收掉系統的媒體工作階段，再結束行程，由使用者再開。
///
/// 為什麼不能只靠 `SystemNavigator.pop`：它只結束 Activity，`MainActivity` 與 audio_service
/// 共用的 `FlutterEngine`、前景服務會讓行程活著；實測（2026-10-14，Android 模擬器）暫停播放
/// （media session 還在）時按返回鍵回到桌面，行程不變，再開 App 只是把原本的 task 帶回前景，
/// `main()` 沒有重跑。那樣 App 會拿著已被刪掉重建的資料庫與已清空的狀態繼續跑，所以要結束行程。
final class AndroidAppRestarter implements AppRestarter {
  AndroidAppRestarter({
    required this.stopMediaSession,
    required this.exitProcess,
  });

  /// 用 [controls]（沒有系統媒體控制時為 `null`）的 `publish(NowPlaying.nothing)` 與 `dispose`
  /// 收掉前景服務與 media session。
  factory AndroidAppRestarter.forMediaControls(
    SystemMediaControls? controls, {
    void Function(int code)? exitProcess,
  }) => AndroidAppRestarter(
    stopMediaSession: () async {
      if (controls == null) return;
      await controls.publish(NowPlaying.nothing);
      await controls.dispose();
    },
    exitProcess: exitProcess ?? exit,
  );

  final Future<void> Function() stopMediaSession;
  final void Function(int code) exitProcess;

  @override
  Future<void> restart() async {
    try {
      await stopMediaSession();
    } finally {
      // 收不掉也要結束：行程一死，系統會跟著收掉前景服務與通知。
      exitProcess(0);
    }
  }
}
