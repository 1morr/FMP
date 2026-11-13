import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 資料庫檔案的位置：App 的 application support 目錄，使用者平常看不到、
/// 系統也不會自動清掉。dev 身分（brief〈舊版的資料與升級〉）的目錄和舊版分開。
Future<File> databaseFile() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File('${dir.path}${Platform.pathSeparator}fmp.sqlite');
}
