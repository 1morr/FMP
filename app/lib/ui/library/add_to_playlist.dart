import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
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

/// 「加入歌單」對話框（ADR 0019 §決定 4、ADR 0033 §決定 11）：只列本機歌單，可勾多張；頂端
/// 「新增歌單」開建立對話框，建好的那張直接勾上。按「加入」把 [tracks] 依序接在每張勾選的
/// 歌單尾端（同一首可重複加入，ADR 0019），成功後關閉並提示；失敗時提示、對話框留著。
/// 加入不確認（Namida 的「加入不確認、移除才確認」）。回傳有沒有加入（取消是 `false`）：多選
/// 加入了才離開選取模式。
Future<bool> showAddToPlaylist(
  BuildContext context,
  List<TrackInfo> tracks,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _AddToPlaylistDialog(tracks: tracks),
    ) ??
    false;

class _AddToPlaylistDialog extends ConsumerStatefulWidget {
  const _AddToPlaylistDialog({required this.tracks});

  final List<TrackInfo> tracks;

  @override
  ConsumerState<_AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<_AddToPlaylistDialog> {
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
    return AlertDialog(
      title: Text(t.addToPlaylistTitle),
      contentPadding: EdgeInsets.symmetric(vertical: spacing.x4),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: spacing.x6),
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
                contentPadding: EdgeInsets.symmetric(horizontal: spacing.x6),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _busy || chosen.isEmpty
              ? null
              : () => unawaited(_add(chosen)),
          child: Text(t.add),
        ),
      ],
    );
  }
}
