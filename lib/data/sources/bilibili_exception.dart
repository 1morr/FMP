import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_exception.dart';

/// Bilibili API 错误
class BilibiliApiException extends SourceApiException {
  final int numericCode;
  @override
  final String message;

  const BilibiliApiException({
    required this.numericCode,
    required this.message,
  });

  /// B 站的風控碼。遇到一律分類成 `rateLimited`，由呼叫端退避，不換指紋重試；
  /// 為什麼見 `bilibili_source.dart` 裡 `_checkResponse` 的三輪量測。
  ///
  /// 這份清單是唯一來源：`_checkResponse` 與直播 client 都經過
  /// [isRiskControlCode]。`source_exception_test.dart` 釘住它的內容。
  static const Set<int> riskControlCodes = {-352, -412, -509, -799};

  static bool isRiskControlCode(int code) => riskControlCodes.contains(code);

  /// HTTP 412 / 429 在 `_handleDioError` 裡轉成的合成碼，同樣算限流。
  static const int httpRateLimitedCode = -429;

  @override
  String get code => _mapCode(numericCode);

  @override
  String get sourceType => SourceIds.bilibili;

  @override
  String toString() => 'BilibiliApiException($numericCode): $message';

  @override
  SourceErrorKind get kind {
    if (numericCode == -1) return SourceErrorKind.timeout;
    if (numericCode == -2) return SourceErrorKind.network;
    if (isRiskControlCode(numericCode) || numericCode == httpRateLimitedCode) {
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
    if (isRiskControlCode(code) || code == httpRateLimitedCode) {
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
