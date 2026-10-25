import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/account_import_page.dart';
import 'package:fmp/ui/accounts/account_playlists_state.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/library_state.dart' show trackCountText;
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/plugin_widgets.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 在 [context] 所在的 Navigator 開 [pluginId] 的帳號歌單頁：帳號頁在設定分頁自己的巢狀導覽裡，
/// 導覽與播放列留著（同 `openHistory`）。
Future<void> openAccountPlaylists(BuildContext context, String pluginId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 自己的 Material：理由見 `AppShell` 的根頁。
        builder: (_) => Material(
          type: MaterialType.transparency,
          child: AccountPlaylistsPage(pluginId: pluginId),
        ),
      ),
    );

/// 帳號的歌單頁（M4 design §7.3）：登入帳號在平台上的歌單（`libraryPlaylists` 讀完所有頁），勾選後
/// 一次匯入成匯入歌單。
///
/// - 每列：勾選框、封面、名稱、首數、「可寫」標記；同插件同 id 已在音樂庫的（`playlist_remote`）標
///   「已匯入」並停用勾選，匯入完成就翻過來。
/// - 「匯入所選」逐張經 [PlaylistImporter.importPlaylistId]（不經網址）：進度「n／總數」；失敗的那列在
///   下面寫原因、其他照做；完成提示「已匯入 n 張」，有失敗附「k 張失敗」。進行中不能再選、再按。
/// - 讀取失敗可重試，離線時用共用的離線空狀態；沒有歌單是空狀態。
///
/// 帳號歌單要網路；已匯入的標記是本機資料。
class AccountPlaylistsPage extends ConsumerStatefulWidget {
  const AccountPlaylistsPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<AccountPlaylistsPage> createState() =>
      _AccountPlaylistsPageState();
}

class _AccountPlaylistsPageState extends ConsumerState<AccountPlaylistsPage> {
  final _selected = <String>{};

  /// 這次匯入失敗的列（`playlistId` → 顯示的原因）；下一次匯入開始時清掉要重來的那些。
  final _failures = <String, String>{};
  var _importing = false;

  String get _pluginId => widget.pluginId;

  /// 現在的網路狀態對應的離線說法；`online` 是 `null`。
  String? _offlineText(Translations t) =>
      switch (ref.read(networkStatusProvider)) {
        NetworkStatus.noInterface => t.offline.noInterface,
        NetworkStatus.unreachable => t.offline.unreachable,
        NetworkStatus.online => null,
      };

  /// [error] 給使用者看的原因：離線時是離線的說法（同匯入對話框），否則是錯誤類別的訊息。
  String _reason(Translations t, AppError error) =>
      _offlineText(t) ??
      errorMessage(
        t,
        error,
        sourceName: ref.read(pluginNameProvider(error.pluginId ?? _pluginId)),
      );

  Future<void> _import(List<LibraryPlaylist> chosen) async {
    if (_importing || chosen.isEmpty) return;
    final t = ref.read(translationsProvider);
    final run = AccountImportRun(
      pluginId: _pluginId,
      playlists: chosen,
      importer: ref.read(playlistImporterProvider),
      log: ref.read(logProvider),
      translations: t,
      // 匯入頁擋住返回，這一頁通常還在；整個巢狀導覽被拆掉時 `ref` 不能再讀，退回不帶音源名的訊息，
      // 不讓剩下的匯入中斷。
      failureReason: (error) => mounted
          ? _reason(ref.read(translationsProvider), error)
          : errorMessage(t, error),
    );
    setState(() {
      _importing = true;
      for (final playlist in chosen) {
        _failures.remove(playlist.playlistId);
      }
    });
    await openAccountImport(context, run);
    if (!mounted) return;
    setState(() {
      _importing = false;
      _failures.addAll(run.failures);
      _selected.removeAll(run.importedIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final name = ref.watch(pluginNameProvider(_pluginId)) ?? _pluginId;
    final playlists = ref.watch(accountPlaylistsProvider(_pluginId));
    final imported =
        ref.watch(importedRemoteIdsProvider(_pluginId)).value ??
        const <String>{};
    // 還能選的：已匯入的不算；選到的列重畫時（清單、已匯入集合變了）只留下仍然存在的。
    final selectable = [
      for (final playlist in playlists.value ?? const <LibraryPlaylist>[])
        if (!imported.contains(playlist.playlistId)) playlist,
    ];
    final chosen = [
      for (final playlist in selectable)
        if (_selected.contains(playlist.playlistId)) playlist,
    ];
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
                  tooltip: t.shell.backTooltip,
                  icon: const BackButtonIcon(),
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    a.playlistsTitle(name: name),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              FilledButton(
                onPressed: chosen.isEmpty || _importing
                    ? null
                    : () => unawaited(_import(chosen)),
                child: Text(a.importSelected(count: chosen.length)),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (playlists) {
            AsyncData(:final value) when value.isEmpty => EmptyState(
              icon: Icons.queue_music,
              title: a.playlistsEmpty,
            ),
            AsyncData(:final value) => ListView.builder(
              itemCount: value.length,
              itemBuilder: (context, index) {
                final playlist = value[index];
                final done = imported.contains(playlist.playlistId);
                return _PlaylistRow(
                  key: ValueKey(playlist.playlistId),
                  playlist: playlist,
                  imported: done,
                  selected: done || _selected.contains(playlist.playlistId),
                  failure: _failures[playlist.playlistId],
                  enabled: !done && !_importing,
                  onChanged: (value) => setState(() {
                    if (value) {
                      _selected.add(playlist.playlistId);
                    } else {
                      _selected.remove(playlist.playlistId);
                    }
                  }),
                );
              },
            ),
            AsyncError(:final error) => _failed(
              t,
              error is AppError ? error : null,
            ),
            _ => Center(
              child: CircularProgressIndicator(semanticsLabel: a.working),
            ),
          },
        ),
      ],
    );
  }

  Widget _failed(Translations t, AppError? error) {
    final retry = FilledButton.tonal(
      onPressed: () => ref.invalidate(accountPlaylistsProvider(_pluginId)),
      child: Text(t.accounts.retry),
    );
    final network = ref.watch(networkStatusProvider);
    if (network != NetworkStatus.online) {
      return OfflineMessage(status: network, action: retry);
    }
    return EmptyState(
      icon: Icons.error_outline,
      title: t.accounts.playlistsFailed,
      body: error == null ? t.errors.unexpected : _reason(t, error),
      action: retry,
    );
  }
}

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({
    super.key,
    required this.playlist,
    required this.imported,
    required this.selected,
    required this.failure,
    required this.enabled,
    required this.onChanged,
  });

  final LibraryPlaylist playlist;
  final bool imported;
  final bool selected;

  /// 這一列上次匯入失敗的原因。
  final String? failure;

  /// 勾選框能不能動（已匯入或匯入進行中不能）。
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final count = playlist.trackCount;
    return ListTile(
      enabled: enabled,
      onTap: enabled ? () => onChanged(!selected) : null,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: a.playlistSelect(name: playlist.title),
            child: Checkbox(
              value: selected,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            ),
          ),
          PlaylistCover(
            artwork: [
              for (final image in playlist.artwork)
                TrackArtwork(url: image.url, width: image.width),
            ],
            firstTrack: null,
            size: AppLayout.artworkThumbnail,
          ),
        ],
      ),
      title: Text(playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: spacing.x2,
            runSpacing: spacing.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (count != null) Text(trackCountText(t.library, count)),
              if (playlist.writable) PluginTag(text: a.playlistWritable),
              if (imported)
                PluginTag(
                  text: a.playlistImported,
                  tone: PluginTagTone.primary,
                ),
            ],
          ),
          if (failure != null)
            Padding(
              padding: EdgeInsets.only(top: spacing.x1),
              child: Text(
                failure!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
