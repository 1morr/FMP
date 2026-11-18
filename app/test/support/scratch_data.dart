import 'package:fmp/platform/app_data_directory.dart';

/// 開真的 App（`main.dart`）的 integration_test 與實跑，App 的資料（資料庫、
/// log、封面快取）放在 `FMP_SCRATCH_DATA` 指名的隔離目錄（[appDataDirectory]），
/// 不碰擁有者 dev 版的資料。開 App 前呼叫：沒帶這個 define 就丟 [StateError]，
/// 訊息是 [howToRun]（該怎麼跑）；[fresh] 時清空那個目錄，每次從沒有資料開始。
Future<void> useScratchData({
  required String howToRun,
  bool fresh = true,
}) async {
  if (scratchDataName.isEmpty) throw StateError(howToRun);
  if (!fresh) return;
  final data = await appDataDirectory();
  if (data.existsSync()) data.deleteSync(recursive: true);
}
