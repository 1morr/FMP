import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'track_action_handler.dart';

enum TrackActionMenuScope {
  single,
  multi,
}

class TrackActionMenuOptions {
  const TrackActionMenuOptions({
    this.includePlay = true,
    this.includePlayNext = true,
    this.includeAddToQueue = true,
    this.includeAddToPlaylist = true,
    this.includeMatchLyrics = true,
    this.includeAddToRemote = true,
  });

  final bool includePlay;
  final bool includePlayNext;
  final bool includeAddToQueue;
  final bool includeAddToPlaylist;
  final bool includeMatchLyrics;
  final bool includeAddToRemote;
}

class TrackActionMenuItem {
  const TrackActionMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.trackAction,
    this.enabled = true,
    this.destructive = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final TrackAction trackAction;
  final bool enabled;
  final bool destructive;
}

List<TrackActionMenuItem> buildCommonTrackActionMenuItems({
  required Translations translations,
  TrackActionMenuScope scope = TrackActionMenuScope.single,
  TrackActionMenuOptions options = const TrackActionMenuOptions(),
}) {
  final isSingle = scope == TrackActionMenuScope.single;
  final items = <TrackActionMenuItem>[];

  if (isSingle && options.includePlay) {
    items.add(
      TrackActionMenuItem(
        id: playTrackActionId,
        label: translations.general.play,
        icon: Icons.play_arrow,
        trackAction: TrackAction.play,
      ),
    );
  }

  if (options.includePlayNext) {
    items.add(
      TrackActionMenuItem(
        id: playNextTrackActionId,
        label: translations.general.playNext,
        icon: Icons.queue_play_next,
        trackAction: TrackAction.playNext,
      ),
    );
  }

  if (options.includeAddToQueue) {
    items.add(
      TrackActionMenuItem(
        id: addToQueueTrackActionId,
        label: translations.general.addToQueue,
        icon: Icons.add_to_queue,
        trackAction: TrackAction.addToQueue,
      ),
    );
  }

  if (options.includeAddToPlaylist) {
    items.add(
      TrackActionMenuItem(
        id: addToPlaylistTrackActionId,
        label: translations.general.addToPlaylist,
        icon: Icons.playlist_add,
        trackAction: TrackAction.addToPlaylist,
      ),
    );
  }

  if (isSingle && options.includeMatchLyrics) {
    items.add(
      TrackActionMenuItem(
        id: matchLyricsTrackActionId,
        label: translations.lyrics.matchLyrics,
        icon: Icons.lyrics_outlined,
        trackAction: TrackAction.matchLyrics,
      ),
    );
  }

  if (options.includeAddToRemote) {
    items.add(
      TrackActionMenuItem(
        id: addToRemoteTrackActionId,
        label: translations.remote.addToFavorites,
        icon: Icons.cloud_upload_outlined,
        trackAction: TrackAction.addToRemote,
      ),
    );
  }

  return items;
}

List<PopupMenuEntry<String>> buildTrackActionPopupMenuEntries(
  List<TrackActionMenuItem> items, {
  Color? destructiveColor,
}) {
  return [
    for (final item in items)
      PopupMenuItem(
        value: item.id,
        enabled: item.enabled,
        child: ListTile(
          leading: Icon(
            item.icon,
            color: item.destructive ? destructiveColor : null,
          ),
          title: Text(
            item.label,
            style: item.destructive && destructiveColor != null
                ? TextStyle(color: destructiveColor)
                : null,
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
  ];
}

/// 頁面專用破壞性選單項（不屬於 TrackAction 體系，如刪除記錄、
/// 從遠程收藏夾移除）的共用寫法：icon 與 label 皆以 [color]
/// （通常是 colorScheme.error）呈現，與
/// [buildTrackActionPopupMenuEntries] 的 destructive 項目視覺一致。
PopupMenuItem<String> buildDestructivePopupMenuItem({
  required String value,
  required IconData icon,
  required String label,
  required Color color,
}) {
  return PopupMenuItem(
    value: value,
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      contentPadding: EdgeInsets.zero,
    ),
  );
}
