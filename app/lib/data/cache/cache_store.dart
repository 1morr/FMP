import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
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

  /// 這次開啟以來 [put] 寫過的檔數，用來取不重複的檔名。
  var _written = 0;

  Directory get _files =>
      Directory(p.join(_root.path, cacheFilesDirectoryName));

  Directory get _staging =>
      Directory(p.join(_root.path, cacheStagingDirectoryName));

  $CacheEntriesTableTable get _entries => _database.cacheEntriesTable;

  /// 各類別用了多少位元組（沒有東西的類別是 0）；之後索引每次變動（寫入、淘汰、
  /// 清除、移除插件）再發一次。
  ///
  /// 聽的是 drift 的 `tableUpdates`，不是 `watch()` 的查詢 stream：後者在最後一個
  /// listener 離開後以計時器多留一輪事件迴圈，widget 測試結束時會被當成沒跑完的
  /// 計時器（`createInBackground` 的連線關不掉這個行為）。
  Stream<Map<CacheCategory, int>> watchUsage() async* {
    // 先訂閱再讀，讀的期間的變動不會漏掉。
    final changed = StreamController<void>();
    final subscription = _database
        .tableUpdates(TableUpdateQuery.onTable(_entries))
        .listen((_) => changed.add(null));
    try {
      yield await _usage();
      await for (final _ in changed.stream) {
        yield await _usage();
      }
    } finally {
      await subscription.cancel();
      // 沒有人聽過 `changed`（拿到第一個值就取消）時，close 的 future 不會完成。
      unawaited(changed.close());
    }
  }

  Future<Map<CacheCategory, int>> _usage() async {
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

  /// 把 [bytes] 存成 [category]、[pluginId] 底下鍵為 [key] 的項目（有就取代）；寫完超過
  /// 上限就淘汰。給不經圖片 cache manager 的類別用（[CacheCategory.chart]）。
  ///
  /// 先寫新檔、再換索引、最後刪舊檔，中間失敗時舊的內容還在。這些項目沒有「有效到何時」
  /// 的概念（`valid_until` 記寫入時間，沒人讀）。
  Future<void> put(
    CacheCategory category,
    String pluginId,
    String key,
    Uint8List bytes,
  ) => _serially(() async {
    final directory = await _files.create(recursive: true);
    final name =
        '${category.name}-${_written++}-'
        '${clock.now().microsecondsSinceEpoch}';
    await File(p.join(directory.path, name)).writeAsBytes(bytes, flush: true);
    final now = clock.now();
    final previous = await _row(category, pluginId, key);
    final entry = CacheEntriesTableCompanion.insert(
      key: key,
      category: category,
      pluginId: Value(pluginId),
      relativePath: name,
      sizeBytes: bytes.length,
      lastAccess: now,
      validUntil: now,
    );
    await _database
        .into(_entries)
        .insert(
          entry,
          onConflict: DoUpdate(
            (_) => entry,
            target: [_entries.category, _entries.pluginId, _entries.key],
          ),
        );
    if (previous != null) {
      await _deleteFile(File(p.join(_files.path, previous.relativePath)));
    }
    await _evict();
  });

  /// [put] 存的內容；沒有、被淘汰或檔案已被系統清掉都是 `null`（視為沒有快取）。
  Future<Uint8List?> get(CacheCategory category, String pluginId, String key) =>
      _serially(() async {
        final row = await _row(category, pluginId, key);
        if (row == null) return null;
        try {
          return await File(p.join(_files.path, row.relativePath))
              .readAsBytes();
        } on PathNotFoundException {
          // 索引還在而檔案不見了（系統清掉快取目錄）：下次開啟時的對帳會刪掉那一列。
          return null;
        }
      });

  /// 刪掉 [category]、[pluginId] 底下鍵為 [key] 的項目；不給 [key] 就刪這個插件這個類別
  /// 的全部（其他類別、其他插件的不動）。沒有時什麼都不做。
  Future<void> remove(CacheCategory category, String pluginId, {String? key}) =>
      _serially(() async {
        final rows =
            await (_database.select(_entries)..where(
                  (t) =>
                      t.category.equalsValue(category) &
                      t.pluginId.equals(pluginId) &
                      (key == null ? const Constant(true) : t.key.equals(key)),
                ))
                .get();
        await _remove(rows);
      });

  Future<CacheEntryRow?> _row(
    CacheCategory category,
    String pluginId,
    String key,
  ) =>
      (_database.select(_entries)..where(
            (t) =>
                t.category.equalsValue(category) &
                t.pluginId.equals(pluginId) &
                t.key.equals(key),
          ))
          .getSingleOrNull();

  /// 刪掉 [pluginId] 的所有項目（ADR 0016 §決定 2：移除插件時）。
  Future<void> removePlugin(String pluginId) => _serially(() async {
    final rows = await (_database.select(
      _entries,
    )..where((t) => t.pluginId.equals(pluginId))).get();
    await _remove(rows);
  });

  Future<void> _closing = Future<void>.value();
  var _closeStarted = false;

  /// 關閉索引。之後不能再用；重複呼叫回同一個 future。
  ///
  /// 關到一半時，同一個目錄的 [openCacheStore] 會等它完成才開（[_pendingCloses]）：
  /// 呼叫端不必 await（Riverpod 的 onDispose 等不了），重開也不會撞上還沒放掉的檔案。
  Future<void> close() {
    if (_closeStarted) return _closing;
    _closeStarted = true;
    final key = _closeKey(_root);
    final closing = _database.close();
    _closing = closing;
    _pendingCloses[key] = closing;
    // 關閉失敗由呼叫端從 close() 的 future 收到；這裡只負責登記完成。
    unawaited(
      closing.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_pendingCloses[key], closing)) _pendingCloses.remove(key);
      }),
    );
    return closing;
  }

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

/// 還沒關完的快取庫，以正規化後的目錄路徑為鍵（[CacheStore.close]）。
final _pendingCloses = <String, Future<void>>{};

/// 測試用：登記一個「還沒關完」的快取庫，驗證重開會等它（真的關閉太快，賽跑重現不了）。
@visibleForTesting
Map<String, Future<void>> get pendingCacheCloses => _pendingCloses;

/// [pendingCacheCloses] 的鍵。
@visibleForTesting
String cacheCloseKey(Directory root) => _closeKey(root);

String _closeKey(Directory root) => p.canonicalize(root.path);

/// 資料庫正被別的連線佔著（SQLITE_BUSY / SQLITE_LOCKED）：不是損壞，不能清快取。
bool _isBusy(Object error) {
  // 背景 isolate 的錯誤包在 DriftRemoteException 裡。
  final cause = error is DriftRemoteException ? error.remoteCause : error;
  return cause is SqliteException &&
      (cause.resultCode == 5 || cause.resultCode == 6);
}

/// 開啟 [directory] 的快取庫，上限 [limitBytes]。
///
/// 開不起來（`cache.db` 損壞）就把整個快取目錄清空、重新開一次，不顯示錯誤頁
/// （ADR 0016 §決定 1：快取可以隨時丟；主資料庫則停在錯誤頁，ADR 0010 §決定 3）。
/// 第二次也失敗就拋出。資料庫被佔住（busy / locked）不算損壞：直接拋出，不清目錄。
/// 同一個目錄上一個快取庫還在關時，先等它關完。開好之後先對帳（[CacheStore._reconcile]）
/// 才交出去，對帳時沒有別的寫入。
Future<CacheStore> openCacheStore(
  CacheDirectory directory, {
  required int limitBytes,
  required Log log,
}) async {
  final root = await directory.resolve();
  final closing = _pendingCloses[_closeKey(root)];
  if (closing != null) {
    // 關閉本身的錯誤由關閉它的人處理。
    await closing.then<void>((_) {}, onError: (Object _) {});
  }
  try {
    return await _open(root, limitBytes, log);
  } on Object catch (error, stackTrace) {
    if (_isBusy(error)) rethrow;
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
/// 上限是「網路」設定的快取上限，沒設定就是平台宣告的預設：開啟時取當時的值，
/// 之後設定改了就 `setLimit`（馬上淘汰到新上限以下），不重開快取庫。
///
/// 直接訂閱 repository，不經 `networkProvider`：設定層在資料層之上
/// （`fmp_layer_imports`）。預設與 `resolveNetwork` 同一個來源（平台宣告），
/// 不在這裡另寫數字。訂閱的是 drift 的 stream，不是 Riverpod 的 provider，
/// 沒有人聽這個 provider 時也照樣收到改動。
final cacheStoreProvider = FutureProvider<CacheStore>((ref) async {
  final log = ref.watch(logProvider);
  final directory = ref.watch(cacheDirectoryProvider);
  final defaultMebibytes = ref
      .watch(platformCapabilitiesProvider)
      .cache!
      .defaultLimitMebibytes;
  int limitBytes(NetworkSettings stored) =>
      (stored.cacheLimitMebibytes ?? defaultMebibytes) * 1024 * 1024;

  // 第一個值是開啟時的上限；之後的每個值在開好之後套用，開啟期間來的留到開好。
  final initial = Completer<int>();
  CacheStore? opened;
  int? pending;
  void apply(int bytes) {
    final store = opened;
    if (store == null) {
      pending = bytes;
      return;
    }
    unawaited(
      store
          .setLimit(bytes)
          .catchError(
            (Object error, StackTrace stackTrace) => log.error(
              'Failed to apply the cache limit',
              tag: cacheLogTag,
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
  }

  final subscription = ref
      .watch(networkSettingsRepositoryProvider)
      .watch()
      .listen(
        (stored) => initial.isCompleted
            ? apply(limitBytes(stored))
            : initial.complete(limitBytes(stored)),
        onError: (Object error, StackTrace stackTrace) {
          if (!initial.isCompleted) {
            initial.completeError(error, stackTrace);
            return;
          }
          log.error(
            'Failed to read the cache limit',
            tag: cacheLogTag,
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
  ref.onDispose(subscription.cancel);
  final CacheStore store;
  try {
    store = await openCacheStore(
      directory,
      limitBytes: await initial.future,
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
  // 開啟期間被拆掉（App 結束、排行工作在啟動時就開了快取庫）：之後登記的 onDispose 不會
  // 再跑，這裡不關就沒人關，檔案一直開著。
  if (!ref.mounted) {
    await store.close();
    return store;
  }
  opened = store;
  if (pending case final bytes?) apply(bytes);
  ref.onDispose(() => unawaited(store.close()));
  return store;
});
