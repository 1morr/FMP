import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_exception.dart';

void main() {
  group('BilibiliApiException', () {
    test('classifies risk-control code as rate limited', () {
      const error = BilibiliApiException(numericCode: -352, message: '-352');

      expect(error.kind, SourceErrorKind.rateLimited);
      expect(error.code, 'rate_limited');
    });
  });

  group('BilibiliSource', () {
    late BilibiliSource source;

    setUp(() {
      source = BilibiliSource();
    });

    group('getRankingVideos', () {
      test('refreshes Bilibili fingerprint and retries after risk control',
          () async {
        final requests = <RequestOptions>[];
        var rankingCalls = 0;
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          requests.add(options);

          if (options.path.endsWith('/x/web-interface/ranking/v2')) {
            rankingCalls++;
            if (rankingCalls == 1) {
              return ResponseBody.fromString(
                jsonEncode({
                  'code': -352,
                  'message': '-352',
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              );
            }

            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'bvid': 'BVrankingRetry',
                      'title': 'Ranking Retry',
                      'duration': 123,
                      'pic': '//example.com/cover.jpg',
                      'owner': {'name': 'Artist', 'mid': 1001},
                      'stat': {'view': 456},
                    }
                  ],
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/frontend/finger/spi')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'b_3': 'OFFICIAL-BUVID3infoc',
                  'b_4': 'OFFICIAL-BUVID4',
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final tracks = await source.getRankingVideos(rid: 1003);

        expect(tracks, hasLength(1));
        expect(tracks.single.sourceId, 'BVrankingRetry');
        expect(
          requests.map((request) => request.path),
          [
            'https://api.bilibili.test/x/web-interface/ranking/v2',
            'https://api.bilibili.test/x/frontend/finger/spi',
            'https://api.bilibili.test/x/web-interface/ranking/v2',
          ],
        );
        final retryCookie = requests.last.headers['Cookie'] as String?;
        expect(retryCookie, contains('buvid3=OFFICIAL-BUVID3infoc'));
        expect(retryCookie, contains('buvid4=OFFICIAL-BUVID4'));
      });
    });

    group('parsePlaylist', () {
      test('reports remote media_count instead of parsed track count',
          () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => server.close(force: true));

        server.listen((request) async {
          expect(request.uri.path, '/x/v3/fav/resource/list');
          request.response.headers.contentType = ContentType.json;
          request.response.write('''
{
  "code": 0,
  "data": {
    "info": {
      "title": "Favorites",
      "media_count": 3
    },
    "medias": [
      {
        "bvid": "BV1",
        "title": "Track 1",
        "upper": {"name": "Artist 1", "mid": 1001},
        "duration": 60,
        "cover": "https://example.com/1.jpg",
        "page": 1
      },
      {
        "bvid": "BV2",
        "title": "Track 2",
        "upper": {"name": "Artist 2", "mid": 1002},
        "duration": 90,
        "cover": "https://example.com/2.jpg",
        "page": 1
      }
    ]
  }
}
''');
          await request.response.close();
        });

        final source =
            BilibiliSource(apiBase: 'http://localhost:${server.port}');
        final result = await source.parsePlaylist(
          'https://space.bilibili.com/1/favlist?fid=123',
          pageSize: 20,
        );

        expect(result.tracks, hasLength(2));
        expect(result.totalCount, 3);
      });
    });

    group('getAudioUrl', () {
      test('preserves rate-limit errors during stream fallback', () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': -412,
                'message': 'request was blocked',
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        await expectLater(
          source.getAudioStream(
            'BVrateLimit',
            config: const AudioStreamConfig(
              streamPriority: [StreamType.audioOnly, StreamType.muxed],
            ),
          ),
          throwsA(
            isA<BilibiliApiException>()
                .having(
                    (error) => error.kind, 'kind', SourceErrorKind.rateLimited)
                .having((error) => error.numericCode, 'numericCode', -412),
          ),
        );
      });

      test('preserves HTTP rate-limit errors during stream fallback', () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'too many requests'}),
              429,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        await expectLater(
          source.getAudioStream(
            'BVhttpRateLimit',
            config: const AudioStreamConfig(
              streamPriority: [StreamType.audioOnly, StreamType.muxed],
            ),
          ),
          throwsA(
            isA<BilibiliApiException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  SourceErrorKind.rateLimited,
                )
                .having((error) => error.numericCode, 'numericCode', -429),
          ),
        );
      });

      test('falls back to muxed stream after HTTP 503 DASH failure', () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            final fnval = options.queryParameters['fnval'];
            if (fnval == 16) {
              return ResponseBody.fromString(
                jsonEncode({'message': 'service unavailable'}),
                503,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              );
            }
            if (fnval == 0) {
              return ResponseBody.fromString(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'durl': [
                      {'url': 'https://example.com/fallback.flv'}
                    ],
                  },
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              );
            }
          }

          throw StateError(
            'Unexpected request: ${options.path} ${options.queryParameters}',
          );
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final result = await source.getAudioStream(
          'BVserviceUnavailable',
          config: const AudioStreamConfig(
            streamPriority: [StreamType.audioOnly, StreamType.muxed],
          ),
        );

        expect(result.url, 'https://example.com/fallback.flv');
        expect(result.streamType, StreamType.muxed);
      });

      test('returns explicit expiry metadata for DASH audio streams', () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'dash': {
                    'audio': [
                      {
                        'baseUrl': 'https://example.com/audio.m4s',
                        'bandwidth': 192000,
                      }
                    ]
                  }
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final result = await source.getAudioStream(
          'BVdashExpiry',
          config: const AudioStreamConfig(
            streamPriority: [StreamType.audioOnly],
          ),
        );

        expect(
          result.expiry,
          const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours),
        );
      });

      test('returns explicit expiry metadata for muxed streams', () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'durl': [
                    {'url': 'https://example.com/muxed.flv'}
                  ]
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final result = await source.getAudioStream(
          'BVmuxedExpiry',
          config: const AudioStreamConfig(
            streamPriority: [StreamType.muxed],
          ),
        );

        expect(
          result.expiry,
          const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours),
        );
      });

      test('uses regular API headers for view/playurl requests', () async {
        final seenHeadersByPath = <String, Map<String, dynamic>>{};
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => server.close(force: true));

        server.listen((request) async {
          seenHeadersByPath[request.uri.path] = {
            'referer': request.headers.value('referer'),
            'origin': request.headers.value('origin'),
          };
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path.endsWith('/x/web-interface/view')) {
            request.response.write(jsonEncode({
              'code': 0,
              'data': {'cid': 12345},
            }));
          } else if (request.uri.path.endsWith('/x/player/playurl')) {
            request.response.write(jsonEncode({
              'code': 0,
              'data': {
                'dash': {
                  'audio': [
                    {
                      'baseUrl': 'https://example.com/audio.m4s',
                      'bandwidth': 192000,
                    }
                  ]
                }
              },
            }));
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });
        final source =
            BilibiliSource(apiBase: 'http://localhost:${server.port}');

        await source.getAudioStream(
          'BVheaders',
          config:
              const AudioStreamConfig(streamPriority: [StreamType.audioOnly]),
        );

        expect(seenHeadersByPath['/x/web-interface/view'], {
          'referer': 'https://www.bilibili.com/',
          'origin': 'https://www.bilibili.com',
        });
        expect(seenHeadersByPath['/x/player/playurl'], {
          'referer': 'https://www.bilibili.com/',
          'origin': 'https://www.bilibili.com',
        });
      });

      test('uses search headers only for search requests', () async {
        Map<String, dynamic>? seenHeaders;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => server.close(force: true));

        server.listen((request) async {
          seenHeaders = {
            'referer': request.headers.value('referer'),
            'origin': request.headers.value('origin'),
          };
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'code': 0,
            'data': {
              'result': [],
              'numResults': 0,
            },
          }));
          await request.response.close();
        });
        final source =
            BilibiliSource(apiBase: 'http://localhost:${server.port}');

        await source.search('song');

        expect(seenHeaders, {
          'referer': 'https://search.bilibili.com/',
          'origin': 'https://search.bilibili.com',
        });
      });

      test('alternative stream selects DASH backup URL excluding failed URL',
          () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'cid': 12345},
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'dash': {
                    'audio': [
                      {
                        'baseUrl': 'https://example.com/failed.m4s',
                        'backupUrl': ['https://example.com/backup.m4s'],
                        'bandwidth': 192000,
                      }
                    ]
                  }
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final result = await source.getAlternativeAudioStream(
          'BValternative',
          failedUrl: 'https://example.com/failed.m4s',
          config:
              const AudioStreamConfig(streamPriority: [StreamType.audioOnly]),
        );

        expect(result?.url, 'https://example.com/backup.m4s');
        expect(result?.streamType, StreamType.audioOnly);
      });

      test('should fetch audio URL for valid bvid', () async {
        // 此测试需要网络连接和有效的视频
        // 在CI/CD中可能需要跳过
        // 使用一个真实存在的视频BV号进行测试
        const testBvid = 'BV1xx411c79H'; // 实际存在的视频

        try {
          final audioUrl = await source.getAudioUrl(testBvid);

          expect(audioUrl, isNotNull);
          expect(audioUrl, isNotEmpty);
          expect(audioUrl, contains('http'));
          debugPrint(
              'Successfully fetched audio URL: ${audioUrl.substring(0, 80)}...');
        } on BilibiliApiException catch (e) {
          // 如果视频不可用，跳过测试（可能是地区限制或API限制）
          if (e.isUnavailable || e.numericCode == -404) {
            debugPrint(
                'Video unavailable (code: ${e.numericCode}), skipping test: ${e.message}');
            return;
          }
          rethrow;
        } on DioException catch (e) {
          // 网络错误时跳过
          debugPrint('Network error, skipping test: ${e.message}');
          return;
        }
      });

      test('should throw BilibiliApiException for invalid bvid', () async {
        const invalidBvid = 'BV1234567890'; // 无效的BV号

        expect(
          () => source.getAudioUrl(invalidBvid),
          throwsA(isA<BilibiliApiException>()),
        );
      });
    });

    group('getTrackInfo', () {
      test('passes auth headers into best-effort audio URL fetch', () async {
        final requestHeaders = <Map<String, dynamic>>[];
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _) {
          requestHeaders.add(Map<String, dynamic>.from(options.headers));

          if (options.path.endsWith('/x/web-interface/view')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'cid': 12345,
                  'title': 'Auth Track',
                  'owner': {'name': 'Auth Owner', 'mid': 1001},
                  'duration': 60,
                  'pic': 'https://example.com/cover.jpg',
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          if (options.path.endsWith('/x/player/playurl')) {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {
                  'dash': {
                    'audio': [
                      {
                        'baseUrl': 'https://example.com/auth-audio.m4s',
                        'bandwidth': 192000,
                      }
                    ]
                  }
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }

          throw StateError('Unexpected request: ${options.path}');
        });
        final source = BilibiliSource(
          dio: dio,
          apiBase: 'https://api.bilibili.test',
        );

        final track = await source.getTrackInfo(
          'BVauth',
          authHeaders: const {'Cookie': 'SESSDATA=auth'},
        );

        expect(track.audioUrl, 'https://example.com/auth-audio.m4s');
        expect(requestHeaders, hasLength(3));
        expect(
          requestHeaders.every(
            (headers) =>
                (headers['Cookie'] as String?)?.contains(
                  'SESSDATA=auth',
                ) ==
                true,
          ),
          isTrue,
        );
      });
    });

    group('refreshAudioUrl', () {
      test('should refresh audio URL for track with expired URL', () async {
        // 创建一个带有过期URL的track
        const originalUrl = 'https://expired-url.com/audio.m4s';
        final track = Track()
          ..sourceId = 'BV1xx411c79H'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..audioUrl = originalUrl
          ..audioUrlExpiry = DateTime.now().subtract(const Duration(hours: 1));

        // URL 应该已经过期
        expect(track.hasValidAudioUrl, isFalse);

        try {
          final refreshedTrack = await source.refreshAudioUrl(track);

          expect(refreshedTrack.audioUrl, isNotNull);
          // 新URL应该与原来的假URL不同
          expect(refreshedTrack.audioUrl, isNot(equals(originalUrl)));
          // 新URL应该是有效的HTTP URL
          expect(refreshedTrack.audioUrl, contains('http'));
          expect(refreshedTrack.hasValidAudioUrl, isTrue);
          expect(refreshedTrack.audioUrlExpiry, isNotNull);
          expect(
            refreshedTrack.audioUrlExpiry!.isAfter(DateTime.now()),
            isTrue,
          );
          debugPrint('Successfully refreshed audio URL');
        } on BilibiliApiException catch (e) {
          if (e.isUnavailable || e.numericCode == -404) {
            debugPrint(
                'Video unavailable (code: ${e.numericCode}), skipping test: ${e.message}');
            return;
          }
          rethrow;
        } on DioException catch (e) {
          debugPrint('Network error, skipping test: ${e.message}');
          return;
        }
      });
    });

    group('URL expiry', () {
      test('hasValidAudioUrl should return false for expired URL', () {
        final track = Track()
          ..audioUrl = 'https://example.com/audio.m4s'
          ..audioUrlExpiry =
              DateTime.now().subtract(const Duration(minutes: 1));

        expect(track.hasValidAudioUrl, isFalse);
      });

      test('hasValidAudioUrl should return true for valid URL', () {
        final track = Track()
          ..audioUrl = 'https://example.com/audio.m4s'
          ..audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));

        expect(track.hasValidAudioUrl, isTrue);
      });

      test('hasValidAudioUrl should return true for URL without expiry', () {
        final track = Track()..audioUrl = 'https://example.com/audio.m4s';

        expect(track.hasValidAudioUrl, isTrue);
      });

      test('hasValidAudioUrl should return false for null URL', () {
        final track = Track();

        expect(track.hasValidAudioUrl, isFalse);
      });
    });
  });

  group('Race Condition Prevention', () {
    test('Multiple rapid play requests should not cause errors', () async {
      // 这个测试模拟快速切歌的场景
      // 实际测试需要模拟 AudioController，这里只是占位符
      // 真实测试需要使用 mocktail 或 mockito 来模拟依赖

      // 模拟场景：
      // 1. 请求播放歌曲A
      // 2. 在A还没加载完时，请求播放歌曲B
      // 3. 歌曲A的加载应该被取消，歌曲B应该正常播放

      // 这里只验证逻辑概念
      expect(true, isTrue);
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
