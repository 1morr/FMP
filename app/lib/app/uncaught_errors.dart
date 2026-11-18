import 'package:flutter/foundation.dart';
import 'package:fmp/core/log/log.dart';

/// 沒有人接住的錯誤寫進 [log]（brief〈錯誤、log 與診斷〉）：框架回報的
/// （build、layout、手勢裡丟的）照舊交給原本的處理（debug 版印到 console），
/// 非同步裡沒人接的標成已處理，不再由引擎另外印。`main` 開好 log 後呼叫。
void logUncaughtErrors(Log log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final where = details.library == null ? '' : ' (${details.library})';
    log.error(
      'Uncaught error$where',
      error: details.exception,
      stackTrace: details.stack,
    );
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.error(
      'Uncaught asynchronous error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
}
