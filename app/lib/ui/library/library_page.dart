import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/library/playlist_dialogs.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 音樂庫的歌單卡（依 `sort_order`），本機資料，離線照常顯示。歌單或項目一變動就重讀
/// （先訂閱再讀，讀的期間的變動排在後面再讀一次）；讀失敗發出錯誤、之後的變動照樣重讀。
final playlistOverviewsProvider = StreamProvider<List<PlaylistOverview>>((
  ref,
) async* {
  final repository = ref.watch(playlistRepositoryProvider);
  final changed = StreamController<void>();
  final changes = repository.changes().listen(changed.add);
  ref.onDispose(() {
    unawaited(changes.cancel());
    unawaited(changed.close());
  });
  Stream<List<PlaylistOverview>> read() async* {
    try {
      yield await repository.overviews();
    } on Object catch (error, stackTrace) {
      yield* Stream.error(error, stackTrace);
    }
  }

  yield* read();
  await for (final _ in changed.stream) {
    yield* read();
  }
});

/// 音樂庫（ADR 0033 §決定 8，M4 design §10.3）。
///
/// - 標題列：「新增歌單」（「匯入」在 PR 8b）。
/// - 頂端「歷史」一列：在音樂庫的巢狀導覽裡開歷史頁（YouTube Music 把歷史放在音樂庫）。
/// - 歌單卡：封面（第一首的封面）、名稱、「本機 · n 首」。內容區是 compact、medium 時是清單，
///   expanded 以上是格狀（M3 的 list／grid 依寬度切換）。拖曳把手排序（同電台頁：只有把手能拖，
///   長按留給選單），放下後整批寫 `sort_order`；資料庫追上之前照拖曳後的順序畫。
/// - 卡片選單（右鍵、長按、「⋯」）：全部加入佇列、隨機加入佇列、編輯、刪除（先確認）。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// 拖曳後還沒從資料庫回來的順序（歌單 id）；回來之前照它畫，清單才不會跳回去。
  List<int>? _pendingOrder;

  Future<void> _create() async {
    // 對話框期間外殼可能重建這一頁：要用的先讀好。
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final input = await showPlaylistDialog(context);
    if (input == null) return;
    try {
      await service.create(name: input.name, description: input.description);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to create a playlist',
        tag: 'library',
        sentence: (reason) => t.createFailed(reason: reason),
      );
      return;
    }
    toaster.success(t.created);
  }

  void _reorder(List<int> ids) {
    setState(() => _pendingOrder = ids);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).library;
    unawaited(
      ref.read(playlistServiceProvider).reorder(ids).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (mounted) setState(() => _pendingOrder = null);
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to reorder the playlists',
          tag: 'library',
          sentence: (reason) => t.reorderFailed(reason: reason),
        );
      }),
    );
  }

  /// 畫面上的順序：拖曳後的順序在資料庫追上之前優先；清單在這期間增減了就以資料庫為準。
  List<PlaylistOverview> _shown(List<PlaylistOverview> overviews) {
    final pending = _pendingOrder;
    if (pending == null) return overviews;
    final ids = [for (final overview in overviews) overview.playlist.id];
    if (listEquals(ids, pending) || !setEquals(ids.toSet(), pending.toSet())) {
      _pendingOrder = null;
      return overviews;
    }
    final byId = {
      for (final overview in overviews) overview.playlist.id: overview,
    };
    return [for (final id in pending) byId[id]!];
  }

  @override
  Widget build(BuildContext context) {
    // 讀資料庫失敗：報一次（畫面是錯誤狀態，不是「還沒有歌單」）。
    ref.listen(playlistOverviewsProvider, (previous, next) {
      if (next case AsyncError(:final error, :final stackTrace)
          when previous is! AsyncError) {
        ref
            .read(logProvider)
            .report(
              'Failed to read the playlists',
              AppError.wrap(error, stackTrace),
              tag: 'library',
            );
      }
    });
    final translations = ref.watch(translationsProvider);
    final t = translations.library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final overviews = ref.watch(playlistOverviewsProvider);
    final top = [
      ListTile(
        leading: const Icon(Icons.history),
        title: Text(t.history),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(openHistory(context)),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.x4,
          spacing.x4,
          spacing.x4,
          spacing.x2,
        ),
        child: Semantics(
          header: true,
          child: Text(t.playlists, style: theme.textTheme.titleLarge),
        ),
      ),
    ];
    final wide = switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => false,
      _ => true,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.x4,
            spacing.x4,
            spacing.x2,
            spacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.title, style: theme.textTheme.headlineSmall),
                ),
              ),
              IconButton(
                tooltip: t.newPlaylist,
                icon: const Icon(Icons.add),
                onPressed: () => unawaited(_create()),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (overviews) {
            AsyncData(:final value) when value.isEmpty => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                Expanded(
                  child: EmptyState(
                    icon: Icons.queue_music,
                    title: t.empty,
                    body: t.emptyHint,
                    action: FilledButton.tonal(
                      onPressed: () => unawaited(_create()),
                      child: Text(t.newPlaylist),
                    ),
                  ),
                ),
              ],
            ),
            AsyncData(:final value) when wide => _PlaylistGrid(
              header: top,
              overviews: _shown(value),
              onReorder: _reorder,
            ),
            AsyncData(:final value) => _PlaylistList(
              header: top,
              overviews: _shown(value),
              onReorder: _reorder,
            ),
            AsyncError(:final error) => EmptyState(
              icon: Icons.error_outline,
              title: errorMessage(
                translations,
                AppError.wrap(error, StackTrace.current),
              ),
            ),
            AsyncLoading() => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// compact、medium：一列一張（同電台頁），拖曳把手排序。
class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.header,
    required this.overviews,
    required this.onReorder,
  });

  final List<Widget> header;
  final List<PlaylistOverview> overviews;
  final ValueChanged<List<int>> onReorder;

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: header,
    ),
    padding: EdgeInsets.only(bottom: AppTokens.of(context).spacing.x4),
    buildDefaultDragHandles: false,
    itemCount: overviews.length,
    // `onReorderItem` 的 `newIndex` 已扣掉被拿起來的那一格（同佇列、電台頁）。
    onReorderItem: (from, to) {
      final ids = [for (final overview in overviews) overview.playlist.id];
      ids.insert(to, ids.removeAt(from));
      onReorder(ids);
    },
    itemBuilder: (context, index) {
      final overview = overviews[index];
      return _PlaylistMenu(
        key: ValueKey(overview.playlist.id),
        overview: overview,
        builder: (context, more, openMenu) => ListTile(
          leading: _PlaylistCover(
            overview: overview,
            size: AppLayout.artworkThumbnail,
          ),
          title: Text(
            overview.playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _PlaylistSubtitle(overview: overview),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              more,
              ReorderableDragStartListener(
                index: index,
                child: const _DragHandle(),
              ),
            ],
          ),
          onLongPress: openMenu,
        ),
      );
    },
  );
}

/// expanded 以上：格狀的卡片（封面在上、名稱與「本機 · n 首」在下），每張的寬度不超過
/// [AppLayout.playlistCardMaxWidth]。Flutter 沒有內建可拖曳排序的格狀清單，所以用
/// `Draggable`（把手）與每張卡的 `DragTarget`：拖過某張卡時被拖的卡移到它的位置（畫面
/// 跟著換），放開時整批寫入。
class _PlaylistGrid extends StatefulWidget {
  const _PlaylistGrid({
    required this.header,
    required this.overviews,
    required this.onReorder,
  });

  final List<Widget> header;
  final List<PlaylistOverview> overviews;
  final ValueChanged<List<int>> onReorder;

  @override
  State<_PlaylistGrid> createState() => _PlaylistGridState();
}

class _PlaylistGridState extends State<_PlaylistGrid> {
  /// 拖曳中的歌單與拖曳中的順序（id）；沒在拖時是 `null`。
  int? _dragging;
  List<int>? _order;

  List<int> get _ids => [
    for (final overview in widget.overviews) overview.playlist.id,
  ];

  void _start(int id) => setState(() {
    _dragging = id;
    _order = _ids;
  });

  /// 拖到 [target] 上：被拖的那張移到它的位置。
  void _over(int target) {
    final order = _order;
    final dragging = _dragging;
    if (order == null || dragging == null || target == dragging) return;
    final to = order.indexOf(target);
    if (to < 0) return;
    setState(() {
      order.remove(dragging);
      order.insert(to, dragging);
    });
  }

  void _end() {
    final order = _order;
    setState(() {
      _dragging = null;
      _order = null;
    });
    if (order != null && !listEquals(order, _ids)) widget.onReorder(order);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    final byId = {
      for (final overview in widget.overviews) overview.playlist.id: overview,
    };
    // 拖曳中照拖曳的順序；清單在拖曳中變了（別處刪了一張）就照資料庫的。
    final order = _order;
    final shown = order != null && setEquals(order.toSet(), byId.keys.toSet())
        ? [for (final id in order) byId[id]!]
        : widget.overviews;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - 2 * spacing.x4;
        final columns =
            ((available + spacing.x4) /
                    (AppLayout.playlistCardMaxWidth + spacing.x4))
                .ceil();
        final width = (available - (columns - 1) * spacing.x4) / columns;
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...widget.header,
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.x4),
                child: Wrap(
                  spacing: spacing.x4,
                  runSpacing: spacing.x4,
                  children: [
                    for (final overview in shown)
                      _GridCard(
                        key: ValueKey(overview.playlist.id),
                        overview: overview,
                        width: width,
                        dragging: overview.playlist.id == _dragging,
                        onDragStart: () => _start(overview.playlist.id),
                        onDragOver: () => _over(overview.playlist.id),
                        onDragEnd: _end,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GridCard extends StatefulWidget {
  const _GridCard({
    super.key,
    required this.overview,
    required this.width,
    required this.dragging,
    required this.onDragStart,
    required this.onDragOver,
    required this.onDragEnd,
  });

  final PlaylistOverview overview;
  final double width;

  /// 這張正被拖著：原位置淡出（拖著走的是 `Draggable` 的 feedback）。
  final bool dragging;
  final VoidCallback onDragStart;

  /// 別張卡被拖到這張上面。
  final VoidCallback onDragOver;
  final VoidCallback onDragEnd;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  /// 拖著走的卡片貼在卡片原本的位置（不是把手的位置）：以它換算按下的點。
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final overview = widget.overview;
    final id = overview.playlist.id;
    final handle = Draggable<int>(
      data: id,
      dragAnchorStrategy: (draggable, context, position) {
        final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
        return box?.globalToLocal(position) ?? Offset.zero;
      },
      onDragStarted: widget.onDragStart,
      onDragEnd: (_) => widget.onDragEnd(),
      feedback: Material(
        elevation: AppLayout.dragElevation,
        borderRadius: BorderRadius.circular(tokens.radius.small),
        child: SizedBox(
          width: widget.width,
          child: _GridCardBody(
            overview: overview,
            more: const SizedBox.shrink(),
            handle: const _DragHandle(),
          ),
        ),
      ),
      child: const _DragHandle(),
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        if (details.data == id) return false;
        widget.onDragOver();
        return true;
      },
      builder: (context, _, _) => _PlaylistMenu(
        overview: overview,
        // 同 ListTile：整張卡合成一個語意節點，長按開選單。
        builder: (context, more, openMenu) => Opacity(
          opacity: widget.dragging ? AppLayout.draggedOpacity : 1,
          child: SizedBox(
            key: _cardKey,
            width: widget.width,
            child: MergeSemantics(
              child: InkWell(
                borderRadius: BorderRadius.circular(tokens.radius.small),
                onLongPress: openMenu,
                child: _GridCardBody(
                  overview: overview,
                  more: more,
                  handle: handle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridCardBody extends StatelessWidget {
  const _GridCardBody({
    required this.overview,
    required this.more,
    required this.handle,
  });

  final PlaylistOverview overview;
  final Widget more;
  final Widget handle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              _PlaylistCover(overview: overview, size: constraints.maxWidth),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(start: spacing.x1),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: _PlaylistSubtitle(overview: overview),
                    ),
                  ],
                ),
              ),
              more,
              handle,
            ],
          ),
        ),
      ],
    );
  }
}

/// 拖曳把手（同電台頁）：tooltip 當語意名稱，不能點，只有拖曳。
class _DragHandle extends ConsumerWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: Tooltip(
      message: ref.watch(translationsProvider).library.reorder,
      triggerMode: TooltipTriggerMode.manual,
      child: Padding(
        padding: EdgeInsets.all(AppTokens.of(context).spacing.x3),
        child: const Icon(Icons.drag_handle),
      ),
    ),
  );
}

/// 歌單的封面：第一首的封面；空歌單是佔位圖。自訂封面與匯入歌單的遠端封面在之後的 PR。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.overview, required this.size});

  final PlaylistOverview overview;
  final double size;

  @override
  Widget build(BuildContext context) {
    final first = overview.firstTrack;
    final scheme = Theme.of(context).colorScheme;
    return ArtworkImage(
      pluginId: first?.sourceTypeId ?? '',
      artwork: first?.artwork ?? const [],
      size: size,
      fallback: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.queue_music,
            size: size / 2,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 「本機 · n 首」。
class _PlaylistSubtitle extends ConsumerWidget {
  const _PlaylistSubtitle({required this.overview});

  final PlaylistOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    return Text(
      '${t.local} · ${trackCountText(t, overview.trackCount)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 歌單的首數（英文的 1 首是單數）。
String trackCountText(Translations$library$zh_TW t, int count) =>
    count == 1 ? t.trackCountOne : t.trackCount(count: count);

/// 一張歌單的選單（右鍵、長按、「⋯」）：全部加入佇列、隨機加入佇列、編輯、刪除。
class _PlaylistMenu extends ConsumerWidget {
  const _PlaylistMenu({
    super.key,
    required this.overview,
    required this.builder,
  });

  final PlaylistOverview overview;
  final Widget Function(
    BuildContext context,
    Widget moreButton,
    VoidCallback openMenu,
  )
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final inMix = ref.watch(inMixProvider);
    final playlist = overview.playlist;
    // 空歌單沒有東西可加；Mix 中佇列不收（同搜尋與歷史的選單）。
    final canAdd = !inMix && overview.trackCount > 0;
    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.playlist_add),
          onPressed: canAdd ? () => unawaited(_addToQueue(ref)) : null,
          child: Text(inMix ? t.addToQueueInMix : t.addToQueue),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.shuffle),
          onPressed: canAdd
              ? () => unawaited(_addToQueue(ref, shuffle: true))
              : null,
          child: Text(inMix ? t.shuffleToQueueInMix : t.shuffleToQueue),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => unawaited(_edit(context, ref)),
          child: Text(t.edit),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(_delete(context, ref, playlist)),
          child: Text(t.delete),
        ),
      ],
      builder: builder,
    );
  }

  /// 超過佇列上限時控制器整批拒絕、發 `QueueFull`，提示由外殼跳（ADR 0018 §決定 4）。
  Future<void> _addToQueue(WidgetRef ref, {bool shuffle = false}) async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final playlist = overview.playlist;
    try {
      final added = await service.addToQueue(playlist.id, shuffle: shuffle);
      if (added != null) toaster.success(t.addedToQueue(name: playlist.name));
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to add a playlist to the queue',
        tag: 'library',
        sentence: (reason) => t.addFailed(reason: reason),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final input = await showPlaylistDialog(context, editing: overview);
    if (input == null) return;
    try {
      await service.edit(
        overview.playlist,
        name: input.name,
        description: input.description,
      );
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to save a playlist',
        tag: 'library',
        sentence: (reason) => t.saveFailed(reason: reason),
      );
      return;
    }
    toaster.success(t.saved);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteTitle),
        content: Text(t.deleteBody(name: playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.delete(playlist.id);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to delete a playlist',
        tag: 'library',
        sentence: (reason) => t.deleteFailed(reason: reason),
      );
      return;
    }
    toaster.success(t.deleted);
  }
}
