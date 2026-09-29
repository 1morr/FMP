import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// App 資料目錄（資料庫、設定、log）的能力（ADR 0009 §決定 7）。
///
/// 開發版與正式版各用一個目錄（ADR 0015 §決定 8），而且開發版拒絕舊版正式
/// 資料的位置，見 [ensureOutsideLegacyData]。實作只有 Android 與 Windows，
/// 由 `platform.dart` 組裝。
abstract interface class AppDataDirectory {
  /// 解析並建立目錄。
  Future<Directory> resolve();
}

/// 已解析的資料目錄。`main()` 在 `runApp` 之前解析，再以 override 注入；
/// 其他地方不自己解析。
final dataDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'dataDirectoryProvider is overridden by main() with the resolved '
    'directory',
  ),
);

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
