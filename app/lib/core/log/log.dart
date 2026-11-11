import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:logger/logger.dart' as lg;

/// 整個 App 共用的 log。`main` 開好再 override 進來。
final logProvider = Provider<Log>(
  (ref) => throw StateError('logProvider is overridden in main()'),
);

/// log 的層級，由低到高。
enum LogLevel { debug, info, warning, error }

/// release 版保留 info 以上，其他建置保留 debug 以上（brief §13）。
LogLevel minimumLogLevel({required bool release}) =>
    release ? LogLevel.info : LogLevel.debug;

/// App 唯一的 log 門面（brief §13）。每一筆在寫出前都經過 [redact]，寫進
/// `fmp.log` 並依大小輪替。
///
/// 只有 `core/log/` 能 import `logger` 套件（依賴規則測試守著）；其他模組只用
/// 這個類別。訊息用英文、不拼進憑證：遮蔽是最後一道防線，不是藉口。
class Log {
  Log._(this._logger);

  /// 正在寫的檔名；輪替出去的檔是 `fmp-<時間>.log`。
  static const fileName = 'fmp.log';

  /// 單檔上限，超過就輪替。
  static const defaultMaxFileKB = 2048;

  /// 最多保留的檔案數，含正在寫的 `fmp.log`。
  static const defaultKeptFiles = 3;

  final lg.Logger _logger;

  /// 在 [directory] 開 log。目錄只放 log 檔：輪替時會刪掉這裡最舊的其他檔。
  ///
  /// 輪替每 [rotationCheck] 檢查一次（開啟時也檢查），所以檔案可能略超過
  /// [maxFileKB]。[console] 為真時同時印到 console（debug 建置用）。
  static Future<Log> open(
    Directory directory, {
    required LogLevel minimumLevel,
    bool console = false,
    int maxFileKB = defaultMaxFileKB,
    int keptFiles = defaultKeptFiles,
    Duration rotationCheck = const Duration(minutes: 1),
  }) async {
    final file = lg.AdvancedFileOutput(
      path: directory.path,
      latestFileName: fileName,
      fileNameFormatter: _rotatedFileName,
      maxFileSizeKB: maxFileKB,
      maxRotatedFilesCount: keptFiles - 1,
      fileUpdateDuration: rotationCheck,
      // 每筆都馬上交給檔案，不在記憶體裡等 2 秒：當掉前的最後幾筆最有用。
      writeImmediately: lg.Level.values,
    );
    final logger = lg.Logger(
      filter: lg.ProductionFilter(),
      printer: _RedactingPrinter(),
      output: console ? lg.MultiOutput([file, lg.ConsoleOutput()]) : file,
      level: _levels[minimumLevel],
    );
    await logger.init;
    return Log._(logger);
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.d(message, error: error, stackTrace: stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.i(message, error: error, stackTrace: stackTrace);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  /// 把還沒寫出的紀錄寫完並關檔。之後不能再寫。
  Future<void> close() => _logger.close();
}

const _levels = {
  LogLevel.debug: lg.Level.debug,
  LogLevel.info: lg.Level.info,
  LogLevel.warning: lg.Level.warning,
  LogLevel.error: lg.Level.error,
};

String _rotatedFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'fmp-${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
      '${t.millisecond.toString().padLeft(3, '0')}.log';
}

/// 一筆一行：`<UTC 時間> <層級> <訊息>[ | <error>]`，stack trace 接在後面幾行。
/// 整筆先經過 [redact] 才交給輸出端，檔案與 console 都拿到遮過的內容。
class _RedactingPrinter extends lg.LogPrinter {
  @override
  List<String> log(lg.LogEvent event) {
    final level = event.level.name.toUpperCase();
    final buffer = StringBuffer(
      '${event.time.toUtc().toIso8601String()} $level ${event.message}',
    );
    if (event.error case final error?) buffer.write(' | $error');
    if (event.stackTrace case final stack?) {
      buffer.write('\n${stack.toString().trimRight()}');
    }
    return redact(buffer.toString()).split('\n');
  }
}
