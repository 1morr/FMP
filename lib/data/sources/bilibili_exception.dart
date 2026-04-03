import '../models/track.dart';
import 'source_exception.dart';

/// Bilibili API 错误
class BilibiliApiException extends SourceApiException {
  final int numericCode;
  @override
  final String message;

  const BilibiliApiException({required this.numericCode, required this.message});

  @override
  String get code => _mapCode(numericCode);

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String toString() => 'BilibiliApiException($numericCode): $message';

  /// 是否是视频不可用（已删除/下架）
  @override
  bool get isUnavailable => numericCode == -404 || numericCode == 62002;

  /// 是否是限流
  @override
  bool get isRateLimited =>
      numericCode == -412 ||
      numericCode == -509 ||
      numericCode == -799 ||
      numericCode == -429;

  /// 是否需要登录
  @override
  bool get requiresLogin => numericCode == -101;

  /// 是否是权限不足（私人收藏夹/视频）
  @override
  bool get isPermissionDenied => numericCode == -403 || numericCode == 62012;

  /// 是否是地区限制
  @override
  bool get isGeoRestricted => numericCode == -10403;

  /// 网络连接错误
  @override
  bool get isNetworkError => numericCode == -2 || numericCode == -3;

  /// 超时
  @override
  bool get isTimeout => numericCode == -1;

  /// 将数字错误码映射为语义化字符串
  static String _mapCode(int code) {
    if (code == -404 || code == 62002) return 'unavailable';
    if (code == -412 || code == -509 || code == -799 || code == -429) {
      return 'rate_limited';
    }
    if (code == -10403) return 'geo_restricted';
    if (code == -101) return 'login_required';
    if (code == -403 || code == 62012) return 'permission_denied';
    if (code == -1) return 'timeout';
    if (code == -2 || code == -3) return 'network_error';
    if (code == -999) return 'error';
    return 'api_error';
  }
}
