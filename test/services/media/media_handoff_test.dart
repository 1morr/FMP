import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/media/media_handoff.dart';

void main() {
  group('DefaultMediaHandoff.prepareDownloadHop', () {
    test('bilibili media headers do not leak auth cookies', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.bilibili,
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
        streamResolutionAuth: const {'Cookie': 'SESSDATA=secret'},
      ));

      expect(
        result.url.toString(),
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
      );
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(result.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('youtube media headers do not leak authorization headers', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.youtube,
        'https://rr1---sn.googlevideo.com/videoplayback',
        streamResolutionAuth: const {
          'Authorization': 'Bearer secret',
          'Cookie': 'SID=secret',
        },
      ));

      expect(result.credentialsIncluded, isFalse);
      expect(result.headers['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(result.headers['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(result.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(result.headers.containsKey('Authorization'), isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('netease credentials attach only to allowlisted HTTPS media hosts',
        () {
      final handoff = DefaultMediaHandoff();
      final authHeaders = SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');

      final safe = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));
      final unsafe = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'https://cdn.example.com/song.m4a',
        streamResolutionAuth: authHeaders,
      ));
      final insecure = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'http://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(safe.credentialsIncluded, isTrue);
      expect(safe.headers['Cookie'], 'MUSIC_U=token');
      expect(
        safe.headers['User-Agent'],
        SourceHttpPolicy.neteaseDesktopUserAgent,
      );

      expect(unsafe.credentialsIncluded, isFalse);
      expect(unsafe.headers.containsKey('Cookie'), isFalse);

      expect(insecure.credentialsIncluded, isFalse);
      expect(insecure.headers.containsKey('Cookie'), isFalse);
    });

    test('rangeStart adds a Range header for resumed downloads', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.youtube,
        'https://rr1---sn.googlevideo.com/videoplayback',
        rangeStart: 4096,
      ));

      expect(result.headers[HttpHeaders.rangeHeader], 'bytes=4096-');
    });
  });

  group('DefaultMediaHandoff.preparePlayback', () {
    test('safe Netease redirect keeps credentials', () async {
      final authHeaders = SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          expect(url.toString(), 'https://m701.music.126.net/song.m4a');
          expect(authHeaders['Cookie'], 'MUSIC_U=token');
          return MediaPlaybackRedirectResolution(
            url: Uri.parse('https://m802.music.126.net/song.m4a'),
          );
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://m802.music.126.net/song.m4a');
      expect(result.credentialsIncluded, isTrue);
      expect(result.headers['Cookie'], 'MUSIC_U=token');
    });

    test('unsafe Netease redirect strips credentials', () async {
      final authHeaders = SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          return MediaPlaybackRedirectResolution(
            url: Uri.parse('https://attacker.example/song.m4a'),
            includeCredentials: false,
          );
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://attacker.example/song.m4a');
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('preflight exception strips credentials and keeps the original URL',
        () async {
      final authHeaders = SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          throw const SocketException('preflight failed');
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://m701.music.126.net/song.m4a');
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });
  });
}

MediaHandoffRequest _request(
  SourceType sourceType,
  String url, {
  Map<String, String>? streamResolutionAuth,
  int? rangeStart,
}) {
  return MediaHandoffRequest(
    sourceType: sourceType,
    url: Uri.parse(url),
    streamResolutionAuth: streamResolutionAuth,
    rangeStart: rangeStart,
  );
}
