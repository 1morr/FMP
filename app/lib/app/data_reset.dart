import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';

/// Debug 頁的備份、從備份還原與重設資料（ADR 0025 §決定 8、9，M3 design §12.2）。
///
/// [resetAndRestart] 與 [restoreAndRestart] 都以結束這個行程收尾：資料庫在中途關閉，
/// 呼叫之後這個 App 不能再用，回傳只發生在重啟實作不結束行程時（測試）。
abstract interface class DataReset {
  /// 立即備份。失敗就拋出：重設資料的呼叫端據此停在這裡，什麼都不清。
  Future<DatabaseBackup> backUp();

  /// `backups/` 裡的備份，最新的在前。
  Future<List<DatabaseBackup>> backups();

  /// 清空資料並重啟。[backup] 是剛為了這次重設做的備份：它不見了就拋出、什麼都不清，
  /// 所以沒有備份就清不了。
  ///
  /// 順序固定：secure storage 的憑證 → 登入 WebView 的資料 → 快取 → 資料庫（關閉、刪檔）→
  /// 寫完 log → 重啟。不動 log 檔與 `backups/`。某一步失敗就停在那一步並拋出，之後的不做；
  /// 失敗發生在資料庫關閉之後（刪檔失敗）時照樣重啟：這個行程已經不能用資料庫了。
  Future<void> resetAndRestart(DatabaseBackup backup);

  /// 以 [backup] 取代資料庫並重啟；原來的資料庫檔改名留在資料目錄。[backup] 不見了就拋出、
  /// 什麼都不動。
  ///
  /// 憑證不在備份裡（ADR 0012），所以先清 secure storage 的憑證與登入 WebView 的資料：
  /// 留著的話，現在的憑證會配上備份裡的 `accounts` 列（可能是另一個帳號），還原後一律重新
  /// 登入（M3 design §12.2）。換檔失敗（原檔已改回來）時，只要資料庫已經關閉，照樣重啟。
  Future<void> restoreAndRestart(DatabaseBackup backup);
}

final class AppDataReset implements DataReset {
  AppDataReset({
    required this.databaseBackups,
    required this.secureStorage,
    required this.loginWebView,
    required this.clearCache,
    required this.log,
    required this.restarter,
  });

  final DatabaseBackups databaseBackups;
  final SecureStorage secureStorage;

  /// 平台沒有登入 WebView 時為 `null`，那一步略過。
  final LoginWebView? loginWebView;
  final Future<void> Function() clearCache;
  final Log log;
  final AppRestarter restarter;

  static const _tag = 'data';

  @override
  Future<DatabaseBackup> backUp() async {
    try {
      final backup = await databaseBackups.create();
      log.info('Database backup created', tag: _tag);
      return backup;
    } on Object catch (error, stackTrace) {
      log.error(
        'Failed to back up the database',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<List<DatabaseBackup>> backups() => databaseBackups.list();

  @override
  Future<void> resetAndRestart(DatabaseBackup backup) async {
    if (!await databaseBackups.exists(backup)) {
      throw StateError('The backup is missing; nothing was cleared');
    }
    log.warning('Resetting all data', tag: _tag);
    await secureStorage.deleteAll();
    await loginWebView?.clearAll();
    await clearCache();
    await _closeDatabaseAndRestart(
      done: 'Data reset',
      failed: 'The data reset failed after the database was closed',
      work: databaseBackups.erase,
    );
  }

  @override
  Future<void> restoreAndRestart(DatabaseBackup backup) async {
    if (!await databaseBackups.exists(backup)) {
      throw StateError('The backup is missing; nothing was restored');
    }
    log.warning('Restoring the database from a backup', tag: _tag);
    await secureStorage.deleteAll();
    await loginWebView?.clearAll();
    await _closeDatabaseAndRestart(
      done: 'Database restored',
      failed: 'The restore failed after the database was closed',
      work: () => databaseBackups.restore(backup),
    );
  }

  /// 跑會關閉資料庫的 [work]，然後重啟。[work] 在關閉資料庫之前失敗（備份不見、複製失敗）
  /// 就只拋出，App 還能用；關閉之後才失敗時資料庫已經不能用（之後的查詢都丟錯），留在這個
  /// 行程裡只會是一個壞掉的 App，所以記下錯誤、照樣重啟（還原失敗時原檔已改回來）。
  Future<void> _closeDatabaseAndRestart({
    required String done,
    required String failed,
    required Future<void> Function() work,
  }) async {
    try {
      await work();
    } on Object catch (error, stackTrace) {
      if (!databaseBackups.isClosed) rethrow;
      log.error(failed, tag: _tag, error: error, stackTrace: stackTrace);
      await _restart('Database closed');
      rethrow;
    }
    await _restart(done);
  }

  Future<void> _restart(String message) async {
    log.warning('$message; restarting', tag: _tag);
    // 重啟會結束行程：log 的寫入佇列要先排空，結束後沒有機會了。
    await log.file?.flush();
    await restarter.restart();
  }
}

final dataResetProvider = Provider<DataReset>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return AppDataReset(
    databaseBackups: DatabaseBackups(
      database,
      ref.watch(dataDirectoryProvider),
      ref.watch(logProvider),
    ),
    secureStorage: ref.watch(secureStorageProvider),
    loginWebView: ref.watch(loginWebViewProvider),
    clearCache: () async {
      // 開不起來（已由 cacheStoreProvider 記下）就沒有磁碟上的快取要清。
      final store = await ref
          .read(cacheStoreProvider.future)
          .then<CacheStore?>((store) => store, onError: (Object _) => null);
      await store?.clear();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    },
    log: ref.watch(logProvider),
    restarter: ref.watch(appRestarterProvider),
  );
});
