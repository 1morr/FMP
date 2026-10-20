import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';

// 帳號頁「歌單」讀的資料（M4 design §7.3、§4.4）。

/// 一次最多讀幾頁 `libraryPlaylists`：帳號歌單通常不多，超過就停下、顯示已讀的並記 warning
/// （防插件的 cursor 永遠不結束）。
const maxAccountPlaylistPages = 20;

/// [pluginId] 帳號自己的歌單：讀完所有頁（`libraryPlaylists` 從沒有 cursor 的第一頁到 cursor 為空，
/// 最多 [maxAccountPlaylistPages] 頁），依插件給的順序；跨頁重複的 `playlistId` 只留先出現的。
///
/// 任何一頁失敗，整份失敗（`AppError`）：只顯示一半的清單會讓使用者以為其餘的不存在。沒有登入是
/// `AuthRequired`（請求 `required`）。離開帳號頁就釋放。
final accountPlaylistsProvider = FutureProvider.autoDispose
    .family<List<LibraryPlaylist>, String>((ref, pluginId) async {
      try {
        final plugins = await ref.read(pluginRegistryProvider.future);
        final plugin = plugins[pluginId];
        if (plugin == null ||
            !plugin.manifest.capabilities.contains(
              PluginCapability.libraryRead,
            )) {
          throw Unsupported(
            pluginId: pluginId,
            cause: StateError('The source cannot list playlists'),
          );
        }
        final playlists = <String, LibraryPlaylist>{};
        String? cursor;
        var pages = 0;
        do {
          final page = await plugin.libraryPlaylists(
            LibraryPlaylistsQuery(cursor: cursor),
          );
          pages++;
          // 頁面離開後不再抓剩下的頁。
          if (!ref.mounted) return const <LibraryPlaylist>[];
          for (final playlist in page.playlists) {
            playlists.putIfAbsent(playlist.playlistId, () => playlist);
          }
          cursor = page.cursor;
        } while (cursor != null && pages < maxAccountPlaylistPages);
        if (cursor != null) {
          // 歌單名稱不進 log。
          ref
              .read(logProvider)
              .warning(
                'The account playlists stopped at the page limit',
                tag: libraryLogTag,
                fields: {'pluginId': pluginId, 'pages': pages},
              );
        }
        return List.unmodifiable(playlists.values);
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          AppError.wrap(error, stackTrace, pluginId: pluginId),
          stackTrace,
        );
      }
    });

/// [pluginId] 已匯入的遠端歌單 id（同插件同 id 在 `playlist_remote`）；匯入完成就更新，列上的
/// 「已匯入」跟著翻過來。
final importedRemoteIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>(
      (ref, pluginId) => ref
          .watch(playlistRepositoryProvider)
          .watchImportedRemoteIds(pluginId),
    );
