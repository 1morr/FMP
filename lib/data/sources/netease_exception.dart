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
  bool get isUnavailable => numericCode == -200;

  @override
  bool get isRateLimited => numericCode == -460 || numericCode == -462;

  @override
  bool get isGeoRestricted => false;

  @override
  bool get requiresLogin => numericCode == 301;

  @override
  bool get isNetworkError => numericCode == -998;

  @override
  bool get isTimeout => numericCode == -997;

  @override
  bool get isPermissionDenied => numericCode == 403;

  /// VIP 歌曲需付費
  @override
  bool get isVipRequired => numericCode == -10;

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
