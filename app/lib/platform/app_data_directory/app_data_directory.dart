import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';

/// App 資料目錄（資料庫、設定、log）的能力（ADR 0009 §決定 7）。
///
/// 開發版與正式版各用一個目錄（ADR 0015 §決定 8），而且開發版拒絕舊版正式
/// 資料的位置，見 [ensureOutsideLegacyData]。
abstract interface class AppDataDirectory {
  /// 解析並建立目錄。
  Future<Directory> resolve();
}

/// 目前平台的實作；平台沒有實作時回 `null`。
///
/// 只有 Android 與 Windows 有實作。其他平台驗證前不寫實作
/// （ADR 0009 §決定 4）。
AppDataDirectory? appDataDirectoryFor(AppFlavor flavor) {
  if (Platform.isAndroid) {
    return AndroidAppDataDirectory(
      flavor: flavor,
      applicationSupportPath: () async =>
          (await getApplicationSupportDirectory()).path,
    );
  }
  if (Platform.isWindows) {
    return WindowsAppDataDirectory(
      flavor: flavor,
      executablePath: Platform.resolvedExecutable,
      roamingAppDataPath: Platform.environment['APPDATA'],
      applicationSupportPath: () async =>
          (await getApplicationSupportDirectory()).path,
      documentsPath: () async =>
          (await getApplicationDocumentsDirectory()).path,
    );
  }
  return null;
}

/// 開發版解析出的資料目錄等於或位於舊版正式資料位置之下時拋出。
final class LegacyDataLocationException implements Exception {
  const LegacyDataLocationException({
    required this.path,
    required this.legacyLocation,
  });

  final String path;
  final String legacyLocation;

  @override
  String toString() =>
      'LegacyDataLocationException: the dev flavor refuses data directory '
      '$path because it is inside the legacy data location $legacyLocation';
}

/// [path] 等於或位於任一 [legacyLocations] 之下就拋
/// [LegacyDataLocationException]。
///
/// 只給開發版用：正式版之後要從這些位置匯入舊資料（ADR 0010）。
void ensureOutsideLegacyData(String path, Iterable<String> legacyLocations) {
  for (final legacy in legacyLocations) {
    if (p.equals(path, legacy) || p.isWithin(legacy, path)) {
      throw LegacyDataLocationException(path: path, legacyLocation: legacy);
    }
  }
}
