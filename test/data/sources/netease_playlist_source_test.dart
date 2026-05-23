import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/playlist_import/netease_playlist_source.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

void main() {
  group('NeteasePlaylistSource', () {
    test('uses shared Netease API headers for playlist and song detail',
        () async {
      final seenHeaders = <String, Map<String, dynamic>>{};
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
        seenHeaders[options.path] = Map<String, dynamic>.from(options.headers);

        if (options.path.endsWith('/api/v6/playlist/detail')) {
          return ResponseBody.fromString(
            jsonEncode({
              'code': 200,
              'playlist': {
                'name': 'Shared Headers',
                'trackIds': [
                  {'id': 1001},
                ],
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (options.path.endsWith('/api/v3/song/detail')) {
          return ResponseBody.fromString(
            jsonEncode({
              'songs': [
                {
                  'id': 1001,
                  'name': 'Song',
                  'ar': [
                    {'name': 'Artist'},
                  ],
                  'al': {'name': 'Album'},
                  'dt': 180000,
                },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        throw StateError('Unexpected request: ${options.path}');
      });
      final source = NeteasePlaylistSource(dio: dio);

      final playlist = await source.fetchPlaylist(
        'https://music.163.com/#/playlist?id=123',
      );

      expect(playlist.tracks, hasLength(1));
      final expected = SourceHttpPolicy.apiHeaders(SourceType.netease);
      for (final headers in seenHeaders.values) {
        expect(headers['User-Agent'], expected['User-Agent']);
        expect(headers['Referer'], expected['Referer']);
        expect(headers['Origin'], expected['Origin']);
      }
    });
  });
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
        : utf8.decode(
            (await requestStream.expand((chunk) => chunk).toList()),
          );
    return _handler(options, requestBody);
  }

  @override
  void close({bool force = false}) {}
}
