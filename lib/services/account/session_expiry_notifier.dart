import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 登入失效提示的去重閘門：一個 app session 內每個平台最多提示一次。
///
/// 失效從兩邊被偵測到 —— 啟動與帳號頁的狀態檢查，以及請求期的攔截器（後者拿
/// 不到 Riverpod，只寫 `Account.sessionExpired`，提示由
/// `accountSessionExpiryWatcherProvider` 看著那一列補上）。兩邊共用這一個 Set，
/// 所以同一次失效不會提示兩次，一直重試的請求也不會連環彈。
class SessionExpiryNotifier {
  SessionExpiryNotifier(this._toastService);

  final ToastService _toastService;
  final Set<String> _notifiedPlatforms = <String>{};

  /// 提示 [platform] 的登入已失效；同一個平台第二次之後是 no-op。
  void notifyExpired(String platform) {
    if (!_notifiedPlatforms.add(platform)) return;
    _toastService.showWarning(
      t.account.sessionExpired(platform: SourceIds.displayNameFor(platform)),
    );
  }
}
