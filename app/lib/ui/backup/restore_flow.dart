import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/backup.dart';
import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/backup/blocking_progress.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

// 還原的確認與執行，設定頁的「從備份檔還原」與 Debug 頁的「從備份還原」共用
// （ADR 0034 §決定 4）。

/// 備份被拒絕時給使用者看的一句話。
String backupRejectionMessage(Translations t, BackupRejection reason) =>
    switch (reason) {
      BackupRejection.newerVersion => t.backup.rejectedNewer,
      BackupRejection.notFmpBackup => t.backup.rejectedNotFmp,
      BackupRejection.corrupt => t.backup.rejectedCorrupt,
    };

/// 確認框（取代安裝確認，ADR 0034 §決定 4 第 2 條）後取代資料並重啟。
///
/// 使用者取消，或自動備份、寫入、換檔失敗時，刪掉 [staged] 的暫存檔、什麼都不取代。
/// provider 在第一個 `await` 之前讀好，`await` 之後先看 `context.mounted`。
Future<void> confirmAndRestore(
  BuildContext context,
  WidgetRef ref,
  StagedBackup staged,
) async {
  final t = ref.read(translationsProvider);
  final reset = ref.read(dataResetProvider);
  final toaster = ref.read(toasterProvider);
  final restartsItself = ref.read(platformCapabilitiesProvider).restartsItself;
  final plugins = ref.read(pluginRepositoryProvider);
  final RestoreReview review;
  try {
    review = reviewRestore(staged, await plugins.list());
  } on Object catch (error, stackTrace) {
    unawaited(reset.discardStaged(staged));
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to read the installed plugins',
      tag: 'backup',
      sentence: (message) => t.backup.restoreFailed(message: message),
    );
    return;
  }
  if (!context.mounted) {
    await reset.discardStaged(staged);
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        RestoreConfirmDialog(review: review, restartsItself: restartsItself),
  );
  if (confirmed != true || !context.mounted) {
    await reset.discardStaged(staged);
    return;
  }
  await runBlocking(
    context,
    message: t.backup.restoreWorking,
    work: () => reset.restoreAndRestart(staged),
    onError: (error, stackTrace) {
      unawaited(reset.discardStaged(staged));
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to restore a backup',
        tag: 'backup',
        sentence: (message) => t.backup.restoreFailed(message: message),
      );
    },
  );
}

/// 還原確認框：列出備份裡的插件（名稱、版本、會連的網域，取自腳本標頭）、備份帶進來的自訂
/// 插件庫、ADR 0030 §決定 8 的警告，並說明「目前的資料會被取代；取代前會自動備份」。
/// 這台也裝了同 id 的插件時，標出備份的版本比較舊、比這台多出來的網域（強調顯示，像更新確認框，
/// ADR 0030 §決定 9）。按「還原並重新啟動」才是 `true`。
class RestoreConfirmDialog extends ConsumerWidget {
  const RestoreConfirmDialog({
    super.key,
    required this.review,
    required this.restartsItself,
  });

  final RestoreReview review;
  final bool restartsItself;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final b = t.backup;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final emphasis = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
      fontWeight: FontWeight.bold,
    );
    Widget heading(String text) => Padding(
      padding: EdgeInsets.only(top: spacing.x4, bottom: spacing.x1),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return AlertDialog(
      title: Text(b.restoreTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.restoreBody),
            SizedBox(height: spacing.x2),
            Text(restartsItself ? b.restartsItself : b.restartsManually),
            heading(b.pluginsHeading),
            if (review.plugins.isEmpty && review.unusablePluginIds.isEmpty)
              Text(b.noPlugins),
            for (final item in review.plugins) ...[
              Text(
                b.pluginLine(
                  name: item.plugin.name,
                  version: item.plugin.version,
                ),
                style: theme.textTheme.titleSmall,
              ),
              if (item.older)
                Text(
                  b.olderThanInstalled(version: item.installedVersion!),
                  style: emphasis,
                ),
              if (item.plugin.hosts.isNotEmpty)
                Text(
                  '${b.hosts}: ${item.plugin.hosts.join(b.listSeparator)}',
                  style: theme.textTheme.bodyMedium,
                ),
              if (item.installedVersion != null && item.addedHosts.isNotEmpty)
                Text(
                  b.addedHosts(hosts: item.addedHosts.join(b.listSeparator)),
                  style: emphasis,
                ),
              SizedBox(height: spacing.x2),
            ],
            if (review.unusablePluginIds.isNotEmpty) ...[
              heading(b.unusableHeading),
              for (final id in review.unusablePluginIds)
                Text(id, style: theme.textTheme.bodyMedium),
            ],
            if (review.indexUrls.isNotEmpty) ...[
              heading(b.indexesHeading),
              for (final url in review.indexUrls)
                Text(url, style: theme.textTheme.bodyMedium),
            ],
            if (review.plugins.isNotEmpty) ...[
              SizedBox(height: spacing.x2),
              WarningNote(text: t.plugins.loginWarning),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(b.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(b.confirm),
        ),
      ],
    );
  }
}
