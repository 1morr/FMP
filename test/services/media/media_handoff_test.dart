import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/media/media_handoff.dart';

/// `MediaHandoff` 是「串流解析結果」交給位元組請求的那道縫。
///
/// 它的合約現在只有兩條：URL 原樣傳遞，header 是該音源 CDN 需要的那幾個且
/// **絕不包含帳號憑證** —— 即使呼叫端把 `streamResolutionAuth` 傳進來也一樣。
///
/// （曾經還有第三條：對網易的 https URL 做重導向預檢並附上 Cookie。實測 eapi 回
/// 的是 `http://`，那條路徑在生產環境從未執行，已整段移除。）
void main() {
  const handoff = DefaultMediaHandoff();

  group('DefaultMediaHandoff', () {
    test('never forwards stream-resolution auth onto the byte request', () {
      final cases = {
        SourceIds.bilibili: (
          'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
          const {'Cookie': 'SESSDATA=secret'},
        ),
        SourceIds.youtube: (
          'https://rr1---sn.googlevideo.com/videoplayback',
          const {'Authorization': 'Bearer secret', 'Cookie': 'SID=secret'},
        ),
        SourceIds.netease: (
          'https://m701.music.126.net/song.m4a',
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token'),
        ),
      };

      for (final entry in cases.entries) {
        final (url, auth) = entry.value;
        final request = _request(entry.key, url, streamResolutionAuth: auth);

        for (final result in [
          handoff.prepareDownloadHop(request),
          // preparePlayback 與下載走同一條路徑，兩者都要守住這條邊界。
        ]) {
          final lowerKeys = result.headers.keys.map((k) => k.toLowerCase());
          expect(result.url.toString(), url, reason: '${entry.key}');
          expect(lowerKeys, isNot(contains('cookie')), reason: '${entry.key}');
          expect(lowerKeys, isNot(contains('authorization')),
              reason: '${entry.key}');
        }
      }
    });

    test('playback and download produce the same headers', () async {
      final request = _request(
        SourceIds.netease,
        'http://m801.music.126.net/song.mp3',
        streamResolutionAuth: SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=t'),
      );

      final playback = await handoff.preparePlayback(request);
      final download = handoff.prepareDownloadHop(request);

      expect(playback.url, download.url);
      expect(playback.headers, download.headers);
      expect(
          playback.headers.keys.toSet(), {'Origin', 'Referer', 'User-Agent'});
    });

    test('keeps each source CDN header set', () {
      final result = handoff.prepareDownloadHop(_request(
        SourceIds.bilibili,
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
      ));

      expect(result.headers['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(result.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
    });

    test('range start becomes a Range header, zero and null do not', () {
      const url = 'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a';

      final resumed = handoff.prepareDownloadHop(
        _request(SourceIds.bilibili, url, rangeStart: 1024),
      );
      expect(resumed.headers[HttpHeaders.rangeHeader], 'bytes=1024-');

      for (final rangeStart in [0, null]) {
        final fresh = handoff.prepareDownloadHop(
          _request(SourceIds.bilibili, url, rangeStart: rangeStart),
        );
        expect(fresh.headers.containsKey(HttpHeaders.rangeHeader), isFalse,
            reason: 'rangeStart=$rangeStart');
      }
    });
  });
}

MediaHandoffRequest _request(
  String sourceType,
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
