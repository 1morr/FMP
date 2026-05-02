import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_track_filter.dart';

void main() {
  test(
      'filters tracks to logged-in remote sources without requiring the first track',
      () {
    final tracks = [
      _track(SourceType.youtube, 'yt'),
      _track(SourceType.netease, 'ne'),
      _track(SourceType.bilibili, 'bi'),
    ];

    final filtered = filterLoggedInRemoteTracks(
      tracks,
      isLoggedIn: (sourceType) => sourceType == SourceType.netease,
    );

    expect(filtered.map((track) => track.sourceId), ['ne']);
  });
}

Track _track(SourceType sourceType, String sourceId) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = sourceId
    ..title = sourceId;
}
