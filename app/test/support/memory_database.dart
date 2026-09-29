import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';

/// 記憶體內的 [AppDatabase]，測試結束時關閉。
///
/// 和 App 用同一個資料庫類別，所以 migration 策略（含外鍵）一樣會跑；只有
/// 執行器換成記憶體。`closeStreamsSynchronously` 照 drift 的測試指南，避免
/// `watch` 的串流在測試結束後還留著計時器。
AppDatabase memoryDatabase() {
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(database.close);
  return database;
}
