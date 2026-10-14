import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/app/diagnostics/diagnostics_report.dart';
import 'package:fmp/app/diagnostics/diagnostics_zip.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/share/share.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/settings/network_settings.dart';
import 'package:fmp/settings/playback_settings.dart';

/// 分享用的 zip 暫存的目錄名，在資料目錄底下。殘留的由啟動維護清單刪掉
/// （[deleteDiagnosticsTemp]）。
const diagnosticsTempDirectoryName = 'diagnostics-tmp';

/// 診斷包的 MIME 類型。
const diagnosticsMimeType = 'application/zip';

/// 要存檔或分享的一個 zip。
@immutable
final class DiagnosticsBundle {
  const DiagnosticsBundle({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// 組裝診斷包（ADR 0025 §決定 10）：產生時組裝一次，匯出只用這份結果。
///
/// 內容是版本、平台、語系、各插件的 id／版本／啟用與是否登入（是／否）、非敏感設定的摘要，
/// 加上 log 檔；不含帳號名稱、硬體識別（輸出裝置的名稱）、歌單內容（ADR 0011 §決定 6）。
final class DiagnosticsService {
  DiagnosticsService({
    required this.redactor,
    required this.logFile,
    required this.collect,
  });

  final Redactor redactor;

  /// 沒有資料目錄的平台為 `null`，診斷包就沒有 log 檔。
  final LogFile? logFile;

  /// 目前的狀態，只放 JSON 能表示的值；內容見 [diagnosticsDataProvider]。
  final Future<Map<String, Object?>> Function() collect;

  Future<DiagnosticsReport> report() async =>
      DiagnosticsReport.build(await collect(), redactor);

  /// `diagnostics.txt`、`diagnostics.json` 加上全部的 log 檔。
  Future<DiagnosticsBundle> diagnosticsBundle() async {
    final report = await this.report();
    final logs = await _logEntries();
    return DiagnosticsBundle(
      fileName: 'fmp-diagnostics-${_timestamp()}.zip',
      bytes: await zipEntries([
        ZipEntry('diagnostics.txt', _utf8(report.text)),
        ZipEntry('diagnostics.json', _utf8(report.json)),
        ...logs,
      ]),
    );
  }

  /// 只有 log 檔（Debug 頁 Log 區塊的「匯出 log 檔」）。
  Future<DiagnosticsBundle> logsBundle() async => DiagnosticsBundle(
    fileName: 'fmp-logs-${_timestamp()}.zip',
    bytes: await zipEntries(await _logEntries()),
  );

  /// 全部的 log 檔，以目前的遮蔽函式再遮一次（[redactLogFiles]）。
  Future<List<ZipEntry>> _logEntries() async =>
      redactLogFiles(await logFile?.readAll() ?? const [], redactor);

  /// 檔名裡的本機時間，不含冒號（Windows 的檔名不能有）。
  static String _timestamp() {
    final now = clock.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

/// 以 [redactor] 再遮一次 log 檔（[redactLogLines]），在另一個 isolate 做（最多 6MB）。
///
/// log 檔寫入時已經遮蔽，但家目錄登記之前（更早的版本）或憑證值登記之前寫的行仍帶原值；
/// 診斷包要送出裝置，送出前以現在的名單重遮。檔名照舊，輸出仍是 JSON Lines。
///
/// 頂層函數：`Isolate.run` 的閉包只帶 [files] 與 [redactor]，不帶 [DiagnosticsService]
/// （它的 `collect` 抓著 `ref`，送不進 isolate）。
Future<List<ZipEntry>> redactLogFiles(
  List<({String name, Uint8List bytes})> files,
  Redactor redactor,
) {
  if (files.isEmpty) return Future.value(const []);
  return Isolate.run(
    () => [
      for (final file in files)
        ZipEntry(
          file.name,
          _utf8(
            redactLogLines(
              utf8.decode(file.bytes, allowMalformed: true),
              redactor,
            ),
          ),
        ),
    ],
  );
}

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

/// 存檔與分享診斷包。
final class DiagnosticsExporter {
  DiagnosticsExporter({
    required this.fileDialogs,
    required this.fileSharer,
    required this.tempDirectory,
    required this.log,
  });

  /// 平台沒有檔案對話框時為 `null`；呼叫端依能力宣告決定要不要提供存檔。
  final FileDialogs? fileDialogs;

  /// 平台沒有檔案分享時為 `null`。
  final FileSharer? fileSharer;

  /// 分享用的 zip 暫存在這裡（[diagnosticsTempDirectoryName]）。
  final Directory tempDirectory;

  final Log log;

  /// 讓使用者選位置存檔。取消回 `false`，什麼都沒寫。
  Future<bool> save(DiagnosticsBundle bundle) async {
    final saved = await fileDialogs!.saveFile(
      name: bundle.fileName,
      bytes: bundle.bytes,
      mimeType: diagnosticsMimeType,
    );
    return saved != null;
  }

  /// 寫進暫存、開系統的分享視窗。分享視窗開不起來時刪掉暫存檔並拋出。
  ///
  /// 平台回報分享結束（[FileSharer.shareFiles] 回 `true`）就刪暫存檔；Windows 的分享視窗開了
  /// 就回傳、接收端之後才讀檔，所以不刪，留給下一次分享前的清理與啟動維護。
  Future<void> share(DiagnosticsBundle bundle) async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
    await tempDirectory.create(recursive: true);
    final file = File(p.join(tempDirectory.path, bundle.fileName));
    await file.writeAsBytes(bundle.bytes, flush: true);
    try {
      final finished = await fileSharer!.shareFiles([
        file.path,
      ], mimeType: diagnosticsMimeType);
      if (finished) await _delete(file);
    } on Object {
      await _delete(file);
      rethrow;
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error, stackTrace) {
      // 殘留的由下一次分享前的清理與啟動維護清單刪掉。
      log.warning(
        'Deleting the shared diagnostics file failed',
        tag: 'debug',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// 刪掉資料目錄底下殘留的分享暫存（啟動維護清單的「診斷包暫存」）。回傳刪了幾個檔案。
/// 只動 [diagnosticsTempDirectoryName] 這一個目錄。
Future<int> deleteDiagnosticsTemp(Directory dataDirectory) async {
  final directory = Directory(
    p.join(dataDirectory.path, diagnosticsTempDirectoryName),
  );
  if (!await directory.exists()) return 0;
  var count = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) count++;
  }
  await directory.delete(recursive: true);
  return count;
}

/// 診斷包的資料：產生時讀一次目前的狀態。欄位名避開遮蔽名單的鍵名（`…sid`、`…token`）。
final diagnosticsDataProvider =
    Provider<Future<Map<String, Object?>> Function()>(
      (ref) => () async {
        final info = ref.read(appInfoProvider);
        // 設定的 Notifier 是 Stream：沒有人聽的時候不會發值，讀一次的這段時間先聽著。
        final listening = [
          ref.listen(appearanceProvider, (_, _) {}),
          ref.listen(networkProvider, (_, _) {}),
          ref.listen(playbackPreferencesProvider, (_, _) {}),
          ref.listen(developerProvider, (_, _) {}),
        ];
        final Appearance appearance;
        final Network network;
        final PlaybackPreferences playback;
        final Developer developer;
        try {
          appearance = await ref.read(appearanceProvider.future);
          network = await ref.read(networkProvider.future);
          playback = await ref.read(playbackPreferencesProvider.future);
          developer = await ref.read(developerProvider.future);
        } finally {
          for (final subscription in listening) {
            subscription.close();
          }
        }
        final credentials = ref.read(credentialStoreProvider);
        final plugins = <Map<String, Object?>>[];
        for (final plugin in await ref.read(pluginRepositoryProvider).list()) {
          final entry = <String, Object?>{
            'id': plugin.id,
            'version': plugin.version,
            'enabled': plugin.enabled,
          };
          if (_declaresLogin(plugin.manifestJson)) {
            // 只說登入與否與憑證能不能用；帳號名稱不放。
            final state = await credentials.state(plugin.id);
            entry['loggedIn'] = state != CredentialState.none;
            entry['credentials'] = state.name;
          }
          plugins.add(entry);
        }
        final logFile = ref.read(logProvider).file;
        return {
          'generatedAt': clock.now().toUtc().toIso8601String(),
          'app': {
            'version': info.version,
            'flavor': ref.read(appFlavorProvider).name,
            'buildMode': kReleaseMode
                ? 'release'
                : kProfileMode
                ? 'profile'
                : 'debug',
          },
          'platform': {
            'name': info.platform,
            'osVersion': info.osVersion,
            // 路徑含使用者名稱時，家目錄在 [Redactor] 已換成 `~`。
            'dataDirectory': ref.read(dataDirectoryProvider).path,
          },
          'locale': {
            'ui': appearance.locale.name,
            'system': [
              for (final locale in ref.read(systemLocalesProvider))
                locale.toLanguageTag(),
            ],
          },
          'plugins': plugins,
          'settings': {
            'appearance': {'themeMode': appearance.themeMode.name},
            'network': {'cacheLimitMebibytes': network.cacheLimitMebibytes},
            'playback': {
              'audioQuality': playback.audioQuality.name,
              'audioFormatPriority': playback.audioFormatPriority.name,
              'rememberPosition': playback.rememberPosition,
              'tempPlayRewindSeconds': playback.tempPlayRewindSeconds,
              'skipPreviewClips': playback.skipPreviewClips,
              // 輸出裝置的名稱是硬體識別，只說有沒有選。
              'outputDeviceSelected': playback.outputDevice != null,
              'restartRewindSeconds': playback.restartRewindSeconds,
              'playHistoryLimit': playback.playHistoryLimit,
              'autoScrollToCurrent': playback.autoScrollToCurrent,
            },
            'developer': {
              'developerMode': developer.developerMode,
              'logLevel': developer.logLevel.name,
              // 路徑可能含使用者名稱：只說有沒有設。
              'pluginDevFolderSet': developer.stored.pluginDevFolder != null,
              'reportReminderDismissed':
                  developer.stored.reportReminderDismissed ?? false,
            },
          },
          'log': {
            'hasFile': logFile != null,
            'writeFailures': logFile?.failureCount ?? 0,
          },
        };
      },
    );

bool _declaresLogin(String manifestJson) {
  try {
    return PluginManifest.parse(manifestJson).login != null;
  } on AppError {
    return false;
  }
}

final diagnosticsServiceProvider = Provider<DiagnosticsService>(
  (ref) => DiagnosticsService(
    redactor: ref.watch(redactorProvider),
    logFile: ref.watch(logProvider).file,
    collect: ref.watch(diagnosticsDataProvider),
  ),
);

final diagnosticsExporterProvider = Provider<DiagnosticsExporter>(
  (ref) => DiagnosticsExporter(
    fileDialogs: ref.watch(fileDialogsProvider),
    fileSharer: ref.watch(fileSharerProvider),
    tempDirectory: Directory(
      p.join(
        ref.watch(dataDirectoryProvider).path,
        diagnosticsTempDirectoryName,
      ),
    ),
    log: ref.watch(logProvider),
  ),
);
