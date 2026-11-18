import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.steps.dart';
import 'package:fmp/data/queue_tables.dart';
import 'package:fmp/domain/queue.dart';

part 'database.g.dart';

/// 整個 App 共用的資料庫。`main` 啟動時開好再 override 進來；沒有資料庫
/// （開不了，或測試沒給）時是 null，什麼都不保存。
final appDatabaseProvider = Provider<AppDatabase?>((ref) => null);

/// 新版的 drift 資料庫。檔案位置由 `platform/` 決定（architecture〈依賴規則〉），這裡只管
/// schema 與升級。
///
/// 改 schema 的流程（快照、[migration]、升級測試）照 architecture〈測試策略〉。
@DriftDatabase(tables: [QueueEntries, QueueStates])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 開在 [file] 上；SQLite 跑在背景 isolate，不卡 UI。
  AppDatabase.open(File file) : this(NativeDatabase.createInBackground(file));

  /// 開在 [file] 上並確認開得起來（建立或升級跑完）；開不了就寫 log、回
  /// null，App 照常跑、只是不保存。
  static Future<AppDatabase?> openOrNull(File file, Log log) async {
    final database = AppDatabase.open(file);
    try {
      final version = await database.storedSchemaVersion();
      log.info('Database opened, schema version $version');
      return database;
    } catch (error, stackTrace) {
      log.error(
        'Opening the database failed; nothing will be saved this time',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await database.close();
      } catch (_) {
        // 本來就沒開起來，關不了也沒關係。
      }
      return null;
    }
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.queueEntries);
        await m.createTable(schema.queueStates);
      },
    ),
  );

  /// 檔案裡記的 schema 版本（`PRAGMA user_version`）。查詢會讓資料庫真的
  /// 開起來並跑完建立或升級，啟動時用它確認開庫成功。
  Future<int> storedSchemaVersion() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }
}
