import 'dart:io';

import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/data/queue_store.dart';
import 'package:fmp/platform/database_file.dart';

/// 啟動時開好的儲存：`main` 把三個值 override 進 `appDatabaseProvider`、
/// `savedQueueProvider`、[storageNoticeProvider]。
typedef Storage = ({
  AppDatabase? database,
  SavedQueue? saved,
  StorageNotice? notice,
});

/// 開 [file] 上的資料庫、讀回上次的佇列。
///
/// - 開不了：不保存（`database` 是 null），提示 [StorageNotice.databaseUnavailable]。
/// - 佇列讀不回來：不靜靜蓋掉。整個資料庫先另存成 [unreadableBackupFile]
///   （[now] 決定檔名），再清掉存的佇列、從空佇列開始，提示
///   [StorageNotice.queueUnreadable]；之後的寫入只動原本的檔，不碰另存的
///   那份。連另存都失敗時當成開不了，這次不保存，壞掉的資料留在原處。
///
/// log 只寫原因（例外與堆疊），不寫曲目等內容。
Future<Storage> openStorage(
  File file,
  Log log, {
  DateTime Function() now = DateTime.now,
}) async {
  final database = await AppDatabase.openOrNull(file, log);
  if (database == null) {
    return (
      database: null,
      saved: null,
      notice: StorageNotice.databaseUnavailable,
    );
  }
  final store = QueueStore(database);
  try {
    return (database: database, saved: await store.load(), notice: null);
  } catch (error, stackTrace) {
    log.error(
      'Restoring the saved queue failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
  final backup = unreadableBackupFile(file, now());
  try {
    await database.copyTo(backup);
    await store.clear();
  } catch (error, stackTrace) {
    log.error(
      'Keeping a copy of the unreadable queue failed; nothing will be saved '
      'this time',
      error: error,
      stackTrace: stackTrace,
    );
    await database.close();
    return (
      database: null,
      saved: null,
      notice: StorageNotice.databaseUnavailable,
    );
  }
  log.warning(
    'Kept the unreadable queue in ${backup.uri.pathSegments.last}; '
    'starting with an empty queue',
  );
  return (
    database: database,
    saved: null,
    notice: StorageNotice.queueUnreadable,
  );
}
