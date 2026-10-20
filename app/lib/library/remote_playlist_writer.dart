import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

final remotePlaylistWriterProvider = Provider<RemotePlaylistWriter>(
  RemotePlaylistWriter.new,
);

/// 寫入之後多久才刷新那張匯入歌單。YouTube 寫後讀有延遲（2026-10 實測約 40 秒）：立刻刷新看不到
/// 剛加的歌，移除後則讀到舊清單、把剛從本地刪掉的又加回來。
const remoteRefreshDelay = Duration(seconds: 60);

/// 建立延後刷新的計時器；測試換成假的，不真的等。
typedef RefreshTimerFactory = Timer Function(
  Duration delay,
  void Function() fire,
);

final remoteRefreshTimerProvider = Provider<RefreshTimerFactory>(
  (ref) => Timer.new,
);

/// 加入一張遠端歌單的結果（一次 `addToPlaylist`）。
@immutable
final class RemoteAddOutcome {
  const RemoteAddOutcome({
    required this.playlistId,
    this.added = 0,
    this.alreadyPresent = 0,
    this.failed = 0,
    this.error,
  });

  /// 音源內的歌單 id（`libraryPlaylists` 給的）。
  final String playlistId;
  final int added;
  final int alreadyPresent;

  /// 失敗的曲目數；整個呼叫失敗時是送出的曲目數。
  final int failed;

  /// 整個呼叫失敗的錯誤，或第一個失敗曲目的錯誤（插件沒說原因就是 `null`）。
  final AppError? error;

  /// 至少一首在遠端歌單裡了（加進去或本來就有）。
  bool get succeeded => added + alreadyPresent > 0;
}

/// 移除一項失敗：[entry] 是本地的那一項，[error] 是插件給的原因（可能沒有）。
@immutable
final class RemoteRemoveFailure {
  const RemoteRemoveFailure(this.entry, this.error);

  final PlaylistEntry entry;
  final AppError? error;
}

/// 從遠端歌單移除的結果。`removed` 與 `notPresent` 的項目已從本地刪掉。
@immutable
final class RemoteRemoveOutcome {
  const RemoteRemoveOutcome({
    required this.removed,
    required this.notPresent,
    required this.failures,
  });

  final int removed;
  final int notPresent;
  final List<RemoteRemoveFailure> failures;
}

/// 遠端歌單的寫入（`libraryWrite`，ADR 0019 §決定 4、ADR 0032 §決定 4，M4 design §7.1、§7.2）：
/// 加入、建立、移除，與寫入之後匯入歌單的刷新。
///
/// 呼叫端（`ui/`）負責入口條件（插件宣告 `libraryWrite`、已登入、歌單可寫）與結果的提示；這裡只
/// 在插件不在清單或沒宣告 `libraryWrite` 時丟 [Unsupported]。log 用 tag [libraryLogTag]，欄位只有插件
/// id、本地歌單 id 與筆數，不放歌單名稱與曲名（ADR 0011 §決定 6）。
final class RemotePlaylistWriter {
  RemotePlaylistWriter(this._ref) {
    // App 結束或 provider 被拆時取消：沒做的刷新由之後的排程刷新補上。
    _ref.onDispose(() {
      for (final timer in _pending.values) {
        timer.cancel();
      }
      _pending.clear();
    });
  }

  final Ref _ref;

  /// 等著刷新的歌單（本地 id）與它的計時器；同一張在延遲內再次寫入就重新計時，只刷一次。
  final _pending = <int, Timer>{};

  /// 在 [pluginId] 的帳號上新增一張空歌單，回傳音源內的歌單 id。[title] 去掉頭尾空白後不得為空。
  Future<String> createRemote(String pluginId, String title) async {
    final plugin = await _writer(pluginId);
    final result = await plugin.createPlaylist(
      CreatePlaylistQuery(title: title),
    );
    _ref
        .read(logProvider)
        .info(
          'Remote playlist created',
          tag: libraryLogTag,
          fields: {'pluginId': pluginId},
        );
    return result.playlistId;
  }

  /// 把 [tracks]（都屬於 [pluginId]）加進 [playlistIds] 的每一張遠端歌單：每張一次 `addToPlaylist`，依
  /// 序做；一張整個失敗不影響其他張（記在那一張的結果）。每個成功的目標若已匯入
  /// （`playlist_remote` 同插件同 `remote_id`）就在背景排一次刷新（走刷新器的鎖，不提示）。
  /// 有一首不屬於 [pluginId] 就整批不送（[ArgumentError]）：別的音源的 id 不能寫進這個帳號的歌單。
  Future<List<RemoteAddOutcome>> addToRemote(
    String pluginId,
    List<TrackInfo> tracks,
    Iterable<String> playlistIds,
  ) async {
    if (tracks.any((track) => track.sourceTypeId != pluginId)) {
      throw ArgumentError.value(
        pluginId,
        'pluginId',
        'every track must belong to the plugin',
      );
    }
    final plugin = await _writer(pluginId);
    // 同一首選了好幾次（歷史的多選）只送一次：同一次呼叫裡重複的曲目，有的平台會加兩次
    // （ADR 0019 §決定 4：不重複加入）。計數對的是送出的曲目。
    final seen = <TrackKeyParts>{};
    final refs = [
      for (final track in tracks)
        if (seen.add(track.key))
          AddTrackRef(sourceId: track.sourceId, cid: track.cid),
    ];
    final outcomes = <RemoteAddOutcome>[];
    for (final playlistId in playlistIds) {
      outcomes.add(await _addTo(plugin, playlistId, refs));
    }
    final repository = _ref.read(playlistRepositoryProvider);
    for (final outcome in outcomes) {
      if (!outcome.succeeded) continue;
      final remote = await repository.findRemote(pluginId, outcome.playlistId);
      if (remote != null) _refreshInBackground(remote.playlistId);
    }
    _ref
        .read(logProvider)
        .info(
          'Remote add finished',
          tag: libraryLogTag,
          fields: {
            'pluginId': pluginId,
            'playlists': outcomes.length,
            'tracks': refs.length,
            'added': outcomes.fold<int>(0, (sum, o) => sum + o.added),
            'alreadyPresent': outcomes.fold<int>(
              0,
              (sum, o) => sum + o.alreadyPresent,
            ),
            'failed': outcomes.fold<int>(0, (sum, o) => sum + o.failed),
          },
        );
    return outcomes;
  }

  Future<RemoteAddOutcome> _addTo(
    SourcePlugin plugin,
    String playlistId,
    List<AddTrackRef> refs,
  ) async {
    final AddToPlaylistResponse response;
    try {
      response = await plugin.addToPlaylist(
        AddToPlaylistQuery(playlistId: playlistId, tracks: refs),
      );
    } on Object catch (error, stackTrace) {
      final wrapped = AppError.wrap(
        error,
        stackTrace,
        pluginId: plugin.manifest.id,
      );
      _ref
          .read(logProvider)
          .warning(
            'Remote add failed',
            tag: libraryLogTag,
            error: wrapped,
            fields: {'pluginId': plugin.manifest.id, 'tracks': refs.length},
          );
      return RemoteAddOutcome(
        playlistId: playlistId,
        failed: refs.length,
        error: wrapped,
      );
    }
    final failed = [
      for (final result in response.results)
        if (result.status == LibraryWriteStatus.failed) result,
    ];
    return RemoteAddOutcome(
      playlistId: playlistId,
      added: _count(response.results, LibraryWriteStatus.added),
      alreadyPresent: _count(
        response.results,
        LibraryWriteStatus.alreadyPresent,
      ),
      failed: failed.length,
      error: failed.map((result) => result.error).nonNulls.firstOrNull,
    );
  }

  /// 從匯入歌單 [playlistId]（本地 id）的遠端歌單移除 [entries]（本地項目）。
  ///
  /// 整個呼叫失敗（`AuthRequired`、網路…）原樣丟 `AppError`，本地什麼都不動。否則 `removed` 與
  /// `notPresent` 的項目從本地刪掉，有刪的話在背景排一次刷新（走刷新器的鎖，不提示）；`failed` 的
  /// 項目留著，列在回傳值裡。不是匯入歌單丟 [StateError]；入口開著時歌單變成不可寫（刷新寫了
  /// `writable = false`）是 [Unsupported]，有一項不屬於這張歌單的插件是 [ArgumentError]，都不呼叫插件。
  Future<RemoteRemoveOutcome> removeFromRemote(
    int playlistId,
    List<PlaylistEntry> entries,
  ) async {
    final repository = _ref.read(playlistRepositoryProvider);
    final remote = await repository.remote(playlistId);
    if (remote == null) {
      throw StateError('Playlist $playlistId is not an imported playlist');
    }
    if (!remote.writable) {
      throw Unsupported(
        pluginId: remote.pluginId,
        cause: StateError('The remote playlist is not writable'),
      );
    }
    if (entries.any((entry) => entry.track.sourceTypeId != remote.pluginId)) {
      throw ArgumentError.value(
        playlistId,
        'playlistId',
        'every entry must belong to the plugin of the playlist',
      );
    }
    final plugin = await _writer(remote.pluginId);
    final response = await _wrap(
      remote.pluginId,
      () => plugin.removeFromPlaylist(
        RemoveFromPlaylistQuery(
          playlistId: remote.remoteId,
          items: [
            for (final entry in entries)
              RemoveItemRef(
                sourceId: entry.track.sourceId,
                cid: entry.track.cid,
                remoteItemId: entry.remoteItemId,
              ),
          ],
        ),
      ),
      logMessage: 'Remote remove failed',
      fields: {'pluginId': remote.pluginId, 'playlistId': playlistId},
    );
    final gone = <int>[];
    final failures = <RemoteRemoveFailure>[];
    var removed = 0;
    var notPresent = 0;
    for (final (index, result) in response.results.indexed) {
      switch (result.status) {
        case LibraryWriteStatus.removed:
          removed++;
          gone.add(entries[index].id);
        case LibraryWriteStatus.notPresent:
          notPresent++;
          gone.add(entries[index].id);
        default:
          failures.add(RemoteRemoveFailure(entries[index], result.error));
      }
    }
    await repository.removeEntries(playlistId, gone);
    if (gone.isNotEmpty) _refreshInBackground(playlistId);
    _ref
        .read(logProvider)
        .info(
          'Remote remove finished',
          tag: libraryLogTag,
          fields: {
            'pluginId': remote.pluginId,
            'playlistId': playlistId,
            'removed': removed,
            'notPresent': notPresent,
            'failed': failures.length,
          },
        );
    return RemoteRemoveOutcome(
      removed: removed,
      notPresent: notPresent,
      failures: List.unmodifiable(failures),
    );
  }

  Future<T> _wrap<T>(
    String pluginId,
    Future<T> Function() call, {
    required String logMessage,
    required Map<String, Object?> fields,
  }) async {
    try {
      return await call();
    } on Object catch (error, stackTrace) {
      final wrapped = AppError.wrap(error, stackTrace, pluginId: pluginId);
      _ref
          .read(logProvider)
          .warning(
            logMessage,
            tag: libraryLogTag,
            error: wrapped,
            fields: fields,
          );
      Error.throwWithStackTrace(wrapped, stackTrace);
    }
  }

  int _count(List<LibraryWriteResult> results, LibraryWriteStatus status) =>
      results.where((result) => result.status == status).length;

  /// 已啟用、宣告 `libraryWrite` 的 [pluginId]；其他情況 [Unsupported]。
  Future<SourcePlugin> _writer(String pluginId) async {
    final plugin = (await _ref.read(pluginRegistryProvider.future))[pluginId];
    if (plugin == null ||
        !plugin.manifest.capabilities.contains(PluginCapability.libraryWrite)) {
      throw Unsupported(
        pluginId: pluginId,
        cause: StateError('The source cannot change remote playlists'),
      );
    }
    return plugin;
  }

  /// 寫入之後的刷新，延後 [remoteRefreshDelay]（理由見該常數），到時與手動、排程共用刷新器的
  /// FIFO 鎖，不提示（design §13：背景的錯誤進錯誤歷史，狀態由刷新器寫進資料庫）。
  void _refreshInBackground(int playlistId) {
    _pending.remove(playlistId)?.cancel();
    _pending[playlistId] = _ref.read(remoteRefreshTimerProvider)(
      remoteRefreshDelay,
      () {
        _pending.remove(playlistId);
        _refreshNow(playlistId);
      },
    );
  }

  void _refreshNow(int playlistId) {
    // 刷新結束時 provider 可能已經釋放（App 結束、測試結束）：log 先拿好。
    final log = _ref.read(logProvider);
    unawaited(
      _ref
          .read(playlistRefresherProvider)
          .refresh(playlistId)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              // 資料庫本身的例外（刷新器原樣丟出）。
              log.report(
                'Failed to refresh a playlist after a remote write',
                AppError.wrap(error, stackTrace),
                tag: libraryLogTag,
              );
            },
          ),
    );
  }
}
