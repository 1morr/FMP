import '../models/live_room.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';
import 'dynamic_playlist_types.dart';

abstract interface class SourceCapability {
  SourceType get sourceType;
}

/// Optional capability for sources that own disposable resources (HTTP
/// clients, live clients, etc.). `SourceManager.dispose()` checks this
/// interface instead of concrete source types, so a newly registered source
/// is disposed automatically as long as it implements this.
abstract interface class DisposableSource {
  void dispose();
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

abstract interface class TrackDetailSource implements SourceCapability {
  Future<VideoDetail> getVideoDetail(
    String sourceId, {
    Map<String, String>? authHeaders,
  });
}

abstract interface class PagedVideoSource implements SourceCapability {
  Future<List<VideoPage>> getVideoPages(
    String sourceId, {
    Map<String, String>? authHeaders,
  });
}

abstract interface class DynamicPlaylistSource implements SourceCapability {
  bool isDynamicPlaylistUrl(String url);

  Future<MixPlaylistInfo> getMixPlaylistInfo(String url);

  Future<MixFetchResult> fetchMixTracks({
    required String playlistId,
    required String currentVideoId,
  });
}

class SourceRankingRequest {
  const SourceRankingRequest({
    this.regionId,
    this.category,
    this.limit,
  });

  final int? regionId;
  final String? category;
  final int? limit;
}

abstract interface class RankingSource implements SourceCapability {
  Future<List<Track>> getRankingTracks(SourceRankingRequest request);
}

abstract interface class LiveSource implements SourceCapability {
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  });

  Future<String?> getLiveStreamUrl(int roomId);
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
