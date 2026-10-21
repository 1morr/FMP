import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/open_app_database.dart';

/// 備份放在資料目錄底下的這個子目錄（ADR 0025 §決定 9）。
const backupDirectoryName = 'backups';

/// 一份備份：`backups/fmp-<UTC 時間>.db`，是一個完整的 SQLite 檔。
@immutable
final class DatabaseBackup {
  const DatabaseBackup({
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String path;

  /// 建立時間（UTC），讀自檔名。
  final DateTime createdAt;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is DatabaseBackup &&
      other.path == path &&
      other.createdAt == createdAt &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(path, createdAt, sizeBytes);
}

/// 資料庫檔的備份、匯出、還原與刪除（ADR 0025 §決定 8、9，ADR 0034，M4 design §11）。
///
/// [create] 是重設與還原前的自動備份：`VACUUM INTO` 的整份副本，放
/// `backups/fmp-<UTC 時間>.db`，時間不含冒號（Windows 檔名不准）。[export] 是交給使用者的
/// 備份檔：同樣的副本，再去掉這台的裝置資料與帳號資料（[backupExcludedTables]、
/// [backupDeviceColumns]）。憑證在 secure storage、不在資料庫，兩種都不含。
///
/// 還原是 [stageBytes]／[stageFile]（驗證並 migration 成暫存檔）→ [carryOver]（寫入這台的
/// 值）→ [restoreStaged]（換檔）。[restoreStaged] 與 [erase] 會先關閉資料庫：呼叫之後這個 App
/// 行程裡的資料庫不能再用，呼叫端接著重啟。
final class DatabaseBackups {
  DatabaseBackups(
    this._database,
    this._dataDirectory,
    this._log, {
    required this._readPlugin,
  });

  /// 把 `installed_plugins` 的一列轉成確認框要列的插件；列與腳本標頭不一致就拋
  /// [BackupRejected]。資料層不認得插件的格式，由 `lib/app/backup.dart` 提供。
  final BackupPluginReader _readPlugin;

  final AppDatabase _database;
  final Directory _dataDirectory;
  final Log _log;

  static const _tag = 'data';

  var _closed = false;

  /// [restoreStaged] 或 [erase] 已經開始關閉資料庫：之後不論成功或失敗，這個行程裡的資料庫都不能
  /// 再用，呼叫端要結束行程（失敗時也一樣，`DataReset` 據此照樣重啟）。
  bool get isClosed => _closed;

  Directory get _backupDirectory =>
      Directory(p.join(_dataDirectory.path, backupDirectoryName));

  File get _databaseFile => File(p.join(_dataDirectory.path, databaseFileName));

  /// 把目前的資料庫複製成一份新備份。失敗（磁碟滿、同一毫秒已有同名檔）就拋出，並清掉
  /// 寫到一半的檔。
  Future<DatabaseBackup> create() async {
    final now = clock.now().toUtc();
    await _backupDirectory.create(recursive: true);
    final file = File(p.join(_backupDirectory.path, 'fmp-${_stamp(now)}.db'));
    // VACUUM INTO 要求目標不存在，存在時 SQLite 自己會報錯；先擋是為了不去刪別人的檔。
    if (await file.exists()) {
      throw FileSystemException('The backup already exists', file.path);
    }
    try {
      await _database.customStatement('VACUUM INTO ?', [file.path]);
    } on Object {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (error, stackTrace) {
        // 清不掉就留著；原本的錯誤比較重要，這裡只記下來。
        _log.warning(
          'Failed to delete a partial backup',
          tag: _tag,
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
    return DatabaseBackup(
      path: file.path,
      createdAt: now,
      sizeBytes: await file.length(),
    );
  }

  /// `backups/` 裡的備份，最新的在前。沒有目錄、檔名不是備份格式的檔都略過。
  Future<List<DatabaseBackup>> list() async {
    final directory = _backupDirectory;
    if (!await directory.exists()) return const [];
    final backups = <DatabaseBackup>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final createdAt = _parseStamp(p.basename(entity.path));
      if (createdAt == null) continue;
      backups.add(
        DatabaseBackup(
          path: entity.path,
          createdAt: createdAt,
          sizeBytes: await entity.length(),
        ),
      );
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// 備份檔還在、而且不是空的（重設前的最後一道確認）。
  Future<bool> exists(DatabaseBackup backup) async {
    final file = File(backup.path);
    return await file.exists() && await file.length() > 0;
  }

  /// 匯出給使用者的備份檔（ADR 0034 §決定 1）：`VACUUM INTO` 到 [target] 旁的暫存檔 →
  /// 清掉不帶走的資料 → `VACUUM`（刪掉的列不留在空閒頁）→ 改名成 [target]。開始與失敗時
  /// 刪掉暫存檔與兩個檔案的 `-journal`、`-wal`、`-shm`。
  ///
  /// 暫存檔在清完之前含完整的資料（包括 cookie），所以清除緊接在 `VACUUM INTO` 之後。
  Future<void> export(File target) async {
    final partial = File('${target.path}.partial');
    try {
      await _deleteWithSidecars(partial);
      await _deleteSidecars(target);
      await _database.customStatement('VACUUM INTO ?', [partial.path]);
      final path = partial.path;
      await Isolate.run(() => _scrubExport(path));
      await partial.rename(target.path);
    } on Object {
      await _deleteWithSidecars(partial);
      await _deleteSidecars(target);
      rethrow;
    }
  }

  /// 刪掉 [export] 的結果 [target] 與它的暫存、旁檔（交給使用者之後）。
  Future<void> deleteExport(File target) async {
    await _deleteWithSidecars(target);
    await _deleteWithSidecars(File('${target.path}.partial'));
  }

  /// 把使用者選的檔案內容 [bytes] 寫成暫存檔並驗證（見 [_stage]）。
  Future<StagedBackup> stageBytes(Uint8List bytes) =>
      _stage((file) => file.writeAsBytes(bytes, flush: true));

  /// 把 [source]（`backups/` 裡的檔）複製成暫存檔並驗證（見 [_stage]）。
  Future<StagedBackup> stageFile(File source) =>
      _stage((file) => source.copy(file.path));

  /// 暫存檔寫到 `backups/staged-<UTC>.db`，依序檢查：SQLite 標頭、`user_version`、
  /// `integrity_check`、沒有 trigger／view、以 App 的 migration 開到目前版本、`sqlite_master`
  /// 的（類型, 名稱）與全新資料庫一致、插件列與腳本標頭一致；最後 schema 由 App 自己重建
  /// （[_rebuild]）。任何一步失敗就刪暫存、拋 [BackupRejected]；目前的資料庫不動。
  ///
  /// 備份檔是外來的檔案，而 [carryOver] 會在它上面寫入，裡面的 trigger 會被觸發：
  /// 每個連線都先 `PRAGMA trusted_schema = OFF`，而且 trigger、view、不認得的物件一律拒絕
  /// （App 的 schema 從來沒有 trigger 與 view）。
  Future<StagedBackup> _stage(Future<void> Function(File file) write) async {
    await _backupDirectory.create(recursive: true);
    await _deleteStaleStaged();
    final file = File(
      p.join(_backupDirectory.path, 'staged-${_stamp(clock.now().toUtc())}.db'),
    );
    try {
      await write(file);
      final path = file.path;
      final current = _database.schemaVersion;
      final (rejection, detail) = await Isolate.run(
        () => _inspect(path, current),
      );
      if (rejection != null) throw BackupRejected(rejection, detail);
      await _migrateAndCheck(file);
      await _rebuild(file);
      // 插件清單與 index 網址從重建好的檔讀：欄位型別是 App 定義的，備份檔自己的型別
      // （例如拿掉型別的 `from_dev_folder`）騙不了過濾。
      return await _readRebuilt(file);
    } on Object {
      await _deleteStagedFiles(file);
      await _deleteStagedFiles(File('${file.path}.rebuilt'));
      rethrow;
    }
  }

  /// 以 `AppDatabase` 開啟 [file]（跑 migration 到目前版本），核對 schema 的名稱。
  Future<void> _migrateAndCheck(File file) async {
    final staged = AppDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (raw) => raw.execute('PRAGMA trusted_schema = OFF'),
      ),
    );
    final reference = openInMemoryDatabase();
    try {
      final Set<(String, String)> found;
      try {
        // 第一個查詢才開檔並跑 migration。
        await staged.customSelect('SELECT 1').get();
        found = await _schemaObjects(staged);
      } on Object catch (error) {
        throw BackupRejected(
          BackupRejection.corrupt,
          'migration failed: ${error.runtimeType}',
        );
      }
      final expected = await _schemaObjects(reference);
      if (found.length != expected.length || !found.containsAll(expected)) {
        throw const BackupRejected(
          BackupRejection.notFmpBackup,
          'the schema objects differ from the app schema',
        );
      }
    } finally {
      await reference.close();
      await staged.close();
    }
  }

  /// 重建好的 [file] 的插件清單與自訂 index 網址。腳本解析不出來的插件列（[_readPlugin] 回
  /// `null`）從檔案刪掉（外鍵 cascade 照常），id 記在 [StagedBackup.unusablePluginIds]。
  Future<StagedBackup> _readRebuilt(File file) async {
    final database = AppDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (raw) => raw.execute('PRAGMA trusted_schema = OFF'),
      ),
    );
    try {
      try {
        final plugins = <BackupPlugin>[];
        final unusable = <String>[];
        for (final row
            in await database
                .customSelect(
                  'SELECT id, version, manifest_json, script '
                  'FROM installed_plugins '
                  'WHERE $backupDevMarkerColumn = 0 ORDER BY id',
                )
                .get()) {
          final id = row.read<String>('id');
          final plugin = _readPlugin(
            id: id,
            version: row.read<String>('version'),
            manifestJson: row.read<String>('manifest_json'),
            script: row.read<String>('script'),
          );
          if (plugin == null) {
            unusable.add(id);
          } else {
            plugins.add(plugin);
          }
        }
        // 比照移除插件（ADR 0030 §決定 10）：每音源設定與榜單設定一起刪，
        // 之後正式裝回同 id 的插件時，備份裡的設定不會靜默生效。
        for (final id in unusable) {
          for (final table in const ['source_settings', 'chart_settings']) {
            await database.customStatement(
              'DELETE FROM $table WHERE plugin_id = ?',
              [id],
            );
          }
          await database.customStatement(
            'DELETE FROM installed_plugins WHERE id = ?',
            [id],
          );
        }
        return StagedBackup(
          path: file.path,
          plugins: plugins,
          unusablePluginIds: unusable,
          indexUrls: await _readIndexUrls(database),
        );
      } on BackupRejected {
        rethrow;
      } on Object catch (error) {
        throw BackupRejected(
          BackupRejection.corrupt,
          'reading the backup failed: ${error.runtimeType}',
        );
      }
    } finally {
      await database.close();
    }
  }

  /// schema 一律由 App 自己建：在新檔建一份全新的 schema，`ATTACH` 已 migration 的暫存檔，
  /// 逐表只複製全新表有的欄位，再以結果檔取代暫存檔。備份檔裡改過的欄位定義、CHECK、型別、
  /// 預設值、多出的欄位都不會進來。
  ///
  /// 能走到這裡的檔，名稱與版本都是 FMP 的，所以複製失敗（缺欄位、型別或 CHECK 不合）與外鍵
  /// 違規（`foreign_key_check`）都歸為 [BackupRejection.corrupt]：內容與 App 的 schema 對不上。
  Future<void> _rebuild(File file) async {
    final rebuilt = File('${file.path}.rebuilt');
    await _deleteStagedFiles(rebuilt);
    final fresh = AppDatabase(
      NativeDatabase.createInBackground(
        rebuilt,
        setup: (raw) => raw.execute('PRAGMA trusted_schema = OFF'),
      ),
    );
    var violations = 0;
    try {
      try {
        await fresh.customSelect('SELECT 1').get();
        // 複製時關外鍵（表的順序不照依賴）；`PRAGMA foreign_keys` 在交易內無效，所以在交易外設。
        await fresh.customStatement('PRAGMA foreign_keys = OFF');
        await fresh.customStatement('ATTACH DATABASE ? AS bk', [file.path]);
        await fresh.transaction(() async {
          for (final table in fresh.allTables) {
            final name = table.actualTableName;
            final columns = table.$columns
                .map((column) => '"${column.name}"')
                .join(', ');
            await fresh.customStatement(
              'INSERT INTO main."$name" ($columns) '
              'SELECT $columns FROM bk."$name"',
            );
          }
        });
        violations =
            (await fresh.customSelect('PRAGMA main.foreign_key_check').get())
                .length;
        await fresh.customStatement('DETACH DATABASE bk');
      } on Object catch (error) {
        throw BackupRejected(
          BackupRejection.corrupt,
          'rebuilding the schema failed: ${error.runtimeType}',
        );
      }
    } finally {
      await fresh.close();
    }
    if (violations > 0) {
      throw const BackupRejected(
        BackupRejection.corrupt,
        'foreign key violations',
      );
    }
    await _deleteStagedFiles(file);
    await rebuilt.rename(file.path);
  }

  static Future<Set<(String, String)>> _schemaObjects(
    AppDatabase database,
  ) async => {
    for (final row
        in await database
            .customSelect('SELECT type, name FROM sqlite_master')
            .get())
      (row.read<String>('type'), row.read<String>('name')),
  };

  static Future<List<String>> _readIndexUrls(AppDatabase database) async => [
    for (final row
        in await database
            .customSelect('SELECT url FROM plugin_indexes ORDER BY added_at')
            .get())
      row.read<String>('url'),
  ];

  /// 這台目前的值（[carryOver] 的輸入），照 [backupKeptOnDeviceTables]、[backupDeviceColumns]、
  /// 開發標記列的常數取。
  Future<CarriedState> readCarriedState() async {
    Future<List<Map<String, Object?>>> rows(String sql) async => [
      for (final row in await _database.customSelect(sql).get())
        Map<String, Object?>.of(row.data),
    ];
    final deviceColumns = <String, Map<String, Object?>>{};
    for (final MapEntry(key: table, value: columns)
        in backupDeviceColumns.entries) {
      final selected = columns.map((column) => '"$column"').join(', ');
      final row = (await rows('SELECT $selected FROM "$table" WHERE id = 1'))
          .firstOrNull;
      deviceColumns[table] = {
        for (final column in columns) column: row?[column],
      };
    }
    return CarriedState(
      tables: {
        for (final table in backupKeptOnDeviceTables)
          table: await rows('SELECT * FROM "$table"'),
      },
      deviceColumns: deviceColumns,
      devMarkerPlugins: await rows(
        'SELECT * FROM $backupDevMarkerTable WHERE $backupDevMarkerColumn = 1',
      ),
    );
  }

  /// 把 [state] 寫進 [staged]，取代裡面同類的資料（ADR 0034 §決定 4 第 4 條）。一個交易，
  /// 失敗就整個回滾。
  Future<void> carryOver(StagedBackup staged, CarriedState state) {
    final path = staged.path;
    return Isolate.run(() => _carryOver(path, state));
  }

  /// 刪掉暫存檔（使用者取消、自動備份失敗）。
  Future<void> discard(StagedBackup staged) =>
      _deleteStagedFiles(File(staged.path));

  /// 以 [staged] 取代資料庫：移進資料目錄的 `.restoring`，關閉資料庫，原檔（連同 `-wal`、
  /// `-shm`、`-journal`）改名成 `fmp.db.before-restore-<時間>` 留著，`.restoring` 改名成
  /// `fmp.db`。換上去失敗就把原檔改回來。
  Future<void> restoreStaged(StagedBackup staged) async {
    final source = File(staged.path);
    if (!await source.exists()) {
      throw FileSystemException('The staged backup is missing', source.path);
    }
    final swapIn = File('${_databaseFile.path}.restoring');
    await source.rename(swapIn.path);
    final suffix = '.before-restore-${_stamp(clock.now().toUtc())}';
    try {
      _closed = true;
      await _database.close();
      final moved = <(File, File)>[];
      try {
        for (final file in _databaseFiles()) {
          if (!await file.exists()) continue;
          final aside = await file.rename('${file.path}$suffix');
          moved.add((file, aside));
        }
        await swapIn.rename(_databaseFile.path);
      } on Object {
        // 換不上去：能改回來的改回來，讓下次啟動還是原本的資料庫。
        for (final (original, aside) in moved) {
          try {
            await aside.rename(original.path);
          } on FileSystemException catch (error, stackTrace) {
            // 改不回來時原檔仍以 $suffix 留在資料目錄，由使用者處理。
            _log.error(
              'Failed to put the database back after a failed restore',
              tag: _tag,
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
        rethrow;
      }
    } finally {
      await _deleteQuietly(swapIn);
    }
  }

  Future<void> _deleteStaleStaged() async {
    await for (final entity in _backupDirectory.list()) {
      if (entity is File && p.basename(entity.path).startsWith('staged-')) {
        await _deleteQuietly(entity);
      }
    }
  }

  Future<void> _deleteStagedFiles(File file) => _deleteWithSidecars(file);

  /// [file] 與它的 `-journal`、`-wal`、`-shm`。
  Future<void> _deleteWithSidecars(File file) async {
    await _deleteQuietly(file);
    await _deleteSidecars(file);
  }

  Future<void> _deleteSidecars(File file) async {
    for (final extra in const ['-journal', '-wal', '-shm']) {
      await _deleteQuietly(File('${file.path}$extra'));
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error, stackTrace) {
      // 留著不影響啟動；下次匯出或暫存會蓋掉或清掉它。
      _log.warning(
        'Failed to delete a temporary backup file',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 關閉資料庫並刪掉檔案（含 `-wal`、`-shm`、`-journal`）；下次啟動會建一個空的。
  /// `backups/` 不動。
  Future<void> erase() async {
    _closed = true;
    await _database.close();
    for (final file in _databaseFiles()) {
      if (await file.exists()) await file.delete();
    }
  }

  List<File> _databaseFiles() => [
    _databaseFile,
    for (final extra in const ['-wal', '-shm', '-journal'])
      File('${_databaseFile.path}$extra'),
  ];

  static final _namePattern = RegExp(
    r'^fmp-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(\d{3})Z\.db$',
  );

  static String _stamp(DateTime time) => backupTimestamp(time);

  static DateTime? _parseStamp(String name) {
    final match = _namePattern.firstMatch(name);
    if (match == null) return null;
    int part(int group) => int.parse(match.group(group)!);
    return DateTime.utc(
      part(1),
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
      part(7),
    );
  }
}

// 以下是在背景 isolate 跑的同步函式，只吃可傳送的值。

const _sqliteHeader = 'SQLite format 3\u0000';

/// schema 第 1 版的三張表（`drift_schemas/app_database/drift_schema_v1.json`）。
const _baseTables = [
  'appearance_settings',
  'installed_plugins',
  'plugin_storage',
];

/// 匯出暫存檔的清除（ADR 0034 §決定 1、2）。
void _scrubExport(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('PRAGMA trusted_schema = OFF');
    db.execute('BEGIN');
    // 先清 plugin_storage 再刪標記列：它的外鍵指向 installed_plugins。
    for (final table in backupExcludedTables) {
      db.execute('DELETE FROM "$table"');
    }
    for (final MapEntry(key: table, value: columns)
        in backupDeviceColumns.entries) {
      final assignments = columns
          .map((column) => '"$column" = NULL')
          .join(', ');
      db.execute('UPDATE "$table" SET $assignments');
    }
    db.execute(
      'DELETE FROM "$backupDevMarkerTable" WHERE "$backupDevMarkerColumn" = 1',
    );
    db.execute('COMMIT');
    // 刪掉的列不留在空閒頁。
    db.execute('VACUUM');
  } finally {
    db.close();
  }
}

/// 標頭、`user_version`、`integrity_check` 與 trigger／view 的檢查。回傳拒絕的原因與細節，
/// 通過是 `(null, null)`。
(BackupRejection?, String?) _inspect(String path, int currentVersion) {
  final head = Uint8List(_sqliteHeader.length);
  final file = File(path).openSync();
  try {
    final read = file.readIntoSync(head);
    if (read != head.length || latin1.decode(head) != _sqliteHeader) {
      return (BackupRejection.notFmpBackup, 'not an SQLite file');
    }
  } finally {
    file.closeSync();
  }
  final sqlite.Database db;
  try {
    db = sqlite.sqlite3.open(path);
  } on sqlite.SqliteException {
    return (BackupRejection.corrupt, 'cannot open');
  }
  try {
    db.execute('PRAGMA trusted_schema = OFF');
    final version = db.select('PRAGMA user_version').single.values.first as int;
    if (version <= 0) {
      return (BackupRejection.notFmpBackup, 'user_version is $version');
    }
    if (version > currentVersion) {
      return (BackupRejection.newerVersion, 'user_version $version');
    }
    final check = db.select('PRAGMA integrity_check');
    if (check.length != 1 || check.single.values.first != 'ok') {
      return (BackupRejection.corrupt, 'integrity_check failed');
    }
    // 第一版就有的表：沒有就是別的 App 的資料庫，不必去跑 migration。
    final base = db.select(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN "
      '(${List.filled(_baseTables.length, '?').join(', ')})',
      _baseTables,
    );
    if (base.single.values.first != _baseTables.length) {
      return (BackupRejection.notFmpBackup, 'the base tables are missing');
    }
    final hostile = db.select(
      "SELECT 1 FROM sqlite_master WHERE type IN ('trigger', 'view') LIMIT 1",
    );
    if (hostile.isNotEmpty) {
      return (BackupRejection.notFmpBackup, 'contains a trigger or a view');
    }
    return (null, null);
  } on sqlite.SqliteException {
    return (BackupRejection.corrupt, 'cannot read');
  } finally {
    db.close();
  }
}

/// [DatabaseBackups.carryOver] 的內容：[backupExcludedTables] 逐表處理（先清空，
/// [backupKeptOnDeviceTables] 再寫入這台的列）、[backupDeviceColumns] 逐欄、開發標記列。
void _carryOver(String path, CarriedState state) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('PRAGMA trusted_schema = OFF');
    // 刪標記列時 plugin_storage 的外鍵 cascade 要生效。
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('BEGIN');
    try {
      for (final table in backupExcludedTables) {
        _replaceRows(db, table, state.tables[table] ?? const []);
      }
      for (final MapEntry(key: table, value: columns)
          in backupDeviceColumns.entries) {
        _setDeviceColumns(db, table, {
          for (final column in columns)
            column: state.deviceColumns[table]?[column],
        });
      }
      db.execute(
        'DELETE FROM "$backupDevMarkerTable" '
        'WHERE "$backupDevMarkerColumn" = 1',
      );
      // 同 id 的列在備份裡是使用者裝的：留備份的。
      _insertRows(
        db,
        backupDevMarkerTable,
        state.devMarkerPlugins,
        'OR IGNORE',
      );
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    db.close();
  }
}

void _replaceRows(
  sqlite.Database db,
  String table,
  List<Map<String, Object?>> rows,
) {
  db.execute('DELETE FROM "$table"');
  _insertRows(db, table, rows, '');
}

void _insertRows(
  sqlite.Database db,
  String table,
  List<Map<String, Object?>> rows,
  String conflict,
) {
  for (final row in rows) {
    final columns = row.keys.map((column) => '"$column"').join(', ');
    final marks = List.filled(row.length, '?').join(', ');
    db.execute(
      'INSERT $conflict INTO "$table" ($columns) VALUES ($marks)',
      row.values.toList(),
    );
  }
}

/// 單列表（`id = 1`）的裝置欄位換成這台的值。全是空值時只清掉已有的列，不為了空值新增一列。
void _setDeviceColumns(
  sqlite.Database db,
  String table,
  Map<String, Object?> values,
) {
  final columns = values.keys.map((column) => '"$column"').toList();
  if (values.values.every((value) => value == null)) {
    db.execute(
      'UPDATE "$table" SET ${columns.map((c) => '$c = NULL').join(', ')}',
    );
    return;
  }
  final marks = List.filled(values.length, '?').join(', ');
  final updates = columns.map((c) => '$c = excluded.$c').join(', ');
  db.execute(
    'INSERT INTO "$table" (id, ${columns.join(', ')}) VALUES (1, $marks) '
    'ON CONFLICT(id) DO UPDATE SET $updates',
    values.values.toList(),
  );
}
