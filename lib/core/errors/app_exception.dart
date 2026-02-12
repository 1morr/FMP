import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../logger.dart';

/// 应用异常基类
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() => message;
}

/// 网络异常
class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    super.code,
    super.originalError,
  });
}

/// 服务器异常
class ServerException extends AppException {
  final int? statusCode;

  const ServerException(
    super.message, {
    this.statusCode,
    super.code,
    super.originalError,
  });
}

/// 资源未找到异常
class NotFoundException extends AppException {
  const NotFoundException(
    super.message, {
    super.code,
    super.originalError,
  });
}

/// 权限异常
class PermissionException extends AppException {
  const PermissionException(
    super.message, {
    super.code,
    super.originalError,
  });
}

/// 取消异常（用户主动取消）
class CancelledException extends AppException {
  const CancelledException([
    super.message = '操作已取消',
  ]);
}

/// 错误处理工具类
class ErrorHandler with Logging {
  ErrorHandler._();

  static final _instance = ErrorHandler._();

  /// 将原始异常转换为 AppException
  static AppException wrap(dynamic error) {
    if (error is AppException) {
      return error;
    }

    if (error is DioException) {
      return _handleDioError(error);
    }

    if (error is SocketException) {
      return NetworkException(
        t.error.networkError,
        originalError: error,
      );
    }

    if (error is HttpException) {
      return NetworkException(
        t.error.networkRequestFailedDetail(message: error.message),
        originalError: error,
      );
    }

    if (error is FormatException) {
      return ServerException(
        t.error.dataFormatError,
        originalError: error,
      );
    }

    return AppException(
      error?.toString() ?? t.error.unknownError,
      originalError: error,
    );
  }

  static AppException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return NetworkException(
          t.error.connectionTimeout,
          code: 'TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.sendTimeout:
        return NetworkException(
          t.error.sendTimeout,
          code: 'SEND_TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.receiveTimeout:
        return NetworkException(
          t.error.receiveTimeout,
          code: 'RECEIVE_TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          t.error.certificateFailed,
          code: 'CERT_ERROR',
          originalError: error,
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 404) {
          return NotFoundException(
            t.error.resourceNotFound,
            code: '404',
            originalError: error,
          );
        }
        if (statusCode == 403 || statusCode == 401) {
          return PermissionException(
            t.error.noPermission,
            code: statusCode.toString(),
            originalError: error,
          );
        }
        if (statusCode != null && statusCode >= 500) {
          return ServerException(
            t.error.serverError(code: statusCode),
            statusCode: statusCode,
            originalError: error,
          );
        }
        return NetworkException(
          t.error.requestFailed(code: statusCode ?? 0),
          code: statusCode?.toString(),
          originalError: error,
        );

      case DioExceptionType.cancel:
        return CancelledException();

      case DioExceptionType.connectionError:
        return NetworkException(
          t.error.cannotConnectServer,
          code: 'CONNECTION_ERROR',
          originalError: error,
        );

      case DioExceptionType.unknown:
        final message = error.message ?? t.error.networkRequestFailed;
        return NetworkException(
          message,
          originalError: error,
        );
    }
  }

  /// 获取用户友好的错误消息
  static String getDisplayMessage(dynamic error) {
    final appError = wrap(error);
    return appError.message;
  }

  /// 记录错误日志
  static void log(dynamic error, [StackTrace? stackTrace]) {
    _instance.logError('Error occurred', error, stackTrace);
  }

  /// 是否为取消异常
  static bool isCancelled(dynamic error) {
    if (error is CancelledException) return true;
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return true;
    }
    return false;
  }

  /// 是否为网络异常
  static bool isNetworkError(dynamic error) {
    if (error is NetworkException) return true;
    if (error is SocketException) return true;
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout;
    }
    return false;
  }
}
