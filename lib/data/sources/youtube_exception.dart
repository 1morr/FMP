import '../models/track.dart';
import 'source_exception.dart';

/// YouTube API 错误
class YouTubeApiException extends SourceApiException {
  @override
  final String code;
  @override
  final String message;

  const YouTubeApiException({required this.code, required this.message});

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  String toString() => 'YouTubeApiException($code): $message';

  /// 是否是视频不可用
  @override
  bool get isUnavailable =>
      code == 'unavailable' || code == 'not_found' || code == 'unplayable' || code == 'no_stream';

  /// 是否是限流
  @override
  bool get isRateLimited => code == 'rate_limited';

  /// 是否需要登录（年龄限制等）
  @override
  bool get requiresLogin => code == 'age_restricted' || code == 'login_required';

  /// 是否是权限不足（私人视频/播放列表）
  @override
  bool get isPermissionDenied =>
      code == 'login_required' ||
      code == 'private_or_inaccessible' ||
      code == 'age_restricted';

  /// 是否是地区限制
  @override
  bool get isGeoRestricted => code == 'geo_restricted';

  /// 网络连接错误
  @override
  bool get isNetworkError => code == 'network_error';

  /// 超时
  @override
  bool get isTimeout => code == 'timeout';

  /// 是否是私人或無法訪問的播放列表
  bool get isPrivateOrInaccessible => code == 'private_or_inaccessible';
}
