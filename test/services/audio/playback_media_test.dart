import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/playback_media.dart';

void main() {
  group('PreparedPlaybackMedia', () {
    test('local media exposes track and debug path', () {
      final track = _track('local');

      final media = LocalPlaybackMedia(
        path: '/music/local.m4a',
        track: track,
      );

      expect(media.track, same(track));
      expect(media.path, '/music/local.m4a');
      expect(media.debugUrl, '/music/local.m4a');
    });

    test('remote media exposes track headers and debug URL', () {
      final track = _track('remote');

      final media = RemotePlaybackMedia(
        url: Uri.parse('https://cdn.example.com/remote.m4a'),
        headers: const {'X-Test': 'yes'},
        track: track,
      );

      expect(media.track, same(track));
      expect(media.url.toString(), 'https://cdn.example.com/remote.m4a');
      expect(media.headers, {'X-Test': 'yes'});
      expect(media.debugUrl, 'https://cdn.example.com/remote.m4a');
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}
