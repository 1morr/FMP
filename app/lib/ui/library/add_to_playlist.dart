import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/playlist_dialogs.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 曲目選單的「加入歌單…」（M4 design §10.6）。選了就開 [showAddToPlaylist]；[onPressed]
/// 由呼叫端給，要以列本身的 `context` 開對話框（選單項目在選單關掉後就不在了）。
class AddToPlaylistItem extends ConsumerWidget {
  const AddToPlaylistItem({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MenuItemButton(
    leadingIcon: const Icon(Icons.playlist_add),
    onPressed: onPressed,
    child: Text(ref.watch(translationsProvider).library.addToPlaylist),
  );
}

/// 「加入歌單」（ADR 0019 §決定 4、ADR 0033 §決定 11、ADR 0035 R7.8）：compact 寬度是底部面板，其他寬度是
/// 對話框，內容相同——頂端一張歌曲資訊卡（一首是封面、曲名、上傳者；多首是「n 首歌曲」），
/// 「新增歌單」開建立對話框，建好的那張直接勾上；只列本機歌單，可勾多張。
/// 按「加入」把 [tracks] 依序接在每張勾選的歌單尾端（同一首可重複加入，ADR 0019），成功後關閉並提示；
/// 失敗時提示、面板留著。加入不確認（Namida 的「加入不確認、移除才確認」）。回傳有沒有加入（取消是
/// `false`）：多選加入了才離開選取模式。
Future<bool> showAddToPlaylist(
  BuildContext context,
  List<TrackInfo> tracks,
) async {
  final compact = WindowClass.of(context) == WindowClass.compact;
  if (!compact) {
    return await showDialog<bool>(
          context: context,
          builder: (_) => _AddToPlaylistView(tracks: tracks, sheet: false),
        ) ??
        false;
  }
  return await showModalBottomSheet<bool>(
        context: context,
        // 蓋住外殼（含底部導覽列與播放列）。
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AddToPlaylistView(tracks: tracks, sheet: true),
      ) ??
      false;
}

class _AddToPlaylistView extends ConsumerStatefulWidget {
  const _AddToPlaylistView({required this.tracks, required this.sheet});

  final List<TrackInfo> tracks;

  /// 底部面板（compact）；否則是對話框。
  final bool sheet;

  @override
  ConsumerState<_AddToPlaylistView> createState() => _AddToPlaylistViewState();
}

class _AddToPlaylistViewState extends ConsumerState<_AddToPlaylistView> {
  final _selected = <int>{};

  /// 正在建立歌單或寫入：按鈕停用。
  var _busy = false;

  Future<void> _create() async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    final input = await showPlaylistDialog(context);
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await service.create(
        name: input.name,
        description: input.description,
        artwork: input.artwork,
      );
      if (mounted) setState(() => _selected.add(id));
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to create a playlist',
        tag: 'library',
        sentence: (reason) => t.createFailed(reason: reason),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<({int id, String name})> chosen) async {
    final t = ref.read(translationsProvider).library;
    final service = ref.read(playlistServiceProvider);
    final toaster = ref.read(toasterProvider);
    setState(() => _busy = true);
    try {
      await service.addTracks([
        for (final playlist in chosen) playlist.id,
      ], widget.tracks);
    } on Object catch (error, stackTrace) {
      if (mounted) setState(() => _busy = false);
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to add songs to a playlist',
        tag: 'library',
        sentence: (reason) => t.addToPlaylistFailed(reason: reason),
      );
      return;
    }
    toaster.success(
      chosen.length == 1
          ? t.addedToPlaylist(name: chosen.single.name)
          : t.addedToPlaylists(count: chosen.length),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final local = [
      for (final overview
          in ref.watch(playlistOverviewsProvider).value ??
              const <PlaylistOverview>[])
        if (overview.playlist.kind == PlaylistKind.local) overview,
    ];
    // 勾過、之後在別處被刪掉的不算。
    final chosen = [
      for (final overview in local)
        if (_selected.contains(overview.playlist.id))
          (id: overview.playlist.id, name: overview.playlist.name),
    ];
    final padding = EdgeInsets.symmetric(horizontal: spacing.x6);
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x6, 0, spacing.x6, spacing.x2),
          child: _TracksInfoCard(tracks: widget.tracks),
        ),
        ListTile(
          contentPadding: padding,
          leading: const Icon(Icons.add),
          title: Text(t.newPlaylist),
          enabled: !_busy,
          onTap: () => unawaited(_create()),
        ),
        if (local.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.x6,
              vertical: spacing.x2,
            ),
            child: Text(
              t.noLocalPlaylists,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final overview in local)
          CheckboxListTile(
            key: ValueKey(overview.playlist.id),
            contentPadding: padding,
            value: _selected.contains(overview.playlist.id),
            onChanged: _busy
                ? null
                : (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(overview.playlist.id);
                    } else {
                      _selected.remove(overview.playlist.id);
                    }
                  }),
            secondary: PlaylistCover(
              artwork: overview.playlist.artwork,
              firstTrack: overview.firstTrack,
              size: AppLayout.artworkThumbnail,
            ),
            title: Text(
              overview.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(trackCountText(t, overview.trackCount)),
          ),
      ],
    );
    final addButton = FilledButton(
      onPressed: _busy || chosen.isEmpty ? null : () => unawaited(_add(chosen)),
      child: Text(t.add),
    );
    if (!widget.sheet) {
      return AlertDialog(
        title: Text(t.addToPlaylistTitle),
        contentPadding: EdgeInsets.symmetric(vertical: spacing.x4),
        content: SingleChildScrollView(child: list),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          addButton,
        ],
      );
    }
    // 底部面板：標題、可捲動的內容、全寬的「加入」。最高到螢幕的 9 成。
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.x6,
                0,
                spacing.x6,
                spacing.x2,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  t.addToPlaylistTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            Flexible(child: SingleChildScrollView(child: list)),
            Padding(
              padding: EdgeInsets.all(spacing.x4),
              child: SizedBox(width: double.infinity, child: addButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板頂端的歌曲資訊卡：一首是封面、曲名、上傳者；多首是一個圖示與「n 首歌曲」。
class _TracksInfoCard extends ConsumerWidget {
  const _TracksInfoCard({required this.tracks});

  final List<TrackInfo> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = AppTokens.of(context);
    final single = tracks.length == 1 ? tracks.single : null;
    final Widget leading = single == null
        ? SizedBox.square(
            dimension: AppLayout.addToPlaylistInfoCover,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(tokens.radius.small),
              ),
              child: Icon(
                Icons.library_music_outlined,
                color: scheme.onSecondaryContainer,
              ),
            ),
          )
        : ArtworkImage(
            pluginId: single.sourceTypeId,
            artwork: single.artwork,
            size: AppLayout.addToPlaylistInfoCover,
          );
    final uploader = single?.uploader;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.medium),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.x3),
        child: Row(
          children: [
            leading,
            SizedBox(width: tokens.spacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    single?.displayTitle ??
                        t.addToPlaylistTracks(count: tracks.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (uploader != null)
                    Text(
                      uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
