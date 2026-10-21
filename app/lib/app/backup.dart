import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';

/// 備份檔的 MIME 類型（SQLite 的 IANA 登記）。
const backupMimeType = 'application/vnd.sqlite3';

/// 匯出時暫存的檔名，在資料目錄底下。清完裝置資料之前它含完整的資料，所以用固定的名字：
/// 當機後殘留的，下一次匯出會蓋掉。
const backupExportTempName = 'backup-export.tmp';

/// 備份檔大小的上限；平台在讀進記憶體之前就報得出大小時，超過的直接拒絕。
const backupMaxBytes = 1024 * 1024 * 1024;

/// 備份裡 `installed_plugins` 的一列 → 確認框要列的插件（[DatabaseBackups] 的
/// `readPlugin`，ADR 0034 §決定 4）。
///
/// 確認框的名稱、版本、網域取自**腳本標頭的 manifest**：執行時載入的是
/// `PluginFile.parse(script)`，以它的 id 為鍵、取它的 `allowedHosts`（`PluginRegistry`），
/// 不是 `manifest_json` 欄。列的 `id`、`version`、`manifest_json` 必須和標頭完全一致（安裝時
/// 就是這樣寫入的，`PluginInstaller`），否則以 [BackupRejection.notFmpBackup] 拒絕，確認框
/// 才不會顯示和實際不同的網域。
///
/// 腳本解析不出來（壞了、或 `apiVersion` 這個 App 不支援）的列回 `null`：`stage` 把它從
/// 暫存檔刪掉，還原後不會有它（否則 App 升級到支援那個 `apiVersion` 時它會被自動載入，而
/// 沒有人確認過它的網域），確認框另列。不放寬成讀 JSON 的 `allowedHosts`。
BackupPlugin? readBackupPlugin({
  required String id,
  required String version,
  required String manifestJson,
  required String script,
}) {
  final PluginFile file;
  try {
    file = PluginFile.parse(script);
  } on AppError {
    return null;
  }
  if (file.manifest.id != id ||
      file.manifest.version != version ||
      file.manifestJson != manifestJson) {
    throw const BackupRejected(
      BackupRejection.notFmpBackup,
      'a plugin row does not match its script header',
    );
  }
  return BackupPlugin(
    id: id,
    name: file.manifest.name,
    version: file.manifest.version,
    hosts: file.manifest.allowedHosts,
  );
}

/// 腳本標頭的 `allowedHosts`；讀不出來（載入不了的插件）是空的。
Set<String> _scriptHosts(String script) {
  try {
    return PluginFile.parse(script).manifest.allowedHosts.toSet();
  } on AppError {
    return const {};
  }
}

/// 確認框裡一個插件與這台的對照（ADR 0030 §決定 9 的延伸）。
@immutable
final class BackupPluginReview {
  const BackupPluginReview({
    required this.plugin,
    required this.installedVersion,
    required this.older,
    required this.addedHosts,
  });

  final BackupPlugin plugin;

  /// 這台裝了同 id 的插件時它的版本；沒裝是 `null`。
  final String? installedVersion;

  /// 備份的版本比這台的舊。
  final bool older;

  /// 比這台目前多出來的網域（這台沒裝這個插件時是全部）。
  final List<String> addedHosts;
}

/// 還原確認框要列的全部內容。
@immutable
final class RestoreReview {
  const RestoreReview({
    required this.plugins,
    required this.unusablePluginIds,
    required this.indexUrls,
  });

  final List<BackupPluginReview> plugins;

  /// 這個版本無法使用、不會還原的插件 id。
  final List<String> unusablePluginIds;

  /// 備份會帶進來的自訂插件 index 網址。
  final List<String> indexUrls;
}

/// [staged] 與這台已安裝的 [installed] 的對照。開發標記列不是已安裝的插件；這台的網域取自
/// 腳本標頭（執行時用的），讀不出來當成沒有。
RestoreReview reviewRestore(
  StagedBackup staged,
  List<InstalledPlugin> installed,
) {
  final current = <String, ({String version, Set<String> hosts})>{};
  for (final plugin in installed) {
    if (plugin.fromDevFolder) continue;
    current[plugin.id] = (
      version: plugin.version,
      hosts: _scriptHosts(plugin.script),
    );
  }
  return RestoreReview(
    plugins: [
      for (final plugin in staged.plugins)
        BackupPluginReview(
          plugin: plugin,
          installedVersion: current[plugin.id]?.version,
          older:
              current[plugin.id] != null &&
              isOlderVersion(plugin.version, current[plugin.id]!.version),
          addedHosts: [
            for (final host in plugin.hosts)
              if (!(current[plugin.id]?.hosts.contains(host) ?? false)) host,
          ],
        ),
    ],
    unusablePluginIds: staged.unusablePluginIds,
    indexUrls: staged.indexUrls,
  );
}

/// 設定頁「備份與還原」的匯出，與還原的前半（選檔、驗證）（ADR 0034，M4 design §11）。
///
/// 還原的後半（自動備份、寫入這台的值、換檔、重啟）是 `DataReset.restoreAndRestart`：
/// 設定頁與 Debug 頁走同一條。
abstract interface class AppBackup {
  /// 匯出備份檔：讓使用者選位置存。回傳存好的位置；使用者取消回 `null`。
  Future<Uri?> export();

  /// 讓使用者選備份檔並驗證（[DatabaseBackups.stageBytes]）。使用者取消回 `null`；檔案不能用
  /// 拋 [BackupRejected]。呼叫端用完要交給 `DataReset.restoreAndRestart` 或
  /// `DataReset.discardStaged`。
  Future<StagedBackup?> pickAndStage();
}

final class FileAppBackup implements AppBackup {
  FileAppBackup({
    required this.databaseBackups,
    required this.dataDirectory,
    required this.fileDialogs,
    required this.log,
  });

  final DatabaseBackups databaseBackups;
  final Directory dataDirectory;

  /// 平台沒有檔案對話框時為 `null`：呼叫端不提供這個入口，呼叫了就拋 [UnsupportedError]。
  final FileDialogs? fileDialogs;
  final Log log;

  static const _tag = 'backup';

  @override
  Future<Uri?> export() async {
    final dialogs = _dialogs();
    final temp = File(p.join(dataDirectory.path, backupExportTempName));
    try {
      await databaseBackups.deleteExport(temp);
      await databaseBackups.export(temp);
      final bytes = await temp.readAsBytes();
      final saved = await dialogs.saveFile(
        name: 'fmp-backup-${backupTimestamp(clock.now().toUtc())}.db',
        bytes: bytes,
        mimeType: backupMimeType,
      );
      if (saved != null) log.info('Backup exported', tag: _tag);
      return saved;
    } on Object catch (error, stackTrace) {
      log.error(
        'Failed to export a backup',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      await _deleteTemp(temp);
    }
  }

  @override
  Future<StagedBackup?> pickAndStage() async {
    final PickedFile? picked;
    try {
      picked = await _dialogs().pickFile(
        extension: 'db',
        maxBytes: backupMaxBytes,
      );
    } on PickedFileTooLarge catch (error) {
      // 這麼大的檔不是 FMP 的備份。
      log.warning(
        'A backup file was rejected',
        tag: _tag,
        fields: {'reason': 'tooLarge', 'size': error.size},
      );
      throw const BackupRejected(BackupRejection.notFmpBackup, 'too large');
    }
    if (picked == null) return null;
    try {
      final staged = await databaseBackups.stageBytes(picked.bytes);
      log.info(
        'Backup restore staged',
        tag: _tag,
        fields: {'plugins': staged.plugins.length},
      );
      return staged;
    } on BackupRejected catch (error) {
      log.warning(
        'A backup file was rejected',
        tag: _tag,
        fields: {'reason': error.reason.name, 'detail': error.detail},
      );
      rethrow;
    }
  }

  FileDialogs _dialogs() =>
      fileDialogs ??
      (throw UnsupportedError('This platform has no file dialogs'));

  Future<void> _deleteTemp(File temp) async {
    try {
      await databaseBackups.deleteExport(temp);
    } on FileSystemException catch (error, stackTrace) {
      // 殘留的由下一次匯出蓋掉。
      log.warning(
        'Failed to delete the export temp file',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// 備份檔的讀寫（自動備份、匯出、暫存、換檔）。
final databaseBackupsProvider = Provider<DatabaseBackups>(
  (ref) => DatabaseBackups(
    ref.watch(appDatabaseProvider),
    ref.watch(dataDirectoryProvider),
    ref.watch(logProvider),
    readPlugin: readBackupPlugin,
  ),
);

final appBackupProvider = Provider<AppBackup>(
  (ref) => FileAppBackup(
    databaseBackups: ref.watch(databaseBackupsProvider),
    dataDirectory: ref.watch(dataDirectoryProvider),
    fileDialogs: ref.watch(fileDialogsProvider),
    log: ref.watch(logProvider),
  ),
);
