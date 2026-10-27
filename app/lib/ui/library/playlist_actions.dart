import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_service.dart';
import 'package:fmp/ui/dialogs/destructive_confirm.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/playlist_dialogs.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 建立一張本機歌單：開對話框、存、提示。音樂庫的「建立歌單」與首頁的「建立歌單」卡共用。
Future<void> createPlaylist(BuildContext context, WidgetRef ref) async {
  // 對話框期間外殼可能重建呼叫的頁面：要用的先讀好。
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

/// 編輯 [overview] 這張歌單：開對話框、存、提示。匯入歌單另讀遠端資料（哪些欄位被覆寫、
/// 自動刷新間隔）。音樂庫的卡片選單與 Mix 歌單詳情共用。
Future<void> editPlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistOverview overview,
) async {
  final t = ref.read(translationsProvider).library;
  final service = ref.read(playlistServiceProvider);
  final toaster = ref.read(toasterProvider);
  final repository = ref.read(playlistRepositoryProvider);
  final playlist = overview.playlist;
  // 匯入歌單的編輯要知道哪些欄位已被覆寫（「使用遠端的」）。
  final remote = playlist.kind == PlaylistKind.imported
      ? await repository.remote(playlist.id)
      : null;
  if (!context.mounted) return;
  final input = await showPlaylistDialog(
    context,
    editing: overview,
    remote: remote,
  );
  if (input == null) return;
  try {
    if (remote == null) {
      await service.edit(
        playlist,
        name: input.name,
        description: input.description,
        artwork: input.artwork,
      );
    } else {
      await service.editImported(
        playlist,
        remote,
        name: input.name,
        description: input.description,
        artwork: input.artwork,
        useRemote: input.useRemote,
      );
      if (input.refreshIntervalHours != remote.refreshIntervalHours) {
        await service.setRefreshInterval(
          playlist.id,
          input.refreshIntervalHours,
        );
      }
    }
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

/// 確認後刪 [playlist]，成功回 `true`。音樂庫的卡片選單與 Mix 歌單詳情共用。
Future<bool> deletePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final t = ref.read(translationsProvider).library;
  final service = ref.read(playlistServiceProvider);
  final toaster = ref.read(toasterProvider);
  final confirmed = await showDestructiveConfirm(
    context,
    title: t.deleteTitle,
    body: t.deleteBody(name: playlist.name),
    confirmLabel: t.delete,
    cancelLabel: t.cancel,
  );
  if (!confirmed) return false;
  try {
    await service.delete(playlist.id);
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to delete a playlist',
      tag: 'library',
      sentence: (reason) => t.deleteFailed(reason: reason),
    );
    return false;
  }
  toaster.success(t.deleted);
  return true;
}
