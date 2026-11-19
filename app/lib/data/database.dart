import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/chart_tables.dart';
import 'package:fmp/data/database.steps.dart';
import 'package:fmp/data/queue_tables.dart';
import 'package:fmp/data/search_history_tables.dart';
import 'package:fmp/data/settings_tables.dart';
import 'package:fmp/domain/queue.dart';

part 'database.g.dart';

/// 整個 App 共用的資料庫。`main` 啟動時開好再 override 進來；沒有資料庫
/// （開不了，或測試沒給）時是 null，什麼都不保存。
final appDatabaseProvider = Provider<AppDatabase?>((ref) => null);

/// SQLite 說資料庫檔本身壞了：結果碼 SQLITE_CORRUPT（11）或 SQLITE_NOTADB
/// （26）。權限、磁碟滿這類其他開檔錯誤不算。
bool isCorruptDatabase(Object error) {
  final cause = error is DriftRemoteException ? error.remoteCause : error;
  return cause is SqliteException && const {11, 26}.contains(cause.resultCode);
}

/// 新版的 drift 資料庫。檔案位置由 `platform/` 決定（architecture〈依賴規則〉），這裡只管
/// schema 與升級。
///
/// 改 schema 的流程（快照、[migration]、升級測試）照 architecture〈測試策略〉。
@DriftDatabase(
  tables: [
    QueueEntries,
    QueueStates,
    SearchHistoryEntries,
    ChartSnapshots,
    ChartEntries,
    SettingEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 開在 [file] 上；SQLite 跑在背景 isolate，不卡 UI。
  AppDatabase.open(File file) : this(NativeDatabase.createInBackground(file));

  /// 把整個資料庫複製成 [file]（SQLite 的 `VACUUM INTO`：開著也能做出一致
  /// 的副本）。[file] 已存在時丟例外，不覆寫。
  Future<void> copyTo(File file) =>
      customStatement('VACUUM INTO ?', [file.path]);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.queueEntries);
        await m.createTable(schema.queueStates);
      },
      from2To3: (m, schema) async {
        await m.createTable(schema.searchHistoryEntries);
      },
      from3To4: (m, schema) async {
        await m.addColumn(
          schema.queueEntries,
          schema.queueEntries.coverLargeUrl,
        );
      },
      from4To5: (m, schema) async {
        await m.createTable(schema.chartSnapshots);
        await m.createTable(schema.chartEntries);
      },
      from5To6: (m, schema) async {
        await m.createTable(schema.settingEntries);
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
