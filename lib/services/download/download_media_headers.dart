import '../../data/models/track.dart';
import '../../data/sources/source_http_policy.dart';

Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
  String? requestUrl,
}) {
  return SourceHttpPolicy.mediaHeaders(
    sourceType,
    authHeaders: authHeaders,
    requestUrl: requestUrl,
  );
}

Map<String, String> buildDownloadImageHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  return SourceHttpPolicy.imageHeaders(sourceType);
}
