import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

/// `SourceHttpPolicy` 的行為。
///
/// **憑證邊界**：任何音源的帳號憑證都不會出現在媒體位元組請求上。曾經有一個
/// 例外 —— 網易的 https 媒體 URL 可以附上 Cookie。實測 eapi 回的媒體 URL 是
/// `http://`，那條分支在生產環境從未執行過，已整段移除；現在「不帶憑證」是由
/// `mediaHeaders` 的簽章保證的（它根本收不到 authHeaders），不是執行期檢查。
void main() {
  group('SourceHttpPolicy', () {
    test('no source can put credentials on a media byte request', () {
      for (final sourceType in SourceIds.values) {
        final headers = SourceHttpPolicy.mediaHeaders(sourceType);
        final lowerKeys = headers.keys.map((k) => k.toLowerCase()).toList();

        expect(lowerKeys, isNot(contains('cookie')), reason: sourceType);
        expect(lowerKeys, isNot(contains('authorization')), reason: sourceType);
        expect(lowerKeys, isNot(contains('x-csrf-token')), reason: sourceType);
      }
    });

    test('mediaHeaders takes nothing but the source type', () {
      // 簽章保證：沒有 authHeaders / requestUrl / includeCredentials 可以傳，
      // 所以不存在「某個呼叫端不小心把憑證傳進來」的可能。這條測試存在的意義
      // 是：如果有人把那些參數加回去，它會編譯失敗而不是靜靜地通過。
      final headers = SourceHttpPolicy.mediaHeaders(SourceIds.netease);
      expect(headers.keys.toSet(), {'Origin', 'Referer', 'User-Agent'});
    });

    test('each source still carries the headers its CDN requires', () {
      final bilibili = SourceHttpPolicy.mediaHeaders(SourceIds.bilibili);
      expect(bilibili['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(bilibili['User-Agent'], SourceHttpPolicy.mediaUserAgent);

      final youtube = SourceHttpPolicy.mediaHeaders(SourceIds.youtube);
      expect(youtube['Origin'], 'https://www.youtube.com');
      expect(youtube['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(youtube['User-Agent'], SourceHttpPolicy.mediaUserAgent);

      final netease = SourceHttpPolicy.mediaHeaders(SourceIds.netease);
      expect(netease['Origin'], 'https://music.163.com');
      expect(netease['Referer'], 'https://music.163.com/');
      expect(netease['User-Agent'], SourceHttpPolicy.mediaUserAgent);
    });

    test('api headers keep source-specific referer origin and user agent', () {
      expect(
        SourceHttpPolicy.apiHeaders(SourceIds.bilibili),
        containsPair('Referer', SourceHttpPolicy.bilibiliReferer),
      );
      expect(
        SourceHttpPolicy.apiHeaders(SourceIds.youtube),
        containsPair('Origin', SourceHttpPolicy.youtubeOrigin),
      );
      expect(
        SourceHttpPolicy.apiHeaders(SourceIds.netease),
        containsPair('User-Agent', SourceHttpPolicy.neteaseDesktopUserAgent),
      );
    });

    test(
      'bilibili search api headers keep search host and generated cookie',
      () {
        final headers = SourceHttpPolicy.bilibiliSearchApiHeaders(
          cookie: 'buvid3=test; buvid4=test',
        );

        expect(headers['Referer'], SourceHttpPolicy.bilibiliSearchReferer);
        expect(headers['Origin'], SourceHttpPolicy.bilibiliSearchOrigin);
        expect(
          headers['Accept-Language'],
          SourceHttpPolicy.bilibiliSearchAcceptLanguage,
        );
        expect(headers['Cookie'], 'buvid3=test; buvid4=test');
        expect(headers['User-Agent'], SourceHttpPolicy.webUserAgent);
      },
    );

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
        dio.options.headers['User-Agent'],
        SourceHttpPolicy.mediaUserAgent,
      );
      expect(dio.options.connectTimeout, isNotNull);
      dio.close();
    });

    test('createApiDio applies source defaults and optional content type', () {
      final dio = SourceHttpPolicy.createApiDio(
        SourceIds.youtube,
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
