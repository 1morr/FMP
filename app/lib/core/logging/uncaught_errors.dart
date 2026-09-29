import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';

/// 把未捕捉的錯誤經門面以 `error` 寫入（ADR 0011 §決定 5）：
///
/// - [FlutterError.onError]：框架回報的錯誤（build、layout、手勢等）；
/// - [PlatformDispatcher.onError]：其餘沒人接的非同步錯誤。回傳 `true` 表示已
///   處理，引擎不再印到 console，release 版因此不輸出到 logcat。
///
/// 未捕捉的是 [AppError] 時改走 [AppErrorReport.report]：它的原始 error 與
/// stackTrace 是私有欄位，傳給 `error:` 只會寫出不含原因的 `toString()`。
/// 層級仍固定是 `error`（`report` 的 `level`）：沒人接的錯誤就是沒處理，
/// [AppError.expected] 只決定處理過的錯誤的層級。
///
/// debug build 的 console 由門面輸出，所以不再接回原本的處理器。
void routeUncaughtErrors(Log log, PlatformDispatcher dispatcher) {
  FlutterError.onError = (details) {
    const message = 'Uncaught Flutter error';
    if (details.exception case final AppError error) {
      return log.report(message, error, tag: 'flutter', level: LogLevel.error);
    }
    log.error(
      message,
      tag: 'flutter',
      error: details.exception,
      stackTrace: details.stack,
      fields: {
        'library': ?details.library,
        if (details.context case final context?) 'context': '$context',
      },
    );
  };
  dispatcher.onError = (error, stackTrace) {
    const message = 'Uncaught error';
    if (error case final AppError appError) {
      log.report(message, appError, tag: 'platform', level: LogLevel.error);
    } else {
      log.error(message, tag: 'platform', error: error, stackTrace: stackTrace);
    }
    return true;
  };
}
