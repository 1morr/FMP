import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';

void main() {
  group('QQMusicSource lyrics', () {
    test('fetches lyrics through musicu PlayLyricInfo endpoint', () async {
      final dio = Dio();
      final capturedUrls = <String>[];
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedUrls.add(options.uri.toString());
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'req': {
            'data': {
              'lyric': base64Encode(utf8.encode('[00:01.00]Line&#10;')),
              'trans': base64Encode(utf8.encode('[00:01.00]翻译')),
            },
          },
        });
      });

      final lyrics = await QQMusicSource(dio: dio).getLyrics('song-mid');

      expect(capturedUrls, ['https://u.y.qq.com/cgi-bin/musicu.fcg']);
      expect(
          capturedBody?['req']?['module'], 'music.musichallSong.PlayLyricInfo');
      expect(capturedBody?['req']?['method'], 'GetPlayLyricInfo');
      expect(capturedBody?['req']?['param']?['songMID'], 'song-mid');
      expect(lyrics.lyric, '[00:01.00]Line\n');
      expect(lyrics.trans, '[00:01.00]翻译');
    });

    test('returns empty lyrics when musicu response has no lyric data',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        return _jsonResponse({
          'req': {'data': <String, dynamic>{}},
        });
      });

      final lyrics = await QQMusicSource(dio: dio).getLyrics('song-mid');

      expect(lyrics.songmid, 'song-mid');
      expect(lyrics.hasLyric, isFalse);
      expect(lyrics.hasTranslation, isFalse);
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final ResponseBody Function(RequestOptions options, Object? requestBody)
      _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = requestStream == null
        ? null
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    return _handler(options, requestBody);
  }

  @override
  void close({bool force = false}) {}
}
