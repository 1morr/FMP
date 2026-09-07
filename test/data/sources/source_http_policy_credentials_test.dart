import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

/// 真實行為測試：**任何音源的帳號憑證都不會出現在媒體位元組請求上。**
///
/// 這條 auth 邊界過去只靠 static-rule 字串比對測試（source_http_policy_usage_test），
/// 重構字串寫法即可繞過；本測試直接斷言 `SourceHttpPolicy.mediaHeaders` 的輸出，
/// 對重構免疫。
///
/// 曾經有一個例外：網易的 https 媒體 URL 可以附上 Cookie。實測 eapi 回的媒體 URL
/// 是 `http://`，那條分支在生產環境從未執行過，已整段移除 —— 現在「不帶憑證」是
/// 由函式簽章保證的（`mediaHeaders` 根本收不到 authHeaders），而不是靠執行期檢查。
void main() {
  group('mediaHeaders credential boundary', () {
    test('no source can put credentials on a media byte request', () {
      for (final sourceType in SourceIds.values) {
        final headers = SourceHttpPolicy.mediaHeaders(sourceType);
        final lowerKeys = headers.keys.map((k) => k.toLowerCase()).toList();

        expect(lowerKeys, isNot(contains('cookie')), reason: '$sourceType');
        expect(
          lowerKeys,
          isNot(contains('authorization')),
          reason: '$sourceType',
        );
        expect(
          lowerKeys,
          isNot(contains('x-csrf-token')),
          reason: '$sourceType',
        );
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
      final netease = SourceHttpPolicy.mediaHeaders(SourceIds.netease);
      expect(netease['Origin'], 'https://music.163.com');
      expect(netease['Referer'], 'https://music.163.com/');
      expect(netease.containsKey('User-Agent'), isTrue);

      final bilibili = SourceHttpPolicy.mediaHeaders(SourceIds.bilibili);
      expect(bilibili.containsKey('Referer'), isTrue);
      expect(bilibili.containsKey('User-Agent'), isTrue);

      final youtube = SourceHttpPolicy.mediaHeaders(SourceIds.youtube);
      expect(youtube['Origin'], 'https://www.youtube.com');
      expect(youtube.containsKey('Referer'), isTrue);
      expect(youtube.containsKey('User-Agent'), isTrue);
    });
  });
}
