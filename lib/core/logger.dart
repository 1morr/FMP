import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

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
}

/// 简单日志工具
class AppLogger {
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// 日志缓冲区（最多保留 500 条）
  static final List<LogEntry> _logBuffer = [];
  static const int _maxBufferSize = 500;

  /// 日志流控制器（用于实时更新）
  static final _logStreamController = StreamController<LogEntry>.broadcast();

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
  static void error(String message, [Object? error, StackTrace? stackTrace, String? tag]) {
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

    final prefix = switch (level) {
      LogLevel.debug => '[DEBUG]',
      LogLevel.info => '[INFO]',
      LogLevel.warning => '[WARN]',
      LogLevel.error => '[ERROR]',
    };

    final tagStr = tag != null ? '[$tag] ' : '';
    final fullMessage = '$prefix $tagStr$message';

    // 创建日志条目
    final entry = LogEntry(
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
    );

    // 添加到缓冲区
    _logBuffer.add(entry);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }

    // 发送到流
    _logStreamController.add(entry);

    // 在 debug 模式下使用 developer.log，release 模式下使用 debugPrint
    if (kDebugMode) {
      developer.log(
        fullMessage,
        name: 'FMP',
        error: error,
        stackTrace: stackTrace,
        level: level == LogLevel.error ? 1000 : 800,
      );
    }

    // 始终输出到控制台
    debugPrint(fullMessage);
    if (error != null) {
      debugPrint('  Error: $error');
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
