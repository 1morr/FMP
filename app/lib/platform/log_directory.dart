import 'dart:io';

import 'package:fmp/platform/app_data_directory.dart';

/// log 檔的目錄：[data]（[appDataDirectory]）底下的 `logs/`，平常就是 App
/// 支援目錄，各平台的實際位置見 brief 事實 K13。目錄只放 log 門面的檔案：
/// 輪替時會刪掉這裡最舊的其他檔。
Directory logDirectory(Directory data) =>
    Directory('${data.path}${Platform.pathSeparator}logs');
