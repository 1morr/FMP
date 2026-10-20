import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/root_navigator.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/remote_playlist_writer.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/account_playlists_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/remote_write_report.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 曲目選單的「加入遠端歌單…」（M4 design §7.1、§10.6）。[pluginIds] 是要加入的曲目所屬的插件
/// （單首就一個）；曲目所屬的插件不能寫遠端（沒宣告 `libraryWrite`、停用、沒登入）時整項不出現。
/// [onPressed] 由呼叫端給，要以列本身的 `context` 開對話框（選單項目在選單關掉後就不在了）。
class AddToRemoteItem extends ConsumerWidget {
  const AddToRemoteItem({
    super.key,
    required this.pluginIds,
    required this.onPressed,
  });

  final Set<String> pluginIds;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = remoteAddEntryFor(
      ref.watch(remoteWritablePluginsProvider),
      pluginIds,
    );
    if (entry == RemoteAddEntry.hidden) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).library;
    return MenuItemButton(
      leadingIcon: const Icon(Icons.cloud_upload_outlined),
      onPressed: entry == RemoteAddEntry.available ? onPressed : null,
      child: Text(
        entry == RemoteAddEntry.available ? t.addToRemote : t.addToRemoteMixed,
      ),
    );
  }
}

/// 「加入遠端歌單」對話框（M4 design §7.1，ADR 0019 §決定 4）：開啟時讀完帳號的歌單
/// （`libraryPlaylists` 所有頁），只列可寫的，可勾多張；「在遠端新增歌單」輸入名稱後建好、出現在清單並已
/// 勾上。按「加入」直接送出（不另確認），每張勾選的歌單一次 `addToPlaylist`，之後關閉並提示結果。
/// [tracks] 都屬於同一個插件。回傳有沒有送出（取消是 `false`）：多選送出了才離開選取模式。
Future<bool> showAddToRemote(
  BuildContext context,
  List<TrackInfo> tracks,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _AddToRemoteDialog(tracks: tracks),
    ) ??
    false;

class _AddToRemoteDialog extends ConsumerStatefulWidget {
  const _AddToRemoteDialog({required this.tracks});

  final List<TrackInfo> tracks;

  @override
  ConsumerState<_AddToRemoteDialog> createState() => _AddToRemoteDialogState();
}

class _AddToRemoteDialogState extends ConsumerState<_AddToRemoteDialog> {
  final _selected = <String>{};

  /// 這個對話框裡新增的歌單（還沒出現在讀到的清單裡，沒有首數）。
  final _created = <LibraryPlaylist>[];

  /// 正在建立歌單或寫入：按鈕停用。
  var _busy = false;

  String get _pluginId => widget.tracks.first.sourceTypeId;

  String? _offlineText(Translations t) =>
      switch (ref.read(networkStatusProvider)) {
        NetworkStatus.noInterface => t.offline.noInterface,
        NetworkStatus.unreachable => t.offline.unreachable,
        NetworkStatus.online => null,
      };

  String _reason(Translations t, AppError error) =>
      _offlineText(t) ??
      errorMessage(
        t,
        error,
        sourceName: ref.read(pluginNameProvider(error.pluginId ?? _pluginId)),
      );

  Future<void> _create() async {
    final t = ref.read(translationsProvider);
    final writer = ref.read(remotePlaylistWriterProvider);
    final toaster = ref.read(toasterProvider);
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NewRemotePlaylistDialog(),
    );
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await writer.createRemote(_pluginId, title);
      if (!mounted) return;
      setState(() {
        _created.add(
          LibraryPlaylist(playlistId: id, title: title.trim(), writable: true),
        );
        _selected.add(id);
      });
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace, pluginId: _pluginId),
        operation: 'Failed to create a remote playlist',
        tag: 'library',
        sentence: (reason) => t.library.remoteNewFailed(reason: reason),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<LibraryPlaylist> chosen) async {
    // 送出後對話框就關了：要用的東西在第一個 await 之前讀好。
    final t = ref.read(translationsProvider);
    final writer = ref.read(remotePlaylistWriterProvider);
    final toaster = ref.read(toasterProvider);
    final navigatorKey = ref.read(rootNavigatorKeyProvider);
    final sourceName = ref.read(pluginNameProvider(_pluginId));
    final offline = _offlineText(t);
    setState(() => _busy = true);
    final List<RemoteAddOutcome> outcomes;
    try {
      outcomes = await writer.addToRemote(_pluginId, widget.tracks, [
        for (final playlist in chosen) playlist.playlistId,
      ]);
    } on Object catch (error, stackTrace) {
      if (mounted) setState(() => _busy = false);
      toaster.error(
        AppError.wrap(error, stackTrace, pluginId: _pluginId),
        operation: 'Failed to add songs to a remote playlist',
        tag: 'library',
        sentence: (reason) => t.library.remoteAddError(reason: reason),
      );
      return;
    }
    final titles = {
      for (final playlist in chosen) playlist.playlistId: playlist.title,
    };
    var playlists = 0;
    var present = 0;
    var failed = 0;
    final rows = <RemoteFailureRow>[];
    for (final outcome in outcomes) {
      if (outcome.succeeded) playlists++;
      present += outcome.alreadyPresent;
      failed += outcome.failed;
      if (outcome.failed > 0) {
        final error = outcome.error;
        rows.add((
          title: t.library.remoteDetailCount(
            name: titles[outcome.playlistId] ?? outcome.playlistId,
            count: outcome.failed,
          ),
          reason:
              offline ??
              (error == null
                  ? t.library.remoteNoReason
                  : errorMessage(t, error, sourceName: sourceName)),
        ));
      }
    }
    final message =
        (switch (playlists) {
          0 => t.library.remoteAddNone,
          // 英文的 1 張是單數（同 `trackCountText`）。
          1 => t.library.remoteAddedOne,
          _ => t.library.remoteAdded(count: playlists),
        }) +
        (present > 0 ? t.library.remoteAlreadyThere(count: present) : '') +
        (failed > 0 ? t.library.remoteFailedCount(count: failed) : '');
    final details = failed == 0
        ? null
        : ToastAction(
            label: t.errorReport.actionDetail,
            onPressed: () {
              final navigator = navigatorKey.currentState;
              if (navigator == null) return;
              unawaited(showRemoteFailureDetails(navigator, t, rows: rows));
            },
          );
    if (failed == 0) {
      toaster.success(message);
    } else {
      toaster.warning(message, action: details);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final l = t.library;
    final spacing = AppTokens.of(context).spacing;
    final playlists = ref.watch(accountPlaylistsProvider(_pluginId));
    final listed = playlists.value;
    // 讀到的清單裡可寫的，接著這個對話框新增的（讀到的清單已經有同一個 id 就不重複）。
    final writable = listed == null
        ? const <LibraryPlaylist>[]
        : [
            for (final playlist in listed)
              if (playlist.writable) playlist,
            for (final playlist in _created)
              if (!listed.any((p) => p.playlistId == playlist.playlistId))
                playlist,
          ];
    final chosen = [
      for (final playlist in writable)
        if (_selected.contains(playlist.playlistId)) playlist,
    ];
    return AlertDialog(
      title: Text(l.remoteTitle),
      contentPadding: EdgeInsets.symmetric(vertical: spacing.x4),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (playlists) {
              AsyncData() => _list(t, writable),
              AsyncError(:final error) => _failed(
                t,
                error is AppError ? error : null,
              ),
              _ => Padding(
                padding: EdgeInsets.all(spacing.x6),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: l.remoteLoading,
                  ),
                ),
              ),
            },
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _busy || chosen.isEmpty
              ? null
              : () => unawaited(_add(chosen)),
          child: Text(l.add),
        ),
      ],
    );
  }

  Widget _list(Translations t, List<LibraryPlaylist> writable) {
    final l = t.library;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: spacing.x6),
          leading: const Icon(Icons.add),
          title: Text(l.remoteNew),
          enabled: !_busy,
          onTap: () => unawaited(_create()),
        ),
        if (writable.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.x6,
              vertical: spacing.x2,
            ),
            child: Text(
              l.remoteEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final playlist in writable)
          CheckboxListTile(
            key: ValueKey(playlist.playlistId),
            contentPadding: EdgeInsets.symmetric(horizontal: spacing.x6),
            value: _selected.contains(playlist.playlistId),
            onChanged: _busy
                ? null
                : (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(playlist.playlistId);
                    } else {
                      _selected.remove(playlist.playlistId);
                    }
                  }),
            secondary: PlaylistCover(
              artwork: [
                for (final image in playlist.artwork)
                  TrackArtwork(url: image.url, width: image.width),
              ],
              firstTrack: null,
              size: AppLayout.artworkThumbnail,
            ),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: playlist.trackCount == null
                ? null
                : Text(trackCountText(l, playlist.trackCount!)),
          ),
      ],
    );
  }

  Widget _failed(Translations t, AppError? error) {
    final l = t.library;
    final spacing = AppTokens.of(context).spacing;
    final reason =
        _offlineText(t) ??
        (error == null ? t.errors.unexpected : _reason(t, error));
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.x6,
        vertical: spacing.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.remoteLoadFailed),
          SizedBox(height: spacing.x1),
          Text(reason),
          SizedBox(height: spacing.x2),
          FilledButton.tonal(
            onPressed: () =>
                ref.invalidate(accountPlaylistsProvider(_pluginId)),
            child: Text(l.retry),
          ),
        ],
      ),
    );
  }
}

/// 「在遠端新增歌單」的名稱輸入；按「新增」回傳去掉頭尾空白的名稱，取消回 `null`。
class _NewRemotePlaylistDialog extends ConsumerStatefulWidget {
  const _NewRemotePlaylistDialog();

  @override
  ConsumerState<_NewRemotePlaylistDialog> createState() =>
      _NewRemotePlaylistDialogState();
}

class _NewRemotePlaylistDialogState
    extends ConsumerState<_NewRemotePlaylistDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(translationsProvider).library;
    return AlertDialog(
      title: Text(l.remoteNewTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.remoteNewName),
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: Text(l.remoteNewAction),
        ),
      ],
    );
  }
}
