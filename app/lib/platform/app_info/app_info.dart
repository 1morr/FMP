import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App 與執行平台的資訊：「關於」的版本列與 Debug 頁的概覽讀它（ADR 0025 §決定 2、
/// M3 design §12.1）。啟動時讀一次，之後不變。
@immutable
final class AppInfo {
  const AppInfo({
    required this.version,
    required this.platform,
    required this.osVersion,
    this.homeDirectory,
  });

  /// `pubspec.yaml` 的版本號（發版時等於 release-please 的 manifest，ADR 0022）；不含
  /// build number。
  final String version;

  /// 平台的名稱（`Android`、`Windows`）。是產品名稱，不翻譯。
  final String platform;

  /// 系統的版本字串（`Platform.operatingSystemVersion`），錯誤報告用（ADR 0023 §決定 4）。
  final String osVersion;

  /// 使用者的家目錄；顯示路徑時換成 `~`，畫面與截圖才不帶使用者名稱（M3 design
  /// §12.4）。資料目錄不在家目錄底下的平台（Android 的沙盒）為 `null`。
  final String? homeDirectory;

  @override
  bool operator ==(Object other) =>
      other is AppInfo &&
      other.version == version &&
      other.platform == platform &&
      other.osVersion == osVersion &&
      other.homeDirectory == homeDirectory;

  @override
  int get hashCode => Object.hash(version, platform, osVersion, homeDirectory);

  @override
  String toString() =>
      'AppInfo(version: $version, platform: $platform, '
      'osVersion: $osVersion, homeDirectory: $homeDirectory)';
}

/// 讀 [AppInfo]。實作有 Android、Windows 與 macOS（`package_info_app_info.dart`），由
/// `platform.dart` 組裝；`main()` 在 `runApp` 之前讀一次。
abstract interface class AppInfoReader {
  /// 使用者的家目錄（[AppInfo.homeDirectory]）。同步給：`main()` 在寫第一筆 log 之前就要登記
  /// 到遮蔽函式（M3 design §12.4）。
  String? get homeDirectory;

  Future<AppInfo> read();
}

/// 這次執行的 [AppInfo]。`main()` 讀好後以 override 注入；沒 override 就讀會拋錯。
final appInfoProvider = Provider<AppInfo>(
  (ref) => throw UnimplementedError(
    'appInfoProvider is overridden by main() with the platform app info',
  ),
);
