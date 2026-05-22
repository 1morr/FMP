import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../services/audio/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../i18n/strings.g.dart';

class PlaylistCardMenuItem {
  const PlaylistCardMenuItem({
    required this.id,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.destructive = false,
    this.showProgress = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool destructive;
  final bool showProgress;
}

/// PlaylistCard 共享操作工具类
class PlaylistCardActions {
  static const String actionPlayMix = 'play_mix';
  static const String actionAddAll = 'add_all';
  static const String actionShuffleAdd = 'shuffle_add';
  static const String actionEdit = 'edit';
  static const String actionRefresh = 'refresh';
  static const String actionDelete = 'delete';

  static List<PlaylistCardMenuItem> buildMenuItems({
    required Playlist playlist,
    required bool isRefreshing,
  }) {
    return [
      if (playlist.isMix)
        PlaylistCardMenuItem(
          id: actionPlayMix,
          icon: Icons.play_arrow,
          label: t.library.main.playMix,
        )
      else ...[
        PlaylistCardMenuItem(
          id: actionAddAll,
          icon: Icons.play_arrow,
          label: t.library.addAll,
        ),
        PlaylistCardMenuItem(
          id: actionShuffleAdd,
          icon: Icons.shuffle,
          label: t.library.shuffleAdd,
        ),
      ],
      PlaylistCardMenuItem(
        id: actionEdit,
        icon: Icons.edit,
        label: t.library.main.editPlaylist,
      ),
      if (playlist.isImported && !playlist.isMix)
        PlaylistCardMenuItem(
          id: actionRefresh,
          icon: isRefreshing ? Icons.hourglass_empty : Icons.refresh,
          label: isRefreshing
              ? t.library.main.refreshing
              : t.library.main.refreshPlaylist,
          enabled: !isRefreshing,
          showProgress: isRefreshing,
        ),
      PlaylistCardMenuItem(
        id: actionDelete,
        icon: Icons.delete,
        label: t.library.main.deletePlaylist,
        destructive: true,
      ),
    ];
  }

  static List<PopupMenuEntry<String>> buildPopupMenuEntries({
    required BuildContext context,
    required List<PlaylistCardMenuItem> items,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      for (final item in items)
        PopupMenuItem(
          value: item.id,
          enabled: item.enabled,
          child: ListTile(
            leading: Icon(
              item.icon,
              color: item.destructive ? colorScheme.error : null,
            ),
            title: Text(
              item.label,
              style:
                  item.destructive ? TextStyle(color: colorScheme.error) : null,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
  }

  static List<Widget> buildBottomSheetTiles({
    required BuildContext context,
    required List<PlaylistCardMenuItem> items,
    required ValueChanged<String> onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      for (final item in items)
        ListTile(
          leading: item.showProgress
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                )
              : Icon(
                  item.icon,
                  color: item.destructive ? colorScheme.error : null,
                ),
          title: Text(
            item.label,
            style:
                item.destructive ? TextStyle(color: colorScheme.error) : null,
          ),
          enabled: item.enabled,
          onTap: item.enabled
              ? () {
                  Navigator.pop(context);
                  onSelected(item.id);
                }
              : null,
        ),
    ];
  }

  /// 添加歌单所有歌曲到队列
  static Future<void> addAllToQueue(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(result.tracks);

    if (added && context.mounted) {
      ToastService.success(
          context, t.library.addedToQueue(n: result.tracks.length));
    }
  }

  /// 随机添加歌单所有歌曲到队列
  static Future<void> shuffleAddToQueue(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(result.tracks)..shuffle();
    final added = await controller.addAllToQueue(shuffled);

    if (added && context.mounted) {
      ToastService.success(
          context, t.library.shuffledAddedToQueue(n: result.tracks.length));
    }
  }

  /// 播放 Mix 歌单
  static Future<void> playMix(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    if (playlist.mixPlaylistId == null || playlist.mixSeedVideoId == null) {
      ToastService.error(context, t.library.main.mixInfoIncomplete);
      return;
    }

    try {
      final controller = ref.read(audioControllerProvider.notifier);
      await controller.startMixFromPlaylist(playlist);
    } catch (e) {
      if (context.mounted) {
        ToastService.error(context, '${t.library.main.playMixFailed}: $e');
      }
    }
  }
}
