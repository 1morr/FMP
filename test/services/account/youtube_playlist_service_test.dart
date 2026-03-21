import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/account/youtube_playlist_service.dart';

void main() {
  group('YouTubePlaylistService.pickBestVideoCountText', () {
    test('prefers playlist count over updated time metadata', () {
      expect(
        YouTubePlaylistService.pickBestVideoCountText([
          'Updated 4 days ago',
          '2.5K videos',
        ]),
        '2.5K videos',
      );
    });
  });

  group('YouTubePlaylistService.parseVideoCount', () {
    test('parses plain integer counts', () {
      expect(YouTubePlaylistService.parseVideoCount('473 videos'), 473);
    });

    test('parses abbreviated thousands counts', () {
      expect(YouTubePlaylistService.parseVideoCount('2.5K videos'), 2500);
    });

    test('parses abbreviated count when metadata includes other numbers first',
        () {
      expect(
        YouTubePlaylistService.parseVideoCount(
          YouTubePlaylistService.pickBestVideoCountText([
            'Updated 4 days ago',
            '2.5K videos',
          ]),
        ),
        2500,
      );
    });
  });
}
