import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fmp/core/errors/app_exception.dart';

/// Offline scenario tests to verify error handling.
///
/// These tests verify that the app handles network errors gracefully.
/// Run with: flutter test test/scenarios/offline_scenarios_test.dart
void main() {
  group('ErrorHandler', () {
    group('DioException handling', () {
      test('connection timeout should return NetworkException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('连接超时'));
        expect((result as NetworkException).code, equals('TIMEOUT'));
      });

      test('send timeout should return NetworkException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.sendTimeout,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('发送超时'));
      });

      test('receive timeout should return NetworkException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.receiveTimeout,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('接收超时'));
      });

      test('connection error should return NetworkException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('无法连接'));
      });

      test('cancel should return CancelledException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.cancel,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<CancelledException>());
        expect(ErrorHandler.isCancelled(error), isTrue);
      });

      test('404 response should return NotFoundException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 404,
          ),
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NotFoundException>());
        expect(result.message, contains('不存在'));
      });

      test('500 response should return ServerException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<ServerException>());
        expect(result.message, contains('服务器错误'));
      });

      test('403 response should return PermissionException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 403,
          ),
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<PermissionException>());
        expect(result.message, contains('权限'));
      });

      test('bad certificate should return NetworkException', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badCertificate,
        );

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('证书'));
      });
    });

    group('SocketException handling', () {
      test('SocketException should return NetworkException', () {
        final error = const SocketException('Connection refused');

        final result = ErrorHandler.wrap(error);

        expect(result, isA<NetworkException>());
        expect(result.message, contains('网络连接'));
      });
    });

    group('isNetworkError detection', () {
      test('should detect connection timeout as network error', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        expect(ErrorHandler.isNetworkError(error), isTrue);
      });

      test('should detect connection error as network error', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        expect(ErrorHandler.isNetworkError(error), isTrue);
      });

      test('should detect SocketException as network error', () {
        const error = SocketException('No route to host');

        expect(ErrorHandler.isNetworkError(error), isTrue);
      });

      test('should detect NetworkException as network error', () {
        const error = NetworkException('Test network error');

        expect(ErrorHandler.isNetworkError(error), isTrue);
      });

      test('should not detect bad response as network error', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 404,
          ),
        );

        expect(ErrorHandler.isNetworkError(error), isFalse);
      });
    });

    group('isCancelled detection', () {
      test('should detect DioException cancel', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.cancel,
        );

        expect(ErrorHandler.isCancelled(error), isTrue);
      });

      test('should detect CancelledException', () {
        const error = CancelledException();

        expect(ErrorHandler.isCancelled(error), isTrue);
      });

      test('should not detect other errors as cancelled', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        expect(ErrorHandler.isCancelled(error), isFalse);
      });
    });

    group('getDisplayMessage', () {
      test('should return user-friendly message for timeout', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final message = ErrorHandler.getDisplayMessage(error);

        expect(message, contains('超时'));
      });

      test('should return user-friendly message for connection error', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        final message = ErrorHandler.getDisplayMessage(error);

        expect(message, contains('服务器'));
      });

      test('should preserve AppException message', () {
        const error = NetworkException('Custom error message');

        final message = ErrorHandler.getDisplayMessage(error);

        expect(message, equals('Custom error message'));
      });
    });

    group('wrap preserves original error', () {
      test('should preserve DioException as originalError', () {
        final originalError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = ErrorHandler.wrap(originalError);

        expect(result.originalError, equals(originalError));
      });

      test('should preserve SocketException as originalError', () {
        const originalError = SocketException('Test');

        final result = ErrorHandler.wrap(originalError);

        expect(result.originalError, equals(originalError));
      });

      test('should return AppException unchanged', () {
        const original = NetworkException('Test');

        final result = ErrorHandler.wrap(original);

        expect(identical(result, original), isTrue);
      });
    });
  });

  group('Exception types', () {
    test('NetworkException has correct properties', () {
      const error = NetworkException(
        'Test message',
        code: 'TEST_CODE',
      );

      expect(error.message, equals('Test message'));
      expect(error.code, equals('TEST_CODE'));
      expect(error.toString(), equals('Test message'));
    });

    test('ServerException has statusCode', () {
      const error = ServerException(
        'Server error',
        statusCode: 503,
      );

      expect(error.statusCode, equals(503));
    });

    test('CancelledException has default message', () {
      const error = CancelledException();

      expect(error.message, contains('取消'));
    });
  });
}
