import 'package:fmp/data/sources/dynamic_playlist_types.dart'
    show MixFetchResult;
export 'package:fmp/data/sources/dynamic_playlist_types.dart'
    show MixFetchResult;

typedef MixTracksFetcher =
    Future<MixFetchResult> Function({
      required String playlistId,
      required String currentVideoId,
    });
