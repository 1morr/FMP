import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/backup.dart';
import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/backup/legacy_import_flow.dart';
import 'package:fmp/ui/backup/restore_flow.dart';
import 'package:fmp/ui/format/home_path.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 進行中的是哪一件事。
enum _Busy { none, exporting, checking, importing }

/// 設定頁的「備份與還原」組（ADR 0034 §決定 5）：一段說明、「匯出備份」、「從備份檔還原」與
/// 「從舊版匯入…」（M5 design §7.4）。平台沒有檔案對話框（`PlatformCapabilities.files`）時只有
/// 說明。
///
/// 進行中按鈕都停用，進行中的那個顯示進度。還原選好檔、驗證通過後交給
/// [confirmAndRestore]（確認框、自動備份、換檔、重啟）；舊版匯入走 [importFromLegacy]。
/// 找得到舊資料庫、而 `legacy_imports` 沒有紀錄時（例如首次匯入失敗後以空白資料啟動），
/// 按鈕旁多一句提示。
class BackupControls extends ConsumerStatefulWidget {
  const BackupControls({super.key});

  @override
  ConsumerState<BackupControls> createState() => _BackupControlsState();
}

class _BackupControlsState extends ConsumerState<BackupControls> {
  var _busy = _Busy.none;

  void _setBusy(_Busy busy) {
    if (mounted) setState(() => _busy = busy);
  }

  Future<void> _export() async {
    final translations = ref.read(translationsProvider);
    final t = translations.backup;
    final backup = ref.read(appBackupProvider);
    final toaster = ref.read(toasterProvider);
    final home = ref.read(appInfoProvider).homeDirectory;
    _setBusy(_Busy.exporting);
    try {
      final saved = await backup.export();
      // 使用者在存檔對話框取消：什麼都沒寫，不提示。
      if (saved != null) {
        toaster.success(t.exported(location: _location(saved, home)));
      }
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to export a backup',
        tag: 'backup',
        sentence: (message) => t.exportFailed(message: message),
      );
    } finally {
      _setBusy(_Busy.none);
    }
  }

  Future<void> _restore() async {
    final translations = ref.read(translationsProvider);
    final t = translations.backup;
    final backup = ref.read(appBackupProvider);
    final reset = ref.read(dataResetProvider);
    final toaster = ref.read(toasterProvider);
    _setBusy(_Busy.checking);
    final StagedBackup? staged;
    try {
      staged = await backup.pickAndStage();
    } on BackupRejected catch (error) {
      toaster.warning(backupRejectionMessage(translations, error.reason));
      _setBusy(_Busy.none);
      return;
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to read a backup',
        tag: 'backup',
        sentence: (message) => t.restoreFailed(message: message),
      );
      _setBusy(_Busy.none);
      return;
    }
    _setBusy(_Busy.none);
    if (staged == null) return;
    if (!mounted) {
      await reset.discardStaged(staged);
      return;
    }
    await confirmAndRestore(context, ref, staged);
  }

  Future<void> _importLegacy() async {
    _setBusy(_Busy.importing);
    try {
      await importFromLegacy(context, ref);
    } finally {
      _setBusy(_Busy.none);
    }
  }

  /// 存好的位置：檔案路徑把家目錄換成 `~`；Android 的 SAF 給的是 `content://`，照原樣。
  static String _location(Uri uri, String? home) => uri.scheme == 'file'
      ? homeRelativePath(uri.toFilePath(), home)
      : uri.toString();

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).backup;
    final files = ref.watch(platformCapabilitiesProvider).files;
    final spacing = AppTokens.of(context).spacing;
    const progress = SizedBox.square(
      dimension: AppLayout.buttonSpinner,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    final idle = _busy == _Busy.none;
    final offer = ref.watch(legacyImportOfferProvider).value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.intro),
        if (files) ...[
          SizedBox(height: spacing.x4),
          Wrap(
            spacing: spacing.x3,
            runSpacing: spacing.x3,
            children: [
              FilledButton.icon(
                onPressed: idle ? () => unawaited(_export()) : null,
                icon: _busy == _Busy.exporting
                    ? progress
                    : const Icon(Icons.file_upload_outlined),
                label: Text(
                  _busy == _Busy.exporting ? t.exportWorking : t.export,
                ),
              ),
              OutlinedButton.icon(
                onPressed: idle ? () => unawaited(_restore()) : null,
                icon: _busy == _Busy.checking
                    ? progress
                    : const Icon(Icons.settings_backup_restore),
                label: Text(
                  _busy == _Busy.checking ? t.stageWorking : t.restore,
                ),
              ),
              OutlinedButton.icon(
                onPressed: idle ? () => unawaited(_importLegacy()) : null,
                // 進行中的畫面是對話框（進度、確認），按鈕只停用，不轉圈。
                icon: const Icon(Icons.history),
                label: Text(t.legacyImport),
              ),
            ],
          ),
          if (offer != null && offer.source != null && !offer.imported) ...[
            SizedBox(height: spacing.x3),
            Text(t.legacyHint),
          ],
        ],
      ],
    );
  }
}
