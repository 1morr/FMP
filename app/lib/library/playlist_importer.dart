import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// [PlaylistImporter.importUrl] 的結果。
sealed class ImportResult {
  const ImportResult();
}

/// 沒有插件認得這個網址（「無法辨識這個網址」）。
@immutable
final class ImportUnrecognized extends ImportResult {
  const ImportUnrecognized();
}

/// 這個網址是一個 Mix：[PlaylistImporter.importUrl] 什麼都沒寫，由呼叫端交給
/// [PlaylistImporter.createMix] 建 Mix 歌單。
@immutable
final class ImportMixSeed extends ImportResult {
  const ImportMixSeed({required this.pluginId, required this.seed});

  final String pluginId;
  final MixSeedQuery seed;
}

/// 認得網址的插件沒有 `resolveStream`（僅元資料來源，Spotify、QQ）：交給匯入預覽（PR 19），
/// 這裡什麼都沒寫、也沒有取任何一頁。
@immutable
final class ImportMetadataOnly extends ImportResult {
  const ImportMetadataOnly({required this.pluginId, required this.playlistId});

  final String pluginId;

  /// 音源內的歌單 id。
  final String playlistId;
}

/// 匯入歌單已經在音樂庫裡：新建的（[created]）或同一張的重新匯入（刷新那一列）。
/// [refresh] 是刷新器對這一列的結果（第一頁以外的頁失敗時是 `partial`）。
@immutable
final class ImportedPlaylist extends ImportResult {
  const ImportedPlaylist({
    required this.playlistId,
    required this.created,
    required this.refresh,
  });

  final int playlistId;
  final bool created;
  final RefreshOutcome refresh;
}

/// [PlaylistImporter.createMix] 建好的 Mix 歌單。
@immutable
final class CreatedMix extends ImportResult {
  const CreatedMix({required this.playlistId});

  final int playlistId;
}

final playlistImporterProvider = Provider<PlaylistImporter>(
  PlaylistImporter.new,
);

/// 從網址匯入歌單（ADR 0033 §決定 2、M4 design §5.1）。
final class PlaylistImporter {
  PlaylistImporter(this._ref);

  final Ref _ref;

  /// 依序問已啟用、宣告 `importPlaylist` 的插件 `playlistFromUrl`，第一個認得的勝出；插件拋錯
  /// 就停在那裡，不再問下一個。
  ///
  /// - `mixSeed` → [ImportMixSeed]；插件沒有 `resolveStream` → [ImportMetadataOnly]。
  /// - （插件, 歌單 id）已在 `playlist_remote` → 重新匯入＝刷新那一列，不覆寫名稱、間隔等
  ///   本地設定。
  /// - 否則取第一頁，**第一頁成功才建列**（名稱取遠端標題，不唯一、不自動改名；間隔 24 小時），
  ///   之後的頁交給刷新器。第一頁失敗什麼都不建。
  ///
  /// 失敗一律丟 `AppError`，由呼叫端提示：插件的錯誤原樣丟出，其他的包成 `UnexpectedError`。
  ///
  /// [onProgress] 在每一頁寫進資料庫後收到已讀的項目數（同 `PlaylistRefresher.refresh`）。
  Future<ImportResult> importUrl(
    String url, {
    void Function(int count)? onProgress,
  }) async {
    try {
      return await _import(url.trim(), onProgress);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(AppError.wrap(error, stackTrace), stackTrace);
    }
  }

  /// 以插件與音源內的歌單 id 匯入，不經網址（帳號頁的「歌單」，`playlistId` 來自
  /// `libraryPlaylists`）。之後的規則同 [importUrl]：已匯入的是刷新那一列，否則第一頁成功才建列。
  ///
  /// 插件不在已啟用的清單裡（沒安裝、已停用），或沒宣告 `importPlaylist` → [Unsupported]。
  /// 失敗一律丟 `AppError`。
  ///
  /// [writable] 是呼叫端已知的「帳號自己的、可寫」（`libraryPlaylists` 的權威值）：匯入成功後
  /// （新建或既有那列）給了就寫進 `playlist_remote.writable`，因為有的插件的 `importPlaylist` 不給
  /// `writable`，建列時會存成假；之後的刷新在 page 的 `writable` 是 `null` 時保留這個值。
  Future<ImportResult> importPlaylistId(
    String pluginId,
    String playlistId, {
    bool? writable,
    void Function(int count)? onProgress,
  }) async {
    try {
      final plugins = await _ref.read(pluginRegistryProvider.future);
      final plugin = plugins[pluginId];
      if (plugin == null ||
          !plugin.manifest.capabilities.contains(
            PluginCapability.importPlaylist,
          )) {
        throw Unsupported(
          pluginId: pluginId,
          cause: StateError('The source cannot import a playlist'),
        );
      }
      final result = await _importPlaylist(plugin, playlistId, onProgress);
      if (writable != null && result is ImportedPlaylist) {
        await _ref
            .read(playlistRepositoryProvider)
            .setWritable(result.playlistId, writable: writable);
      }
      return result;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(AppError.wrap(error, stackTrace), stackTrace);
    }
  }

  /// 為 [seed] 建一張 Mix 歌單（ADR 0033 §決定 1）：向插件的 `mix` 取一次（驗證種子、拿
  /// `MixBatch.title` 當名稱），成功才建列；不存曲目。同一個種子再來一次是新的一張。
  /// 失敗一律丟 `AppError`（插件的原樣丟出；一首都沒給是 `NotFound`），什麼都沒建。
  Future<CreatedMix> createMix(ImportMixSeed seed) async {
    try {
      final plugins = await _ref.read(pluginRegistryProvider.future);
      final plugin = plugins[seed.pluginId];
      if (plugin == null ||
          !plugin.manifest.capabilities.contains(PluginCapability.mix)) {
        throw Unsupported(
          pluginId: seed.pluginId,
          cause: StateError('The source cannot start a mix'),
        );
      }
      final batch = await plugin.mix(seed.seed);
      // 同 `MixSession.start`：一首都沒給的種子開不了 Mix，不建一張按了就失敗的歌單。
      if (batch.tracks.isEmpty) {
        throw NotFound(
          pluginId: seed.pluginId,
          cause: StateError('The mix has no track'),
        );
      }
      final id = await _ref
          .read(playlistRepositoryProvider)
          .createMix(
            name: batch.title,
            pluginId: seed.pluginId,
            seedSourceId: seed.seed.sourceId,
            seedCid: seed.seed.cid,
          );
      _ref
          .read(logProvider)
          .info(
            'Mix playlist created',
            tag: libraryLogTag,
            fields: {'pluginId': seed.pluginId, 'playlistId': id},
          );
      return CreatedMix(playlistId: id);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(AppError.wrap(error, stackTrace), stackTrace);
    }
  }

  Future<ImportResult> _import(
    String url,
    void Function(int count)? onProgress,
  ) async {
    if (url.isEmpty) return const ImportUnrecognized();
    final plugins = await _ref.read(pluginRegistryProvider.future);
    for (final plugin in plugins.values) {
      if (!plugin.manifest.capabilities.contains(
        PluginCapability.importPlaylist,
      )) {
        continue;
      }
      final found = await plugin.playlistFromUrl(PlaylistUrlQuery(url: url));
      switch (found) {
        case null:
          continue;
        case PlaylistMixSeedRef(:final seed):
          return ImportMixSeed(pluginId: plugin.manifest.id, seed: seed);
        case PlaylistIdRef(:final playlistId):
          return _importPlaylist(plugin, playlistId, onProgress);
      }
    }
    return const ImportUnrecognized();
  }

  Future<ImportResult> _importPlaylist(
    SourcePlugin plugin,
    String playlistId,
    void Function(int count)? onProgress,
  ) async {
    final pluginId = plugin.manifest.id;
    if (!plugin.manifest.capabilities.contains(
      PluginCapability.resolveStream,
    )) {
      return ImportMetadataOnly(pluginId: pluginId, playlistId: playlistId);
    }
    final repository = _ref.read(playlistRepositoryProvider);
    final refresher = _ref.read(playlistRefresherProvider);
    final existing = await repository.findRemote(pluginId, playlistId);
    if (existing != null) {
      return ImportedPlaylist(
        playlistId: existing.playlistId,
        created: false,
        refresh: await refresher.refresh(
          existing.playlistId,
          onProgress: onProgress,
        ),
      );
    }
    final first = await plugin.importPlaylist(
      PlaylistPageQuery(playlistId: playlistId),
    );
    final created = await repository.createImported(
      pluginId: pluginId,
      remoteId: playlistId,
      info: first.playlist.toInfo(),
    );
    if (created == null) {
      // 取第一頁的期間，同一張被另一次匯入建好了：改成刷新那一列（剛取到的第一頁照用）。
      final other = (await repository.findRemote(pluginId, playlistId))!;
      return ImportedPlaylist(
        playlistId: other.playlistId,
        created: false,
        refresh: await refresher.refresh(
          other.playlistId,
          firstPage: first,
          onProgress: onProgress,
        ),
      );
    }
    return ImportedPlaylist(
      playlistId: created,
      created: true,
      refresh: await refresher.refresh(
        created,
        firstPage: first,
        onProgress: onProgress,
      ),
    );
  }
}
