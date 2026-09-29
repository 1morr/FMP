import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart' as talker;

import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';

/// 這個建置的預設層級（ADR 0011 §決定 2）：debug build 是 [LogLevel.debug]，
/// profile 與 release 是 [LogLevel.info]。開發者模式調整層級在 M3。
LogLevel get buildDefaultLogLevel =>
    kDebugMode ? LogLevel.debug : LogLevel.info;

/// 全 App 唯一的 log 入口（ADR 0011 §決定 1）。
///
/// 每筆先經 [Redactor] 遮蔽訊息、error、stackTrace 與結構化欄位，再交給
/// `talker`；talker 只負責記憶體歷史與分派（console、log 檔）。門面以外禁止
/// `print`、`debugPrint`、`dart:developer` 的 `log` 與直接用 talker（lint
/// `fmp_log_facade`）。
///
/// 輸出：
/// - 記憶體歷史：最近 [historyLimit] 筆（[history]）；
/// - log 檔：有給 [file] 才寫；
/// - console：只在 debug build。release 不寫到 logcat／stdout。
final class Log {
  Log({required this._redactor, required this.minimumLevel, this.file}) {
    _talker = talker.Talker(
      settings: talker.TalkerSettings(
        maxHistoryItems: historyLimit,
        useConsoleLogs: kDebugMode,
      ),
      // ANSI 色碼在 logcat 與 IDE 的輸出窗格是亂碼。
      logger: talker.TalkerLogger(
        settings: talker.TalkerLoggerSettings(enableColors: false),
      ),
      observer: _Dispatch(file),
    );
  }

  /// 記憶體歷史的筆數上限。
  static const historyLimit = 1000;

  final Redactor _redactor;
  late final talker.Talker _talker;

  /// 低於這個層級的紀錄直接丟掉，不進任何輸出。
  final LogLevel minimumLevel;

  /// log 檔；沒有資料目錄的平台為 `null`。
  final LogFile? file;

  /// 記憶體歷史，由舊到新。內容都已遮蔽。
  List<LogRecord> get history => [
    for (final data in _talker.history)
      if (data is _RecordLog) data.record,
  ];

  void debug(
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => write(
    LogLevel.debug,
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void info(
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => write(
    LogLevel.info,
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void warning(
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => write(
    LogLevel.warning,
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void error(
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => write(
    LogLevel.error,
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// 寫一筆 log。[tag] 是模組或音源 id；[fields] 會遞迴遮蔽。不會拋出。
  void write(
    LogLevel level,
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    if (level.index < minimumLevel.index) return;
    final time = DateTime.now().toUtc();
    LogRecord record;
    try {
      final redactedFields = _redactor.redactValue(fields);
      record = LogRecord(
        time: time,
        level: level,
        tag: _redactor.redact(tag),
        message: _redactor.redact(message),
        error: error == null ? null : _redactor.redactObject(error),
        stackTrace: stackTrace == null || stackTrace == StackTrace.empty
            ? null
            : _redactor.redact(stackTrace.toString()),
        fields: redactedFields is Map<String, Object?> ? redactedFields : {},
      );
    } on Object catch (failure) {
      // 遮蔽失敗時不能退回原文：只留層級、時間與失敗的型別，原本的內容
      // 整筆丟掉。
      record = LogRecord(
        time: time,
        level: level,
        tag: 'log',
        message: 'Redaction failed; record dropped',
        error: '${failure.runtimeType}',
      );
    }
    // 原始的 error 與 stackTrace 不交給 talker：它的歷史會原樣留著。
    _talker.logCustom(_RecordLog(record));
  }
}

/// talker 的紀錄只包著已遮蔽的 [LogRecord]；console 的文字也由它產生。
final class _RecordLog extends talker.TalkerLog {
  _RecordLog(this.record)
    : super(
        record.message,
        key: talker.TalkerKey.fromLogLevel(_talkerLevel(record.level)),
        logLevel: _talkerLevel(record.level),
        time: record.time.toLocal(),
      );

  final LogRecord record;

  @override
  String generateTextMessage({
    talker.TimeFormat timeFormat = talker.TimeFormat.timeAndSeconds,
  }) {
    final buffer = StringBuffer(
      '${displayTitleWithTime(timeFormat: timeFormat)}'
      '[${record.tag}] ${record.message}',
    );
    if (record.fields.isNotEmpty) buffer.write('\n${record.fields}');
    if (record.error case final error?) buffer.write('\n$error');
    if (record.stackTrace case final stackTrace?) {
      buffer.write('\nStackTrace: $stackTrace');
    }
    return buffer.toString();
  }

  static talker.LogLevel _talkerLevel(LogLevel level) => switch (level) {
    LogLevel.debug => talker.LogLevel.debug,
    LogLevel.info => talker.LogLevel.info,
    LogLevel.warning => talker.LogLevel.warning,
    LogLevel.error => talker.LogLevel.error,
  };
}

/// talker 的分派：每筆紀錄寫一行到 log 檔。
final class _Dispatch extends talker.TalkerObserver {
  const _Dispatch(this.file);

  final LogFile? file;

  @override
  void onLog(talker.TalkerData log) {
    if (log is _RecordLog) file?.write(log.record.toJsonLine());
  }
}
