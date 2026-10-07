import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 可編輯的佇列清單（M2 PR 18b，design §7.3）。播放頁的佇列分頁（expanded 以上）與
/// 底部面板（compact、medium，[showQueueSheet]）共用。
///
/// - 標題列：首數與「清空佇列」（確認後清空、提示一次）；隨機開著時多一行說明
///   （ADR 0018 §後果：拖曳只換歌，不改隨機順序）。
/// - 每列：封面、曲名、上傳者、時長、「⋯」選單與拖曳把手；目前這首以主色標示（臨時播放中
///   不標：`currentIndex` 是回到佇列時的位置）。點一下 `jumpTo`；只有把手能拖
///   （長按留給選單），放下呼叫 `move`。
/// - 固定列高的 `ReorderableListView.builder`，一萬首也只建看得到的；開啟時從目前這首的
///   前兩列開始；「切歌時捲到目前歌曲」開著時，目前這首換了（`currentIndex` 指的項目
///   換了，拖曳讓它換位置不算）就再捲一次，使用者正在拖曳時不捲。
class QueueView extends ConsumerStatefulWidget {
  const QueueView({super.key, this.scrollController});

  /// 清單的捲動控制器；底部面板要把清單的捲動接給 `DraggableScrollableSheet`。不給就
  /// 自己建。
  final ScrollController? scrollController;

  /// 「清空佇列」鈕；測試以它找。
  static const clearKey = ValueKey('queue-clear');

  @override
  ConsumerState<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends ConsumerState<QueueView> {
  /// 目前這首之前先露出的幾列，讓前一首看得到。
  static const _rowsAbove = 2;

  late final ScrollController _scroll =
      widget.scrollController ??
      ScrollController(initialScrollOffset: _currentOffset());

  /// 上一次看到的「目前這首」（佇列項目本身，編輯時沿用實例）。
  QueueEntry? _current;
  var _dragging = false;

  /// 清單上按著的指標數。拖曳被取消（指標 cancel）時 `onReorderEnd` 不會來，最後一個
  /// 指標放開就算拖曳結束，否則之後的自動捲動一直停著。
  var _pointers = 0;

  void _releasePointer() {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _dragging = false;
  }

  @override
  void initState() {
    super.initState();
    final queue = ref.read(playbackQueueProvider).value;
    _current = _currentEntry(queue);
    if (widget.scrollController != null) {
      // 面板的控制器要等清單接上之後才能捲。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrent(animate: false);
      });
    }
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  QueueEntry? _currentEntry(QueueState? queue) => switch (queue?.currentIndex) {
    final index? => queue!.entries[index],
    null => null,
  };

  double _currentOffset() {
    final queue = ref.read(playbackQueueProvider).value;
    // 臨時播放中 `currentIndex` 是回到佇列時的位置，不是在播的那首，開啟時照樣從它附近開始。
    final current = queue?.currentIndex;
    final row = current == null ? 0 : math.max(0, current - _rowsAbove);
    return row * AppLayout.queueItemHeight;
  }

  void _scrollToCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    final target = math.min(_currentOffset(), _scroll.position.maxScrollExtent);
    if (animate) {
      unawaited(
        _scroll.animateTo(
          target,
          duration: AppLayout.queueScrollDuration,
          curve: Curves.easeOut,
        ),
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _onQueue(QueueState? queue) {
    final entry = _currentEntry(queue);
    if (identical(entry, _current)) return;
    _current = entry;
    final autoScroll =
        ref.read(playbackPreferencesProvider).value?.autoScrollToCurrent ??
        false;
    if (entry != null && autoScroll && !_dragging) {
      // 清單這一幀還沒換成新的佇列，等它排好再量。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dragging) _scrollToCurrent(animate: true);
      });
    }
  }

  Future<void> _clear() async {
    final t = ref.read(translationsProvider).playerPage;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.queueClearTitle),
        content: Text(t.queueClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.queueCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.queueClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // 清空之後播放頁與面板會關掉，這個 widget 也跟著 dispose：先把要用的拿好。
    final controller = ref.read(playbackControllerProvider);
    final toaster = ref.read(toasterProvider);
    unawaited(controller.clear());
    // 提示的位移在顯示的當下決定：播放頁還開著時是底部安全區，頁面接著關掉，提示就蓋在
    // compact 的導覽列上。等這一幀（頁面與面板關掉、外殼發佈自己的高度）之後再提示。
    await WidgetsBinding.instance.endOfFrame;
    toaster.success(t.queueCleared);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackQueueProvider, (_, next) => _onQueue(next.value));
    final queue = ref.watch(playbackQueueProvider).value;
    if (queue == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final entries = queue.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.x4,
            end: spacing.x2,
            top: spacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.queueCount(count: entries.length),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: QueueView.clearKey,
                tooltip: t.queueClear,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: entries.isEmpty ? null : () => unawaited(_clear()),
              ),
            ],
          ),
        ),
        if (queue.shuffleEnabled)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.x4,
              end: spacing.x4,
              bottom: spacing.x2,
            ),
            child: Text(
              t.queueShuffleNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: Listener(
            onPointerDown: (_) => _pointers++,
            onPointerUp: (_) => _releasePointer(),
            onPointerCancel: (_) => _releasePointer(),
            child: ReorderableListView.builder(
              scrollController: _scroll,
              buildDefaultDragHandles: false,
              itemExtent: AppLayout.queueItemHeight,
              itemCount: entries.length,
              onReorderStart: (_) => _dragging = true,
              onReorderEnd: (_) => _dragging = false,
              // `onReorderItem` 的 `newIndex` 已扣掉被拿起來的那一格（舊的 `onReorder` 往下拖
              // 時要自己減 1），就是 `move` 的目標位置。
              onReorderItem: (oldIndex, newIndex) =>
                  ref.read(playbackControllerProvider).move(oldIndex, newIndex),
              itemBuilder: (context, index) => _QueueRow(
                // 項目沿用實例，同一首出現兩次也各有各的鍵。
                key: ObjectKey(entries[index]),
                index: index,
                entry: entries[index],
                // 臨時播放中 `currentIndex` 是回到佇列時的位置，不是在播的那首。
                selected:
                    queue.temporary == null && index == queue.currentIndex,
                isQueueCurrent: index == queue.currentIndex,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    super.key,
    required this.index,
    required this.entry,
    required this.selected,
    required this.isQueueCurrent,
  });

  final int index;
  final QueueEntry entry;
  final bool selected;

  /// 佇列的 `currentIndex` 指的就是這一列：「下一首播放」對它沒有意義。
  final bool isQueueCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final tokens = AppTokens.of(context);
    final track = entry.track;
    final uploader = track.uploader;
    final duration = track.duration;
    return TrackRowMenu(
      moreTooltip: t.queueMore,
      menuChildren: [
        if (!isQueueCurrent)
          MenuItemButton(
            leadingIcon: const Icon(Icons.queue_play_next),
            onPressed: () =>
                ref.read(playbackControllerProvider).moveToNext(index),
            child: Text(t.queuePlayNext),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.remove_circle_outline),
          onPressed: () =>
              unawaited(ref.read(playbackControllerProvider).removeAt(index)),
          child: Text(t.queueRemove),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        dense: true,
        selected: selected,
        leading: ArtworkImage(
          pluginId: track.sourceTypeId,
          artwork: track.artwork,
          size: AppLayout.artworkThumbnail,
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: uploader == null
            ? null
            : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (duration != null) Text(formatDuration(duration)),
            more,
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Tooltip(
                  message: t.queueReorder,
                  triggerMode: TooltipTriggerMode.manual,
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.x3),
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          ],
        ),
        onTap: () =>
            unawaited(ref.read(playbackControllerProvider).jumpTo(index)),
        onLongPress: openMenu,
      ),
    );
  }
}

/// 底部面板（compact、medium）：`showModalBottomSheet` 加可拖動高度的
/// `DraggableScrollableSheet`，內容是 [QueueView]。是自己的 route：返回鍵與 Esc 只關
/// 面板；播放快捷鍵和播放頁一樣有效（[PlaybackShortcuts]）；佇列變空時（播放頁也會關）
/// 自己關掉，不留一個蓋在外殼上的面板。
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => const _QueueSheet(),
);

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      playbackQueueProvider.select((queue) => queue.value?.current != null),
      (_, hasTrack) {
        if (hasTrack) return;
        // 面板上可能還有對話框（清空的確認）：移除自己的 route，不是 pop 最上面的。
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          route.navigator?.removeRoute(route);
        }
      },
    );
    // 面板是自己的 route，不在播放頁的 `PlaybackShortcuts` 之下：再包一層，播放鍵才和寬版的
    // 佇列分頁一樣有效（焦點在某一列時空白鍵也是播放暫停，Enter 才跳到那首）。Ctrl+L、Ctrl+Q
    // 在這裡沒有 action，按了不做事。
    return PlaybackShortcuts(
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => unawaited(Navigator.of(context).maybePop()),
            ),
          },
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: AppLayout.queueSheetInitialSize,
              minChildSize: AppLayout.queueSheetMinSize,
              builder: (context, controller) =>
                  QueueView(scrollController: controller),
            ),
          ),
        ),
      ),
    );
  }
}
