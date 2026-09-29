import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

/// Android：App 私有目錄（`Context.getFilesDir()`，即 path_provider 的
/// application support）。
///
/// 私有目錄本來就依 applicationId 分開，開發版的 `.dev` 後綴
/// （`android/app/build.gradle.kts`）已經讓它落在另一個目錄，Dart 端不再加
/// `-dev`。
///
/// 舊版正式資料：舊版 applicationId 是 `com.personal.fmp`（舊專案
/// `android/app/build.gradle.kts:29`），整個沙盒
/// `/data/user/<使用者>/com.personal.fmp/` 都是舊資料；資料庫在其下的
/// `app_flutter/FMP/`（舊專案 `lib/data/database/database_provider.dart:15`、
/// `:51`）。開發版的目錄若落在那裡（例如 flavor 的 applicationId 後綴被拿掉），
/// [resolve] 直接拋錯。
final class AndroidAppDataDirectory implements AppDataDirectory {
  AndroidAppDataDirectory({
    required this.flavor,
    required this._applicationSupportPath,
  });

  /// 舊版的 applicationId，也是它私有目錄的目錄名。
  static const legacyApplicationId = 'com.personal.fmp';

  final AppFlavor flavor;
  final Future<String> Function() _applicationSupportPath;

  @override
  Future<Directory> resolve() async {
    // `<資料根>/<applicationId>/files`
    final path = await _applicationSupportPath();
    if (flavor == AppFlavor.dev) {
      final dataRoot = p.dirname(p.dirname(path));
      ensureOutsideLegacyData(path, [p.join(dataRoot, legacyApplicationId)]);
    }
    return Directory(path).create(recursive: true);
  }
}
