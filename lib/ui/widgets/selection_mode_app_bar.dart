import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/track.dart';
import '../../providers/selection_provider.dart';
import '../../services/audio/audio_provider.dart';
import 'dialogs/add_to_playlist_dialog.dart';

/// 多選模式下可用的操作類型
enum SelectionAction {
  addToQueue,
  playNext,
  addToPlaylist,
  download,
  delete,
}

/// 多選模式 AppBar
/// 
/// 用於歌單詳情頁、探索頁、搜索頁的多選模式
class SelectionModeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  /// 選擇狀態 Provider
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState> selectionProvider;

  /// 所有可選擇的 tracks（用於全選功能）
  final List<Track> allTracks;

  /// 可用的操作列表
  final Set<SelectionAction> availableActions;

  /// 刪除操作回調（僅歌單詳情頁需要）
  final Future<void> Function(List<Track> tracks)? onDelete;

  /// 下載操作回調（僅歌單詳情頁需要）
  final Future<void> Function(List<Track> tracks)? onDownload;

  /// AppBar 底部組件（如 TabBar）
  final PreferredSizeWidget? bottom;

  const SelectionModeAppBar({
    super.key,
    required this.selectionProvider,
    required this.allTracks,
    required this.availableActions,
    this.onDelete,
    this.onDownload,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    final notifier = ref.read(selectionProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    final selectedCount = selectionState.selectedCount;
    final hasSelection = selectionState.hasSelection;

    final isAllSelected = selectionState.selectedCount == allTracks.length && allTracks.isNotEmpty;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: t.selectionMode.exitMode,
        onPressed: () => notifier.exitSelectionMode(),
      ),
      title: Text(t.selectionMode.selectedItems(count: selectedCount)),
      bottom: bottom,
      actions: [
        // 全選按鈕（圖標）
        IconButton(
          icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
          tooltip: isAllSelected ? t.selectionMode.deselectAll : t.selectionMode.selectAll,
          onPressed: () {
            if (isAllSelected) {
              notifier.deselectAll();
            } else {
              notifier.selectAll(allTracks);
            }
          },
        ),

        // 更多操作菜單
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          enabled: hasSelection,
          onSelected: (value) => _handleMenuAction(context, ref, value, selectionState.selectedTracks),
          itemBuilder: (context) => [
            // 添加到隊列
            if (availableActions.contains(SelectionAction.addToQueue))
              PopupMenuItem(
                value: 'add_to_queue',
                child: ListTile(
                  leading: Icon(Icons.add_to_queue),
                  title: Text(t.selectionMode.addToQueue),
                  contentPadding: EdgeInsets.zero,
                ),
              ),

            // 下一首播放
            if (availableActions.contains(SelectionAction.playNext))
              PopupMenuItem(
                value: 'play_next',
                child: ListTile(
                  leading: Icon(Icons.queue_play_next),
                  title: Text(t.selectionMode.playNext),
                  contentPadding: EdgeInsets.zero,
                ),
              ),

            // 添加到歌單
            if (availableActions.contains(SelectionAction.addToPlaylist))
              PopupMenuItem(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text(t.selectionMode.addToPlaylist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),

            // 下載
            if (availableActions.contains(SelectionAction.download))
              PopupMenuItem(
                value: 'download',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text(t.selectionMode.download),
                  contentPadding: EdgeInsets.zero,
                ),
              ),

            // 刪除
            if (availableActions.contains(SelectionAction.delete))
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(t.selectionMode.removeFromPlaylist, style: TextStyle(color: colorScheme.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),

        const SizedBox(width: 8),
      ],
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<Track> tracks,
  ) {
    switch (action) {
      case 'add_to_queue':
        _addToQueue(context, ref, tracks);
        break;
      case 'play_next':
        _playNext(context, ref, tracks);
        break;
      case 'add_to_playlist':
        _addToPlaylist(context, ref, tracks);
        break;
      case 'download':
        _download(context, ref, tracks);
        break;
      case 'delete':
        _delete(context, ref, tracks);
        break;
    }
  }

  Future<void> _addToQueue(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final notifier = ref.read(selectionProvider.notifier);

    int addedCount = 0;
    for (final track in tracks) {
      final added = await controller.addToQueue(track);
      if (added) addedCount++;
    }

    notifier.exitSelectionMode();

    if (context.mounted) {
      ToastService.success(context, t.selectionMode.addedToQueue(count: addedCount));
    }
  }

  Future<void> _playNext(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final notifier = ref.read(selectionProvider.notifier);

    // 反向添加，保持順序
    int addedCount = 0;
    for (final track in tracks.reversed) {
      final added = await controller.addNext(track);
      if (added) addedCount++;
    }

    notifier.exitSelectionMode();

    if (context.mounted) {
      ToastService.success(context, t.selectionMode.addedToNext(count: addedCount));
    }
  }

  Future<void> _addToPlaylist(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);

    notifier.exitSelectionMode();

    if (tracks.length == 1) {
      showAddToPlaylistDialog(context: context, track: tracks.first);
    } else {
      showAddToPlaylistDialog(context: context, tracks: tracks);
    }
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);

    if (onDownload != null) {
      await onDownload!(tracks);
    }

    notifier.exitSelectionMode();
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);

    // 確認對話框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.selectionMode.confirmRemove),
        content: Text(t.selectionMode.confirmRemoveContent(count: tracks.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.general.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.selectionMode.remove),
          ),
        ],
      ),
    );

    if (confirmed == true && onDelete != null) {
      await onDelete!(tracks);
      notifier.exitSelectionMode();

      if (context.mounted) {
        ToastService.success(context, t.selectionMode.removedTracks(count: tracks.length));
      }
    }
  }
}

/// 多選模式下的 Checkbox 組件
class SelectionCheckbox extends ConsumerWidget {
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState> selectionProvider;
  final Track track;

  const SelectionCheckbox({
    super.key,
    required this.selectionProvider,
    required this.track,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    final notifier = ref.read(selectionProvider.notifier);

    if (!selectionState.isSelectionMode) {
      return const SizedBox.shrink();
    }

    return Checkbox(
      value: selectionState.isSelected(track),
      onChanged: (_) => notifier.toggleSelection(track),
    );
  }
}

/// 多選模式下的組 Checkbox 組件（用於多P視頻組）
class SelectionGroupCheckbox extends ConsumerWidget {
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState> selectionProvider;
  final List<Track> tracks;

  const SelectionGroupCheckbox({
    super.key,
    required this.selectionProvider,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(selectionProvider);
    final notifier = ref.read(selectionProvider.notifier);

    if (!selectionState.isSelectionMode) {
      return const SizedBox.shrink();
    }

    final isFullySelected = notifier.isGroupFullySelected(tracks);
    final isPartiallySelected = notifier.isGroupPartiallySelected(tracks);

    return Checkbox(
      value: isFullySelected ? true : (isPartiallySelected ? null : false),
      tristate: true,
      onChanged: (_) => notifier.toggleGroupSelection(tracks),
    );
  }
}
