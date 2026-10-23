import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import 'package:fmp/app/diagnostics/diagnostics_report.dart';
import 'package:fmp/app/diagnostics/diagnostics_service.dart';
import 'package:fmp/app/diagnostics/diagnostics_zip.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/platform/files/files.dart';

/// 啟動失敗時（資料庫開不起來、舊資料匯入失敗）的「匯出診斷」（M5 design §3.1、§7.2）。
///
/// 此時 Riverpod 的 App 組裝還沒有，所以不是 `DiagnosticsService`：存一個 zip，裡面是
/// `diagnostics.txt`（哪一步、錯誤、各 collection 的筆數；經 [Redactor]）加全部的 log 檔
/// （以現在的遮蔽函式重遮）。不含歌單名稱、曲名與憑證：內容只有識別字、筆數與已遮蔽的錯誤訊息。
final class StartupDiagnostics {
  StartupDiagnostics({
    required this.flavor,
    required this.redactor,
    required this.logFile,
    required this.fileDialogs,
  });

  final AppFlavor flavor;
  final Redactor redactor;

  /// 沒有資料目錄的平台為 `null`，診斷包就沒有 log 檔。
  final LogFile? logFile;

  /// 平台沒有檔案對話框時為 `null`；呼叫端不顯示「匯出診斷」。
  final FileDialogs? fileDialogs;

  bool get canExport => fileDialogs != null;

  /// 讓使用者選位置存檔；取消回 `false`。[kind] 是情境（`legacyImport`、`databaseOpen`），
  /// [step] 是失敗的步驟（識別字），[details] 只放 JSON 能表示、且不含使用者資料的值。
  Future<bool> export({
    required String kind,
    required Object error,
    String? step,
    Map<String, Object?> details = const {},
  }) async {
    final report = DiagnosticsReport.build({
      'generatedAt': clock.now().toUtc().toIso8601String(),
      'flavor': flavor.name,
      'kind': kind,
      'step': ?step,
      'error': '$error',
      'errorType': '${error.runtimeType}',
      ...details,
    }, redactor);
    final logs = await redactLogFiles(
      await logFile?.readAll() ?? const [],
      redactor,
    );
    final bytes = await zipEntries([
      ZipEntry('diagnostics.txt', Uint8List.fromList(utf8.encode(report.text))),
      ...logs,
    ]);
    final saved = await fileDialogs!.saveFile(
      name: 'fmp-startup-diagnostics-${_timestamp()}.zip',
      bytes: bytes,
      mimeType: diagnosticsMimeType,
    );
    return saved != null;
  }

  /// 檔名裡的本機時間，不含冒號（Windows 的檔名不能有）。
  static String _timestamp() {
    final now = clock.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

/// 匯入摘要的各 collection 筆數（讀到、寫入、略過），給診斷的 `details`。只有識別字與數字。
Map<String, Object?> summaryDiagnostics(ImportSummary summary) => {
  'collections': {
    for (final MapEntry(:key, :value) in summary.collections.entries)
      key: {
        'read': value.read,
        'written': value.written,
        'skipped': value.skipped.values.fold<int>(0, (a, b) => a + b),
      },
  },
};
