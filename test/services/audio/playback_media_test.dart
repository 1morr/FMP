import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/playback_media.dart';

void main() {
  group('PreparedPlaybackMedia', () {
    test('local media exposes track and debug path', () {
      final track = _track('local');

      final media = LocalPlaybackMedia(path: '/music/local.m4a', track: track);

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

    test('remote media keeps the signed URL as its fallback key', () {
      final media = RemotePlaybackMedia(
        url: Uri.parse(_bilibiliSigned),
        headers: const {},
        track: _track('signed'),
      );

      // fallback 拿 debugUrl 跟來源 adapter 回傳的網址逐字比對，值不能變。
      expect(media.debugUrl, _bilibiliSigned);
      expect(
        media.logLabel,
        'https://upos-sz-mirror.bilivideo.com/…/123-1-30280.m4s',
      );
    });

    test('local media is labelled by its path', () {
      final media = LocalPlaybackMedia(
        path: '/music/local.m4a',
        track: _track('local'),
      );

      expect(media.logLabel, '/music/local.m4a');
    });
  });

  group('redactStreamUrl', () {
    test('drops a query-string signature', () {
      final label = redactStreamUrl(_bilibiliSigned);

      expect(label, 'https://upos-sz-mirror.bilivideo.com/…/123-1-30280.m4s');
      expect(label, isNot(contains('upsig')));
      expect(label, isNot(contains('deadline')));
    });

    test('drops a signature carried in the path', () {
      expect(
        redactStreamUrl(
          'https://manifest.googlevideo.com/api/manifest/hls_playlist/'
          'expire/1758800000/ei/abc/sig/SECRETSIG/file/index.m3u8',
        ),
        'https://manifest.googlevideo.com/…/index.m3u8',
      );
      expect(
        redactStreamUrl(
          'http://m701.music.126.net/20260925120000/'
          '0123456789abcdef0123456789abcdef/jdymusic/obj/abc/123/file.flac',
        ),
        'http://m701.music.126.net/…/file.flac',
      );
    });

    test('keeps scheme and host alone when there is no path', () {
      expect(
        redactStreamUrl('https://cdn.example.com?sig=SECRETSIG'),
        'https://cdn.example.com',
      );
      expect(
        redactStreamUrl('https://cdn.example.com/?sig=SECRETSIG'),
        'https://cdn.example.com',
      );
    });

    test('never echoes something it cannot parse as a URL', () {
      expect(redactStreamUrl('http://[::1'), '[unparsed URL]');
      expect(redactStreamUrl('no-host/SECRETSIG'), '[unparsed URL]');
      expect(redactStreamUrl(''), '[unparsed URL]');
    });
  });
}

const _bilibiliSigned =
    'https://upos-sz-mirror.bilivideo.com/upgcxcode/30/12/123/123-1-30280.m4s'
    '?e=ig8eux&deadline=1758800000&upsig=0123abcdef';

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}
