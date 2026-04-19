import '../../data/sources/youtube_source.dart';

typedef MixTracksFetcher = Future<MixFetchResult> Function({
  required String playlistId,
  required String currentVideoId,
});
