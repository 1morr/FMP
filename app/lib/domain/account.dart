/// 帳號的狀態（ADR 0029 §決定 6）。是否登入只看 `CredentialStore`；這個狀態
/// 只說憑證還能不能用。
enum AccountStatus {
  /// 憑證可用。
  active,

  /// 憑證被音源拒絕：保留、停止帶它，等使用者重新登入（ADR 0012 §決定 5）。
  invalidated,
}

/// 最近一次刷新憑證的結果（帳號頁顯示，ADR 0012 §決定 5）。
enum RefreshResult { refreshed, unchanged, failed }
