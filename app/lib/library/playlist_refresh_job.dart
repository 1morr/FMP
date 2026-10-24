import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/scheduler/background_scheduler.dart';

/// 匯入歌單自動刷新的工作 id（ADR 0033 §決定 4、M4 design §6.1）。
const playlistRefreshJobId = 'playlist-refresh';

/// 工作的間隔：每隔多久看一次有沒有歌單到期（每張歌單自己的間隔在 `playlist_remote`）。
const playlistRefreshJobInterval = Duration(minutes: 30);

/// 匯入歌單的自動刷新（ADR 0033 §決定 4）：登記一個沒有 `pluginId` 的 `playlist-refresh`
/// 工作，每次執行把到期的歌單依 `last_refreshed_at` 由舊到新逐張交給 [PlaylistRefresher]。
///
/// - 到期：`status = active`、有間隔、插件在清單上（已啟用且宣告 `importPlaylist`）、
///   `last_refreshed_at` 為空或已過間隔。失敗的那張不寫 `last_refreshed_at`，下一輪再試；
///   `sourceGone`、`authRequired` 不選。
/// - 單張失敗只寫那張的狀態、繼續下一張。**至少一張失敗而沒有任何一張成功**才丟錯讓排程器
///   退避；沒有到期的是成功。[RefreshDiscarded]、[RefreshSourceUnavailable]（過期、被取消、
///   刪掉、插件中途停用）不是失敗也不是成功，不計入。
/// - 取消：每張以 `RefreshTrigger(isCurrent: …)` 交給刷新器；工作過期（`JobContext`）、那張的
///   間隔被改成不啟用或那一列被刪，都讓 `isCurrent` 變假。插件停用或移除由刷新器自己看。
///
/// 常駐：由 `FmpApp` 聽著，Riverpod 3 沒人聽的 provider 會被暫停。
final playlistRefreshJobProvider = NotifierProvider<PlaylistRefreshJob, void>(
  PlaylistRefreshJob.new,
);

final class PlaylistRefreshJob extends Notifier<void> {
  @override
  void build() {
    // 不在 onDispose 移除工作（生命週期裡不能碰別的 provider）：跟排程器一樣常駐到 App 結束。
    ref
        .read(backgroundSchedulerProvider.notifier)
        .register(
          SchedulerJob(
            id: playlistRefreshJobId,
            interval: playlistRefreshJobInterval,
            run: _run,
          ),
        );
  }

  Future<void> _run(JobContext context) async {
    if (!ref.mounted) return;
    final repository = ref.read(playlistRepositoryProvider);
    final plugins = await ref.read(pluginRegistryProvider.future);
    final pluginIds = {
      for (final plugin in plugins.values)
        if (plugin.manifest.capabilities.contains(
          PluginCapability.importPlaylist,
        ))
          plugin.manifest.id,
    };
    final due = await repository.dueForRefresh(pluginIds, clock.now().toUtc());
    if (due.isEmpty || !context.isCurrent || !ref.mounted) return;

    // 進行中的那張被改成不啟用或刪掉：看資料庫的變動，不用等這一輪結束。
    int? running;
    var cancelled = false;
    final watch = repository.watchRefreshIntervals().listen((intervals) {
      if (running != null && intervals[running] == null) cancelled = true;
    });
    var succeeded = 0;
    AppError? lastError;
    try {
      for (final remote in due) {
        if (!context.isCurrent || !ref.mounted) return;
        try {
          // 排到的時候再確認一次：讀到期清單之後間隔可能已被改掉。
          final latest = await repository.remote(remote.playlistId);
          if (latest?.refreshIntervalHours == null) continue;
          running = remote.playlistId;
          cancelled = false;
          final outcome = await ref
              .read(playlistRefresherProvider)
              .refresh(
                remote.playlistId,
                trigger: RefreshTrigger(
                  isCurrent: () => context.isCurrent && !cancelled,
                ),
              );
          switch (outcome) {
            case RefreshFinished():
              succeeded++;
            case RefreshFailed(:final error):
              lastError = error;
            // 排程的刷新沒有 `ImportCancel`，不會被取消。
            case RefreshDiscarded() ||
                RefreshSourceUnavailable() ||
                RefreshCancelled():
              break;
          }
        } on Object catch (error, stackTrace) {
          // 資料庫本身的例外：該張算失敗，其他繼續。
          if (!context.isCurrent || !ref.mounted) return;
          lastError = AppError.wrap(error, stackTrace);
          ref
              .read(logProvider)
              .warning(
                'Playlist refresh crashed',
                tag: libraryLogTag,
                error: error,
                stackTrace: stackTrace,
                fields: {'playlistId': remote.playlistId},
              );
        } finally {
          running = null;
        }
      }
    } finally {
      unawaited(watch.cancel());
    }
    if (lastError != null && succeeded == 0 && context.isCurrent) {
      throw lastError;
    }
  }
}
