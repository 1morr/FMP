import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';

/// 舊資料庫的檔名（舊 App 的 `fmpDatabaseName` 加副檔名）。`lib/legacy_import/` 的
/// `legacyDatabaseFileName` 是同一個字面值，`legacy_data_locator_test.dart` 核對。
const legacyDatabaseFile = 'fmp_database.isar';

/// 找到的舊資料：舊資料庫檔，與讀這份資料對應的舊憑證的讀取器。
final class LegacySource {
  const LegacySource({required this.database, required this.credentialReader});

  /// 舊資料庫檔。只讀（讀取器複製一份才開），不會被改。
  final File database;

  final LegacyCredentialReader credentialReader;

  @override
  String toString() => 'LegacySource';
}

/// 舊資料可能在哪（平台層組裝，M5 design §4.1、§4.3）。
final class LegacyLocations {
  const LegacyLocations({
    required this.databaseDirectories,
    required this.credentialReader,
  });

  /// 依序找的資料夾，第一個有 [legacyDatabaseFile] 的算數。
  final List<Directory> databaseDirectories;

  final LegacyCredentialReader credentialReader;
}

/// 找舊版的資料庫（M5 design §4.1）：條件只是「檔案存在」，壞檔交給讀取器去拒絕。
///
/// 位置由 `AppPlatform` 依平台與 flavor 給：
/// - Windows：`<文件>\FMP`，其次 `<文件>`；憑證在 application support；
/// - Android：`<app_flutter>/FMP`，其次 `<app_flutter>`；舊 prefs 檔在 App 沙盒；
/// - dev：只有 `--fmp-legacy-dir` 指的資料夾（[legacyDirectoryPath]）。
final class LegacyDataLocator {
  /// [resolve] 在每次 [locate] 時呼叫（路徑要非同步取得）；dev 的資料夾落在真實的舊資料位置時
  /// 拋 `LegacyDataLocationException`。
  LegacyDataLocator({required this._resolve});

  final Future<LegacyLocations> Function(Log? log) _resolve;

  /// 沒有舊資料庫檔回 `null`。[log] 交給舊憑證讀取器記下鍵名與結果（不含值）。
  Future<LegacySource?> locate({Log? log}) async {
    final locations = await _resolve(log);
    for (final directory in locations.databaseDirectories) {
      final file = File(p.join(directory.path, legacyDatabaseFile));
      if (file.existsSync()) {
        return LegacySource(
          database: file,
          credentialReader: locations.credentialReader,
        );
      }
    }
    return null;
  }
}
