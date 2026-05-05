import '../models/track.dart';
import 'source_exception.dart';

/// 網易雲音樂 API 異常
class NeteaseApiException extends SourceApiException {
  /// 網易雲 API 返回的數字碼（如 200, -460, -462, 403）
  final int numericCode;

  @override
  final String message;

  const NeteaseApiException({
    required this.numericCode,
    required this.message,
  });

  @override
  String get code => _mapCode(numericCode);

  @override
  SourceType get sourceType => SourceType.netease;

  @override
  String toString() => 'NeteaseApiException($numericCode): $message';

  @override
  SourceErrorKind get kind {
    if (numericCode == -997) return SourceErrorKind.timeout;
    if (numericCode == -998) return SourceErrorKind.network;
    if (numericCode == -460 || numericCode == -462) {
      return SourceErrorKind.rateLimited;
    }
    if (numericCode == -200) return SourceErrorKind.unavailable;
    if (numericCode == 301) return SourceErrorKind.loginRequired;
    if (numericCode == 403) return SourceErrorKind.permissionDenied;
    if (numericCode == -10) return SourceErrorKind.vipRequired;
    return SourceErrorKind.unknown;
  }

  @override
  bool get isUnavailable => super.isUnavailable;

  @override
  bool get isRateLimited => super.isRateLimited;

  @override
  bool get isGeoRestricted => super.isGeoRestricted;

  @override
  bool get requiresLogin => super.requiresLogin;

  @override
  bool get isNetworkError => super.isNetworkError;

  @override
  bool get isTimeout => super.isTimeout;

  @override
  bool get isPermissionDenied => super.isPermissionDenied;

  /// VIP 歌曲需付費
  @override
  bool get isVipRequired => super.isVipRequired;

  static String _mapCode(int numericCode) {
    switch (numericCode) {
      case -460:
      case -462:
        return 'rate_limited';
      case 301:
        return 'requires_login';
      case 403:
        return 'forbidden';
      case -200:
        return 'unavailable';
      case -997:
        return 'timeout';
      case -998:
        return 'network_error';
      default:
        return 'api_error';
    }
  }
}
