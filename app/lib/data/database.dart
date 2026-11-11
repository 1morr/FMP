import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

/// 整個 App 共用的資料庫。`main` 啟動時開好再 override 進來。
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('appDatabaseProvider is overridden in main()'),
);

/// 新版的 drift 資料庫。檔案位置由 `platform/` 決定（plan §1.3），這裡只管
/// schema 與升級。
///
/// 改 schema 的流程（快照、[migration]、升級測試）照 plan §3。
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 開在 [file] 上；SQLite 跑在背景 isolate，不卡 UI。
  AppDatabase.open(File file) : this(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 1;

  /// 檔案裡記的 schema 版本（`PRAGMA user_version`）。查詢會讓資料庫真的
  /// 開起來並跑完建立或升級，啟動時用它確認開庫成功。
  Future<int> storedSchemaVersion() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }
}
