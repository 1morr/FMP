import 'package:package_info_plus/package_info_plus.dart';

import 'package:fmp/platform/app_info/app_info.dart';

/// [AppInfoReader] 的實作，Android 與 Windows 共用：版本號由 `package_info_plus` 讀
/// （Android 的 `versionName`、Windows 執行檔的 `ProductVersion`，兩者都由 pubspec 的
/// `version` 產生）。平台名稱與家目錄由組裝點給。
final class PackageInfoAppInfo implements AppInfoReader {
  const PackageInfoAppInfo({required this.platform, this.homeDirectory});

  final String platform;
  final String? homeDirectory;

  @override
  Future<AppInfo> read() async => AppInfo(
    version: (await PackageInfo.fromPlatform()).version,
    platform: platform,
    homeDirectory: homeDirectory,
  );
}
