import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/data/database/app_database.dart';

/// 資料庫檔名，放在 App 資料目錄（`AppPlatform.dataDirectory`）底下。
const databaseFileName = 'fmp.db';

/// 開啟 [dataDirectory] 裡的 [databaseFileName]，沒有就建立。
///
/// drift 在第一個查詢時才真正開檔、建表或跑 migration；這裡先跑一個查詢，讓
/// 開不起來（檔案損壞、migration 失敗）在啟動時就拋出，呼叫端才能改開錯誤頁，
/// 不在半開的資料庫上啟動 App（ADR 0010 §決定 3）。失敗時先關閉再拋。
///
/// SQLite 跑在 drift 管理的背景 isolate（`createInBackground`），不佔 UI
/// isolate。
Future<AppDatabase> openAppDatabase(Directory dataDirectory) async {
  final database = AppDatabase(
    NativeDatabase.createInBackground(
      File(p.join(dataDirectory.path, databaseFileName)),
    ),
  );
  try {
    await database.customSelect('SELECT 1').get();
  } on Object {
    await database.close();
    rethrow;
  }
  return database;
}
