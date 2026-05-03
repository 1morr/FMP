import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/track.dart';
import '../../providers/selection_provider.dart';
import '../handlers/track_action_coordinator.dart';
import '../handlers/track_action_handler.dart';
import '../handlers/track_action_menu.dart';

/// 多選模式下可用的操作類型
const selectionActionAddToQueue = addToQueueTrackActionId;
const selectionActionPlayNext = playNextTrackActionId;
const selectionActionAddToPlaylist = addToPlaylistTrackActionId;
const selectionActionAddToRemotePlaylist = addToRemoteTrackActionId;
const selectionActionRemoveFromRemotePlaylist = 'remove_from_remote';
const selectionActionDownload = 'download';
const selectionActionDelete = 'delete';

/// 多選模式 AppBar
///
/// 用於歌單詳情頁、探索頁、搜索頁的多選模式
class SelectionModeAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  /// 選擇狀態 Provider
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState>
      selectionProvider;

  /// 所有可選擇的 tracks（用於全選功能）
  final List<Track> allTracks;

  /// 可用的操作列表
  final Set<String> availableActions;

  /// 刪除操作回調（僅歌單詳情頁需要）
  final Future<void> Function(List<Track> tracks)? onDelete;

  /// 下載操作回調（僅歌單詳情頁需要）
  final Future<void> Function(List<Track> tracks)? onDownload;

  /// 從遠程收藏夾移除回調（僅導入歌單詳情頁需要）
  final Future<void> Function(List<Track> tracks)? onRemoveFromRemote;

  /// AppBar 底部組件（如 TabBar）
  final PreferredSizeWidget? bottom;

  const SelectionModeAppBar({
    super.key,
    required this.selectionProvider,
    required this.allTracks,
    required this.availableActions,
    this.onDelete,
    this.onDownload,
    this.onRemoveFromRemote,
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

    final isAllSelected = selectionState.selectedCount == allTracks.length &&
        allTracks.isNotEmpty;

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
          tooltip: isAllSelected
              ? t.selectionMode.deselectAll
              : t.selectionMode.selectAll,
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
          onSelected: (value) => _handleMenuAction(
              context, ref, value, selectionState.selectedTracks),
          itemBuilder: (context) => _buildSelectionMenuEntries(colorScheme),
        ),

        const SizedBox(width: 8),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildSelectionMenuEntries(
    ColorScheme colorScheme,
  ) {
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

    return [
      ...buildTrackActionPopupMenuEntries(commonItems),
      if (availableActions.contains(selectionActionRemoveFromRemotePlaylist))
        PopupMenuItem(
          value: selectionActionRemoveFromRemotePlaylist,
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: colorScheme.error),
            title: Text(
              t.remote.removeFromFavorites,
              style: TextStyle(color: colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
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
        PopupMenuItem(
          value: selectionActionDelete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: colorScheme.error),
            title: Text(
              t.selectionMode.removeFromPlaylist,
              style: TextStyle(color: colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<Track> tracks,
  ) {
    if (tryParseTrackAction(action) != null) {
      _handleCommonAction(context, ref, action, tracks);
      return;
    }

    switch (action) {
      case selectionActionRemoveFromRemotePlaylist:
        _removeFromRemotePlaylist(context, ref, tracks);
        break;
      case selectionActionDownload:
        _download(context, ref, tracks);
        break;
      case selectionActionDelete:
        _delete(context, ref, tracks);
        break;
    }
  }

  Future<void> _handleCommonAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);
    notifier.exitSelectionMode();
    await TrackActionCoordinator.handleMulti(
      context: context,
      ref: ref,
      tracks: tracks,
      actionId: action,
    );
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
        content:
            Text(t.selectionMode.confirmRemoveContent(count: tracks.length)),
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
        ToastService.success(
            context, t.selectionMode.removedTracks(count: tracks.length));
      }
    }
  }

  Future<void> _removeFromRemotePlaylist(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);

    if (onRemoveFromRemote != null) {
      await onRemoveFromRemote!(tracks);
    }

    notifier.exitSelectionMode();
  }
}

/// 多選模式下的 Checkbox 組件
class SelectionCheckbox extends ConsumerWidget {
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState>
      selectionProvider;
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
  final AutoDisposeStateNotifierProvider<SelectionNotifier, SelectionState>
      selectionProvider;
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
