import 'package:dio/dio.dart';
import '../../i18n/strings.g.dart';
import '../models/track.dart';

enum SourceErrorKind {
  network,
  timeout,
  rateLimited,
  unavailable,
  permissionDenied,
  loginRequired,
  geoRestricted,
  vipRequired,
  unknown;

  bool get isRetryable =>
      this == SourceErrorKind.network || this == SourceErrorKind.timeout;

  bool get shouldSkipTrack =>
      this == SourceErrorKind.unavailable ||
      this == SourceErrorKind.geoRestricted ||
      this == SourceErrorKind.vipRequired;

  bool get canFallbackToLowerAudioQuality =>
      this == SourceErrorKind.unavailable ||
      this == SourceErrorKind.vipRequired;
}

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

  SourceErrorKind get kind => SourceErrorKind.unknown;

  // ========== 统一语义 getter ========== //

  /// 内容不可用（已删除/下架/不可播放）
  bool get isUnavailable => kind == SourceErrorKind.unavailable;

  /// 被限流
  bool get isRateLimited => kind == SourceErrorKind.rateLimited;

  /// 地区限制
  bool get isGeoRestricted => kind == SourceErrorKind.geoRestricted;

  /// 需要登录
  bool get requiresLogin => kind == SourceErrorKind.loginRequired;

  /// 网络连接错误
  bool get isNetworkError => kind == SourceErrorKind.network;

  /// 超时
  bool get isTimeout => kind == SourceErrorKind.timeout;

  /// 权限不足（私人内容，需要登录重试）
  /// 与 requiresLogin 不同：requiresLogin 表示"未登录"，
  /// isPermissionDenied 表示"内容需要特定权限（如私人收藏夹/视频）"
  bool get isPermissionDenied => kind == SourceErrorKind.permissionDenied;

  /// VIP/付費內容（需要會員才能播放）
  bool get isVipRequired => kind == SourceErrorKind.vipRequired;

  // ========== 通用 Dio 错误分类 ========== //

  /// 将 DioException 分类为语义化的 (kind, code, message) 对。
  /// 各 Source 的 _handleDioError 可调用此方法后构造自己的异常类型。
  static ({SourceErrorKind kind, String code, String message}) classifyDioError(
    DioException e,
  ) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return (
          kind: SourceErrorKind.timeout,
          code: 'timeout',
          message: t.error.connectionTimeout,
        );
      case DioExceptionType.connectionError:
        return (
          kind: SourceErrorKind.network,
          code: 'network_error',
          message: t.error.networkError,
        );
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == null) {
          return (
            kind: SourceErrorKind.unknown,
            code: 'api_error',
            message: t.error.networkError,
          );
        }
        if (statusCode == 429 || statusCode == 412) {
          return (
            kind: SourceErrorKind.rateLimited,
            code: 'rate_limited',
            message: t.error.rateLimited,
          );
        }
        if (statusCode == 403) {
          return (
            kind: SourceErrorKind.permissionDenied,
            code: 'forbidden',
            message: 'Access forbidden (HTTP 403)',
          );
        }
        if (statusCode == 404) {
          return (
            kind: SourceErrorKind.unavailable,
            code: 'not_found',
            message: 'Resource not found (HTTP 404)',
          );
        }
        if (statusCode == 503) {
          return (
            kind: SourceErrorKind.unavailable,
            code: 'service_unavailable',
            message: 'Service temporarily unavailable (HTTP 503)',
          );
        }
        return (
          kind: SourceErrorKind.unknown,
          code: 'api_error',
          message: 'Server error: $statusCode',
        );
      default:
        return (
          kind: SourceErrorKind.network,
          code: 'network_error',
          message: t.error.networkError,
        );
    }
  }
}
