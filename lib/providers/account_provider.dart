import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../core/logger.dart';
import '../data/models/account.dart';
import '../data/models/track.dart';
import '../services/account/bilibili_account_service.dart';
import '../services/account/bilibili_favorites_service.dart';
import '../services/account/youtube_account_service.dart';
import '../services/account/youtube_playlist_service.dart';
import 'database_provider.dart';

/// Bilibili 帳號服務 Provider（單例）
final bilibiliAccountServiceProvider =
    Provider<BilibiliAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliAccountService(isar: isar);
});

/// Bilibili 收藏夾服務 Provider
final bilibiliFavoritesServiceProvider =
    Provider<BilibiliFavoritesService>((ref) {
  final accountService = ref.watch(bilibiliAccountServiceProvider);
  final isar = ref.watch(databaseProvider).requireValue;
  return BilibiliFavoritesService(accountService: accountService, isar: isar);
});

/// Bilibili 帳號狀態 Provider（響應式，監聽 Isar Account 變化）
final bilibiliAccountProvider =
    StateNotifierProvider<AccountNotifier, Account?>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return AccountNotifier(isar, SourceType.bilibili);
});

/// 是否已登錄 Bilibili（便捷 Provider）
final isBilibiliLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(bilibiliAccountProvider);
  return account?.isLoggedIn ?? false;
});

// ===== YouTube =====

/// YouTube 帳號服務 Provider（單例）
final youtubeAccountServiceProvider =
    Provider<YouTubeAccountService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return YouTubeAccountService(isar: isar);
});

/// YouTube 播放列表服務 Provider
final youtubePlaylistServiceProvider =
    Provider<YouTubePlaylistService>((ref) {
  final accountService = ref.watch(youtubeAccountServiceProvider);
  return YouTubePlaylistService(accountService: accountService);
});

/// YouTube 帳號狀態 Provider（響應式，監聽 Isar Account 變化）
final youtubeAccountProvider =
    StateNotifierProvider<AccountNotifier, Account?>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return AccountNotifier(isar, SourceType.youtube);
});

/// 是否已登錄 YouTube（便捷 Provider）
final isYouTubeLoggedInProvider = Provider<bool>((ref) {
  final account = ref.watch(youtubeAccountProvider);
  return account?.isLoggedIn ?? false;
});

// ===== 通用 =====

/// 通用：根據平台獲取登錄狀態
final isLoggedInProvider = Provider.family<bool, SourceType>((ref, platform) {
  switch (platform) {
    case SourceType.bilibili:
      return ref.watch(isBilibiliLoggedInProvider);
    case SourceType.youtube:
      return ref.watch(isYouTubeLoggedInProvider);
    case SourceType.netease:
      return false; // TODO: Netease login state (Phase 2)
  }
});

/// 啟動時自動刷新 Bilibili Cookie（後台執行，不阻塞 UI）
///
/// 在 app.dart 中 watch 此 Provider，確保每次啟動時檢查一次。
/// refreshCredentials() 內部已包含 needsRefresh 檢查，無需額外調用。
final accountCookieRefreshProvider = FutureProvider<void>((ref) async {
  final accountService = ref.read(bilibiliAccountServiceProvider);
  final isLoggedIn = await accountService.isLoggedIn();
  if (!isLoggedIn) return;

  try {
    final success = await accountService.refreshCredentials();
    if (success) {
      AppLogger.info('Bilibili cookie refresh check completed', 'AccountRefresh');
    } else {
      AppLogger.warning('Bilibili cookie refresh failed', 'AccountRefresh');
    }
  } catch (e) {
    AppLogger.warning('Bilibili cookie refresh check failed: $e', 'AccountRefresh');
  }
});

/// 通用帳號狀態管理（監聽 Isar Account 變化）
class AccountNotifier extends StateNotifier<Account?> {
  final Isar _isar;
  final SourceType _platform;
  StreamSubscription? _subscription;

  AccountNotifier(this._isar, this._platform) : super(null) {
    _init();
  }

  void _init() {
    final account = _isar.accounts
        .filter()
        .platformEqualTo(_platform)
        .findFirstSync();
    state = account;

    _subscription = _isar.accounts
        .filter()
        .platformEqualTo(_platform)
        .watch(fireImmediately: true)
        .listen((accounts) {
      state = accounts.isNotEmpty ? accounts.first : null;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
