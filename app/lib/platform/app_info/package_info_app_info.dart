import 'package:package_info_plus/package_info_plus.dart';

import 'package:fmp/platform/app_info/app_info.dart';

/// [AppInfoReader] 的實作，Android、Windows 與 macOS 共用：版本號由 `package_info_plus` 讀
/// （Android 的 `versionName`、Windows 執行檔的 `ProductVersion`，兩者都由 pubspec 的
/// `version` 產生）。平台名稱、系統版本與家目錄由組裝點給。
final class PackageInfoAppInfo implements AppInfoReader {
  const PackageInfoAppInfo({
    required this.platform,
    required this.osVersion,
    this.homeDirectory,
  });

  final String platform;
  final String osVersion;
  @override
  final String? homeDirectory;

  @override
  Future<AppInfo> read() async => AppInfo(
    version: (await PackageInfo.fromPlatform()).version,
    platform: platform,
    osVersion: osVersion,
    homeDirectory: homeDirectory,
  );
}
