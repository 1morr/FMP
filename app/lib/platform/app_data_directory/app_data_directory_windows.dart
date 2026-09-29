import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

/// Windows：安裝版用 `%APPDATA%` 下的 App 目錄，免安裝版用程式旁的
/// `userdata/`（ADR 0009 §決定 7 與其更正）。Flutter 自己在程式旁放 `data/`
/// （`flutter_assets`、`app.so`），使用者資料不能混進去，否則免安裝版整目錄更新
/// 時會一起被換掉。
///
/// - 安裝版的判斷照 ADR 0022 §決定 5：程式目錄有 `unins000.exe`。
/// - 安裝版的目錄是 path_provider 的 application support，
///   `%APPDATA%\<CompanyName>\<ProductName>`。開發版的 ProductName 是
///   `fmp-dev`（`windows/runner/app_identity.cmake`），目錄因此分開。
/// - 免安裝版的開發版用 `userdata-dev/`。
///
/// 舊版正式資料有兩處，開發版解析到其中任一處或其下就拋錯：
/// - `Documents\FMP`：資料庫與 log（舊專案
///   `lib/data/database/database_provider.dart:15`、`:51`，
///   `lib/core/log_file_sink.dart:25-26`）。
/// - `%APPDATA%\com.personal\fmp`：舊版的 secure storage 檔
///   （舊專案 `lib/core/secure_key_value_store.dart:43` 用
///   flutter_secure_storage，Windows 實作寫在 application support；
///   CompanyName／ProductName 見舊專案 `windows/runner/Runner.rc:92`、`:98`）。
final class WindowsAppDataDirectory implements AppDataDirectory {
  WindowsAppDataDirectory({
    required this.flavor,
    required this.executablePath,
    required this.roamingAppDataPath,
    required this._applicationSupportPath,
    required this._documentsPath,
  });

  final AppFlavor flavor;

  /// 執行檔的完整路徑（`Platform.resolvedExecutable`）。
  final String executablePath;

  /// `%APPDATA%`；取不到時為 `null`，那一處舊版位置就無從比對。
  final String? roamingAppDataPath;

  final Future<String> Function() _applicationSupportPath;
  final Future<String> Function() _documentsPath;

  @override
  Future<Directory> resolve() async {
    final programDirectory = p.dirname(executablePath);
    final installed = await File(p.join(programDirectory, 'unins000.exe'))
        .exists();
    final path = installed
        ? await _applicationSupportPath()
        : p.join(
            programDirectory,
            flavor == AppFlavor.dev ? 'userdata-dev' : 'userdata',
          );

    if (flavor == AppFlavor.dev) {
      final roaming = roamingAppDataPath;
      ensureOutsideLegacyData(path, [
        p.join(await _documentsPath(), 'FMP'),
        if (roaming != null) p.join(roaming, 'com.personal', 'fmp'),
      ]);
    }
    return Directory(path).create(recursive: true);
  }
}
