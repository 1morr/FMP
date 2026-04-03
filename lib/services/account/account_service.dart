import '../../data/models/account.dart';
import '../../data/models/track.dart';

/// 帳號狀態
enum AccountStatus { valid, invalid, error }

/// 帳號狀態檢查結果
class AccountCheckResult {
  final AccountStatus status;
  final bool? isVip;

  const AccountCheckResult({
    required this.status,
    this.isVip,
  });
}

/// 帳號服務抽象接口（可擴展到 YouTube、網易雲等）
abstract class AccountService {
  SourceType get platform;

  /// 檢查是否已登錄
  Future<bool> isLoggedIn();

  /// 獲取當前用戶信息
  Future<Account?> getCurrentAccount();

  /// 登出
  Future<void> logout();

  /// 刷新認證（Cookie/Token）
  /// 返回 true 表示刷新成功，false 表示需要重新登錄
  Future<bool> refreshCredentials();

  /// 檢查認證是否需要刷新
  Future<bool> needsRefresh();

  /// 檢查帳號登錄狀態和 VIP 狀態
  Future<AccountCheckResult> checkAccountStatus();
}
