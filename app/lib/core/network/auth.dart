/// 請求要不要帶憑證，由音源插件在請求的定義處宣告（ADR 0012 §決定 2）。
/// 認證攔截器只依這個標記注入，不看網址或 service。
enum AuthRequirement {
  /// 寫入遠端歌單、讀收藏夾與私人歌單：未登入就不發請求，直接回
  /// `AuthRequired`。
  required,

  /// 搜尋、排行、詳情、串流解析等：已登入且「以登入身分瀏覽與播放」開啟
  /// 才帶（ADR 0012 §決定 6）。
  userPreference,

  /// 預設。公開頁面抓取、第三方歌詞源。
  never,
}

/// [decideAuth] 的結果。
enum AuthDecision {
  /// 帶上憑證送出。
  attach,

  /// 不帶憑證送出。
  omit,

  /// 不發請求，回 `AuthRequired`。
  refuse,
}

/// ADR 0012 §決定 2 的表：[requirement] 在「是否已登入」「以登入身分瀏覽的
/// 開關」下怎麼處理。開關只影響 [AuthRequirement.userPreference]。
AuthDecision decideAuth(
  AuthRequirement requirement, {
  required bool loggedIn,
  required bool browseAsLoggedIn,
}) => switch (requirement) {
  AuthRequirement.required =>
    loggedIn ? AuthDecision.attach : AuthDecision.refuse,
  AuthRequirement.userPreference =>
    loggedIn && browseAsLoggedIn ? AuthDecision.attach : AuthDecision.omit,
  AuthRequirement.never => AuthDecision.omit,
};

/// 要附加到請求上的憑證材料。`cookies` 是 cookie 名稱對值，`headers` 是憑證
/// 不是 cookie 的音源要附加的標頭；合併成 `Cookie` header 在網路層做（ADR 0029
/// §決定 4），所以這裡不回傳拼好的字串。
typedef CredentialMaterial = ({
  Map<String, String> cookies,
  Map<String, String> headers,
});

/// 認證攔截器與 cookie 管理的資料來源。實作是 `CredentialStore`（ADR 0012
/// §決定 3）與每音源設定表（ADR 0011 §決定 7）。
abstract interface class CredentialSource {
  /// [pluginId] 現在可以帶的憑證；沒登入、暫時無法讀取或已失效時回 `null`
  /// （已失效：保留憑證、停止帶它，ADR 0012 §決定 5）。
  Future<CredentialMaterial?> credentialMaterial(String pluginId);

  /// [pluginId] 的憑證裡有的 cookie 名稱。已失效時照樣回傳：憑證的 cookie 只經
  /// 注入送出，不論這次請求有沒有帶憑證都不准從 cookie jar 送出（ADR 0029
  /// §決定 4）。沒有憑證回空集合。
  Future<Set<String>> credentialCookieNames(String pluginId);

  /// [pluginId] 的「以登入身分瀏覽與播放」開關。
  Future<bool> browseAsLoggedIn(String pluginId);
}
