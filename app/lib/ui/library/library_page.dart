import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/library/import_dialog.dart';
import 'package:fmp/ui/library/import_preview_page.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/manual_refresh.dart';
import 'package:fmp/ui/library/playlist_actions.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/library/playlist_dialogs.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 音樂庫（ADR 0033 §決定 8，M4 design §10.3）。
///
/// - 標題列：「新增歌單」與「匯入」（網址匯入對話框，成功後在巢狀導覽裡開詳情）。
/// - 頂端「歷史」一列：在音樂庫的巢狀導覽裡開歷史頁（YouTube Music 把歷史放在音樂庫）。
/// - 歌單卡：封面（自訂封面，沒有就是第一首的封面）、名稱、「本機 · n 首」；點一下在音樂庫的
///   巢狀導覽裡開歌單詳情。內容區是 compact、medium 時是清單，
///   expanded 以上是格狀（M3 的 list／grid 依寬度切換）。拖曳把手排序（同電台頁：只有把手能拖，
///   長按留給選單），放下後整批寫 `sort_order`；資料庫追上之前照拖曳後的順序畫。螢幕閱讀器
///   以語意動作移動（清單是 `ReorderableListView` 自帶的，格狀的卡片給同樣的四個）。
/// - 卡片選單（右鍵、長按、「⋯」）：全部加入佇列、隨機加入佇列、編輯、刪除（先確認）。
///   Mix 歌單只有 Mix 播放、編輯、刪除。
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
      await service.create(
        name: input.name,
        description: input.description,
        artwork: input.artwork,
      );
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

  Future<void> _import() async {
    // 對話框期間外殼可能重建這一頁：要用的先讀好。
    final t = ref.read(translationsProvider).library;
    final toaster = ref.read(toasterProvider);
    final manual = ref.read(manualRefreshProvider.notifier);
    final result = await showImportDialog(context);
    if (result == null || !mounted) return;
    if (result is CreatedMix) {
      unawaited(openPlaylist(context, result.playlistId));
      return;
    }
    // 僅元資料來源，或選了「配對到其他音源」：開匯入預覽（M4 design §10.9）。
    if (result is ImportForMatching) {
      unawaited(
        openImportPreview(
          context,
          pluginId: result.pluginId,
          playlistId: result.playlistId,
        ),
      );
      return;
    }
    if (result is! ImportedPlaylist) return;
    final imported = result;
    unawaited(openPlaylist(context, imported.playlistId));
    switch (imported.refresh) {
      case RefreshFinished(result: PlaylistRefreshResult.complete)
          when imported.created:
        toaster.success(t.importDone);
      case RefreshFinished() when imported.created:
        toaster.warning(t.importPartial);
      // 重新匯入同一張＝刷新那一列：結果照手動刷新提示。
      case final outcome:
        await manual.report(outcome, imported.playlistId);
    }
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
        PageAppBar(
          title: t.title,
          actions: [
            IconButton(
              tooltip: t.importTooltip,
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => unawaited(_import()),
            ),
            IconButton(
              tooltip: t.newPlaylist,
              icon: const Icon(Icons.add),
              onPressed: () => unawaited(_create()),
            ),
          ],
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
                    action: Wrap(
                      spacing: spacing.x2,
                      runSpacing: spacing.x2,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => unawaited(_create()),
                          child: Text(t.newPlaylist),
                        ),
                        OutlinedButton(
                          onPressed: () => unawaited(_import()),
                          child: Text(t.importAction),
                        ),
                      ],
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
          leading: PlaylistCover(
            artwork: overview.playlist.artwork,
            firstTrack: overview.firstTrack,
            size: AppLayout.artworkThumbnail,
          ),
          title: Text(
            overview.playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _PlaylistSubtitle(overview: overview),
          onTap: () => unawaited(openPlaylist(context, overview.playlist.id)),
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

  /// 螢幕閱讀器的「移到最前面／向左移／向右移／移到最後面」（清單版的 `ReorderableListView`
  /// 自帶同樣的語意動作）：把 [id] 移到第 [to] 張，整批寫入。
  void _move(int id, int to) {
    final ids = _ids..remove(id);
    widget.onReorder(ids..insert(to, id));
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
                    for (final (index, overview) in shown.indexed)
                      _GridCard(
                        key: ValueKey(overview.playlist.id),
                        overview: overview,
                        width: width,
                        dragging: overview.playlist.id == _dragging,
                        onDragStart: () => _start(overview.playlist.id),
                        onDragOver: () => _over(overview.playlist.id),
                        onDragEnd: _end,
                        // 拖曳中不給（順序還沒定）。
                        onMove: _order != null
                            ? null
                            : (to) => _move(overview.playlist.id, to),
                        index: index,
                        count: shown.length,
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
    required this.onMove,
    required this.index,
    required this.count,
  });

  final PlaylistOverview overview;
  final double width;

  /// 移到第幾張（螢幕閱讀器的語意動作）；`null` 時不給動作。
  final ValueChanged<int>? onMove;

  /// 這張在第幾、一共幾張：決定給哪幾個「移到…」。
  final int index;
  final int count;

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
    // 拖曳只有指標能做：螢幕閱讀器改用語意動作移動（同清單版 `ReorderableListView` 的那四個，
    // 字串是 Flutter 內建的翻譯；格狀由左而右排，所以是左右而不是上下）。
    final move = widget.onMove;
    final index = widget.index;
    final words = WidgetsLocalizations.of(context);
    final moves = move == null
        ? null
        : <CustomSemanticsAction, VoidCallback>{
            if (index > 0) ...{
              CustomSemanticsAction(label: words.reorderItemToStart): () =>
                  move(0),
              CustomSemanticsAction(label: words.reorderItemLeft): () =>
                  move(index - 1),
            },
            if (index < widget.count - 1) ...{
              CustomSemanticsAction(label: words.reorderItemRight): () =>
                  move(index + 1),
              CustomSemanticsAction(label: words.reorderItemToEnd): () =>
                  move(widget.count - 1),
            },
          };
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
        // 同 ListTile：點一下開詳情、長按開選單；卡片是一個按鈕的語意節點，「⋯」與把手各自一個。
        builder: (context, more, openMenu) => Opacity(
          opacity: widget.dragging ? AppLayout.draggedOpacity : 1,
          child: SizedBox(
            key: _cardKey,
            width: widget.width,
            child: InkWell(
              borderRadius: BorderRadius.circular(tokens.radius.small),
              onTap: () => unawaited(openPlaylist(context, id)),
              onLongPress: openMenu,
              child: Semantics(
                button: true,
                customSemanticsActions: moves,
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
          builder: (context, constraints) => PlaylistCover(
            artwork: overview.playlist.artwork,
            firstTrack: overview.firstTrack,
            size: constraints.maxWidth,
          ),
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

/// 「本機 · n 首」（匯入歌單是「匯入 · n 首」）。
class _PlaylistSubtitle extends ConsumerWidget {
  const _PlaylistSubtitle({required this.overview});

  final PlaylistOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final progress = ref.watch(
      manualRefreshProvider.select((all) => all[overview.playlist.id]),
    );
    final text = Text(
      playlistSubtitleText(t, overview),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (progress == null) return text;
    // 刷新中：副標題前面一個轉圈，後面是「已更新 n 首」（卡片上的進度，ADR 0035 §決定 11）。
    return Row(
      children: [
        const SizedBox.square(
          dimension: AppLayout.buttonSpinner,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: AppTokens.of(context).spacing.x2),
        Expanded(
          child: Text(
            refreshProgressText(t, progress),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 一張歌單的選單（右鍵、長按、「⋯」）：全部加入佇列、隨機加入佇列、編輯、刪除；匯入歌單另有
/// 刷新，Mix 歌單只有 Mix 播放、編輯、刪除。
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
    final imported = playlist.kind == PlaylistKind.imported;
    final mix = playlist.kind == PlaylistKind.mix;
    // Mix 歌單的音源停用、移除或沒宣告 `mix` 時，「Mix 播放」停用並寫原因。
    final mixReason = mix
        ? ref.watch(mixUnavailableReasonProvider(playlist.mixPluginId ?? ''))
        : null;
    final refreshing = ref.watch(
      manualRefreshProvider.select((ids) => ids.containsKey(playlist.id)),
    );
    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        if (mix)
          MenuItemButton(
            leadingIcon: const Icon(Icons.auto_awesome),
            // 用卡片的 `ref`：選單項目在選取後就卸載，播放的提示要在那之後才出現。
            onPressed: mixReason == null
                ? () => unawaited(startMixFromPlaylist(ref, playlist))
                : null,
            child: Text(
              mixReason == null
                  ? t.mixPlay
                  : t.mixPlayDisabled(reason: mixReason),
            ),
          )
        else ...[
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
          if (imported)
            MenuItemButton(
              leadingIcon: const Icon(Icons.refresh),
              onPressed: refreshing
                  ? null
                  : () => unawaited(
                      ref.read(manualRefreshProvider.notifier)(playlist.id),
                    ),
              child: Text(refreshing ? t.refreshing : t.refresh),
            ),
        ],
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => unawaited(editPlaylist(context, ref, overview)),
          child: Text(t.edit),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(deletePlaylist(context, ref, playlist)),
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
}
