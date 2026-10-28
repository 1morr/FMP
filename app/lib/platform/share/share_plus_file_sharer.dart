import 'package:share_plus/share_plus.dart';

import 'package:fmp/platform/share/share.dart';

/// `share_plus` 的 `SharePlus.share` 的形狀；測試換掉它，不碰平台通道。
typedef ShareFilesCall = Future<ShareResult> Function(ShareParams params);

/// [FileSharer] 的實作，Android、Windows 與 macOS 共用：差異都在 `share_plus` 的原生端（Android 是
/// `ACTION_SEND`，Windows 10 1809 以上是 `DataTransferManager` 的分享視窗）。Linux 不支援
/// 分享檔案，不宣告這個能力。
final class SharePlusFileSharer implements FileSharer {
  SharePlusFileSharer([ShareFilesCall? share])
    : _share = share ?? ((params) => SharePlus.instance.share(params));

  final ShareFilesCall _share;

  @override
  Future<bool> shareFiles(
    List<String> paths, {
    required String mimeType,
  }) async {
    final result = await _share(
      ShareParams(
        files: [for (final path in paths) XFile(path, mimeType: mimeType)],
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  }
}
