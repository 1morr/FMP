import 'package:fmp/data/models/account.dart';

/// 帳號狀態
enum AccountStatus { valid, invalid, error }

/// 帳號狀態檢查結果
class AccountCheckResult {
  final AccountStatus status;
  final bool? isVip;

  const AccountCheckResult({required this.status, this.isVip});
}

/// 帳號服務抽象接口（可擴展到 YouTube、網易雲等）
abstract class AccountService {
  String get platform;

  /// 檢查是否已登錄
  Future<bool> isLoggedIn();

  /// 獲取當前用戶信息
  Future<Account?> getCurrentAccount();

  /// 登出：清掉憑證並刪除 [Account] 列。
  Future<void> logout();

  /// 標記登入已失效：清掉憑證，但保留 [Account] 列（`sessionExpired = true`）。
  ///
  /// 與 [logout] 的差別在於列留不留 —— 帳號頁要靠它把「從沒登入過」和「登入
  /// 過期了」分成兩種呈現。憑證照樣清掉：失效的 cookie 不該再附到請求上。
  Future<void> markSessionExpired();

  /// 刷新認證（Cookie/Token）
  /// 返回 true 表示刷新成功，false 表示需要重新登錄
  Future<bool> refreshCredentials();

  /// 檢查認證是否需要刷新
  Future<bool> needsRefresh();

  /// 檢查帳號登錄狀態和 VIP 狀態
  Future<AccountCheckResult> checkAccountStatus();
}
