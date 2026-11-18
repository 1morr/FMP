import 'dart:io';

import 'package:fmp/platform/app_data_directory.dart';

/// 資料庫檔案的位置：[data]（[appDataDirectory]）底下的 `fmp.sqlite`。
Future<File> databaseFile(Directory data) async {
  await data.create(recursive: true);
  return File('${data.path}${Platform.pathSeparator}fmp.sqlite');
}

/// 讀不回來的資料另存的檔案：[database] 旁邊的
/// `<檔名>.unreadable-<UTC 時間，到秒>`，照 Firefox 把壞掉的 `places.sqlite`
/// 另存成 `.corrupt` 的慣例，留給之後查。
File unreadableBackupFile(File database, DateTime now) {
  final stamp = now
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]'), '')
      .split('.')
      .first;
  return File('${database.path}.unreadable-${stamp}Z');
}
