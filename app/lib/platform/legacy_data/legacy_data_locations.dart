import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_android.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader_windows.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';

/// 舊版在 documents 下放資料庫的目錄名（舊 App 的 `AppConstants.appName`）。
const _legacyDirectoryName = 'FMP';

/// 舊版的 applicationId，也是它的 Android 沙盒的目錄名。
const _legacyApplicationId = 'com.personal.fmp';

/// Windows 的舊資料位置（M5 design §4.1、§4.3）。路徑從建構子注入，單元測試在暫存目錄上跑。
///
/// - prod：資料庫在 `<文件>\FMP`，其次 `<文件>`（極舊版本）；憑證檔 `flutter_secure_storage.dat`
///   在 application support（新舊 App 同一個，新 App 的鍵加了前綴）。
/// - dev：只看 [devDirectory]（`--fmp-legacy-dir`）；憑證檔是同一個資料夾裡可選的
///   `flutter_secure_storage.dat`。[devDirectory] 等於或位於真實的舊資料位置時拋
///   `LegacyDataLocationException`。
LegacyDataLocator windowsLegacyDataLocator({
  required AppFlavor flavor,
  required String? devDirectory,
  required Future<String> Function() documentsPath,
  required Future<String> Function() applicationSupportPath,
  required String? roamingAppDataPath,
}) => LegacyDataLocator(
  resolve: (log) async {
    final documents = await documentsPath();
    if (flavor == AppFlavor.dev) {
      if (devDirectory == null) return _none;
      ensureOutsideLegacyData(p.absolute(devDirectory), [
        p.join(documents, _legacyDirectoryName),
        if (roamingAppDataPath != null)
          p.join(roamingAppDataPath, 'com.personal', 'fmp'),
      ]);
      return LegacyLocations(
        databaseDirectories: [Directory(devDirectory)],
        credentialReader: WindowsLegacyCredentialReader(
          directory: Directory(devDirectory),
          log: log,
        ),
      );
    }
    return LegacyLocations(
      databaseDirectories: [
        Directory(p.join(documents, _legacyDirectoryName)),
        Directory(documents),
      ],
      credentialReader: WindowsLegacyCredentialReader(
        directory: Directory(await applicationSupportPath()),
        log: log,
      ),
    );
  },
);

/// Android 的舊資料位置（M5 design §4.1、§4.3）。
///
/// - prod：資料庫在 `<app_flutter>/FMP`，其次 `<app_flutter>`（`getApplicationDocumentsDirectory()`）；
///   舊 prefs 檔在 App 沙盒的 `shared_prefs/`（沙盒根是 application support 的上一層）。
/// - dev：只看 [devDirectory]；dev 的沙盒看不到 prod 的 Keystore，所以不讀憑證。
///   [devDirectory] 位於 `com.personal.fmp` 的沙盒時拋 `LegacyDataLocationException`。
LegacyDataLocator androidLegacyDataLocator({
  required AppFlavor flavor,
  required String? devDirectory,
  required Future<String> Function() documentsPath,
  required Future<String> Function() applicationSupportPath,
}) => LegacyDataLocator(
  resolve: (log) async {
    // `<資料根>/<applicationId>/files`
    final sandbox = p.dirname(await applicationSupportPath());
    if (flavor == AppFlavor.dev) {
      if (devDirectory == null) return _none;
      ensureOutsideLegacyData(p.absolute(devDirectory), [
        p.join(p.dirname(sandbox), _legacyApplicationId),
      ]);
      return LegacyLocations(
        databaseDirectories: [Directory(devDirectory)],
        credentialReader: const NoLegacyCredentialReader(),
      );
    }
    final documents = await documentsPath();
    return LegacyLocations(
      databaseDirectories: [
        Directory(p.join(documents, _legacyDirectoryName)),
        Directory(documents),
      ],
      credentialReader: AndroidLegacyCredentialReader(
        prefsFile: AndroidLegacyCredentialReader.prefsFileIn(
          Directory(sandbox),
        ),
        log: log,
      ),
    );
  },
);

/// macOS 的舊資料位置：舊 App 從來沒有發行過 macOS，prod 沒有任何位置。dev 只看
/// [devDirectory]（`--fmp-legacy-dir`，別處複製來的舊資料副本），沒有指定就沒有位置。
/// 沒有真實的舊位置，所以不需要 `ensureOutsideLegacyData`；也沒有可讀的舊憑證。
LegacyDataLocator macosLegacyDataLocator({
  required AppFlavor flavor,
  required String? devDirectory,
}) => LegacyDataLocator(
  resolve: (log) async {
    if (flavor != AppFlavor.dev || devDirectory == null) return _none;
    return LegacyLocations(
      databaseDirectories: [Directory(devDirectory)],
      credentialReader: const NoLegacyCredentialReader(),
    );
  },
);

const _none = LegacyLocations(
  databaseDirectories: [],
  credentialReader: NoLegacyCredentialReader(),
);
