/// 舊版資料匯入的來源（`legacy_imports.source`，M5 design §6.4）。
///
/// 存進資料庫的字串在 `lib/data/database/converters.dart`，不是 [name]。
enum LegacyImportSource {
  /// 舊版的 Isar 資料庫。
  database,

  /// 舊版匯出的 JSON 備份檔。
  backup,
}

/// 舊版 JSON 備份檔不能匯入的原因（設定頁的「從舊版匯入…」，M5 design §4.2）。
enum LegacyBackupRejection {
  /// 不是舊版的備份檔（不是 JSON、不是物件，或沒有備份的任何欄位）。
  notBackup,

  /// 備份的格式版本比舊版最後支援的 5 新。
  newerVersion,

  /// 備份檔的欄位壞了（必要的欄位缺少或型別不對）。
  corrupt,

  /// 沒有任何可匯入的資料。
  empty,
}

/// 舊版備份檔被拒絕；不含檔案內容。
final class LegacyBackupRejected implements Exception {
  const LegacyBackupRejected(this.reason);

  final LegacyBackupRejection reason;

  @override
  String toString() => 'LegacyBackupRejected(${reason.name})';
}
