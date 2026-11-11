import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// log 檔的目錄：App 支援目錄底下的 `logs/`，各平台的實際位置見 brief
/// 事實 K13。目錄只放 log 門面的檔案：輪替時會刪掉這裡最舊的其他檔。
Future<Directory> logDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}logs');
}
