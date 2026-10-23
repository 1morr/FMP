import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';

const _tag = 'legacy-import';

/// 要不要自動匯入：資料目錄還沒有 `fmp.db`。有了就不再自動匯入，包括失敗頁的「以空白資料
/// 啟動」之後（建空庫就有了 `fmp.db`）；之後只能從設定頁匯入（M5 design §3.1）。
bool needsFirstLaunchImport(Directory dataDirectory) =>
    !File(p.join(dataDirectory.path, databaseFileName)).existsSync();

/// 首次啟動匯入的結果。
final class FirstLaunchImported {
  const FirstLaunchImported({required this.failedCredentials});

  /// 資料庫換上之後寫憑證失敗的插件 id：帳號列在 `CredentialStore` 載入時會被對齊刪掉，
  /// 需要重新登入；呼叫端開庫之後補記進匯入紀錄。
  final Set<String> failedCredentials;
}

/// 首次啟動的匯入（M5 design §3.1）：[LegacyImport.stage] 通過後，把暫存庫改名成 [target]
/// （`<資料目錄>/fmp.db`，同一個目錄），再寫憑證。
///
/// 憑證在改名之後才寫：先寫憑證、換檔再失敗，會留下沒有帳號列的 cookie（首次啟動沒有已安裝的
/// 插件，`CredentialStore` 不會去清它）；反過來寫憑證失敗，只是已換上的庫裡有帳號列、secure
/// storage 沒有憑證，`CredentialStore` 載入時把那一列刪掉，結果是需要重新登入。
///
/// rename 之前的任何失敗都拋 [LegacyImportFailed]：沒有 [target]、沒有暫存檔、舊檔沒動。
/// [onStaged] 在暫存庫驗證通過時收到摘要（失敗頁的診斷用）。
Future<FirstLaunchImported> importOnFirstLaunch({
  required LegacyImport legacy,
  required LegacySource source,
  required File target,
  required Log log,
  void Function(LegacyImportStep step)? progress,
  void Function(ImportSummary summary)? onStaged,
}) async {
  final staged = await legacy.stage(source, progress: progress);
  onStaged?.call(staged.summary);
  progress?.call(LegacyImportStep.swap);
  try {
    // 不蓋掉既有的庫：呼叫端只在沒有 `fmp.db` 時才進來。
    if (target.existsSync()) {
      throw const FileSystemException('The database file already exists');
    }
    await staged.file.rename(target.path);
  } on Object catch (error) {
    await _deleteDatabaseFiles(staged.file, log);
    throw LegacyImportFailed(
      LegacyImportStep.swap,
      'Moving the imported database into place failed',
      cause: error,
    );
  }
  progress?.call(LegacyImportStep.credentials);
  Set<String> failed;
  try {
    // 首次啟動沒有已登入的平台。
    failed = await legacy.writeCredentials(staged, loggedInPluginIds: const {});
  } on Object catch (error) {
    // 介面約定不拋例外；真的拋了就當全部寫失敗，不擋啟動。
    log.warning(
      'Writing the imported credentials failed',
      tag: _tag,
      fields: {'errorType': '${error.runtimeType}'},
    );
    failed = staged.credentials.keys.toSet();
  }
  log.info(
    'Legacy data imported',
    tag: _tag,
    fields: {'failedCredentials': failed.toList()},
  );
  return FirstLaunchImported(failedCredentials: failed);
}

Future<void> _deleteDatabaseFiles(File file, Log log) async {
  for (final path in [
    file.path,
    '${file.path}-wal',
    '${file.path}-shm',
    '${file.path}-journal',
  ]) {
    try {
      final entity = File(path);
      if (entity.existsSync()) await entity.delete();
    } on FileSystemException catch (error) {
      log.warning(
        'Deleting the staging database failed',
        tag: _tag,
        fields: {'errorType': '${error.runtimeType}'},
      );
    }
  }
}
