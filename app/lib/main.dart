import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';

import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/platform/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = AppFlavor.parse(appFlavor);
  final platform = AppPlatform.current(flavor);
  // 沒有資料目錄的平台不啟動資料層（能力宣告 dataDirectory 為假）。
  switch (platform.dataDirectory) {
    case null:
      runApp(UnsupportedPlatformApp(flavor: flavor));
    case final dataDirectory:
      final directory = await dataDirectory.resolve();
      // 開不起來就只顯示錯誤頁，不在半開的資料庫上啟動（ADR 0010 §決定 3）。
      // 還沒有東西讀寫資料庫：接上 Riverpod 的 PR 會把這裡開好的資料庫交給
      // provider。在那之前開啟只為了建立 fmp.db 並確認它可用。
      try {
        await openAppDatabase(directory);
      } on Object catch (error) {
        runApp(DatabaseErrorApp(flavor: flavor, error: error));
        return;
      }
      runApp(FmpApp(flavor: flavor, dataDirectoryPath: directory.path));
  }
}
