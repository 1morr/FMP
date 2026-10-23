import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';

/// 暫存好、驗證過的匯入結果（M5 design §2.2）：還沒換上。
@immutable
final class LegacyStaged {
  const LegacyStaged({
    required this.file,
    required this.credentials,
    required this.summary,
    this.keptAccountPluginIds = const {},
  });

  /// 驗證過的暫存庫（`<資料目錄>/legacy-import/staging-<UTC>.db`），由呼叫端換上或刪掉。
  final File file;

  /// 插件 id → 要寫進 secure storage 的憑證。只在記憶體，不落地；換上資料庫之後以
  /// [LegacyImport.writeCredentials] 寫。
  final Map<String, LoginCredentials> credentials;

  /// 匯入的結果摘要（筆數、略過的理由；不含使用者的資料），診斷與結果對話框用。
  final ImportSummary summary;

  /// 設定頁的取代：這台有可用登入（帳號列的 `status` 是 `active`）、所以保留這台的帳號與登入的插件 id
  /// （匯入的這些平台不寫）。`invalidated` 的不在裡面：匯入有可用憑證時取代它，沒有就保留原列。
  /// 首次啟動沒有。換上之後把它當作 [LegacyImport.writeCredentials] 的 `loggedInPluginIds`。
  final Set<String> keptAccountPluginIds;

  /// 不印憑證。
  @override
  String toString() => 'LegacyStaged(${credentials.length} credentials)';
}

/// 舊版資料匯入（M5 design §2.2）。實作在 `lib/legacy_import/`，只有 `main()` 認得；
/// `lib/app` 與介面只認這個介面（`fmp_layer_imports` 擋其他位置 import 實作）。
///
/// 設定頁的「從舊版匯入…」是取代：[stage]、[stageBackup] 給了 `replacing`（這台目前的資料庫）時，
/// 暫存庫是它的副本，在副本上換掉音樂庫、合併設定與帳號（design §6.3），保留這台的插件與登入；
/// 沒給（首次啟動）寫全新的庫。
abstract interface class LegacyImport {
  /// 找舊資料庫：首次啟動與設定頁都用。沒有時回 `null`。
  Future<LegacySource?> locate();

  /// 讀、轉換、寫暫存庫、驗證；不換上。[progress] 依序收到 [LegacyImportStep.read]、
  /// `convert`、`write`、`verify`。每一步失敗都拋 [LegacyImportFailed]（暫存檔已刪、舊檔沒動）。
  Future<LegacyStaged> stage(
    LegacySource source, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  });

  /// 舊版匯出的 JSON 備份檔（設定頁）：讀、轉換、寫暫存庫、驗證；不換上。備份沒有佇列與憑證，
  /// 所以取代後佇列是空的，[LegacyStaged.credentials] 為空。檔案不能匯入時拋
  /// [LegacyBackupRejected]；其餘失敗同 [stage]。
  Future<LegacyStaged> stageBackup(
    Uint8List bytes, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  });

  /// 換上資料庫之後寫憑證：只寫 [staged] 帶著、且不在 [loggedInPluginIds]（這台目前已登入）的
  /// 平台。回傳寫失敗而需要重新登入的插件 id（不拋例外）。
  Future<Set<String>> writeCredentials(
    LegacyStaged staged, {
    required Set<String> loggedInPluginIds,
  });
}

/// 舊資料匯入的實作；`main()` 以 override 注入，測試注入假實作。沒有 override 就讀會拋錯。
final legacyImportProvider = Provider<LegacyImport>(
  (ref) => throw UnimplementedError(
    'legacyImportProvider is overridden by main() with the implementation',
  ),
);
