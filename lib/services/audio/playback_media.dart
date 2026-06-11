import '../../data/models/track.dart';

sealed class PreparedPlaybackMedia {
  const PreparedPlaybackMedia();

  Track get track;

  String get debugUrl;
}

final class LocalPlaybackMedia extends PreparedPlaybackMedia {
  const LocalPlaybackMedia({
    required this.path,
    required this.track,
  });

  final String path;

  @override
  final Track track;

  @override
  String get debugUrl => path;
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
}
