import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_url_policy.dart';

class RemotePlaylistIdParser {
  const RemotePlaylistIdParser._();

  static String? parse(String sourceType, String url) {
    switch (sourceType) {
      case SourceIds.bilibili:
        return SourceUrlPolicy.parseBilibiliFavoritesId(url);
      case SourceIds.youtube:
        return parseYoutubePlaylistId(url);
      case SourceIds.netease:
        return parseNeteasePlaylistId(url);
      default:
        // 認不得的音源沒有可用的解析規則。拿別家的 regex 去套只會憑空
        // 生出一個不存在的歌單 id。
        return null;
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
