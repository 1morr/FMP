import '../../data/models/track.dart';
import '../../data/sources/source_url_policy.dart';

class RemotePlaylistIdParser {
  const RemotePlaylistIdParser._();

  static String? parse(SourceType sourceType, String url) {
    switch (sourceType) {
      case SourceType.bilibili:
        return SourceUrlPolicy.parseBilibiliFavoritesId(url);
      case SourceType.youtube:
        return parseYoutubePlaylistId(url);
      case SourceType.netease:
        return parseNeteasePlaylistId(url);
    }
  }

  static int? parseBilibiliFolderId(String url) {
    final folderId = SourceUrlPolicy.parseBilibiliFavoritesId(url);
    return folderId == null ? null : int.tryParse(folderId);
  }

  static String? parseYoutubePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    final id = uri?.queryParameters['list'];
    return id == null || id.isEmpty ? null : id;
  }

  static String? parseNeteasePlaylistId(String url) {
    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (idMatch != null) return idMatch.group(1);

    final mobileMatch = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
    return mobileMatch?.group(1);
  }
}
