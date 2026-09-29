import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log.dart';

/// 把未捕捉的錯誤經門面以 `error` 寫入（ADR 0011 §決定 5）：
///
/// - [FlutterError.onError]：框架回報的錯誤（build、layout、手勢等）；
/// - [PlatformDispatcher.onError]：其餘沒人接的非同步錯誤。回傳 `true` 表示已
///   處理，引擎不再印到 console，release 版因此不輸出到 logcat。
///
/// debug build 的 console 由門面輸出，所以不再接回原本的處理器。
void routeUncaughtErrors(Log log, PlatformDispatcher dispatcher) {
  FlutterError.onError = (details) => log.error(
    'Uncaught Flutter error',
    tag: 'flutter',
    error: details.exception,
    stackTrace: details.stack,
    fields: {
      'library': ?details.library,
      if (details.context case final context?) 'context': '$context',
    },
  );
  dispatcher.onError = (error, stackTrace) {
    log.error(
      'Uncaught error',
      tag: 'platform',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
}
