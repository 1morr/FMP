import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/download/download_media_headers.dart';

void main() {
  group('buildDownloadMediaHeaders', () {
    test('bilibili media headers do not leak auth cookies', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.bilibili,
        authHeaders: const {'Cookie': 'SESSDATA=secret'},
      );

      expect(headers['Referer'], 'https://www.bilibili.com');
      expect(
          headers['User-Agent'], AudioStreamManager.defaultPlaybackUserAgent);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('youtube media headers do not leak authorization headers', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.youtube,
        authHeaders: const {'Authorization': 'Bearer secret'},
      );

      expect(headers['Origin'], 'https://www.youtube.com');
      expect(headers['Referer'], 'https://www.youtube.com/');
      expect(
          headers['User-Agent'], AudioStreamManager.defaultPlaybackUserAgent);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('netease media headers preserve netease auth for media requests', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.netease,
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers['Cookie'], 'MUSIC_U=token');
      expect(headers['Origin'], 'https://music.163.com');
      expect(headers['Referer'], 'https://music.163.com/');
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });
  });
}
