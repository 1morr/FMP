import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/root_navigator.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/remote_playlist_writer.dart';
import 'package:fmp/ui/dialogs/destructive_confirm.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/remote_write_report.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 匯入歌單詳情的曲目選單項目「從遠端歌單移除」（M4 design §7.2、§10.6）：這張是可寫的匯入歌單、
/// 插件宣告 `libraryWrite` 而且已登入時才出現（[remoteRemoveEntryProvider]）。
class RemoveFromRemoteItem extends ConsumerWidget {
  const RemoveFromRemoteItem({
    super.key,
    required this.playlistId,
    required this.onPressed,
  });

  /// 本地的歌單 id。
  final int playlistId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteRemoveEntryProvider(playlistId))) {
      return const SizedBox.shrink();
    }
    return DestructiveMenuItem(
      icon: Icons.cloud_off_outlined,
      onPressed: onPressed,
      child: Text(ref.watch(translationsProvider).library.removeFromRemote),
    );
  }
}

/// 從匯入歌單 [playlistId] 的遠端歌單移除 [entries]：先確認（列出首數），再經
/// [RemotePlaylistWriter.removeFromRemote]；`removed` 與 `notPresent` 的從本地刪掉、背景刷新一次，
/// 有失敗時提示並附「詳細」列出。回傳有沒有移除（取消、整個呼叫失敗是 `false`）：多選移除了才離開
/// 選取模式。
Future<bool> removeFromRemotePlaylist(
  BuildContext context,
  WidgetRef ref,
  int playlistId,
  List<PlaylistEntry> entries,
) async {
  final t = ref.read(translationsProvider);
  final l = t.library;
  final writer = ref.read(remotePlaylistWriterProvider);
  final toaster = ref.read(toasterProvider);
  final navigatorKey = ref.read(rootNavigatorKeyProvider);
  // 確認框開著時那一列可能就不在了（背景刷新改了清單），[ref] 跟著它釋放：之後的讀取走容器。
  final container = ProviderScope.containerOf(context, listen: false);
  final detail = ref.read(playlistDetailProvider(playlistId)).value;
  final pluginId = detail?.remote?.pluginId;
  final sourceName =
      (pluginId == null ? null : ref.read(pluginNameProvider(pluginId))) ??
      pluginId ??
      '';
  final confirmed = await showDestructiveConfirm(
    context,
    title: l.removeRemoteTitle,
    body: l.removeRemoteBody(
      count: entries.length,
      name: detail?.playlist.name ?? '',
      source: sourceName,
    ),
    confirmLabel: l.removeRemoteConfirm,
    cancelLabel: l.cancel,
  );
  if (!confirmed) return false;
  final RemoteRemoveOutcome outcome;
  try {
    outcome = await writer.removeFromRemote(playlistId, entries);
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace, pluginId: pluginId),
      operation: 'Failed to remove songs from a remote playlist',
      tag: 'library',
      sentence: (reason) => l.removeRemoteFailed(reason: reason),
    );
    return false;
  }
  final failed = outcome.failures.length;
  final removed = outcome.removed + outcome.notPresent;
  final message =
      (removed > 0 ? l.removedFromRemote(count: removed) : l.removeRemoteNone) +
      (failed > 0 ? l.remoteFailedCount(count: failed) : '');
  if (failed == 0) {
    toaster.success(message);
    return true;
  }
  final offline = _offlineText(container, t);
  final rows = <RemoteFailureRow>[
    for (final failure in outcome.failures)
      (
        title: failure.entry.track.displayTitle,
        reason:
            offline ??
            (failure.error == null
                ? l.remoteNoReason
                : errorMessage(t, failure.error!, sourceName: sourceName)),
      ),
  ];
  toaster.warning(
    message,
    action: ToastAction(
      label: t.errorReport.actionDetail,
      onPressed: () {
        final navigator = navigatorKey.currentState;
        if (navigator == null) return;
        unawaited(showRemoteFailureDetails(navigator, t, rows: rows));
      },
    ),
  );
  return removed > 0;
}

/// 現在的網路狀態對應的離線說法；`online` 是 `null`。
String? _offlineText(ProviderContainer container, Translations t) =>
    switch (container.read(networkStatusProvider)) {
      NetworkStatus.noInterface => t.offline.noInterface,
      NetworkStatus.unreachable => t.offline.unreachable,
      NetworkStatus.online => null,
    };
