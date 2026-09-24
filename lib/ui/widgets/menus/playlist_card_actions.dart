import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/user_message.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/library/playlist_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/menus/menu_action.dart';
import 'package:fmp/providers/library/refresh_provider.dart';
import 'package:fmp/ui/pages/library/widgets/create_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/confirm_destructive_dialog.dart';

/// PlaylistCard 共享操作工具类
class PlaylistCardActions {
  static const String actionPlayMix = 'play_mix';
  static const String actionAddAll = 'add_all';
  static const String actionShuffleAdd = 'shuffle_add';
  static const String actionEdit = 'edit';
  static const String actionRefresh = 'refresh';
  static const String actionDelete = 'delete';

  static List<MenuAction> buildMenuItems({
    required Playlist playlist,
    required bool isRefreshing,
  }) {
    return [
      if (playlist.isMix)
        MenuAction(
          id: actionPlayMix,
          icon: Icons.play_arrow,
          label: t.library.main.playMix,
        )
      else ...[
        MenuAction(
          id: actionAddAll,
          icon: Icons.play_arrow,
          label: t.library.addAll,
        ),
        MenuAction(
          id: actionShuffleAdd,
          icon: Icons.shuffle,
          label: t.library.shuffleAdd,
        ),
      ],
      MenuAction(
        id: actionEdit,
        icon: Icons.edit,
        label: t.library.main.editPlaylist,
      ),
      if (playlist.isImported && !playlist.isMix)
        MenuAction(
          id: actionRefresh,
          icon: Icons.refresh,
          label: isRefreshing
              ? t.library.main.refreshing
              : t.library.main.refreshPlaylist,
          enabled: !isRefreshing,
          showProgress: isRefreshing,
        ),
      MenuAction(
        id: actionDelete,
        icon: Icons.delete,
        label: t.library.main.deletePlaylist,
        destructive: true,
      ),
    ];
  }

  static List<PopupMenuEntry<String>> buildPopupMenuEntries({
    required BuildContext context,
    required List<MenuAction> items,
  }) {
    return buildMenuActionPopupEntries(
      items,
      Theme.of(context).colorScheme.error,
    );
  }

  static List<Widget> buildBottomSheetTiles({
    required BuildContext context,
    required List<MenuAction> items,
    required ValueChanged<String> onSelected,
  }) {
    return buildMenuActionListTiles(
      context,
      items,
      onSelected,
      Theme.of(context).colorScheme.error,
    );
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
        context,
        t.library.addedToQueue(n: result.tracks.length),
      );
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
        context,
        t.library.shuffledAddedToQueue(n: result.tracks.length),
      );
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
    } catch (e, stack) {
      AppLogger.error('Starting a playlist mix failed', e, stack, 'Library');
      if (context.mounted) {
        ToastService.error(
          context,
          '${t.library.main.playMixFailed}: ${userMessageFor(e)}',
        );
      }
    }
  }

  /// 右鍵選單條目。首頁與音樂庫的歌單卡共用這一份。
  static List<PopupMenuEntry<String>> buildContextMenuEntries(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    return buildPopupMenuEntries(
      context: context,
      items: buildMenuItems(
        playlist: playlist,
        isRefreshing: ref.read(isPlaylistRefreshingProvider(playlist.id)),
      ),
    );
  }

  /// 長按彈出的底部選單，條目與右鍵選單同一份 [buildMenuItems]。
  static void showOptionsSheet(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    final items = buildMenuItems(
      playlist: playlist,
      isRefreshing: ref.read(isPlaylistRefreshingProvider(playlist.id)),
    );

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: buildBottomSheetTiles(
              context: context,
              items: items,
              onSelected: (value) =>
                  handleAction(context, ref, playlist, value),
            ),
          ),
        ),
      ),
    );
  }

  /// 把選單 id 派到對應動作。兩個入口（右鍵、長按）都走這裡。
  static void handleAction(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    String value,
  ) {
    switch (value) {
      case actionPlayMix:
        playMix(context, ref, playlist);
      case actionAddAll:
        addAllToQueue(context, ref, playlist);
      case actionShuffleAdd:
        shuffleAddToQueue(context, ref, playlist);
      case actionEdit:
        showEditDialog(context, playlist);
      case actionRefresh:
        refreshPlaylist(ref, playlist);
      case actionDelete:
        showDeleteConfirm(context, ref, playlist);
    }
  }

  static void showEditDialog(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => CreatePlaylistDialog(playlist: playlist),
    );
  }

  /// 刷新沒有 context 回饋：大歌單刷很久，提示由 RefreshManagerNotifier 發，
  /// 那時這裡的 context 多半已經失效。
  static void refreshPlaylist(WidgetRef ref, Playlist playlist) {
    ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);
  }

  static Future<void> showDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final confirmed = await showConfirmDestructiveDialog(
      context,
      title: t.library.main.deletePlaylist,
      content: t.library.main.deletePlaylistConfirm(name: playlist.name),
      confirmLabel: t.general.delete,
    );
    if (confirmed == true) {
      ref.read(playlistListProvider.notifier).deletePlaylist(playlist.id);
      if (context.mounted) {
        ToastService.success(context, t.library.main.playlistDeleted);
      }
    }
  }
}
