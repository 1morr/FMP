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

  @override
  SourceErrorKind get kind => switch (code) {
        'timeout' => SourceErrorKind.timeout,
        'network_error' => SourceErrorKind.network,
        'rate_limited' => SourceErrorKind.rateLimited,
        'unavailable' ||
        'not_found' ||
        'unplayable' ||
        'no_stream' =>
          SourceErrorKind.unavailable,
        'login_required' || 'age_restricted' => SourceErrorKind.loginRequired,
        'private_or_inaccessible' => SourceErrorKind.permissionDenied,
        'geo_restricted' => SourceErrorKind.geoRestricted,
        _ => SourceErrorKind.unknown,
      };

  /// 是否是视频不可用
  @override
  bool get isUnavailable => super.isUnavailable;

  /// 是否是限流
  @override
  bool get isRateLimited => super.isRateLimited;

  /// 是否需要登录（年龄限制等）
  @override
  bool get requiresLogin => super.requiresLogin;

  /// 是否是权限不足（私人视频/播放列表）
  @override
  bool get isPermissionDenied =>
      super.isPermissionDenied || code == 'age_restricted';

  /// 是否是地区限制
  @override
  bool get isGeoRestricted => super.isGeoRestricted;

  /// 网络连接错误
  @override
  bool get isNetworkError => super.isNetworkError;

  /// 超时
  @override
  bool get isTimeout => super.isTimeout;

  /// 是否是私人或無法訪問的播放列表
  bool get isPrivateOrInaccessible => code == 'private_or_inaccessible';
}
