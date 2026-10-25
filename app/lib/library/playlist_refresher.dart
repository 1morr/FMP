import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/import_progress.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 音樂庫的 log tag（匯入、刷新；M4 design §13）。
const libraryLogTag = 'library';

/// 誰要求這次刷新，以及它還有沒有效（M4 design §5.2）。
///
/// 手動刷新永遠有效（[manual]）；排程工作傳 `JobContext.isCurrent`（PR 10）：工作被移除、
/// 被取代或排程器釋放後為假，刷新器在每一頁寫入前與完整套用前檢查，為假就停、不寫。
@immutable
final class RefreshTrigger {
  const RefreshTrigger({this.isCurrent = _always});

  static const manual = RefreshTrigger();

  /// 這個觸發者還有效嗎。
  final bool Function() isCurrent;

  static bool _always() => true;
}

/// [PlaylistRefresher.refresh] 的結果。
sealed class RefreshOutcome {
  const RefreshOutcome();
}

/// 讀完了（或讀到一半）而且寫進去了：[result] 是 `complete` 或 `partial`。
@immutable
final class RefreshFinished extends RefreshOutcome {
  const RefreshFinished({
    required this.result,
    required this.added,
    required this.removed,
  });

  final PlaylistRefreshResult result;

  /// 新增了幾個項目。
  final int added;

  /// 移除了幾個項目（`partial` 一定是 0）。
  final int removed;
}

/// 第一頁就失敗（寫成 `failed`），或任何一頁 `NotFound`／`AuthRequired`（寫成
/// `sourceGone`／`authRequired`）：既有項目不刪、不重排（前面已寫進去的頁留著）。
/// 呼叫端決定要不要提示（手動才提示）。
@immutable
final class RefreshFailed extends RefreshOutcome {
  const RefreshFailed(this.error);

  final AppError error;
}

/// 插件停用、移除，或不再宣告 `importPlaylist`：什麼都沒寫（呼叫端顯示「音源已停用／未安裝」）。
@immutable
final class RefreshSourceUnavailable extends RefreshOutcome {
  const RefreshSourceUnavailable();
}

/// 沒有寫完：觸發者或代際過期、插件在中途被停用或換掉，或這張歌單已被刪除、不是匯入歌單。
@immutable
final class RefreshDiscarded extends RefreshOutcome {
  const RefreshDiscarded();
}

/// 使用者取消（[ImportCancel]）：停在 [count] 項（這次已寫入的）。一頁都沒寫時什麼都沒動；寫過的頁留著，
/// 歌單標成 `partial`，下一次刷新補齊（ADR 0033 §決定 2），沒有套用移除與重排。`discardOnCancel`
/// （新匯入）時改為整張歌單連同項目與孤兒曲目都刪掉。
@immutable
final class RefreshCancelled extends RefreshOutcome {
  const RefreshCancelled({required this.count});

  final int count;
}

final playlistRefresherProvider = Provider<PlaylistRefresher>(
  PlaylistRefresher.new,
);

/// 匯入歌單的刷新（ADR 0019 §決定 2、ADR 0033 §決定 2、M4 design §5.2）。
///
/// 全 App 一個 FIFO 鎖（這個物件由 provider 持有，只有一個）：手動、寫入後、排程三種觸發都
/// 排進同一個鎖，同時只刷一張。
///
/// 每一頁一個 transaction 寫進正式表，完整（每頁成功、最後 `cursor` 為空、有 `total` 時筆數
/// 相等）才一個 transaction 套用移除與順序；中途被殺只留下代際落後的項目，下一次刷新修好。
/// 寫入資料庫本身丟例外時（磁碟、約束）原樣丟出，該頁已回滾、鎖會釋放，歌單的狀態欄位不動。
final class PlaylistRefresher {
  PlaylistRefresher(this._ref);

  final Ref _ref;

  /// 鎖：每次刷新接在上一次的尾巴後面。
  Future<void> _tail = Future.value();

  /// 刷新 [playlistId]。[firstPage] 是呼叫端剛取到的第一頁（匯入新歌單時，避免再取一次），
  /// 沒給就由刷新器取。[onProgress] 在每一頁寫進資料庫後收到這次刷新的進度（已讀數、插件給的總數、
  /// 最後一首的標題）。[cancel] 在每一頁寫入之前檢查，被取消就停下（[RefreshCancelled]）；它不經
  /// [RefreshTrigger.isCurrent]，因為取消後仍要把 `partial` 寫進去。[discardOnCancel] 給新匯入用：
  /// 被取消就在這把鎖裡把歌單整張刪掉。
  Future<RefreshOutcome> refresh(
    int playlistId, {
    RefreshTrigger trigger = RefreshTrigger.manual,
    PlaylistPage? firstPage,
    void Function(ImportProgress progress)? onProgress,
    ImportCancel? cancel,
    bool discardOnCancel = false,
  }) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous
        .then(
          (_) => _refresh(
            playlistId,
            trigger,
            firstPage,
            onProgress,
            cancel,
            discardOnCancel,
          ),
        )
        .whenComplete(done.complete);
  }

  Future<RefreshOutcome> _refresh(
    int playlistId,
    RefreshTrigger trigger,
    PlaylistPage? firstPage,
    void Function(ImportProgress progress)? onProgress,
    ImportCancel? cancel,
    bool discardOnCancel,
  ) async {
    final outcome = await _refreshInner(
      playlistId,
      trigger,
      firstPage,
      onProgress,
      cancel,
    );
    if (outcome is RefreshCancelled && discardOnCancel) {
      // 新匯入被取消就是放棄：在同一把鎖裡刪掉歌單（`playlist_remote`、項目連帶刪除）與孤兒曲目，
      // 排在後面的刷新（排程、手動）進來時已經找不到這一列。
      await _ref.read(playlistRepositoryProvider).delete(playlistId);
      await _ref.read(tracksRepositoryProvider).deleteOrphans();
      _ref
          .read(logProvider)
          .info(
            'Cancelled import discarded',
            tag: libraryLogTag,
            fields: {'playlistId': playlistId, 'count': outcome.count},
          );
    }
    return outcome;
  }

  Future<RefreshOutcome> _refreshInner(
    int playlistId,
    RefreshTrigger trigger,
    PlaylistPage? firstPage,
    void Function(ImportProgress progress)? onProgress,
    ImportCancel? cancel,
  ) async {
    final repository = _ref.read(playlistRepositoryProvider);
    final remote = await repository.remote(playlistId);
    // 排隊的期間觸發者可能已經失效。
    if (remote == null || !trigger.isCurrent()) return const RefreshDiscarded();
    // 排隊的期間被取消：不開 session、不取頁。
    if (cancel != null && cancel.isCancelled) {
      return const RefreshCancelled(count: 0);
    }
    final plugin = await _usablePlugin(remote.pluginId);
    if (plugin == null) return const RefreshSourceUnavailable();
    final session = await repository.beginRefresh(
      playlistId,
      isCurrent: () => trigger.isCurrent() && _isLoaded(plugin),
    );
    if (session == null) return const RefreshDiscarded();
    final outcome = await _run(
      remote,
      plugin,
      session,
      firstPage,
      onProgress,
      cancel,
    );
    _log(playlistId, session.generation, outcome);
    return outcome;
  }

  Future<RefreshOutcome> _run(
    PlaylistRemote remote,
    SourcePlugin plugin,
    PlaylistRefreshSession session,
    PlaylistPage? firstPage,
    void Function(ImportProgress progress)? onProgress,
    ImportCancel? cancel,
  ) async {
    var page = firstPage;
    String? cursor;
    var pages = 0;
    var count = 0;
    int? total;
    var complete = true;
    final seenCursors = <String>{};
    late PlaylistPage last;
    while (true) {
      if (page == null) {
        try {
          page = await plugin.importPlaylist(
            PlaylistPageQuery(playlistId: remote.remoteId, cursor: cursor),
          );
        } on Object catch (error, stackTrace) {
          return _pageFailed(
            session,
            AppError.wrap(error, stackTrace, pluginId: remote.pluginId),
            pagesWritten: pages,
          );
        }
      }
      // 取消在寫下一頁之前生效：已取到的這一頁丟掉。
      if (cancel != null && cancel.isCancelled) {
        return _cancelled(session, pages: pages, count: count);
      }
      final written = await session.writePage([
        for (final item in page.items) item.toEntry(),
      ]);
      if (!written) return const RefreshDiscarded();
      pages++;
      count += page.items.length;
      last = page;
      total = page.total ?? total;
      onProgress?.call(
        ImportProgress(
          count: count,
          total: total,
          currentTitle: page.items.isEmpty ? null : page.items.last.track.title,
        ),
      );
      final next = page.cursor;
      if (next == null) break;
      // 一直回同一個 cursor 的插件不能讓刷新永遠跑下去：當作沒讀完。
      if (!seenCursors.add(next)) {
        complete = false;
        break;
      }
      cursor = next;
      page = null;
    }
    if (last.total != null && last.total != count) complete = false;
    // 插件說遠端還有它讀不到的：只增不刪。
    if (last.truncated) complete = false;
    if (!complete) return _finishPartial(session);
    final removed = await session.apply(last.playlist.toInfo());
    if (removed == null) return const RefreshDiscarded();
    return RefreshFinished(
      result: PlaylistRefreshResult.complete,
      added: session.added,
      removed: removed,
    );
  }

  Future<RefreshOutcome> _cancelled(
    PlaylistRefreshSession session, {
    required int pages,
    required int count,
  }) async {
    if (pages == 0) return const RefreshCancelled(count: 0);
    return await session.markPartial()
        ? RefreshCancelled(count: count)
        : const RefreshDiscarded();
  }

  /// 取頁失敗。`NotFound`、`AuthRequired` 只改狀態（任何一頁都一樣）；已經寫了頁的其他錯誤
  /// 是不完整（`partial`，不移除不重排）；第一頁就失敗是 `failed`。
  Future<RefreshOutcome> _pageFailed(
    PlaylistRefreshSession session,
    AppError error, {
    required int pagesWritten,
  }) async {
    final bool written;
    switch (error) {
      case NotFound():
        written = await session.markStatus(PlaylistRemoteStatus.sourceGone);
      case AuthRequired():
        written = await session.markStatus(PlaylistRemoteStatus.authRequired);
      case _ when pagesWritten > 0:
        _ref
            .read(logProvider)
            .warning(
              'Playlist page failed',
              tag: libraryLogTag,
              error: error,
              fields: {'generation': session.generation, 'pages': pagesWritten},
            );
        return _finishPartial(session);
      case _:
        written = await session.markFailed();
    }
    return written ? RefreshFailed(error) : const RefreshDiscarded();
  }

  Future<RefreshOutcome> _finishPartial(PlaylistRefreshSession session) async =>
      await session.markPartial()
      ? RefreshFinished(
          result: PlaylistRefreshResult.partial,
          added: session.added,
          removed: 0,
        )
      : const RefreshDiscarded();

  /// 已啟用、宣告 `importPlaylist` 的 [pluginId]；其他情況是 `null`。
  Future<SourcePlugin?> _usablePlugin(String pluginId) async {
    final plugin = (await _ref.read(pluginRegistryProvider.future))[pluginId];
    if (plugin == null ||
        !plugin.manifest.capabilities.contains(
          PluginCapability.importPlaylist,
        )) {
      return null;
    }
    return plugin;
  }

  /// [plugin] 還是清單裡的那一個（沒有被停用、移除或更新換掉）。
  bool _isLoaded(SourcePlugin plugin) => identical(
    _ref.read(pluginRegistryProvider).value?[plugin.manifest.id],
    plugin,
  );

  void _log(int playlistId, int generation, RefreshOutcome outcome) {
    final log = _ref.read(logProvider);
    switch (outcome) {
      case RefreshFinished():
        log.info(
          'Playlist refresh finished',
          tag: libraryLogTag,
          fields: {
            'playlistId': playlistId,
            'result': outcome.result.name,
            'added': outcome.added,
            'removed': outcome.removed,
            'generation': generation,
          },
        );
      case RefreshFailed():
        log.info(
          'Playlist refresh failed',
          tag: libraryLogTag,
          error: outcome.error,
          fields: {'playlistId': playlistId, 'generation': generation},
        );
      case RefreshCancelled():
        log.info(
          'Playlist refresh cancelled',
          tag: libraryLogTag,
          fields: {
            'playlistId': playlistId,
            'count': outcome.count,
            'generation': generation,
          },
        );
      case RefreshDiscarded():
        log.info(
          'Playlist refresh discarded',
          tag: libraryLogTag,
          fields: {'playlistId': playlistId, 'generation': generation},
        );
      case RefreshSourceUnavailable():
        break;
    }
  }
}
