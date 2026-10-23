import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/data_reset.dart';
import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/backup/blocking_progress.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

// 設定頁「備份與還原」組的「從舊版匯入…」（M5 design §3.2、§7.4）。選來源 → 進度 → 確認框 →
// 取代並重啟。匯入是取代：換掉音樂庫與舊版有的設定，保留這台的插件、插件設定與登入。

/// 舊 JSON 備份檔大小的上限；舊版的備份是幾 MB 的文字檔，這麼大的不是備份。
const _maxBackupBytes = 256 * 1024 * 1024;

/// 這台裝置上有沒有舊資料庫，與匯入過沒有（決定選單能不能選「舊版資料庫」與要不要顯示提示）。
class LegacyImportOffer {
  const LegacyImportOffer({required this.source, required this.imported});

  /// 找到的舊資料庫；沒有為 `null`。
  final LegacySource? source;

  /// `legacy_imports` 已有紀錄。
  final bool imported;
}

/// 找舊資料庫的結果。沒有注入匯入實作或找的時候出錯（例如 dev 的資料夾不合法）時沒有提供，
/// 呼叫端當成「找不到」。
final legacyImportOfferProvider = FutureProvider.autoDispose<LegacyImportOffer>(
  (ref) async {
    final legacy = ref.watch(legacyImportProvider);
    LegacySource? source;
    try {
      source = await legacy.locate();
    } on Object catch (error) {
      ref
          .read(logProvider)
          .warning(
            'Failed to look for the legacy data',
            tag: 'legacy-import',
            fields: {'errorType': '${error.runtimeType}'},
          );
    }
    final imported = await ref.watch(legacyImportsRepositoryProvider).hasAny();
    return LegacyImportOffer(source: source, imported: imported);
  },
);

enum _Source { database, backup }

/// 「從舊版匯入…」的整個流程。provider 在第一個 `await` 之前讀好，`await` 之後先看
/// `context.mounted`。使用者取消或任何一步失敗，暫存庫都刪掉、資料庫不變。
Future<void> importFromLegacy(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider);
  final legacy = ref.read(legacyImportProvider);
  final reset = ref.read(dataResetProvider);
  final toaster = ref.read(toasterProvider);
  final database = ref.read(appDatabaseProvider);
  final dialogs = ref.read(fileDialogsProvider);
  final restartsItself = ref.read(platformCapabilitiesProvider).restartsItself;
  ref.invalidate(legacyImportOfferProvider);
  final found = await ref
      .read(legacyImportOfferProvider.future)
      .then<LegacySource?>(
        (offer) => offer.source,
        onError: (Object _) => null,
      );
  if (!context.mounted) return;
  final choice = await showDialog<_Source>(
    context: context,
    builder: (_) => _ChooseSourceDialog(
      t: t,
      hasDatabase: found != null,
      hasFiles: dialogs != null,
    ),
  );
  if (choice == null || !context.mounted) return;

  // JSON 備份先選檔：進度對話框蓋住畫面之前。
  PickedFile? picked;
  if (choice == _Source.backup) {
    try {
      picked = await dialogs!.pickFile(
        extension: 'json',
        maxBytes: _maxBackupBytes,
      );
    } on PickedFileTooLarge {
      toaster.warning(t.backup.legacyRejectedNotBackup);
      return;
    }
    if (picked == null || !context.mounted) return;
  }

  LegacyStaged? staged;
  await runBlocking(
    context,
    message: t.backup.legacyImportWorking,
    work: () async {
      staged = choice == _Source.database
          ? await legacy.stage(found!, replacing: database)
          : await legacy.stageBackup(picked!.bytes, replacing: database);
    },
    onError: (error, stackTrace) =>
        _reportFailure(t, toaster, error, stackTrace),
  );
  final ready = staged;
  if (ready == null) return;
  if (!context.mounted) {
    await reset.discardImport(ready.file);
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      t: t,
      summary: ready.summary,
      isBackup: choice == _Source.backup,
      restartsItself: restartsItself,
    ),
  );
  if (confirmed != true || !context.mounted) {
    await reset.discardImport(ready.file);
    return;
  }
  await runBlocking(
    context,
    message: t.backup.legacyWorking,
    work: () => reset.replaceWithImportAndRestart(
      ready.file,
      afterSwap: () => legacy.writeCredentials(
        ready,
        loggedInPluginIds: ready.keptAccountPluginIds,
      ),
    ),
    onError: (error, stackTrace) {
      unawaited(reset.discardImport(ready.file));
      _reportFailure(t, toaster, error, stackTrace);
    },
  );
}

void _reportFailure(
  Translations t,
  Toaster toaster,
  Object error,
  StackTrace stackTrace,
) {
  if (error is LegacyBackupRejected) {
    toaster.warning(switch (error.reason) {
      LegacyBackupRejection.notBackup => t.backup.legacyRejectedNotBackup,
      LegacyBackupRejection.newerVersion => t.backup.legacyRejectedNewer,
      LegacyBackupRejection.corrupt => t.backup.legacyRejectedCorrupt,
      LegacyBackupRejection.empty => t.backup.legacyRejectedEmpty,
    });
    return;
  }
  final l = t.startup.legacyImport;
  // 同首次啟動（`main.dart`）：轉換步驟的例外訊息可能帶著舊資料的值（曲名、歌單名），不進 log
  // 與錯誤詳情，只留 `LegacyImportFailed` 本身（它的 `toString` 不帶原因）。
  final reported = error is LegacyImportFailed
      ? (error.step == LegacyImportStep.convert ? error : error.cause ?? error)
      : error;
  toaster.error(
    AppError.wrap(reported, stackTrace),
    operation: 'Failed to import the legacy data',
    tag: 'legacy-import',
    sentence: (message) => t.backup.legacyFailed(
      message: error is LegacyImportFailed
          ? switch (error.step) {
              LegacyImportStep.read => l.stepRead,
              LegacyImportStep.convert => l.stepConvert,
              LegacyImportStep.write ||
              LegacyImportStep.swap ||
              LegacyImportStep.credentials => l.stepWrite,
              LegacyImportStep.verify => l.stepVerify,
            }
          : message,
    ),
  );
}

/// 選來源。舊資料庫找不到、平台沒有檔案對話框時，對應的選項不能選。
class _ChooseSourceDialog extends StatelessWidget {
  const _ChooseSourceDialog({
    required this.t,
    required this.hasDatabase,
    required this.hasFiles,
  });

  final Translations t;
  final bool hasDatabase;
  final bool hasFiles;

  @override
  Widget build(BuildContext context) {
    final b = t.backup;
    return AlertDialog(
      title: Text(b.legacyChooseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            enabled: hasDatabase,
            leading: const Icon(Icons.storage_outlined),
            title: Text(
              hasDatabase ? b.legacyFromDatabase : b.legacyFromDatabaseMissing,
            ),
            onTap: () => Navigator.of(context).pop(_Source.database),
          ),
          ListTile(
            enabled: hasFiles,
            leading: const Icon(Icons.description_outlined),
            title: Text(b.legacyFromBackup),
            onTap: () => Navigator.of(context).pop(_Source.backup),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(b.cancel),
        ),
      ],
    );
  }
}

/// 確認框：會取代什麼、保留什麼、要匯入多少。按「取代並重新啟動」才是 `true`。
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.t,
    required this.summary,
    required this.isBackup,
    required this.restartsItself,
  });

  final Translations t;
  final ImportSummary summary;
  final bool isBackup;
  final bool restartsItself;

  // `ImportSummary.collections` 的鍵（轉換器的 `SummaryCollection`，在封住的 `lib/legacy_import/`）。
  int _written(String collection) =>
      summary.collections[collection]?.written ?? 0;

  @override
  Widget build(BuildContext context) {
    final b = t.backup;
    final r = t.legacyResult;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(b.legacyConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.legacyConfirmBody),
            SizedBox(height: spacing.x2),
            Text(restartsItself ? b.restartsItself : b.restartsManually),
            SizedBox(height: spacing.x4),
            Text(b.legacyWillImport, style: theme.textTheme.titleSmall),
            SizedBox(height: spacing.x1),
            Text(r.playlists(count: _written('playlists'))),
            Text(r.tracks(count: _written('tracks'))),
            Text(r.history(count: _written('history'))),
            Text(r.radio(count: _written('radioStations'))),
            if (!isBackup) ...[
              Text(b.legacyQueue(count: _written('queue'))),
              Text(r.accounts(count: _written('accounts'))),
            ],
            if (isBackup) ...[
              SizedBox(height: spacing.x3),
              Text(b.legacyBackupNoQueue),
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
          child: Text(b.legacyConfirm),
        ),
      ],
    );
  }
}
