import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/database/app_database.dart';
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

/// 資料庫檔的備份、還原與刪除（ADR 0025 §決定 8、9，M3 design §12.2）。
///
/// 備份格式是 SQLite 的 `VACUUM INTO`（官方的線上備份做法）：一個獨立、已壓實的
/// 資料庫檔，檔名 `fmp-<UTC 時間>.db`，時間不含冒號（Windows 檔名不准）。憑證在 secure
/// storage、不在資料庫，所以備份不含憑證，還原後要重新登入。M4 的匯出格式另定。
///
/// [restore] 與 [erase] 會先關閉資料庫：呼叫之後這個 App 行程裡的資料庫不能再用，
/// 呼叫端接著重啟。
final class DatabaseBackups {
  DatabaseBackups(this._database, this._dataDirectory, this._log);

  final AppDatabase _database;
  final Directory _dataDirectory;
  final Log _log;

  static const _tag = 'data';

  var _closed = false;

  /// [restore] 或 [erase] 已經開始關閉資料庫：之後不論成功或失敗，這個行程裡的資料庫都不能
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

  /// 以 [backup] 取代資料庫：先把備份複製成資料目錄裡的暫存檔（失敗時原資料庫還沒動），
  /// 關閉資料庫，原檔（連同 `-wal`、`-shm`、`-journal`）改名成
  /// `fmp.db.before-restore-<時間>` 留著，暫存檔改名成 `fmp.db`。換上去失敗就把原檔改回來。
  Future<void> restore(DatabaseBackup backup) async {
    final source = File(backup.path);
    if (!await exists(backup)) {
      throw FileSystemException('The backup is missing', source.path);
    }
    final staged = File('${_databaseFile.path}.restoring');
    await source.copy(staged.path);
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
        await staged.rename(_databaseFile.path);
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
      if (await staged.exists()) {
        try {
          await staged.delete();
        } on FileSystemException catch (error, stackTrace) {
          // 暫存檔留著不影響啟動；下次還原會蓋掉它。
          _log.warning(
            'Failed to delete the staged restore file',
            tag: _tag,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
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

  /// `20261014T123456789Z`：UTC、毫秒、不含冒號（Windows 檔名不准）。
  static String _stamp(DateTime time) {
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(time.year, 4)}${pad(time.month, 2)}${pad(time.day, 2)}'
        'T${pad(time.hour, 2)}${pad(time.minute, 2)}${pad(time.second, 2)}'
        '${pad(time.millisecond, 3)}Z';
  }

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
