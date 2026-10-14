import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用系統的分享視窗送出檔案（診斷包與 log 檔的「分享」，ADR 0025 §決定 10）。實作有 Android
/// 與 Windows（`share_plus_file_sharer.dart`），由 `platform.dart` 組裝。
abstract interface class FileSharer {
  /// 開系統的分享視窗，分享 [paths] 的檔案（[mimeType] 給接收端挑 App）。分享視窗開不起來
  /// （平台拒絕、檔案不存在）時拋錯，由呼叫端提示。
  ///
  /// 回傳 `true`＝平台回報了分享的結果（完成或取消），原檔不再被讀；`false`＝視窗開了但
  /// 平台不回報結果（Windows 的 `DataTransferManager`、Android 5.1 以前），接收端之後才讀檔，
  /// 呼叫端不能馬上刪。
  Future<bool> shareFiles(List<String> paths, {required String mimeType});
}

/// 平台的檔案分享；平台沒有這個能力（`PlatformCapabilities.shareFiles` 為假）時為 `null`。
/// `main()` 以 `AppPlatform.fileSharer` override；沒 override 就讀會拋錯。
final fileSharerProvider = Provider<FileSharer?>(
  (ref) => throw UnimplementedError(
    'fileSharerProvider is overridden by main() with the platform '
    'implementation',
  ),
);
