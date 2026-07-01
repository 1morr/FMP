import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

/// 真實行為測試：帳號憑證（Cookie）只能附加到 Netease 官方媒體 host（且只有
/// Netease 音源）；Bilibili / YouTube 的帳號憑證絕不送到 media / CDN byte 請求。
///
/// 這條 auth 邊界過去只靠 static-rule 字串比對測試（source_http_policy_usage_test），
/// 重構字串寫法即可繞過；本測試直接斷言 `SourceHttpPolicy.mediaHeaders` 的輸出，
/// 對重構免疫——重構不會誤判也不會漏判（F5 / 01-action-plan.md）。
void main() {
  const neteaseAuth = {
    'Cookie': 'MUSIC_U=secret; osver=pc',
    'Origin': 'https://music.163.com',
    'Referer': 'https://music.163.com/',
    'User-Agent': 'netease-desktop',
  };
  const bilibiliAuth = {'Cookie': 'SESSDATA=abc; bili_jct=def'};
  const youtubeAuth = {
    'Cookie': 'SAPISIDHASH=xyz',
    'Authorization': 'Bearer t',
  };

  group('mediaHeaders credential boundary', () {
    test('netease attaches Cookie only to allowlisted media hosts', () {
      for (final url in [
        'https://music.163.com/song/media/outer/url.mp3',
        'https://m701.music.126.net/abc/track.mp3',
        'https://something.music.163.com/media.mp3',
      ]) {
        final h = SourceHttpPolicy.mediaHeaders(
          SourceType.netease,
          authHeaders: neteaseAuth,
          requestUrl: url,
        );
        expect(h.containsKey('Cookie'), isTrue, reason: url);
        expect(h['Cookie'], neteaseAuth['Cookie'], reason: url);
      }
    });

    test('netease does NOT attach Cookie to non-allowlisted hosts', () {
      for (final url in [
        'https://example.com/track.mp3', // 完全無關 host
        'https://music.163.com.evil.com/x.mp3', // 偽造子網域
        'http://music.163.com/track.mp3', // 非 https
        null, // 無 requestUrl
      ]) {
        final h = SourceHttpPolicy.mediaHeaders(
          SourceType.netease,
          authHeaders: neteaseAuth,
          requestUrl: url,
        );
        expect(h.containsKey('Cookie'), isFalse, reason: '$url');
      }
    });

    test('netease does not attach Cookie when includeCredentials is false', () {
      final h = SourceHttpPolicy.mediaHeaders(
        SourceType.netease,
        authHeaders: neteaseAuth,
        requestUrl: 'https://music.163.com/song.mp3',
        includeCredentials: false,
      );
      expect(h.containsKey('Cookie'), isFalse);
    });

    test('netease media headers keep non-credential headers even without auth',
        () {
      final h = SourceHttpPolicy.mediaHeaders(
        SourceType.netease,
        requestUrl: 'https://music.163.com/song.mp3',
      );
      expect(h.containsKey('Cookie'), isFalse);
      expect(h['Origin'], 'https://music.163.com');
      expect(h['Referer'], 'https://music.163.com/');
      expect(h.containsKey('User-Agent'), isTrue);
    });

    test('bilibili never attaches account credentials to media requests', () {
      final h = SourceHttpPolicy.mediaHeaders(
        SourceType.bilibili,
        authHeaders: bilibiliAuth,
        requestUrl: 'https://cn-something.hdslb.com/audio.m4a',
      );
      expect(h.containsKey('Cookie'), isFalse);
      // 仍帶必要的無憑證播放標頭
      expect(h.containsKey('Referer'), isTrue);
      expect(h.containsKey('User-Agent'), isTrue);
    });

    test('youtube never attaches account credentials to media requests', () {
      final h = SourceHttpPolicy.mediaHeaders(
        SourceType.youtube,
        authHeaders: youtubeAuth,
        requestUrl: 'https://rr1---sn-xgp.googlevideo.com/audio.m4a',
      );
      expect(h.containsKey('Cookie'), isFalse);
      expect(h.containsKey('Authorization'), isFalse);
      expect(h.containsKey('Referer'), isTrue);
    });
  });

  group('canAttachNeteaseMediaCredentials', () {
    test('allowlists only official netease media hosts over https', () {
      // 正例：官方 host（含子網域）且 https
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'https://music.163.com/x'),
          isTrue);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'https://a.b.music.163.com/x'),
          isTrue);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'https://music.126.net/x'),
          isTrue);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'https://m701.music.126.net/x'),
          isTrue);

      // 負例：偽造子網域、無關 host、非 https、無 url
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'https://music.163.com.evil.com/x'),
          isFalse);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials('https://evil.com/x'),
          isFalse);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials(
              'http://music.163.com/x'),
          isFalse);
      expect(SourceHttpPolicy.canAttachNeteaseMediaCredentials(null), isFalse);
      expect(SourceHttpPolicy.canAttachNeteaseMediaCredentials(''), isFalse);
      expect(
          SourceHttpPolicy.canAttachNeteaseMediaCredentials('not a url'),
          isFalse);
    });
  });
}
