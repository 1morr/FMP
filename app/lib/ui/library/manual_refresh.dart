import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 使用者按下的刷新（歌單卡選單、詳情頁的「刷新」與狀態列的「重試」，M4 design §5.3）。
///
/// 狀態是正在手動刷新的歌單 id：按鈕以它顯示進行中、不再接受第二次（刷新器本身有 FIFO 鎖，
/// 但重複按只會排出一串沒意義的刷新）。結果的提示在這裡：手動才提示，自動刷新只更新狀態
/// （ADR 0013 §決定 5）。
final manualRefreshProvider = NotifierProvider<ManualRefresh, Set<int>>(
  ManualRefresh.new,
);

final class ManualRefresh extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// 刷新 [playlistId] 並提示結果；這張已經在刷新時什麼都不做。
  Future<void> call(int playlistId) async {
    if (state.contains(playlistId)) return;
    state = {...state, playlistId};
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).library;
    try {
      await report(
        await ref.read(playlistRefresherProvider).refresh(playlistId),
        playlistId,
      );
    } on Object catch (error, stackTrace) {
      // 寫入資料庫本身失敗（磁碟、約束）：刷新器原樣丟出。
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to refresh a playlist',
        tag: libraryLogTag,
        sentence: (reason) => t.refreshFailed(reason: reason),
      );
    } finally {
      state = {...state}..remove(playlistId);
    }
  }

  /// [outcome] 對使用者的提示。失敗而網路不是 `online` 時寫離線的字樣（ADR 0016 §決定 7），
  /// 其餘照 ADR 0013 的類別表；被丟棄（歌單已刪除、被取代）時沒有可說的。
  Future<void> report(RefreshOutcome outcome, int playlistId) async {
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).library;
    switch (outcome) {
      case RefreshFinished(:final result)
          when result == PlaylistRefreshResult.partial:
        toaster.warning(t.refreshedPartly);
      case RefreshFinished():
        toaster.success(t.refreshed);
      case RefreshFailed(:final error):
        if (ref.read(networkStatusProvider) != NetworkStatus.online) {
          toaster.warning(t.refreshOffline);
        } else {
          toaster.error(
            error,
            operation: 'Failed to refresh a playlist',
            tag: libraryLogTag,
            sentence: (reason) => t.refreshFailed(reason: reason),
          );
        }
      case RefreshSourceUnavailable():
        final remote = await ref
            .read(playlistRepositoryProvider)
            .remote(playlistId);
        final reason = remote == null
            ? null
            : ref.read(sourceUnavailableProvider(remote.pluginId));
        toaster.warning(reason ?? t.refreshNoSource);
      case RefreshDiscarded():
        break;
    }
  }
}
