import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../handlers/track_action_handler.dart';
import '../../handlers/track_action_menu.dart';

/// 多選模式下可用的操作類型
const selectionActionAddToQueue = addToQueueTrackActionId;
const selectionActionPlayNext = playNextTrackActionId;
const selectionActionAddToPlaylist = addToPlaylistTrackActionId;
const selectionActionAddToRemotePlaylist = addToRemoteTrackActionId;
const selectionActionRemoveFromRemotePlaylist = 'remove_from_remote';
const selectionActionDownload = 'download';
const selectionActionDelete = 'delete';

/// 構建多選模式的溢出菜單項目。
///
/// 前半段為共用曲目操作（[buildCommonTrackActionMenuItems] 的 multi scope
/// 子集），後半段為頁面特定的額外操作：從遠程收藏夾移除與刪除以
/// [colorScheme] 的 error 色呈現，下載維持一般樣式。兩組之間以
/// [PopupMenuDivider] 分隔（僅當兩組皆非空時）。
List<PopupMenuEntry<String>> buildSelectionMenuEntries({
  required ColorScheme colorScheme,
  required Set<String> availableActions,
}) {
  final commonItems = buildCommonTrackActionMenuItems(
    translations: t,
    scope: TrackActionMenuScope.multi,
    options: TrackActionMenuOptions(
      includePlayNext: availableActions.contains(selectionActionPlayNext),
      includeAddToQueue: availableActions.contains(selectionActionAddToQueue),
      includeAddToPlaylist:
          availableActions.contains(selectionActionAddToPlaylist),
      includeAddToRemote:
          availableActions.contains(selectionActionAddToRemotePlaylist),
    ),
  );

  final commonEntries = buildTrackActionPopupMenuEntries(commonItems);

  final extraEntries = <PopupMenuEntry<String>>[
    if (availableActions.contains(selectionActionRemoveFromRemotePlaylist))
      buildDestructivePopupMenuItem(
        value: selectionActionRemoveFromRemotePlaylist,
        icon: Icons.cloud_off_outlined,
        label: t.remote.removeFromFavorites,
        color: colorScheme.error,
      ),
    if (availableActions.contains(selectionActionDownload))
      PopupMenuItem(
        value: selectionActionDownload,
        child: ListTile(
          leading: const Icon(Icons.download),
          title: Text(t.selectionMode.download),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (availableActions.contains(selectionActionDelete))
      buildDestructivePopupMenuItem(
        value: selectionActionDelete,
        icon: Icons.delete_outline,
        label: t.selectionMode.removeFromPlaylist,
        color: colorScheme.error,
      ),
  ];

  return [
    ...commonEntries,
    if (commonEntries.isNotEmpty && extraEntries.isNotEmpty)
      const PopupMenuDivider(),
    ...extraEntries,
  ];
}
