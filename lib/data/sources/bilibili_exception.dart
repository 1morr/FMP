import '../models/track.dart';
import 'source_exception.dart';

/// Bilibili API 错误
class BilibiliApiException extends SourceApiException {
  final int numericCode;
  @override
  final String message;

  const BilibiliApiException(
      {required this.numericCode, required this.message});

  @override
  String get code => _mapCode(numericCode);

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String toString() => 'BilibiliApiException($numericCode): $message';

  @override
  SourceErrorKind get kind {
    if (numericCode == -1) return SourceErrorKind.timeout;
    if (numericCode == -2) return SourceErrorKind.network;
    if (numericCode == -412 ||
        numericCode == -509 ||
        numericCode == -799 ||
        numericCode == -429) {
      return SourceErrorKind.rateLimited;
    }
    if (numericCode == -404 || numericCode == -503 || numericCode == 62002) {
      return SourceErrorKind.unavailable;
    }
    if (numericCode == -101) return SourceErrorKind.loginRequired;
    if (numericCode == -403 || numericCode == 62012) {
      return SourceErrorKind.permissionDenied;
    }
    if (numericCode == -10403) return SourceErrorKind.geoRestricted;
    return SourceErrorKind.unknown;
  }

  /// 将数字错误码映射为语义化字符串
  static String _mapCode(int code) {
    if (code == -404 || code == -503 || code == 62002) return 'unavailable';
    if (code == -412 || code == -509 || code == -799 || code == -429) {
      return 'rate_limited';
    }
    if (code == -10403) return 'geo_restricted';
    if (code == -101) return 'login_required';
    if (code == -403 || code == 62012) return 'permission_denied';
    if (code == -1) return 'timeout';
    if (code == -2) return 'network_error';
    if (code == -999) return 'error';
    return 'api_error';
  }
}
