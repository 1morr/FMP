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

    test('media headers preserve only allowed Netease auth media headers', () {
      final headers = SourceHttpPolicy.mediaHeaders(
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
      expect(headers['Origin'], SourceHttpPolicy.neteaseOrigin);
      expect(headers['Referer'], SourceHttpPolicy.neteaseReferer);
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
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
