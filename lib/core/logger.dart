import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 简单日志工具
class AppLogger {
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

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
