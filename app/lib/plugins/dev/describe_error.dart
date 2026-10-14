import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';

/// 把 [error] 寫成一行「類別名: 已遮蔽的原因」（原因只有 `log.report` 讀得到，
/// 所以經 [log]，tag 是 [tag]、訊息是 [message]）。
///
/// 獨立一個檔：`plugin_folder.dart` 與 `case_runner.dart` 互相需要時不致循環。
String describeError(
  AppError error,
  Log log, {
  required String tag,
  String message = 'Plugin case',
}) {
  log.report(message, error, tag: tag);
  final cause = log.history.last.error;
  return cause == null ? error.typeName : '${error.typeName}: $cause';
}
