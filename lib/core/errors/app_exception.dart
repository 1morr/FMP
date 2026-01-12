import 'dart:io';

import 'package:dio/dio.dart';

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
        '网络连接失败',
        originalError: error,
      );
    }

    if (error is HttpException) {
      return NetworkException(
        '网络请求失败: ${error.message}',
        originalError: error,
      );
    }

    if (error is FormatException) {
      return ServerException(
        '数据格式错误',
        originalError: error,
      );
    }

    return AppException(
      error?.toString() ?? '未知错误',
      originalError: error,
    );
  }

  static NetworkException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return NetworkException(
          '连接超时，请检查网络',
          code: 'TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.sendTimeout:
        return NetworkException(
          '发送超时，请检查网络',
          code: 'SEND_TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.receiveTimeout:
        return NetworkException(
          '接收超时，请检查网络',
          code: 'RECEIVE_TIMEOUT',
          originalError: error,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          '证书验证失败',
          code: 'CERT_ERROR',
          originalError: error,
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 404) {
          return NotFoundException(
            '请求的资源不存在',
            code: '404',
            originalError: error,
          ) as NetworkException;
        }
        if (statusCode == 403 || statusCode == 401) {
          return PermissionException(
            '没有权限访问',
            code: statusCode.toString(),
            originalError: error,
          ) as NetworkException;
        }
        if (statusCode != null && statusCode >= 500) {
          return ServerException(
            '服务器错误 ($statusCode)',
            statusCode: statusCode,
            originalError: error,
          ) as NetworkException;
        }
        return NetworkException(
          '请求失败 ($statusCode)',
          code: statusCode?.toString(),
          originalError: error,
        );

      case DioExceptionType.cancel:
        return CancelledException() as NetworkException;

      case DioExceptionType.connectionError:
        return NetworkException(
          '无法连接到服务器',
          code: 'CONNECTION_ERROR',
          originalError: error,
        );

      case DioExceptionType.unknown:
        final message = error.message ?? '网络请求失败';
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
