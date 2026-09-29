import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/media_headers.dart';

void main() {
  // ADR 0012 §如何確認：媒體請求不帶 Cookie／Authorization。M1 由這個函數與
  // PR 10 的播放後端接線守。
  test('keeps only the media headers, whatever the case', () {
    final headers = mediaRequestHeaders({
      'Referer': 'https://www.bilibili.com/',
      'user-agent': 'Mozilla/5.0',
      'ORIGIN': 'https://www.bilibili.com',
      'Range': 'bytes=0-',
      'Cookie': 'SESSDATA=FAKE_SESSDATA_123',
      'cookie': 'buvid3=FAKE_BUVID_123',
      'Authorization': 'Bearer FAKE_TOKEN_123',
      'Proxy-Authorization': 'Basic FAKE_BASIC_123',
      'X-Csrf-Token': 'FAKE_CSRF_123',
      'Accept': 'application/json',
    });

    expect(headers, {
      'Referer': 'https://www.bilibili.com/',
      'user-agent': 'Mozilla/5.0',
      'ORIGIN': 'https://www.bilibili.com',
      'Range': 'bytes=0-',
    });
  });

  test('a name that only contains an allowed name is dropped', () {
    expect(
      mediaRequestHeaders({
        'X-Referer-Cookie': 'FAKE_123',
        'Range-Cookie': 'FAKE_456',
      }),
      isEmpty,
    );
  });

  test('no headers in, no headers out', () {
    expect(mediaRequestHeaders({}), isEmpty);
  });
}
