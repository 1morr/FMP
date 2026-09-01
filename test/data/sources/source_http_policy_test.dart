import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

void main() {
  group('SourceHttpPolicy', () {
    test('media headers carry no credentials for any source', () {
      // `mediaHeaders` 只收 SourceType —— 憑證進不來是簽章保證的，不是執行期
      // 檢查。詳細的邊界斷言在 source_http_policy_credentials_test.dart。
      for (final sourceType in SourceType.values) {
        final headers = SourceHttpPolicy.mediaHeaders(sourceType);
        expect(
            headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')),
            reason: '$sourceType');
      }

      final bilibili = SourceHttpPolicy.mediaHeaders(SourceType.bilibili);
      expect(bilibili['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(bilibili['User-Agent'], SourceHttpPolicy.mediaUserAgent);

      final youtube = SourceHttpPolicy.mediaHeaders(SourceType.youtube);
      expect(youtube['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(youtube['Referer'], SourceHttpPolicy.youtubeReferer);

      final netease = SourceHttpPolicy.mediaHeaders(SourceType.netease);
      expect(netease['Origin'], SourceHttpPolicy.neteaseOrigin);
      expect(netease['Referer'], SourceHttpPolicy.neteaseReferer);
      expect(netease['User-Agent'], SourceHttpPolicy.mediaUserAgent);
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
