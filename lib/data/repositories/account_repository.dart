import 'package:isar_community/isar.dart';

import '../models/account.dart';
import '../models/track.dart';

/// Account 數據倉庫。
///
/// 三個帳號服務先前各自寫了一份一模一樣的 upsert 交易，只有 platform 不同；
/// [upsert] 是那份實作的唯一版本。
class AccountRepository {
  AccountRepository(this._isar);

  final Isar _isar;

  /// 取得某平台的帳號。
  Future<Account?> getByPlatform(SourceType platform) {
    return _isar.accounts.filter().platformEqualTo(platform).findFirst();
  }

  /// 同步版本 —— 供需要在建構期立刻拿到初始狀態的呼叫端使用。
  Account? getByPlatformSync(SourceType platform) {
    return _isar.accounts.filter().platformEqualTo(platform).findFirstSync();
  }

  /// 監聽某平台的帳號變化；沒有帳號時發出 null。
  Stream<Account?> watchByPlatform(SourceType platform) {
    return _isar.accounts
        .filter()
        .platformEqualTo(platform)
        .watch(fireImmediately: true)
        .map((accounts) => accounts.isNotEmpty ? accounts.first : null);
  }

  /// 取得所有帳號（資料完整性掃描用）。
  Future<List<Account>> getAll() => _isar.accounts.where().findAll();

  /// 建立或更新某平台的帳號。傳 null 的欄位保持原值。
  ///
  /// `lastRefreshed` 每次都會更新 —— 這個方法就是「剛跟來源確認過」的意思。
  Future<void> upsert(
    SourceType platform, {
    bool? isLoggedIn,
    String? userId,
    String? userName,
    String? avatarUrl,
    DateTime? loginAt,
    bool? isVip,
  }) async {
    await _isar.writeTxn(() async {
      final account = await getByPlatform(platform) ??
          (Account()..platform = platform);

      if (isLoggedIn != null) account.isLoggedIn = isLoggedIn;
      if (userId != null) account.userId = userId;
      if (userName != null) account.userName = userName;
      if (avatarUrl != null) account.avatarUrl = avatarUrl;
      if (loginAt != null) account.loginAt = loginAt;
      if (isVip != null) account.isVip = isVip;
      account.lastRefreshed = DateTime.now();

      await _isar.accounts.put(account);
    });
  }

  /// 用 [account] 整個取代某平台的帳號；傳 null 表示刪除該平台的帳號。
  ///
  /// 給「從備份 / 憑證快照還原」用 —— 那條路徑要的是覆蓋而不是合併。
  Future<void> replaceForPlatform(SourceType platform, Account? account) async {
    await _isar.writeTxn(() async {
      final existing =
          await _isar.accounts.filter().platformEqualTo(platform).findAll();

      if (account == null) {
        await _isar.accounts.deleteAll([for (final a in existing) a.id]);
        return;
      }

      // 清掉不是這一列的舊資料。少了這一步，一個 id 未設的 Account 會被
      // 當成新列插進去，該平台就會同時有兩列。
      final stale = [for (final a in existing) if (a.id != account.id) a.id];
      if (stale.isNotEmpty) await _isar.accounts.deleteAll(stale);

      await _isar.accounts.put(account);
    });
  }
}
