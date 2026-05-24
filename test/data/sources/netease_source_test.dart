import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/netease_exception.dart';
import 'package:fmp/data/sources/netease_source.dart';

void main() {
  group('NeteaseSource getHotRankingTracks', () {
    test('fetches hot playlist metadata up to limit without audio stream',
        () async {
      final requests = <_RecordedRequest>[];
      final source = NeteaseSource(
        dio: _dioRecordingRequests(
          requests,
          (options) {
            if (options.path.endsWith('/api/v6/playlist/detail')) {
              return {
                'code': 200,
                'playlist': {
                  'trackCount': 4,
                  'trackIds': [
                    {'id': 101},
                    {'id': 102},
                    {'id': 103},
                    {'id': 104},
                  ],
                },
              };
            }

            if (options.path.endsWith('/api/v3/song/detail')) {
              return {
                'code': 200,
                'songs': [
                  {
                    'id': 101,
                    'name': 'First Song',
                    'ar': [
                      {'name': 'Artist A'},
                      {'name': 'Artist B'},
                    ],
                    'al': {'picUrl': 'https://example.com/first.jpg'},
                    'dt': 213000,
                    'fee': 0,
                  },
                  {
                    'id': 102,
                    'name': 'VIP Unavailable Song',
                    'artists': [
                      {'name': 'Legacy Artist'},
                    ],
                    'album': {'picUrl': 'https://example.com/second.jpg'},
                    'duration': 180000,
                    'fee': 1,
                  },
                ],
                'privileges': [
                  {'id': 101, 'fee': 0, 'st': 0},
                  {'id': 102, 'fee': 4, 'st': -200},
                ],
              };
            }

            fail('Unexpected request: ${options.path}');
          },
        ),
      );

      final tracks = await source.getHotRankingTracks(limit: 2);

      expect(tracks, hasLength(2));
      expect(tracks.map((track) => track.sourceId), ['101', '102']);
      expect(tracks.every((track) => track.sourceType == SourceType.netease),
          isTrue);
      expect(tracks.first.title, 'First Song');
      expect(tracks.first.artist, 'Artist A, Artist B');
      expect(tracks.first.durationMs, 213000);
      expect(tracks.first.thumbnailUrl, 'https://example.com/first.jpg');
      expect(tracks.first.isVip, isFalse);
      expect(tracks.first.isAvailable, isTrue);
      expect(tracks.first.audioUrl, isNull);
      expect(tracks[1].artist, 'Legacy Artist');
      expect(tracks[1].durationMs, 180000);
      expect(tracks[1].thumbnailUrl, 'https://example.com/second.jpg');
      expect(tracks[1].isVip, isTrue);
      expect(tracks[1].isAvailable, isFalse);
      expect(tracks[1].audioUrl, isNull);

      final playlistRequest = requests.singleWhere(
        (request) => request.path.endsWith('/api/v6/playlist/detail'),
      );
      expect(playlistRequest.data, 'id=3778678');

      final detailRequest = requests.singleWhere(
        (request) => request.path.endsWith('/api/v3/song/detail'),
      );
      expect(detailRequest.data, contains('"id":101'));
      expect(detailRequest.data, contains('"id":102'));
      expect(detailRequest.data, isNot(contains('"id":103')));
      expect(detailRequest.data, isNot(contains('"id":104')));

      expect(
        requests.map((request) => request.path),
        isNot(contains(contains('/eapi/song/enhance/player/url/v1'))),
      );
    });
  });

  group('NeteaseSource getAudioStream', () {
    test('classifies stream item copyright restriction as geo restricted',
        () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 123,
              'url': null,
              'code': -110,
              'message': '因版权方要求，该资源暂时无法播放',
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('123'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isGeoRestricted, 'isGeoRestricted', isTrue)
              .having((e) => e.message, 'message', contains('版权')),
        ),
      );
    });

    test('classifies stream item VIP message as VIP required', () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 123,
              'url': null,
              'code': 403,
              'fee': 0,
              'message': 'VIP song, payment required',
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('123'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isVipRequired, 'isVipRequired', isTrue)
              .having((e) => e.message, 'message', contains('VIP')),
        ),
      );
    });

    test('classifies stream 404 with copyright flag as geo restricted',
        () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 435948605,
              'url': null,
              'code': 404,
              'fee': 0,
              'flag': 256,
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('435948605'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isGeoRestricted, 'isGeoRestricted', isTrue)
              .having((e) => e.code, 'code', 'geo_restricted'),
        ),
      );
    });

    test('classifies stream 404 with VIP flag as VIP required', () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 1831476071,
              'url': null,
              'code': 404,
              'fee': 0,
              'flag': 260,
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('1831476071'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isVipRequired, 'isVipRequired', isTrue)
              .having((e) => e.code, 'code', 'vip_required'),
        ),
      );
    });
  });
}

Dio _dioReturning(Map<String, dynamic> data) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: data,
          ),
        );
      },
    ),
  );
  return dio;
}

Dio _dioRecordingRequests(
  List<_RecordedRequest> requests,
  Map<String, dynamic> Function(RequestOptions options) responseFor,
) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(_RecordedRequest(options.path, options.data));
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: responseFor(options),
          ),
        );
      },
    ),
  );
  return dio;
}

class _RecordedRequest {
  final String path;
  final Object? data;

  const _RecordedRequest(this.path, this.data);
}
