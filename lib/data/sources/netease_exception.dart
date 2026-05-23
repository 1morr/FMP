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
    if (numericCode == 404 || numericCode == -404 || numericCode == -503) {
      return SourceErrorKind.unavailable;
    }
    if (numericCode == 301) return SourceErrorKind.loginRequired;
    if (numericCode == 403 || numericCode == -403) {
      return SourceErrorKind.permissionDenied;
    }
    if (numericCode == -10) return SourceErrorKind.vipRequired;
    if (numericCode == -110) return SourceErrorKind.geoRestricted;
    return SourceErrorKind.unknown;
  }

  static String _mapCode(int numericCode) {
    switch (numericCode) {
      case -460:
      case -462:
        return 'rate_limited';
      case 301:
        return 'login_required';
      case -403:
      case 403:
        return 'forbidden';
      case -200:
      case 404:
      case -404:
      case -503:
        return 'unavailable';
      case -10:
        return 'vip_required';
      case -110:
        return 'geo_restricted';
      case -997:
        return 'timeout';
      case -998:
        return 'network_error';
      default:
        return 'api_error';
    }
  }
}
