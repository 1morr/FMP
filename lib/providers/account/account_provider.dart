import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/account/account_service.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/bilibili_favorites_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/netease_playlist_service.dart';
import 'package:fmp/services/account/session_expiry_notifier.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:fmp/services/account/youtube_playlist_service.dart';
import 'package:fmp/data/database/database_provider.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';

/// Bilibili 帳號服務 Provider（單例）
final bilibiliAccountServiceProvider = Provider<BilibiliAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliAccountService(isar: isar);
});

/// Bilibili 收藏夾服務 Provider
final bilibiliFavoritesServiceProvider = Provider<BilibiliFavoritesService>((
  ref,
) {
  final accountService = ref.watch(bilibiliAccountServiceProvider);
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliFavoritesService(accountService: accountService, isar: isar);
});

/// Bilibili 帳號狀態 Provider（響應式，監聽 Isar Account 變化）
final bilibiliAccountProvider = NotifierProvider<AccountNotifier, Account?>(
  () => AccountNotifier(SourceIds.bilibili),
);

/// 是否已登錄 Bilibili（便捷 Provider）
final isBilibiliLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(bilibiliAccountProvider);
  return account?.isLoggedIn ?? false;
});

// ===== YouTube =====

/// YouTube 帳號服務 Provider（單例）
final youtubeAccountServiceProvider = Provider<YouTubeAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return YouTubeAccountService(isar: isar);
});

/// YouTube 播放列表服務 Provider
final youtubePlaylistServiceProvider = Provider<YouTubePlaylistService>((ref) {
  final accountService = ref.watch(youtubeAccountServiceProvider);
  return YouTubePlaylistService(accountService: accountService);
});

/// YouTube 帳號狀態 Provider（響應式，監聽 Isar Account 變化）
final youtubeAccountProvider = NotifierProvider<AccountNotifier, Account?>(
  () => AccountNotifier(SourceIds.youtube),
);

/// 是否已登錄 YouTube（便捷 Provider）
final isYouTubeLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(youtubeAccountProvider);
  return account?.isLoggedIn ?? false;
});

// ===== 通用 =====

/// 各平台的帳號狀態，以音源 id 為鍵。
final Map<String, NotifierProvider<AccountNotifier, Account?>>
accountProvidersBySource = {
  SourceIds.bilibili: bilibiliAccountProvider,
  SourceIds.youtube: youtubeAccountProvider,
  SourceIds.netease: neteaseAccountProvider,
};

/// 各平台的帳號服務，以音源 id（[AccountService.platform]）為鍵。
final accountServicesProvider = Provider<Map<String, AccountService>>((ref) {
  return {
    for (final service in <AccountService>[
      ref.watch(bilibiliAccountServiceProvider),
      ref.watch(youtubeAccountServiceProvider),
      ref.watch(neteaseAccountServiceProvider),
    ])
      service.platform: service,
  };
});

/// 通用：根據平台獲取登錄狀態。沒有帳號體系的音源一律視為未登入。
final isLoggedInProvider = Provider.family<bool, String>((ref, platform) {
  final accountProvider = accountProvidersBySource[platform];
  if (accountProvider == null) return false;
  return ref.watch(accountProvider)?.isLoggedIn ?? false;
});

// ===== 網易雲 =====

/// 網易雲帳號服務 Provider（單例）
final neteaseAccountServiceProvider = Provider<NeteaseAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return NeteaseAccountService(isar: isar);
});

/// 網易雲帳號狀態 Provider（響應式，監聽 Isar Account 變化）
final neteaseAccountProvider = NotifierProvider<AccountNotifier, Account?>(
  () => AccountNotifier(SourceIds.netease),
);

/// 是否已登錄網易雲（便捷 Provider）
final isNeteaseLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(neteaseAccountProvider);
  return account?.isLoggedIn ?? false;
});

/// 網易雲歌單服務 Provider
final neteasePlaylistServiceProvider = Provider<NeteasePlaylistService>((ref) {
  final accountService = ref.watch(neteaseAccountServiceProvider);
  return NeteasePlaylistService(accountService: accountService);
});

/// 啟動時自動刷新 Bilibili Cookie（後台執行，不阻塞 UI）
///
/// 在 accountStatusCheckProvider 中 watch 此 Provider，確保在狀態檢查前完成。
/// refreshCredentials() 內部已包含 needsRefresh 檢查，無需額外調用。
final accountCookieRefreshProvider = FutureProvider<void>((ref) async {
  final accountService = ref.read(bilibiliAccountServiceProvider);
  final isLoggedIn = await accountService.isLoggedIn();
  if (!isLoggedIn) return;

  try {
    final success = await accountService.refreshCredentials();
    if (success) {
      AppLogger.info(
        'Bilibili cookie refresh check completed',
        'AccountRefresh',
      );
    } else {
      AppLogger.warning('Bilibili cookie refresh failed', 'AccountRefresh');
    }
  } catch (e) {
    AppLogger.warning(
      'Bilibili cookie refresh check failed: $e',
      'AccountRefresh',
    );
  }
});

/// 啟動時檢查所有已登錄帳號的狀態（Session 有效性 + VIP 狀態）
///
/// 在 app.dart 中 watch 此 Provider。內部先等待 Cookie 刷新完成，
/// 再依序檢查各平台，避免併發網絡請求。
final accountStatusCheckProvider = FutureProvider<void>((ref) async {
  // 這四個都不依賴 Cookie 刷新的結果，所以在 await 之前就讀完。
  // Riverpod 3 對 dispose 之後的 Ref 會拋 UnmountedRefException（2.x 只有
  // debug assert），在 await 之前讀完比事後補 ref.mounted 護欄更直接。
  final toastService = ref.read(toastServiceProvider);
  final sessionExpiry = ref.read(sessionExpiryNotifierProvider);
  final services = ref.read(accountServicesProvider).values.toList();

  // 先完成 Bilibili Cookie 刷新
  await ref.watch(accountCookieRefreshProvider.future);

  await verifyAllAccountStatuses(
    services,
    toastService,
    sessionExpiry: sessionExpiry,
  );
});

/// 登入失效提示的去重閘門（見 [SessionExpiryNotifier]）。
final sessionExpiryNotifierProvider = Provider<SessionExpiryNotifier>((ref) {
  return SessionExpiryNotifier(ref.watch(toastServiceProvider));
});

/// 監看三個平台的帳號列，在「剛轉成失效」時提示一次。
///
/// 攔截器建構時拿不到 Riverpod，所以請求期偵測到的失效只寫得進 Isar；提示由
/// 這裡補。只認「從非失效轉成失效」的那一次變化 —— 開 app 時就已經是失效的列
/// 不該每次啟動都再唸一遍。實際的一次性由 [SessionExpiryNotifier] 保證。
///
/// 副作用 provider 必須錨在 `MaterialApp` 之上（`lib/app.dart`）：Riverpod 3 會
/// 暫停被不透明路由蓋住的頁面上的 `ref.watch`，錨在頁面上的副作用在使用者打開
/// 全螢幕播放頁時就停了（`riverpod3_static_rule_test.dart` 守著）。
final accountSessionExpiryWatcherProvider = Provider<void>((ref) {
  final sessionExpiry = ref.watch(sessionExpiryNotifierProvider);
  for (final entry in accountProvidersBySource.entries) {
    ref.listen(entry.value, (previous, next) {
      if (previous?.sessionExpired != true && next?.sessionExpired == true) {
        sessionExpiry.notifyExpired(entry.key);
      }
    });
  }
});

class AccountStatusVerificationResult {
  const AccountStatusVerificationResult({
    required this.checkedPlatforms,
    required this.failedPlatforms,
  });

  final List<String> checkedPlatforms;
  final List<String> failedPlatforms;

  bool get hasFailures => failedPlatforms.isNotEmpty;
}

/// 檢查所有已登錄帳號的 Session 有效性和 VIP 狀態
///
/// 供 [accountStatusCheckProvider] 和帳號管理頁面共用。
Future<AccountStatusVerificationResult> verifyAllAccountStatuses(
  List<AccountService> services,
  ToastService toastService, {
  required SessionExpiryNotifier sessionExpiry,
}) async {
  final checkedPlatforms = <String>[];
  final failedPlatforms = <String>[];

  for (final service in services) {
    if (!await service.isLoggedIn()) continue;
    final oldAccount = await service.getCurrentAccount();
    final oldIsVip = oldAccount?.isVip ?? false;
    final name = SourceIds.displayNameFor(service.platform);

    try {
      final result = await service.checkAccountStatus();
      checkedPlatforms.add(service.platform);
      if (result.status == AccountStatus.invalid) {
        // 標記而不是登出：帳號列留著，帳號頁才有第三態可以畫。
        await service.markSessionExpired();
        sessionExpiry.notifyExpired(service.platform);
      } else if (result.status == AccountStatus.valid) {
        if (oldIsVip && result.isVip == false) {
          toastService.showInfo(t.account.vipExpired(platform: name));
        }
      }
    } catch (e) {
      failedPlatforms.add(service.platform);
      AppLogger.warning(
        '${service.platform} status check failed: $e',
        'AccountStatusCheck',
      );
    }
  }

  return AccountStatusVerificationResult(
    checkedPlatforms: checkedPlatforms,
    failedPlatforms: failedPlatforms,
  );
}

/// 通用帳號狀態管理（監聽 Isar Account 變化）
class AccountNotifier extends Notifier<Account?> {
  AccountNotifier(this._platform);

  final String _platform;
  late AccountRepository _accounts;
  StreamSubscription? _subscription;

  @override
  Account? build() {
    _accounts = ref.watch(accountRepositoryProvider);
    _subscription = _accounts.watchByPlatform(_platform).listen((account) {
      state = account;
    });
    ref.onDispose(() => _subscription?.cancel());
    // 同步先取一次，讓第一幀就有正確的登入狀態，再接上串流。
    return _accounts.getByPlatformSync(_platform);
  }
}
