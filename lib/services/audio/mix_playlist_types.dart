import '../../data/sources/youtube_source.dart' show MixFetchResult;
export '../../data/sources/youtube_source.dart' show MixFetchResult;

typedef MixTracksFetcher = Future<MixFetchResult> Function({
  required String playlistId,
  required String currentVideoId,
});
