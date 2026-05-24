import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

void main() {
  group('SourceHttpPolicy', () {
    test('media headers do not leak non-Netease auth headers', () {
      final bilibili = SourceHttpPolicy.mediaHeaders(
        SourceType.bilibili,
        authHeaders: const {'Cookie': 'SESSDATA=secret'},
      );
      final youtube = SourceHttpPolicy.mediaHeaders(
        SourceType.youtube,
        authHeaders: const {'Authorization': 'Bearer secret'},
      );

      expect(bilibili['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(bilibili['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(bilibili.containsKey('Cookie'), isFalse);
      expect(youtube['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(youtube['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(youtube.containsKey('Authorization'), isFalse);
    });

    test(
        'media headers preserve Netease auth only for allowlisted https media URLs',
        () {
      final headers = SourceHttpPolicy.mediaHeaders(
        SourceType.netease,
        requestUrl: 'https://m701.music.126.net/song.m4a',
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers['Cookie'], 'MUSIC_U=token');
      expect(headers['Origin'], SourceHttpPolicy.neteaseOrigin);
      expect(headers['Referer'], SourceHttpPolicy.neteaseReferer);
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });

    test(
        'media headers strip Netease auth for missing non-https or non-Netease URLs',
        () {
      for (final url in [
        null,
        'http://m701.music.126.net/song.m4a',
        'https://attacker.example/song.m4a',
      ]) {
        final headers = SourceHttpPolicy.mediaHeaders(
          SourceType.netease,
          requestUrl: url,
          authHeaders: const {'Cookie': 'MUSIC_U=token'},
        );

        expect(headers.containsKey('Cookie'), isFalse, reason: '$url');
      }
    });

    test('api headers keep source-specific referer origin and user agent', () {
      expect(
          SourceHttpPolicy.apiHeaders(SourceType.bilibili),
          containsPair(
            'Referer',
            SourceHttpPolicy.bilibiliReferer,
          ));
      expect(
          SourceHttpPolicy.apiHeaders(SourceType.youtube),
          containsPair(
            'Origin',
            SourceHttpPolicy.youtubeOrigin,
          ));
      expect(
          SourceHttpPolicy.apiHeaders(SourceType.netease),
          containsPair(
            'User-Agent',
            SourceHttpPolicy.neteaseDesktopUserAgent,
          ));
    });

    test('bilibili search api headers keep search host and generated cookie',
        () {
      final headers = SourceHttpPolicy.bilibiliSearchApiHeaders(
        cookie: 'buvid3=test; buvid4=test',
      );

      expect(
        headers['Referer'],
        SourceHttpPolicy.bilibiliSearchReferer,
      );
      expect(
        headers['Origin'],
        SourceHttpPolicy.bilibiliSearchOrigin,
      );
      expect(
        headers['Accept-Language'],
        SourceHttpPolicy.bilibiliSearchAcceptLanguage,
      );
      expect(headers['Cookie'], 'buvid3=test; buvid4=test');
      expect(headers['User-Agent'], SourceHttpPolicy.webUserAgent);
    });

    test('bilibili live headers keep live referer and media user agent', () {
      final headers = SourceHttpPolicy.bilibiliLiveHeaders();

      expect(headers['Referer'], SourceHttpPolicy.bilibiliLiveReferer);
      expect(headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(headers.containsKey('Origin'), isFalse);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('createBilibiliLiveDio applies live headers', () {
      final dio = SourceHttpPolicy.createBilibiliLiveDio();

      expect(
        dio.options.headers['Referer'],
        SourceHttpPolicy.bilibiliLiveReferer,
      );
      expect(
          dio.options.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(dio.options.connectTimeout, isNotNull);
      dio.close();
    });

    test('createApiDio applies source defaults and optional content type', () {
      final dio = SourceHttpPolicy.createApiDio(
        SourceType.youtube,
        contentType: 'application/json',
      );

      expect(dio.options.headers['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(dio.options.headers['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(dio.options.contentType, 'application/json');
      expect(dio.options.connectTimeout, isNotNull);
      dio.close();
    });
  });
}
