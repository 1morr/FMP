import 'package:dio/dio.dart';
import '../../i18n/strings.g.dart';
import '../models/track.dart';

/// 音源 API 统一异常基类
///
/// 所有音源（Bilibili、YouTube 等）的 API 异常都应继承此类，
/// 使 AudioController 能用统一的 catch 块处理不同来源的错误。
abstract class SourceApiException implements Exception {
  const SourceApiException();

  /// 语义化错误代码（如 'rate_limited', 'unavailable', 'timeout'）
  String get code;

  /// 人类可读的错误消息
  String get message;

  /// 错误来源
  SourceType get sourceType;

  // ========== 统一语义 getter ========== //

  /// 内容不可用（已删除/下架/不可播放）
  bool get isUnavailable;

  /// 被限流
  bool get isRateLimited;

  /// 地区限制
  bool get isGeoRestricted;

  /// 需要登录
  bool get requiresLogin;

  /// 网络连接错误
  bool get isNetworkError;

  /// 超时
  bool get isTimeout;

  // ========== 通用 Dio 错误分类 ========== //

  /// 将 DioException 分类为语义化的 (code, message) 对。
  /// 各 Source 的 _handleDioError 可调用此方法后构造自己的异常类型。
  static ({String code, String message}) classifyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return (code: 'timeout', message: t.error.connectionTimeout);
      case DioExceptionType.connectionError:
        return (code: 'network_error', message: t.error.networkError);
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 429 || statusCode == 412) {
          return (code: 'rate_limited', message: t.error.rateLimited);
        }
        return (
          code: 'api_error',
          message: 'Server error: $statusCode',
        );
      default:
        return (code: 'network_error', message: t.error.networkError);
    }
  }
}
