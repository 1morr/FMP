import '../../data/models/track.dart';
import '../../data/sources/source_http_policy.dart';

Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  return SourceHttpPolicy.mediaHeaders(
    sourceType,
    authHeaders: authHeaders,
  );
}

Map<String, String> buildDownloadImageHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  return SourceHttpPolicy.mediaHeaders(
    sourceType,
    authHeaders: authHeaders,
  );
}
