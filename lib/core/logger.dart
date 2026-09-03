import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import 'log_file_sink.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志条目
class LogEntry {
  final LogLevel level;
  final String message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  const LogEntry({
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
    required this.timestamp,
  });

  String get levelPrefix => switch (level) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warning => 'W',
        LogLevel.error => 'E',
      };

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final tagStr = tag != null ? '[$tag] ' : '';
    return '[$levelPrefix] $formattedTime $tagStr$message';
  }

  /// 落盤用的格式。跟 [toString] 分開：畫面上的一行不需要日期，但輪替後的
  /// log 檔會跨天，而且 error 與 stack trace 正是事後翻 log 要看的東西。
  String toFileLine() {
    final date = '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final buffer = StringBuffer('$date $formattedTime [$levelPrefix] ')
      ..write(tag != null ? '[$tag] ' : '')
      ..write(message);
    if (error != null) buffer.write('\n  Error: $error');
    if (stackTrace != null) buffer.write('\n  StackTrace: $stackTrace');
    return buffer.toString();
  }
}

/// 简单日志工具
class AppLogger {
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// 日志缓冲区（最多保留 500 条；用 Queue 讓超出上限時的淘汰為 O(1)，A7）
  static final Queue<LogEntry> _logBuffer = Queue();
  static const int _maxBufferSize = 500;

  /// 日志流控制器（用于实时更新）
  static final _logStreamController = StreamController<LogEntry>.broadcast();

  /// 落盤 sink。要等 `WidgetsFlutterBinding.ensureInitialized()` 之後才裝得起來
  /// （`path_provider` 需要 binding），而 `main.dart` 的兩個錯誤處理器掛在那之前。
  static LogFileSink? _fileSink;

  static final RegExp _authorizationPattern = RegExp(
    r"""(["']?Authorization["']?\s*[:=]\s*["']?)([^"',;}\r\n]+)""",
    caseSensitive: false,
  );
  static final RegExp _sapisidHashPattern = RegExp(
    r'SAPISIDHASH\s+[A-Za-z0-9._:-]+',
    caseSensitive: false,
  );
  static final RegExp _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._-]+',
    caseSensitive: false,
  );
  static final RegExp _cookieHeaderPattern = RegExp(
    r"""(["']?Cookie["']?\s*[:=]\s*["']?)([^"',}\r\n]+)""",
    caseSensitive: false,
  );
  static const List<String> _sensitiveKeys = [
    'MUSIC_U',
    'musicU',
    '__csrf',
    // Bilibili 的写操作把 bili_jct 的值作为裸 csrf 参数发出
    // （bilibili_favorites_service.dart:131 等），只遮 __csrf 漏掉这一路。
    'csrf',
    'eparams',
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
    'refresh_token',
    'access_token',
    'apiKey',
    'SAPISID',
    'APISID',
    'SID',
    'HSID',
    'SSID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    '__Secure-1PAPISID',
    '__Secure-3PAPISID',
    'LOGIN_INFO',
    'storePassword',
    'keyPassword',
    'password',
    'token',
  ];
  static final List<RegExp> _sensitiveKeyPatterns = _sensitiveKeys
      .map(
        (key) => RegExp(
          '(["\\\']?${RegExp.escape(key)}["\\\']?\\s*[:=]\\s*["\\\']?)([^"\\\',;\\s}]+)',
          caseSensitive: false,
        ),
      )
      .toList(growable: false);

  /// 日志流（用于实时监听）
  static Stream<LogEntry> get logStream => _logStreamController.stream;

  /// 获取所有缓存的日志
  static List<LogEntry> get logs => List.unmodifiable(_logBuffer);

  /// 清空日志缓冲区
  static void clearLogs() {
    _logBuffer.clear();
  }

  /// 设置最小日志级别
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// 目前的最小日志级别。
  static LogLevel get minLevel => _minLevel;

  /// 目前掛著的落盤 sink，沒有就是 null。
  static LogFileSink? get fileSink => _fileSink;

  /// 開始把 log 寫進檔案。
  ///
  /// 掛上之後第一件事是把既有的記憶體緩衝整個倒進檔案 —— 啟動期的 log 在
  /// sink 就緒之前就已經產生了（binding 初始化之前的錯誤處理器就會記），
  /// 而那正是最需要事後翻的一批。緩衝有 500 筆，遠大於啟動期的產量。
  static Future<void> attachFileSink(LogFileSink sink) async {
    await sink.open();
    if (!sink.isOpen) return;
    _fileSink = sink;
    for (final entry in _logBuffer) {
      sink.write(entry.toFileLine());
    }
  }

  /// 卸下落盤 sink（測試用）。
  static void detachFileSink() {
    _fileSink = null;
  }

  static String redactSensitive(String input) {
    var redacted = input;
    redacted = redacted.replaceAllMapped(
      _authorizationPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    redacted = redacted.replaceAll(
      _sapisidHashPattern,
      'SAPISIDHASH [REDACTED]',
    );
    redacted = redacted.replaceAll(
      _bearerPattern,
      'Bearer [REDACTED]',
    );
    redacted = redacted.replaceAllMapped(
      _cookieHeaderPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );

    for (final pattern in _sensitiveKeyPatterns) {
      redacted = redacted.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return redacted;
  }

  /// 调试日志
  static void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  /// 信息日志
  static void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  /// 警告日志
  static void warning(String message, [String? tag]) {
    _log(LogLevel.warning, message, tag);
  }

  /// 错误日志
  static void error(String message,
      [Object? error, StackTrace? stackTrace, String? tag]) {
    _log(LogLevel.error, message, tag, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message,
    String? tag, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < _minLevel.index) return;
    final safeMessage = redactSensitive(message);
    final Object? safeError =
        error == null ? null : redactSensitive(error.toString());

    final prefix = switch (level) {
      LogLevel.debug => '[DEBUG]',
      LogLevel.info => '[INFO]',
      LogLevel.warning => '[WARN]',
      LogLevel.error => '[ERROR]',
    };

    final tagStr = tag != null ? '[$tag] ' : '';
    final fullMessage = '$prefix $tagStr$safeMessage';

    // 创建日志条目
    final entry = LogEntry(
      level: level,
      message: safeMessage,
      tag: tag,
      error: safeError,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );

    // 添加到缓冲区
    _logBuffer.add(entry);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeFirst();
    }

    // 发送到流
    _logStreamController.add(entry);

    // 落盤寫的是同一份已 redact 的內容
    _fileSink?.write(entry.toFileLine());

    // 在 debug 模式下使用 developer.log，release 模式下使用 debugPrint
    if (kDebugMode) {
      developer.log(
        fullMessage,
        name: 'FMP',
        error: safeError,
        stackTrace: stackTrace,
        level: level == LogLevel.error ? 1000 : 800,
      );
    }

    // 始终输出到控制台
    debugPrint(fullMessage);
    if (safeError != null) {
      debugPrint('  Error: $safeError');
    }
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
  }
}

/// 便捷扩展 - 为类添加日志方法
mixin Logging {
  String get logTag => runtimeType.toString();

  void logDebug(String message) => AppLogger.debug(message, logTag);
  void logInfo(String message) => AppLogger.info(message, logTag);
  void logWarning(String message) => AppLogger.warning(message, logTag);
  void logError(String message, [Object? error, StackTrace? stackTrace]) =>
      AppLogger.error(message, error, stackTrace, logTag);
}
