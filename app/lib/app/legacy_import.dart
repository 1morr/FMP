import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';

/// 暫存好、驗證過的匯入結果（M5 design §2.2）：還沒換上。
@immutable
final class LegacyStaged {
  const LegacyStaged({
    required this.file,
    required this.credentials,
    required this.summary,
  });

  /// 驗證過的暫存庫（`<資料目錄>/legacy-import/staging-<UTC>.db`），由呼叫端換上或刪掉。
  final File file;

  /// 插件 id → 要寫進 secure storage 的憑證。只在記憶體，不落地；換上資料庫之後以
  /// [LegacyImport.writeCredentials] 寫。
  final Map<String, LoginCredentials> credentials;

  /// 匯入的結果摘要（筆數、略過的理由；不含使用者的資料），診斷與結果對話框用。
  final ImportSummary summary;

  /// 不印憑證。
  @override
  String toString() => 'LegacyStaged(${credentials.length} credentials)';
}

/// 舊版資料匯入（M5 design §2.2）。實作在 `lib/legacy_import/`，只有 `main()` 認得；
/// `lib/app` 與介面只認這個介面（`fmp_layer_imports` 擋其他位置 import 實作）。
///
/// 設定頁的「從舊版匯入…」（PR 7）會再加舊 JSON 備份的入口。
abstract interface class LegacyImport {
  /// 找舊資料庫：首次啟動與設定頁都用。沒有時回 `null`。
  Future<LegacySource?> locate();

  /// 讀、轉換、寫暫存庫、驗證；不換上。[progress] 依序收到 [LegacyImportStep.read]、
  /// `convert`、`write`、`verify`。每一步失敗都拋 [LegacyImportFailed]（暫存檔已刪、舊檔沒動）。
  Future<LegacyStaged> stage(
    LegacySource source, {
    void Function(LegacyImportStep step)? progress,
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
