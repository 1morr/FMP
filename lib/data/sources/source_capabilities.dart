import 'package:fmp/data/models/live_room.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/dynamic_playlist_types.dart';

abstract interface class SourceCapability {
  String get sourceType;
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
  const SourceRankingRequest({this.regionId, this.category, this.limit});

  final int? regionId;
  final String? category;
  final int? limit;
}

abstract interface class RankingSource implements SourceCapability {
  /// 該音源排行榜的預設請求參數。
  ///
  /// 由 adapter 自己決定，呼叫端（`RankingCacheService`）因此不必為每個音源
  /// 各寫一個 switch 分支 —— 新增音源只要實作這個 getter。
  SourceRankingRequest get defaultRankingRequest;

  /// 排行榜的顯示名稱，目前僅用於日誌。
  String get rankingLabel;

  /// 回傳已經排好序的榜單：排序規則屬於各平台自己的語意（例如 YouTube 依播放
  /// 數降序），不該由快取層代為判斷。
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
