import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/diagnostics/diagnostics_service.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/ui/errors/submit_reminder.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/toast/toaster.dart';

// Debug 頁的診斷包與 log 檔匯出（ADR 0025 §決定 3、10，M3 design §12.4）。

/// 匯出什麼：診斷包（摘要加 log 檔），或只有 log 檔。
enum ExportKind { diagnostics, logs }

/// 匯出到哪裡：存成檔案（桌面的存檔對話框、Android 的 SAF），或系統的分享視窗。
enum ExportAction { save, share }

/// 把純文字摘要複製到剪貼簿（「複製」）。複製不開對話框、不寫檔，所以沒有「送出前請檢查」。
Future<void> copyDiagnosticsSummary(WidgetRef ref) async {
  final t = ref.read(translationsProvider).debug;
  final toaster = ref.read(toasterProvider);
  final service = ref.read(diagnosticsServiceProvider);
  try {
    final report = await service.report();
    await Clipboard.setData(ClipboardData(text: report.text));
    toaster.info(t.diagnosticsCopied);
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to build the diagnostics summary',
      tag: 'debug',
      sentence: (message) => t.exportFailed(message: message),
    );
  }
}

/// 匯出 [kind]：第一次先提醒「送出前請檢查」（與 GitHub 回報共用「不再提醒」），再組裝並存檔
/// 或分享。存檔時使用者取消不提示；失敗經 `toaster.error` 進錯誤歷史並顯示原因。
Future<void> exportBundle(
  BuildContext context,
  WidgetRef ref, {
  required ExportKind kind,
  required ExportAction action,
}) async {
  final t = ref.read(translationsProvider).debug;
  final toaster = ref.read(toasterProvider);
  final service = ref.read(diagnosticsServiceProvider);
  final exporter = ref.read(diagnosticsExporterProvider);
  final log = ref.read(logProvider);
  if (!await confirmSubmitReminder(context, ref, body: t.exportReminderBody)) {
    return;
  }
  try {
    final bundle = switch (kind) {
      ExportKind.diagnostics => await service.diagnosticsBundle(),
      ExportKind.logs => await service.logsBundle(),
    };
    switch (action) {
      case ExportAction.save:
        // 使用者在存檔對話框取消：什麼都沒寫，不提示也不記「已匯出」。
        if (!await exporter.save(bundle)) return;
        toaster.success(t.exportSaved);
      case ExportAction.share:
        await exporter.share(bundle);
    }
    log.info(
      'Exported a diagnostics file',
      tag: 'debug',
      fields: {'kind': kind.name, 'action': action.name},
    );
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to export the ${kind.name} file',
      tag: 'debug',
      sentence: (message) => t.exportFailed(message: message),
    );
  }
}
