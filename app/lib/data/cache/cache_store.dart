import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/data/cache/cache_database.dart';
import 'package:fmp/data/cache/cache_tables.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/platform_capabilities.dart';

// 上層拿到的 cache manager 只以這個型別出現（交給 `CachedNetworkImage`），不必
// 自己 import flutter_cache_manager（它只准在這個目錄，fmp_layer_imports）。
export 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show BaseCacheManager;
export 'package:fmp/data/cache/cache_tables.dart' show CacheCategory;

part 'image_cache_manager.dart';

/// 索引檔名，放在快取目錄（`fmp_cache/`）底下。
const cacheDatabaseFileName = 'cache.db';

/// 快取的檔案，檔名就是索引的 `relative_path`。
const cacheFilesDirectoryName = 'files';

/// 下載中的檔案（媒體 client 的 `.part` 與下載好、還沒交給 cache manager 的
/// 檔案）。每次開啟時清空。
const cacheStagingDirectoryName = 'staging';

/// 快取模組的 log tag。
const cacheLogTag = 'cache';

/// 快取庫（ADR 0016 §決定 2–3）：`cache.db` 索引加 `files/` 的檔案，一個總上限，
/// 寫入後超過上限就不分類別、依最後存取由舊到新刪到上限以下（不用計時器，
/// ADR 0017 §決定 1）。
///
/// 寫入索引與會刪檔的動作（淘汰、清除、移除插件）一個接一個跑：不會兩個同時
/// 算出要刪什麼，寫入看到的檔案也不會在寫進索引之前被刪掉。刪檔失敗（Windows 上檔案正被讀）只記 log：索引那一列已經刪了，檔案留到
/// 下次開啟時的對帳。
final class CacheStore {
  CacheStore._(this._database, this._root, this._limitBytes, this._log);

  final CacheDatabase _database;
  final Directory _root;
  int _limitBytes;
  final Log _log;

  /// 上一個會刪檔的動作；下一個接在它後面。
  Future<void> _tail = Future.value();

  /// 這次開啟以來給出的暫存檔數，用來取不重複的檔名。
  var _staged = 0;

  Directory get _files =>
      Directory(p.join(_root.path, cacheFilesDirectoryName));

  Directory get _staging =>
      Directory(p.join(_root.path, cacheStagingDirectoryName));

  $CacheEntriesTableTable get _entries => _database.cacheEntriesTable;

  /// 各類別用了多少位元組；沒有東西的類別是 0。
  Future<Map<CacheCategory, int>> usage() async {
    final total = _entries.sizeBytes.sum();
    final rows =
        await (_database.selectOnly(_entries)
              ..addColumns([_entries.category, total])
              ..groupBy([_entries.category]))
            .get();
    return {
      for (final category in CacheCategory.values) category: 0,
      for (final row in rows)
        row.readWithConverter(_entries.category)!: row.read(total) ?? 0,
    };
  }

  /// 改上限（位元組），超過就馬上淘汰到新上限以下。
  Future<void> setLimit(int bytes) {
    _limitBytes = bytes;
    return _serially(_evict);
  }

  /// 清掉所有快取（索引與 `files/` 裡的每個檔案）。Flutter 記憶體裡的
  /// `ImageCache` 由呼叫端清。
  Future<void> clear() => _serially(() async {
    await _database.delete(_entries).go();
    try {
      await for (final entity in _files.list()) {
        if (entity is File) await _deleteFile(entity);
      }
    } on PathNotFoundException {
      // 系統在 App 執行中清掉了快取目錄（Android 的 getCacheDir()）：沒有檔案要刪。
      return;
    }
  });

  /// 刪掉 [pluginId] 的所有項目（ADR 0016 §決定 2：移除插件時）。
  Future<void> removePlugin(String pluginId) => _serially(() async {
    final rows = await (_database.select(
      _entries,
    )..where((t) => t.pluginId.equals(pluginId))).get();
    await _remove(rows);
  });

  /// 關閉索引。之後不能再用。
  Future<void> close() => _database.close();

  /// 一個寫進 `staging/` 的新檔案路徑（還不存在），這次開啟內不重複。
  Future<File> _stagingFile() async {
    final directory = await _staging.create(recursive: true);
    return File(p.join(directory.path, '${_staged++}'));
  }

  Future<T> _serially<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // 錯誤由呼叫端從 result 收到；這裡只讓下一個動作接得上，不被前一個的錯誤擋住。
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _evict() async {
    final total = _entries.sizeBytes.sum();
    final sum = await (_database.selectOnly(
      _entries,
    )..addColumns([total])).map((row) => row.read(total) ?? 0).getSingle();
    if (sum <= _limitBytes) return;
    var excess = sum - _limitBytes;
    final victims = <CacheEntryRow>[];
    final oldestFirst =
        await (_database.select(_entries)..orderBy([
              (t) => OrderingTerm.asc(t.lastAccess),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    for (final row in oldestFirst) {
      if (excess <= 0) break;
      victims.add(row);
      excess -= row.sizeBytes;
    }
    await _remove(victims);
    _log.debug(
      'Cache evicted',
      tag: cacheLogTag,
      fields: {
        'entries': victims.length,
        'bytes': sum - _limitBytes - excess,
        'limit': _limitBytes,
      },
    );
  }

  /// 刪掉 [rows] 的索引與檔案：先刪索引，檔案刪不掉時下次開啟對帳。
  Future<void> _remove(List<CacheEntryRow> rows) async {
    if (rows.isEmpty) return;
    await (_database.delete(
      _entries,
    )..where((t) => t.id.isIn([for (final row in rows) row.id]))).go();
    for (final row in rows) {
      await _deleteFile(File(p.join(_files.path, row.relativePath)));
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // 已經不在了（系統清掉快取目錄、或 flutter_cache_manager 先刪了）：
      // 正是要的結果。
      return;
    } on FileSystemException catch (error, stackTrace) {
      _log.warning(
        'Failed to delete a cached file',
        tag: cacheLogTag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 開啟時的對帳：清空 `staging/`；索引裡檔案不見的列刪掉（系統清過快取
  /// 目錄），`files/` 裡索引沒有的檔案刪掉（寫到一半就被關掉的 App、刪不掉的
  /// 舊檔）。之後用量才等於實際的檔案。
  Future<void> _reconcile() async {
    if (await _staging.exists()) await _staging.delete(recursive: true);
    await _files.create(recursive: true);
    final rows = await _database.select(_entries).get();
    final onDisk = <String>{
      await for (final entity in _files.list())
        if (entity is File) p.basename(entity.path),
    };
    final indexed = {for (final row in rows) row.relativePath};
    final missing = [
      for (final row in rows)
        if (!onDisk.contains(row.relativePath)) row.id,
    ];
    if (missing.isNotEmpty) {
      await (_database.delete(_entries)..where((t) => t.id.isIn(missing))).go();
    }
    final strays = onDisk.difference(indexed);
    for (final name in strays) {
      await _deleteFile(File(p.join(_files.path, name)));
    }
    if (missing.isNotEmpty || strays.isNotEmpty) {
      _log.info(
        'Cache reconciled',
        tag: cacheLogTag,
        fields: {'missingFiles': missing.length, 'strayFiles': strays.length},
      );
    }
  }
}

/// 開啟 [directory] 的快取庫，上限 [limitBytes]。
///
/// 開不起來（`cache.db` 損壞）就把整個快取目錄清空、重新開一次，不顯示錯誤頁
/// （ADR 0016 §決定 1：快取可以隨時丟；主資料庫則停在錯誤頁，ADR 0010 §決定 3）。
/// 第二次也失敗就拋出。開好之後先對帳（[CacheStore._reconcile]）才交出去，
/// 對帳時沒有別的寫入。
Future<CacheStore> openCacheStore(
  CacheDirectory directory, {
  required int limitBytes,
  required Log log,
}) async {
  final root = await directory.resolve();
  try {
    return await _open(root, limitBytes, log);
  } on Object catch (error, stackTrace) {
    log.warning(
      'Failed to open the cache, starting it over',
      tag: cacheLogTag,
      error: error,
      stackTrace: stackTrace,
    );
  }
  await for (final entity in root.list()) {
    await entity.delete(recursive: true);
  }
  return _open(root, limitBytes, log);
}

Future<CacheStore> _open(Directory root, int limitBytes, Log log) async {
  final database = CacheDatabase(
    NativeDatabase.createInBackground(
      File(p.join(root.path, cacheDatabaseFileName)),
    ),
  );
  final store = CacheStore._(database, root, limitBytes, log);
  try {
    // 第一個查詢才真正開檔、建表或清空重建（drift 的 migration）。
    await store._reconcile();
  } on Object {
    await database.close();
    rethrow;
  }
  return store;
}

/// App 的快取庫，第一次有人讀時開啟（`openCacheStore`）。開不起來是
/// `AsyncError`：封面只顯示佔位圖，App 照常（ADR 0016 §決定 1）。
///
/// 上限目前是平台宣告的預設；「快取上限」設定在 PR 5 接上。
final cacheStoreProvider = FutureProvider<CacheStore>((ref) async {
  final log = ref.watch(logProvider);
  final CacheStore store;
  try {
    store = await openCacheStore(
      ref.watch(cacheDirectoryProvider),
      limitBytes: ref
          .watch(platformCapabilitiesProvider)
          .cache!
          .defaultLimitBytes,
      log: log,
    );
  } on Object catch (error, stackTrace) {
    log.error(
      'Failed to open the cache',
      tag: cacheLogTag,
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
  ref.onDispose(() => unawaited(store.close()));
  return store;
});
