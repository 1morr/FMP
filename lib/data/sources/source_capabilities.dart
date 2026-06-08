import '../models/track.dart';
import 'base_source.dart';

abstract interface class SourceCapability {
  SourceType get sourceType;
}

abstract interface class TrackInfoSource implements SourceCapability {
  String? parseId(String url);
  bool isValidId(String id);
  bool canHandle(String url);

  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  });

  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  });
}

abstract interface class AudioStreamSource implements SourceCapability {
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request);

  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  );
}

extension AudioStreamSourceConvenience on AudioStreamSource {
  Future<String> getAudioUrl(AudioStreamRequest request) async {
    final result = await getAudioStream(request);
    return result.url;
  }

  Future<String?> getAlternativeAudioUrl(AudioStreamRequest request) async {
    final result = await getAlternativeAudioStream(request);
    return result?.url;
  }
}

abstract interface class SearchSource implements SourceCapability {
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  });
}

abstract interface class PlaylistParsingSource implements SourceCapability {
  bool isPlaylistUrl(String url);

  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  });
}

abstract interface class AvailabilitySource implements SourceCapability {
  Future<bool> checkAvailability(String sourceId);
}
