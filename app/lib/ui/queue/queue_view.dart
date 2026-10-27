import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/dialogs/destructive_confirm.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_markers.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 可編輯的佇列清單（M2 PR 18b，design §7.3；ADR 0035 §決定 2、8 與 design §5 照舊版佇列頁）。
/// 佇列目的地（[QueuePage]）的內容，各寬度都是整頁。
///
/// - 頂部：左邊跳到頂／底（依捲動位置切換方向）、中間標題（Mix 時「Mix：標題」）、右邊
///   「打亂」（Mix 與直播時停用）與「清空」（確認後清空）；下面是「正在播放第 n 首」橫幅
///   （點了捲到目前這首）；隨機開著時多一行說明（ADR 0018 §後果：拖曳只換歌，不改隨機順序）。
/// - 每列：封面（目前這首疊 [NowPlayingOverlay]）、曲名、上傳者、時長、「×」移除、「⋯」選單與
///   拖曳把手；目前這首的曲名是主色粗體（臨時播放中不標：`currentIndex` 是回到佇列時的位置）。
///   點一下 `jumpTo`；只有把手能拖（長按留給選單），放下呼叫 `move`。
/// - Mix 補歌時列尾有轉圈。
/// - 固定列高的 `ReorderableListView.builder`，一萬首也只建看得到的；開啟時從目前這首的
///   前兩列開始；「切歌時捲到目前歌曲」開著時，目前這首換了（`currentIndex` 指的項目
///   換了，拖曳讓它換位置不算）就再捲一次，使用者正在拖曳時不捲。
class QueueView extends ConsumerStatefulWidget {
  const QueueView({super.key});

  /// 「清空佇列」鈕；測試以它找。
  static const clearKey = ValueKey('queue-clear');

  /// 頂部的標題；Mix 時是「Mix：標題」並用 [mixNoteKey]。測試以它們找。
  static const titleKey = ValueKey('queue-title');
  static const mixNoteKey = ValueKey('queue-mix-note');

  /// 「打亂」鈕、跳到頂／底鈕與「正在播放」橫幅；測試以它們找。
  static const shuffleKey = ValueKey('queue-shuffle');
  static const jumpKey = ValueKey('queue-jump');
  static const bannerKey = ValueKey('queue-banner');

  /// Mix 補歌時的列尾轉圈。
  static const footerSpinnerKey = ValueKey('queue-footer-spinner');

  @override
  ConsumerState<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends ConsumerState<QueueView> {
  /// 目前這首之前先露出的幾列，讓前一首看得到。
  static const _rowsAbove = 2;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _currentOffset(),
  );

  /// 上一次看到的「目前這首」（佇列項目本身，編輯時沿用實例）。
  QueueEntry? _current;
  var _dragging = false;

  /// 捲動位置離頂端不遠：跳轉鈕往底，否則往頂。
  var _nearTop = true;

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
    _nearTop = _currentOffset() < AppLayout.queueNearTop;
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final nearTop = _scroll.offset < AppLayout.queueNearTop;
    if (nearTop != _nearTop) setState(() => _nearTop = nearTop);
  }

  void _jumpToEnd() {
    if (!_scroll.hasClients) return;
    final target = _nearTop ? _scroll.position.maxScrollExtent : 0.0;
    unawaited(
      _scroll.animateTo(
        target,
        duration: AppLayout.queueScrollDuration,
        curve: Curves.easeOut,
      ),
    );
  }

  void _shuffle() {
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).playerPage;
    if (!ref.read(playbackControllerProvider).shuffleQueue()) return;
    toaster.success(t.queueShuffled);
    // 目前這首移到第一位了：回到清單頂端。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrent(animate: false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
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
    final confirmed = await showDestructiveConfirm(
      context,
      title: t.queueClearTitle,
      body: t.queueClearBody,
      confirmLabel: t.queueClearConfirm,
      cancelLabel: t.queueCancel,
    );
    if (!confirmed || !mounted) return;
    // 清空之後佇列頁換成空狀態，這個 widget 也跟著 dispose：先把要用的拿好。
    final toaster = ref.read(toasterProvider);
    unawaited(ref.read(playbackControllerProvider).clear());
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
    final refilling = ref.watch(playbackMixRefillingProvider).value ?? false;
    final entries = queue.entries;
    final current = queue.isOutsideQueue ? null : queue.currentIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QueueHeader(
          nearTop: _nearTop,
          onJump: _jumpToEnd,
          title: switch (queue.mix) {
            final mix? => t.queueMixNote(title: mix.title),
            null => t.queueTitle,
          },
          titleKey: queue.mix == null
              ? QueueView.titleKey
              : QueueView.mixNoteKey,
          onShuffle:
              queue.mix != null || queue.live != null || entries.length < 2
              ? null
              : _shuffle,
          onClear: entries.isEmpty ? null : () => unawaited(_clear()),
        ),
        if (current != null)
          _NowPlayingBanner(
            index: current,
            total: entries.length,
            onTap: () => _scrollToCurrent(animate: true),
          ),
        if (queue.shuffleEnabled)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.x4,
              end: spacing.x4,
              top: spacing.x2,
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
              footer: queue.mix == null
                  ? null
                  : SizedBox(
                      height: AppLayout.queueFooterHeight,
                      child: refilling
                          ? Center(
                              child: SizedBox.square(
                                key: QueueView.footerSpinnerKey,
                                dimension: AppLayout.queueFooterSpinner,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: t.queueMixLoading,
                                ),
                              ),
                            )
                          : null,
                    ),
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
                // 臨時播放與直播中 `currentIndex` 是回到佇列時的位置，不是在播的那首。
                selected: !queue.isOutsideQueue && index == queue.currentIndex,
                isQueueCurrent: index == queue.currentIndex,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 頂部一列（舊版的 AppBar）：左邊跳到頂／底、中間標題、右邊打亂與清空。
class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({
    required this.nearTop,
    required this.onJump,
    required this.title,
    required this.titleKey,
    required this.onShuffle,
    required this.onClear,
  });

  final bool nearTop;
  final VoidCallback onJump;
  final String title;
  final Key titleKey;
  final VoidCallback? onShuffle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    return PageAppBar(
      leading: IconButton(
        key: QueueView.jumpKey,
        tooltip: nearTop ? t.queueJumpBottom : t.queueJumpTop,
        icon: Icon(
          nearTop ? Icons.vertical_align_bottom : Icons.vertical_align_top,
        ),
        onPressed: onJump,
      ),
      titleWidget: Text(
        title,
        key: titleKey,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          key: QueueView.shuffleKey,
          tooltip: t.queueShuffle,
          icon: const Icon(Icons.shuffle),
          onPressed: onShuffle,
        ),
        IconButton(
          key: QueueView.clearKey,
          tooltip: t.queueClear,
          icon: const Icon(Icons.delete_outline),
          onPressed: onClear,
        ),
      ],
    );
  }
}

/// 「正在播放第 n 首」與「共 m 首」；點了捲到目前這首。
class _NowPlayingBanner extends ConsumerWidget {
  const _NowPlayingBanner({
    required this.index,
    required this.total,
    required this.onTap,
  });

  final int index;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final style = theme.textTheme.bodySmall?.copyWith(color: scheme.primary);
    return Material(
      color: scheme.primaryContainer.withValues(alpha: AppLayout.queueBanner),
      child: Semantics(
        button: true,
        child: InkWell(
          key: QueueView.bannerKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppLayout.queueBannerHeight,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.x4),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_filled,
                    size: 16,
                    color: scheme.primary,
                  ),
                  SizedBox(width: spacing.x2),
                  Expanded(
                    child: Text(
                      t.queuePlayingAt(index: index + 1),
                      style: style,
                    ),
                  ),
                  Text(
                    t.queueCount(count: total),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    // 音源停用或移除時，副標題改說原因（ADR 0030 §決定 7、10）。
    final uploader =
        ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
        track.uploader;
    final duration = track.duration;
    final canMix = ref.watch(canStartMixProvider(track.sourceTypeId));
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
        if (canMix)
          MenuItemButton(
            leadingIcon: const Icon(Icons.auto_awesome),
            onPressed: () => unawaited(startMixFrom(ref, track)),
            child: Text(t.queueStartMix),
          ),
        // 不動佇列：Mix 中照常（M3 的禁止規則只擋加入佇列與下一首播放）。
        AddToPlaylistItem(
          onPressed: () => unawaited(showAddToPlaylist(context, [track])),
        ),
        AddToRemoteItem(
          pluginIds: {track.sourceTypeId},
          onPressed: () => unawaited(showAddToRemote(context, [track])),
        ),
        DestructiveMenuItem(
          icon: Icons.remove_circle_outline,
          onPressed: () =>
              unawaited(ref.read(playbackControllerProvider).removeAt(index)),
          child: Text(t.queueRemove),
        ),
      ],
      builder: (context, more, openMenu) => ListTile(
        dense: true,
        selected: selected,
        leading: Stack(
          children: [
            ArtworkImage(
              pluginId: track.sourceTypeId,
              artwork: track.artwork,
              size: AppLayout.artworkThumbnail,
            ),
            if (selected)
              const NowPlayingOverlay(size: AppLayout.artworkThumbnail),
          ],
        ),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
        subtitle: uploader == null
            ? null
            : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackDuration(duration: duration),
            // 一下就移除，不確認（同選單裡的「從佇列移除」）。
            // 名稱帶曲名：每列都有一顆，讀屏逐顆讀時才分得出是哪一首。
            IconButton(
              tooltip: t.queueRemoveTrack(title: track.displayTitle),
              icon: const Icon(Icons.close),
              onPressed: () => unawaited(
                ref.read(playbackControllerProvider).removeAt(index),
              ),
            ),
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
