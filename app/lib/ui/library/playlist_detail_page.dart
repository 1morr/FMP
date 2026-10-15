import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

/// 在 [context] 所在的 Navigator 開歌單詳情：外殼裡是那個目的地的巢狀導覽（音樂庫的歌單卡，
/// ADR 0033 §決定 5），導覽與播放列留著。
Future<void> openPlaylist(BuildContext context, int playlistId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(playlistId: playlistId),
      ),
    );

/// 歌單詳情（ADR 0033 §決定 9，M4 design §10.4）。
///
/// - 標題列：返回鈕（下面還有頁時）與歌單名稱。
/// - 標頭：封面（自訂或第一首的）、「本機 · n 首」、描述；下面是「全部加入佇列」（只加入，
///   ADR 0018 的 D2）與「隨機加入佇列」，同音樂庫卡片選單的那兩項（`PlaylistService.addToQueue`：
///   超過佇列上限整批拒絕、提示由外殼接 `QueueFull`；空歌單與 Mix 中停用）。匯入歌單的擁有者
///   與狀態列在 PR 8b。
/// - 曲目依歌單順序；同一支影片連續兩個以上的分 P 收在影片標題下（[groupParts]）。點一首是
///   臨時播放；選單（右鍵、長按、「⋯」）有播放、下一首播放、加入佇列、開始 Mix、加入歌單…，
///   本機歌單另有「從歌單移除」（只刪那一筆、不確認，同佇列與歷史的單筆移除）。
/// - 只有本機歌單能拖把手重排（放下後整批寫 `position`，資料庫追上之前照拖曳後的順序畫，
///   寫入失敗回到資料庫的順序並提示）；匯入歌單沒有把手也沒有移除（ADR 0019 §決定 4）。
///
/// 全部是本機資料，離線照常顯示；封面讀不到是佔位圖。
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  /// 拖曳後還沒從資料庫回來的順序（項目 id）；回來之前照它畫，清單才不會跳回去。
  List<int>? _pendingOrder;

  /// 畫面上的順序：拖曳後的順序在資料庫追上之前優先；項目在這期間增減了就以資料庫為準。
  List<PlaylistEntry> _shown(List<PlaylistEntry> entries) {
    final pending = _pendingOrder;
    if (pending == null) return entries;
    final ids = [for (final entry in entries) entry.id];
    if (listEquals(ids, pending) || !setEquals(ids.toSet(), pending.toSet())) {
      _pendingOrder = null;
      return entries;
    }
    final byId = {for (final entry in entries) entry.id: entry};
    return [for (final id in pending) byId[id]!];
  }

  void _reorder(List<int> ids) {
    setState(() => _pendingOrder = ids);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).playlist;
    unawaited(
      ref
          .read(playlistServiceProvider)
          .moveEntries(widget.playlistId, ids)
          .catchError((Object error, StackTrace stackTrace) {
            if (mounted) setState(() => _pendingOrder = null);
            toaster.error(
              AppError.wrap(error, stackTrace),
              operation: 'Failed to reorder the songs of a playlist',
              tag: 'library',
              sentence: (reason) => t.reorderFailed(reason: reason),
            );
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = playlistDetailProvider(widget.playlistId);
    // 讀資料庫失敗：報一次（畫面是錯誤狀態，不是空歌單）。
    ref.listen(provider, (previous, next) {
      if (next case AsyncError(:final error, :final stackTrace)
          when previous is! AsyncError) {
        ref
            .read(logProvider)
            .report(
              'Failed to read a playlist',
              AppError.wrap(error, stackTrace),
              tag: 'library',
            );
      }
    });
    final translations = ref.watch(translationsProvider);
    final t = translations.playlist;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final detail = ref.watch(provider);
    // 下面還有頁（巢狀導覽裡的內頁）時才有返回鈕，同 AppBar 的判斷。
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.x4,
            spacing.x4,
            spacing.x4,
            spacing.x2,
          ),
          child: Row(
            children: [
              if (canGoBack)
                IconButton(
                  tooltip: translations.shell.backTooltip,
                  icon: const BackButtonIcon(),
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    detail.value?.playlist.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (detail) {
            AsyncData(value: null) => EmptyState(
              icon: Icons.playlist_remove,
              title: t.notFound,
            ),
            AsyncData(value: final detail?) => _body(detail),
            // 讀失敗（已在上面報過）：不是空歌單。
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

  Widget _body(PlaylistDetail detail) {
    final t = ref.watch(translationsProvider).playlist;
    final spacing = AppTokens.of(context).spacing;
    final playlist = detail.playlist;
    final local = playlist.kind == PlaylistKind.local;
    final header = _Header(detail: detail);
    final entries = _shown(detail.entries);
    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: EmptyState(
              icon: Icons.queue_music,
              title: t.empty,
              body: local ? t.emptyHint : null,
            ),
          ),
        ],
      );
    }
    final rows = groupParts(entries);
    Widget row(int index) => switch (rows[index]) {
      PlaylistGroupRow(:final parts) => _GroupHeader(
        key: ValueKey('group-${parts.first.id}'),
        track: parts.first.track,
      ),
      PlaylistEntryRow(:final entry, :final inGroup) => _EntryRow(
        key: ValueKey('entry-${entry.id}'),
        playlistId: playlist.id,
        entry: entry,
        inGroup: inGroup,
        // 匯入歌單不能重排、不能移除（ADR 0019 §決定 4）。
        dragIndex: local ? index : null,
        removable: local,
      ),
    };
    final padding = EdgeInsets.only(bottom: spacing.x4);
    if (!local) {
      return ListView.builder(
        padding: padding,
        itemCount: rows.length + 1,
        itemBuilder: (context, index) => index == 0 ? header : row(index - 1),
      );
    }
    return ReorderableListView.builder(
      header: header,
      padding: padding,
      // 只有把手能拖（同佇列）：長按留給選單；群組標題沒有把手。
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      // `onReorderItem` 的 `newIndex` 已扣掉被拿起來的那一格（同佇列、音樂庫）。
      onReorderItem: (from, to) => _reorder(reorderedEntryIds(rows, from, to)),
      itemBuilder: (context, index) => row(index),
    );
  }
}

/// 標頭：封面、「本機 · n 首」、描述，與「全部加入佇列」「隨機加入佇列」。封面在左、資訊在右
/// （Spotify、YouTube Music 的歌單頁），按鈕在下面一整列，窄的時候換行。
class _Header extends ConsumerWidget {
  const _Header({required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final inMix = ref.watch(inMixProvider);
    final playlist = detail.playlist;
    final description = playlist.description;
    final kind = switch (playlist.kind) {
      PlaylistKind.local => t.local,
      PlaylistKind.imported => t.imported,
      PlaylistKind.mix => t.mix,
    };
    // 空歌單沒有東西可加；Mix 中佇列不收（同音樂庫卡片選單）。
    final canAdd = !inMix && detail.entries.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.x4,
        spacing.x2,
        spacing.x4,
        spacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaylistCover(
                artwork: playlist.artwork,
                firstTrack: detail.entries.firstOrNull?.track,
                size: AppLayout.playlistHeaderCover,
              ),
              SizedBox(width: spacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$kind · ${trackCountText(t, detail.entries.length)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (description != null) ...[
                      SizedBox(height: spacing.x2),
                      Text(
                        description,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.x4),
          Wrap(
            spacing: spacing.x2,
            runSpacing: spacing.x2,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.playlist_play),
                onPressed: canAdd ? () => unawaited(_add(ref)) : null,
                label: Text(inMix ? t.addToQueueInMix : t.addToQueue),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.shuffle),
                onPressed: canAdd
                    ? () => unawaited(_add(ref, shuffle: true))
                    : null,
                label: Text(inMix ? t.shuffleToQueueInMix : t.shuffleToQueue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 超過佇列上限時控制器整批拒絕、發 `QueueFull`，提示由外殼跳（ADR 0018 §決定 4）。
  Future<void> _add(WidgetRef ref, {bool shuffle = false}) async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final playlist = detail.playlist;
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

/// 同一支影片連續分 P 上面的標題：封面、影片標題、上傳者（音源停用或未安裝時是原因）。
/// 只是標題，不能點；底下的分 P 各自是一首。
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({super.key, required this.track});

  /// 群組的第一個分 P。
  final TrackInfo track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploader =
        ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
        track.uploader;
    return MergeSemantics(
      child: Semantics(
        header: true,
        child: ListTile(
          leading: ArtworkImage(
            pluginId: track.sourceTypeId,
            artwork: track.artwork,
            size: AppLayout.artworkThumbnail,
          ),
          title: Text(
            track.parentTitle ?? track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: uploader == null
              ? null
              : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// 一首：群組外是封面、`displayTitle`、上傳者（音源不可用時是原因）；群組裡的分 P 縮排、只寫
/// 分 P 的標籤（同搜尋結果展開的分 P）。尾端是時長、「⋯」，本機歌單另有拖曳把手。
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    super.key,
    required this.playlistId,
    required this.entry,
    required this.inGroup,
    required this.dragIndex,
    required this.removable,
  });

  final int playlistId;
  final PlaylistEntry entry;
  final bool inGroup;

  /// 拖曳把手對應的清單位置；`null` 是不能重排（沒有把手）。
  final int? dragIndex;

  /// 選單有「從歌單移除」。
  final bool removable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playlist;
    final spacing = AppTokens.of(context).spacing;
    final track = entry.track;
    final duration = track.duration;
    final inMix = ref.watch(inMixProvider);
    final canMix = ref.watch(canStartMixProvider(track.sourceTypeId));
    // 音源停用或移除時，上傳者的位置改說原因（ADR 0030 §決定 7、10）；群組裡的分 P 由標題說。
    final uploader = inGroup
        ? null
        : ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
              track.uploader;
    final dragIndex = this.dragIndex;

    void play() =>
        unawaited(ref.read(playbackControllerProvider).playTemporary(track));

    void playNext() {
      if (ref.read(playbackControllerProvider).playNext([track])) {
        ref.read(toasterProvider).success(t.addedToNext);
      }
    }

    void addToQueue() {
      if (ref.read(playbackControllerProvider).addToQueue([track])) {
        ref.read(toasterProvider).success(t.addedToQueue);
      }
    }

    // 只刪這一筆，不確認、不提示（同佇列與歷史的單筆移除）；失敗才提示。
    Future<void> remove() async {
      final service = ref.read(playlistServiceProvider);
      final toaster = ref.read(toasterProvider);
      try {
        await service.removeEntries(playlistId, [entry.id]);
      } on Object catch (error, stackTrace) {
        toaster.error(
          AppError.wrap(error, stackTrace),
          operation: 'Failed to remove a song from a playlist',
          tag: 'library',
          sentence: (reason) => t.removeFailed(reason: reason),
        );
      }
    }

    return TrackRowMenu(
      moreTooltip: t.more,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow),
          onPressed: play,
          child: Text(t.play),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.queue_play_next),
          onPressed: inMix ? null : playNext,
          child: Text(inMix ? t.playNextInMix : t.playNext),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_to_queue),
          onPressed: inMix ? null : addToQueue,
          child: Text(inMix ? t.addToQueueInMix : t.addToQueue),
        ),
        if (canMix)
          MenuItemButton(
            leadingIcon: const Icon(Icons.auto_awesome),
            onPressed: () => unawaited(startMixFrom(ref, track)),
            child: Text(t.startMix),
          ),
        AddToPlaylistItem(
          onPressed: () => unawaited(showAddToPlaylist(context, [track])),
        ),
        if (removable)
          MenuItemButton(
            leadingIcon: const Icon(Icons.remove_circle_outline),
            onPressed: () => unawaited(remove()),
            child: Text(t.remove),
          ),
      ],
      builder: (context, more, openMenu) => ListTile(
        dense: inGroup,
        contentPadding: inGroup
            ? EdgeInsetsDirectional.only(
                start: AppLayout.artworkThumbnail + spacing.x8,
                end: spacing.x4,
              )
            : null,
        leading: inGroup
            ? null
            : ArtworkImage(
                pluginId: track.sourceTypeId,
                artwork: track.artwork,
                size: AppLayout.artworkThumbnail,
              ),
        title: Text(
          inGroup ? track.partLabel : track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: uploader == null
            ? null
            : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (duration != null) Text(formatDuration(duration)),
            more,
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: const _DragHandle(),
              ),
          ],
        ),
        onTap: play,
        onLongPress: openMenu,
      ),
    );
  }
}

/// 拖曳把手（同佇列、音樂庫）：tooltip 當語意名稱，不能點，只有拖曳。
class _DragHandle extends ConsumerWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: Tooltip(
      message: ref.watch(translationsProvider).playlist.reorder,
      triggerMode: TooltipTriggerMode.manual,
      child: Padding(
        padding: EdgeInsets.all(AppTokens.of(context).spacing.x3),
        child: const Icon(Icons.drag_handle),
      ),
    ),
  );
}
