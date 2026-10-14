import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/debug/debug_overview.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

// Debug 頁的備份、從備份還原與重設資料的流程（ADR 0025 §決定 8、9，M3 design §12.2）。
// 三個函式都在 [context] 底下開對話框：provider 在第一個 `await` 之前讀好，`await` 之後
// 先看 `context.mounted`。

/// 立即備份：成功顯示檔案位置，失敗顯示原因。
Future<void> backUpNow(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider).debug;
  final reset = ref.read(dataResetProvider);
  final toaster = ref.read(toasterProvider);
  final home = ref.read(appInfoProvider).homeDirectory;
  try {
    final backup = await reset.backUp();
    toaster.success(t.dbBackedUp(path: homeRelativePath(backup.path, home)));
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to back up the database',
      tag: 'data',
      sentence: (message) => t.dbBackUpFailed(message: message),
    );
  }
}

/// 重設資料（ADR 0025 §決定 9）：先備份，備份失敗就停在這裡、什麼都不清；成功才開對話框
/// 列出備份位置並二次確認（勾選「我了解」才能按「清空並重啟」），確認後清空並重啟。
Future<void> startReset(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider).debug;
  final reset = ref.read(dataResetProvider);
  final toaster = ref.read(toasterProvider);
  final restartsItself = ref.read(platformCapabilitiesProvider).restartsItself;
  final home = ref.read(appInfoProvider).homeDirectory;
  final DatabaseBackup backup;
  try {
    backup = await reset.backUp();
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to back up the database before a reset',
      tag: 'data',
      sentence: (message) => t.resetBackupFailed(message: message),
    );
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ResetConfirmDialog(
      path: homeRelativePath(backup.path, home),
      restartsItself: restartsItself,
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _runBlocking(
    context,
    message: t.resetWorking,
    work: () => reset.resetAndRestart(backup),
    onError: (error, stackTrace) => toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to reset the data',
      tag: 'data',
      sentence: (message) => t.resetFailed(message: message),
    ),
  );
}

/// 從備份還原：列出備份、選一個、確認，然後取代資料庫並重啟。
Future<void> startRestore(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider).debug;
  final reset = ref.read(dataResetProvider);
  final toaster = ref.read(toasterProvider);
  final restartsItself = ref.read(platformCapabilitiesProvider).restartsItself;
  final List<DatabaseBackup> backups;
  try {
    backups = await reset.backups();
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to list the database backups',
      tag: 'data',
      sentence: (message) => t.dbRestoreListFailed(message: message),
    );
    return;
  }
  if (!context.mounted) return;
  final chosen = await showDialog<DatabaseBackup>(
    context: context,
    builder: (_) => _BackupListDialog(backups: backups),
  );
  if (chosen == null || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _RestoreConfirmDialog(backup: chosen, restartsItself: restartsItself),
  );
  if (confirmed != true || !context.mounted) return;
  await _runBlocking(
    context,
    message: t.dbRestoreWorking,
    work: () => reset.restoreAndRestart(chosen),
    onError: (error, stackTrace) => toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to restore the database',
      tag: 'data',
      sentence: (message) => t.dbRestoreFailed(message: message),
    ),
  );
}

/// 蓋住畫面的進度對話框，直到 [work] 結束（成功時行程通常已經結束了）。失敗呼叫 [onError]。
Future<void> _runBlocking(
  BuildContext context, {
  required String message,
  required Future<void> Function() work,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final gap = SizedBox(width: AppTokens.of(context).spacing.x4);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              gap,
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    await work();
  } on Object catch (error, stackTrace) {
    onError(error, stackTrace);
  } finally {
    navigator.pop();
  }
}

String _time(DateTime utc) {
  final local = utc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _ResetConfirmDialog extends ConsumerStatefulWidget {
  const _ResetConfirmDialog({required this.path, required this.restartsItself});

  final String path;
  final bool restartsItself;

  @override
  ConsumerState<_ResetConfirmDialog> createState() =>
      _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends ConsumerState<_ResetConfirmDialog> {
  var _understood = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    return AlertDialog(
      title: Text(t.resetConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.resetConfirmBody(path: widget.path)),
            SizedBox(height: spacing.x2),
            Text(
              widget.restartsItself
                  ? t.resetRestartsItself
                  : t.resetRestartsManually,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(t.resetUnderstand),
              value: _understood,
              onChanged: (value) =>
                  setState(() => _understood = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _understood ? () => Navigator.of(context).pop(true) : null,
          child: Text(t.resetConfirm),
        ),
      ],
    );
  }
}

class _BackupListDialog extends ConsumerWidget {
  const _BackupListDialog({required this.backups});

  final List<DatabaseBackup> backups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    return AlertDialog(
      title: Text(t.dbRestoreTitle),
      content: SingleChildScrollView(
        child: backups.isEmpty
            ? Text(t.dbRestoreEmpty)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final backup in backups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_time(backup.createdAt)),
                      subtitle: Text(formatByteSize(backup.sizeBytes)),
                      onTap: () => Navigator.of(context).pop(backup),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}

class _RestoreConfirmDialog extends ConsumerWidget {
  const _RestoreConfirmDialog({
    required this.backup,
    required this.restartsItself,
  });

  final DatabaseBackup backup;
  final bool restartsItself;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    return AlertDialog(
      title: Text(t.dbRestoreConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.dbRestoreConfirmBody(time: _time(backup.createdAt))),
            SizedBox(height: spacing.x2),
            Text(
              restartsItself ? t.resetRestartsItself : t.resetRestartsManually,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.dbRestoreConfirm),
        ),
      ],
    );
  }
}
