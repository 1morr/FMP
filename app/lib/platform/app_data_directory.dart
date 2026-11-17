import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 實跑驅動給的隔離資料名稱（`--dart-define=FMP_SCRATCH_DATA=<名稱>`）；正式版
/// 與平常的 dev 版沒有帶，是空字串。
const scratchDataName = String.fromEnvironment('FMP_SCRATCH_DATA');

/// App 的資料（資料庫、log、封面快取）放在哪個目錄底下。平常是 App 的
/// application support 目錄，使用者平常看不到、系統也不會自動清掉；dev 身分
/// （brief〈舊版的資料與升級〉）的目錄和舊版分開。
///
/// 帶了 [scratch]（預設是 [scratchDataName]）就改放系統暫存目錄底下的
/// `<scratch>/`，整份和 dev 版的資料分開：實跑驅動用它，每次開 App 前清空
/// （docs/development.md〈實跑驅動〉）。不用 Mac 上的路徑，是因為 macOS 的
/// App 在沙盒裡、模擬器裡的 App 碰不到 Mac 的檔案系統。
Future<Directory> appDataDirectory({String scratch = scratchDataName}) async {
  if (scratch.isEmpty) return getApplicationSupportDirectory();
  final temporary = await getTemporaryDirectory();
  return Directory('${temporary.path}${Platform.pathSeparator}$scratch');
}
