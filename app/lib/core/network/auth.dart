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

/// 認證攔截器的資料來源。M3 由 `CredentialStore`（ADR 0012 §決定 3）與每音源
/// 設定表（ADR 0011 §決定 7）實作；M1 只有 [NoCredentials]。
abstract interface class CredentialSource {
  /// [pluginId] 的憑證，以要加到請求上的 headers 表示；未登入回 `null`。
  Future<Map<String, String>?> credentialHeaders(String pluginId);

  /// [pluginId] 的「以登入身分瀏覽與播放」開關。
  Future<bool> browseAsLoggedIn(String pluginId);
}

/// M1 的認證來源：每個音源都未登入。
final class NoCredentials implements CredentialSource {
  const NoCredentials();

  @override
  Future<Map<String, String>?> credentialHeaders(String pluginId) async => null;

  /// ADR 0012 §決定 6 的預設（開）。沒有憑證時這個值不影響結果。
  @override
  Future<bool> browseAsLoggedIn(String pluginId) async => true;
}
