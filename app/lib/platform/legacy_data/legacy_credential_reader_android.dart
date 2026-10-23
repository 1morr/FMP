import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';

const _tag = 'legacy-credentials';

/// 讀單一鍵的函式（[AndroidLegacyCredentialReader] 的注入點）。
typedef LegacyKeyRead = Future<String?> Function(String key);

/// 以 [options] 建一個讀取函式；預設接上 `FlutterSecureStorage`。
typedef LegacyKeyReadFactory = LegacyKeyRead Function(AndroidOptions options);

LegacyKeyRead _systemReadFactory(AndroidOptions options) {
  final storage = FlutterSecureStorage(aOptions: options);
  return (key) => storage.read(key: key);
}

/// Android（只有 prod）：以另一個 `FlutterSecureStorage` 實例讀舊版 10.3.1 存的資料
/// （M5 design §0.1、§4.3；實測見 `research/android-credentials-compat.md`）。
///
/// - 舊 prefs 檔（`shared_prefs/FlutterSecureStorage.xml`）不在就全部「沒有」，**不建立套件
///   實例**：11.x 在沒有舊資料時會建 Keystore 金鑰與標記。
/// - 實例的選項 [options]：不帶 `storageNamespace`（才是舊版的那組檔案與金鑰）、
///   `resetOnError: false`（預設會在讀取失敗時刪鍵）、`migrateOnAlgorithmChange: false`
///   （不重寫舊資料）。
/// - 逐鍵 `read`、不用 `readAll`：一個壞條目會讓 `readAll` 整批失敗；拋例外的鍵是「讀不出」。
final class AndroidLegacyCredentialReader implements LegacyCredentialReader {
  AndroidLegacyCredentialReader({
    required this._prefsFile,
    this._createReader = _systemReadFactory,
    this._log,
  });

  /// 舊版的 secure storage 選項。測試核對。
  static const options = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
  );

  /// 舊 prefs 檔在 [dataDirectory]（App 沙盒根目錄，`/data/user/0/<applicationId>`）下的位置。
  static File prefsFileIn(Directory dataDirectory) =>
      File('${dataDirectory.path}/shared_prefs/FlutterSecureStorage.xml');

  final File _prefsFile;
  final LegacyKeyReadFactory _createReader;
  final Log? _log;

  @override
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys) async {
    final result = <String, LegacyCredentialRead>{};
    LegacyKeyRead? reader;
    var hasLegacyData = false;
    try {
      hasLegacyData = _prefsFile.existsSync();
    } on FileSystemException {
      // 讀不到檔案系統：當作有舊資料但讀不出，不去建實例。
      for (final key in keys) {
        result[key] = const LegacyCredentialUnreadable();
      }
      _logAll(result);
      return result;
    }
    if (hasLegacyData) {
      try {
        reader = _createReader(options);
      } on Object {
        reader = null;
      }
    }
    for (final key in keys) {
      if (!hasLegacyData) {
        result[key] = const LegacyCredentialMissing();
      } else if (reader == null) {
        result[key] = const LegacyCredentialUnreadable();
      } else {
        try {
          final value = await reader(key);
          result[key] = value == null
              ? const LegacyCredentialMissing()
              : LegacyCredentialFound(value);
        } on Object {
          // 例外訊息可能含密文片段，不記。
          result[key] = const LegacyCredentialUnreadable();
        }
      }
    }
    _logAll(result);
    return result;
  }

  void _logAll(Map<String, LegacyCredentialRead> result) {
    for (final MapEntry(:key, :value) in result.entries) {
      _log?.info(
        'Read a legacy credential',
        tag: _tag,
        fields: {'key': key, 'result': value.label},
      );
    }
  }
}
