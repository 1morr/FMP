/// 舊版資料匯入的來源（`legacy_imports.source`，M5 design §6.4）。
///
/// 存進資料庫的字串在 `lib/data/database/converters.dart`，不是 [name]。
enum LegacyImportSource {
  /// 舊版的 Isar 資料庫。
  database,

  /// 舊版匯出的 JSON 備份檔。
  backup,
}
