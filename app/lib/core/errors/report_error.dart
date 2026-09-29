part of 'app_error.dart';

/// 錯誤歷史的寫入口（ADR 0011 §決定 5、ADR 0013 §決定 3）。
///
/// 放在 `app_error.dart` 的函式庫裡（`part`），才讀得到 [AppError] 的私有
/// 原始 error 與 stackTrace；函式庫以外沒有其他路徑拿到它們。
extension AppErrorReport on Log {
  /// 把處理過的 [error] 經門面寫進錯誤歷史。
  ///
  /// [message] 是失敗的動作（英文，例如 `'Search failed'`），[tag] 是模組或
  /// 音源 id，比照 [Log.write]。層級：[AppError.expected] 為真是 `warning`，
  /// 否則是 `error`。原始 error 與 stackTrace 交給門面遮蔽；型別、音源、網路
  /// 紀錄 id、可否重試與 `Retry-After` 放結構化欄位，Debug 頁依它們篩選。
  void report(String message, AppError error, {required String tag}) => write(
    error.expected ? LogLevel.warning : LogLevel.error,
    message,
    tag: tag,
    error: error._cause,
    stackTrace: error._stackTrace,
    fields: {
      'type': _typeName(error),
      'pluginId': ?error.pluginId,
      if (error case Unavailable(:final reason)) 'reason': reason.name,
      'networkRecordId': ?error.networkRecordId,
      'retryable': error.retryable,
      if (error.retryAfter case final delay?)
        'retryAfterMs': delay.inMilliseconds,
    },
  );
}
