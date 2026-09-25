import 'package:fmp/data/models/track.dart';

/// 串流網址寫進 log 的形狀：scheme + host + 最後一個 path 段。
///
/// **簽名串流網址不能寫進 log**（#163）：log 會落盤，而網址本身就是一張在
/// 到期前都能用的通行證。簽章不只在 query —— YouTube HLS manifest 與網易雲把
/// 到期時間與簽章放在中間的 path 段，所以只去掉 query 不夠。host 分得出 CDN
/// mirror，最後一段分得出容器格式（`.m4s` / `.m3u8` / `.flac`），三個來源的
/// 簽章都不在這兩處。
///
/// 解析不出 host 的輸入回 `'[unparsed URL]'`，不原樣照抄。
String redactStreamUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '[unparsed URL]';
  final origin = '${uri.scheme}://${uri.host}';
  final segments = uri.pathSegments.where((s) => s.isNotEmpty);
  if (segments.isEmpty) return origin;
  return '$origin/…/${segments.last}';
}

sealed class PreparedPlaybackMedia {
  const PreparedPlaybackMedia();

  Track get track;

  /// fallback 的比對鍵：`failedUrl` / `attemptedUrl` 拿它和來源 adapter 回傳的
  /// 網址逐字比對，所以遠端媒體是**含簽章的完整網址**。
  ///
  /// **不寫進 log**，寫 [logLabel]。
  String get debugUrl;

  /// 寫進 log 用的標籤：遠端媒體經 [redactStreamUrl]，本機檔案是路徑。
  String get logLabel;
}

final class LocalPlaybackMedia extends PreparedPlaybackMedia {
  const LocalPlaybackMedia({required this.path, required this.track});

  final String path;

  @override
  final Track track;

  @override
  String get debugUrl => path;

  @override
  String get logLabel => path;
}

final class RemotePlaybackMedia extends PreparedPlaybackMedia {
  const RemotePlaybackMedia({
    required this.url,
    required this.headers,
    required this.track,
  });

  final Uri url;
  final Map<String, String>? headers;

  @override
  final Track track;

  @override
  String get debugUrl => url.toString();

  @override
  String get logLabel => redactStreamUrl(url.toString());
}
