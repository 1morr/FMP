import 'dart:io';

import 'package:fmp/platform/app_data_directory.dart';

/// 資料庫檔案的位置：[data]（[appDataDirectory]）底下的 `fmp.sqlite`。
Future<File> databaseFile(Directory data) async {
  await data.create(recursive: true);
  return File('${data.path}${Platform.pathSeparator}fmp.sqlite');
}
