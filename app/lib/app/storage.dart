import 'dart:io';

import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/data/queue_store.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:fmp/platform/database_file.dart';

/// 啟動時開好的儲存：`main` 把四個值 override 進 `appDatabaseProvider`、
/// `savedQueueProvider`、`savedSettingsProvider`、[storageNoticeProvider]。
typedef Storage = ({
  AppDatabase? database,
  SavedQueue? saved,
  Map<String, String> settings,
  StorageNotice? notice,
});

const Storage _unavailable = (
  database: null,
  saved: null,
  settings: {},
  notice: StorageNotice.databaseUnavailable,
);

/// 開 [file] 上的資料庫、讀回上次的佇列與設定。設定讀不回來時用預設值，
/// 不另存（設定只是偏好，重選就好）。讀不回來的資料不靜靜蓋掉，先另存
/// 成 [unreadableBackupFile]（[now] 決定檔名），照 Firefox 把壞掉的
/// `places.sqlite` 另存的慣例：
///
/// - 資料庫檔本身壞了（[isCorruptDatabase]）：把它連同 `-wal`、`-shm`、
///   `-journal` 改名成另存的檔，開一個新的空資料庫，提示
///   [StorageNotice.queueUnreadable]。
/// - 檔案沒壞、存的佇列對不起來：整個資料庫複製成另存的檔（`VACUUM INTO`），
///   清掉存的佇列，從空佇列開始，提示 [StorageNotice.queueUnreadable]。
/// - 其他原因開不了（權限、磁碟滿），或另存也失敗：這次不保存（`database`
///   是 null），原本的檔不動，提示 [StorageNotice.databaseUnavailable]。
///
/// log 只寫原因（例外與堆疊），不寫曲目等內容。
Future<Storage> openStorage(
  File file,
  Log log, {
  DateTime Function() now = DateTime.now,
}) async {
  try {
    return await _openAndRestore(file, log, now);
  } catch (error, stackTrace) {
    if (!isCorruptDatabase(error)) {
      log.error(
        'Opening the database failed; nothing will be saved this time',
        error: error,
        stackTrace: stackTrace,
      );
      return _unavailable;
    }
    log.error(
      'The database file is corrupt',
      error: error,
      stackTrace: stackTrace,
    );
  }
  final backup = unreadableBackupFile(file, now());
  try {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final part = File('${file.path}$suffix');
      if (part.existsSync()) await part.rename('${backup.path}$suffix');
    }
    final database = await _open(file, log);
    log.warning(
      'Moved the corrupt database to ${_name(backup)}; started a new one',
    );
    return (
      database: database,
      saved: null,
      settings: const <String, String>{},
      notice: StorageNotice.queueUnreadable,
    );
  } catch (error, stackTrace) {
    log.error(
      'Moving the corrupt database aside failed; nothing will be saved this '
      'time',
      error: error,
      stackTrace: stackTrace,
    );
    return _unavailable;
  }
}

/// 開資料庫並讀回佇列；資料庫壞了或開不了就關掉它、丟出去。
Future<Storage> _openAndRestore(
  File file,
  Log log,
  DateTime Function() now,
) async {
  final database = await _open(file, log);
  try {
    return await _restore(database, file, log, now);
  } catch (_) {
    await _closeQuietly(database);
    rethrow;
  }
}

/// 開在 [file] 上，查一次讓它真的開起來（建立或升級跑完）；開不了就關掉、
/// 丟出去。
Future<AppDatabase> _open(File file, Log log) async {
  final database = AppDatabase.open(file);
  try {
    final version = await database.storedSchemaVersion();
    log.info('Database opened, schema version $version');
    return database;
  } catch (_) {
    await _closeQuietly(database);
    rethrow;
  }
}

/// 讀回佇列與設定；存的佇列對不起來就另存一份再清掉。資料庫檔壞了就丟出去。
Future<Storage> _restore(
  AppDatabase database,
  File file,
  Log log,
  DateTime Function() now,
) async {
  final settings = await _loadSettings(database, log);
  final store = QueueStore(database);
  try {
    return (
      database: database,
      saved: await store.load(),
      settings: settings,
      notice: null,
    );
  } catch (error, stackTrace) {
    if (isCorruptDatabase(error)) rethrow;
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
    if (isCorruptDatabase(error)) rethrow;
    log.error(
      'Keeping a copy of the unreadable queue failed; nothing will be saved '
      'this time',
      error: error,
      stackTrace: stackTrace,
    );
    await _closeQuietly(database);
    return _unavailable;
  }
  log.warning(
    'Kept the unreadable queue in ${_name(backup)}; starting with an empty '
    'queue',
  );
  return (
    database: database,
    saved: null,
    settings: settings,
    notice: StorageNotice.queueUnreadable,
  );
}

/// 讀不回來時用預設值；資料庫檔壞了就丟出去。
Future<Map<String, String>> _loadSettings(AppDatabase database, Log log) async {
  try {
    return await SettingsStore(database).load();
  } catch (error, stackTrace) {
    if (isCorruptDatabase(error)) rethrow;
    log.error(
      'Restoring the settings failed; using the defaults',
      error: error,
      stackTrace: stackTrace,
    );
    return const {};
  }
}

Future<void> _closeQuietly(AppDatabase database) async {
  try {
    await database.close();
  } catch (_) {
    // 本來就沒開起來，關不了也沒關係。
  }
}

String _name(File file) => file.uri.pathSegments.last;
