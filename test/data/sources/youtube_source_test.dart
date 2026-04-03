import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/youtube_source.dart';

void main() {
  group('YouTubeSource static methods', () {
    group('isMixPlaylistId', () {
      test('returns true for RD prefix', () {
        expect(YouTubeSource.isMixPlaylistId('RDabcdef'), isTrue);
        expect(YouTubeSource.isMixPlaylistId('RD'), isTrue);
      });

      test('returns false for non-RD prefix', () {
        expect(YouTubeSource.isMixPlaylistId('PLabcdef'), isFalse);
        expect(YouTubeSource.isMixPlaylistId('OLabcdef'), isFalse);
        expect(YouTubeSource.isMixPlaylistId(''), isFalse);
      });
    });

    group('isMixPlaylistUrl', () {
      test('returns true for Mix URL', () {
        expect(
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/watch?v=abc&list=RDabc'),
          isTrue,
        );
      });

      test('returns false for normal playlist URL', () {
        expect(
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/playlist?list=PLabc'),
          isFalse,
        );
      });

      test('returns false for no list param', () {
        expect(
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/watch?v=abc'),
          isFalse,
        );
      });

      test('returns false for invalid URL', () {
        expect(YouTubeSource.isMixPlaylistUrl('not a url'), isFalse);
      });
    });

    group('extractMixInfo', () {
      test('extracts playlistId and seedVideoId', () {
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ');

        expect(result.playlistId, 'RDdQw4w9WgXcQ');
        expect(result.seedVideoId, 'dQw4w9WgXcQ');
      });

      test('derives seedVideoId from playlistId when no v param', () {
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/playlist?list=RDdQw4w9WgXcQ');

        expect(result.playlistId, 'RDdQw4w9WgXcQ');
        // seed should be derived from playlist ID by removing RD prefix
        expect(result.seedVideoId, 'dQw4w9WgXcQ');
      });

      test('returns nulls for invalid URL', () {
        final result = YouTubeSource.extractMixInfo('not a url');

        expect(result.playlistId, isNull);
        expect(result.seedVideoId, isNull);
      });

      test('returns null playlistId when no list param', () {
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/watch?v=abc');

        expect(result.playlistId, isNull);
        expect(result.seedVideoId, 'abc');
      });
    });
  });
}
