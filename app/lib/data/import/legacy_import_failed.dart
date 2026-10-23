/// 匯入舊版資料的步驟（M5 design §3.1、§6）。失敗時說明卡在哪一步，進度畫面也依它顯示。
enum LegacyImportStep {
  /// 複製、開啟並讀舊資料庫與舊憑證。
  read,

  /// 舊資料轉成匯入包。
  convert,

  /// 寫暫存庫。
  write,

  /// 驗證暫存庫。
  verify,

  /// 暫存庫改名成 `fmp.db`。
  swap,

  /// 換上之後寫憑證。
  credentials,
}

/// 匯入舊版資料失敗；暫存庫已刪除，這台原本的資料沒動。
final class LegacyImportFailed implements Exception {
  const LegacyImportFailed(this.step, this.reason, {this.cause});

  final LegacyImportStep step;

  /// 一句英文，不含使用者的資料（曲名、歌單名）；給失敗頁與 log。
  final String reason;

  /// 原本的例外，只給 log 用（經 `Log.report` 遮蔽）；不要顯示給使用者。
  final Object? cause;

  @override
  String toString() => 'LegacyImportFailed(${step.name}: $reason)';
}
