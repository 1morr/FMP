/// 匯入舊版資料失敗的步驟（M5 design §6）。之後的 PR 會加讀取、轉換、換上與寫憑證。
enum LegacyImportStep {
  /// 寫暫存庫。
  write,

  /// 驗證暫存庫。
  verify,
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
