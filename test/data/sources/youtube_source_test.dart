import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() {
  group('YouTubeSource stream fallback', () {
    test('preserves login-required errors during stream fallback', () async {
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'login_required',
            message: 'Sign in to confirm your age',
          ),
        ),
      );
      addTearDown(source.dispose);

      await expectLater(
        source.getAudioStream(
          const AudioStreamRequest(
            sourceId: 'login-required-video',
            config: AudioStreamConfig(
              streamPriority: [StreamType.audioOnly, StreamType.muxed],
            ),
          ),
        ),
        throwsA(
          isA<YouTubeApiException>()
              .having(
                  (error) => error.kind, 'kind', SourceErrorKind.loginRequired)
              .having((error) => error.code, 'code', 'login_required'),
        ),
      );
    });

    test('InnerTube fallback honors stream priority before audio-only formats',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        expect(options.path, contains('/player'));
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            adaptiveFormats: [
              _innerTubeAudioFormat(
                url: 'https://example.com/audio-opus.webm',
                mimeType: 'audio/webm; codecs="opus"',
                bitrate: 251000,
              ),
            ],
            formats: [
              _innerTubeMuxedFormat(
                url: 'https://example.com/muxed.mp4',
                bitrate: 128000,
              ),
            ],
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous stream',
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final result = await source.getAudioStream(
        const AudioStreamRequest(
          sourceId: 'auth-priority-video',
          config: AudioStreamConfig(
            streamPriority: [StreamType.muxed, StreamType.audioOnly],
          ),
          authHeaders: {'Authorization': 'SAPISIDHASH test'},
        ),
      );

      expect(result.url, 'https://example.com/muxed.mp4');
      expect(result.streamType, StreamType.muxed);
    });

    test('InnerTube fallback honors configured audio format priority',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        expect(options.path, contains('/player'));
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            adaptiveFormats: [
              _innerTubeAudioFormat(
                url: 'https://example.com/audio-opus.webm',
                mimeType: 'audio/webm; codecs="opus"',
                bitrate: 251000,
              ),
              _innerTubeAudioFormat(
                url: 'https://example.com/audio-aac.mp4',
                mimeType: 'audio/mp4; codecs="mp4a.40.2"',
                bitrate: 128000,
              ),
            ],
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous stream',
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final result = await source.getAudioStream(
        const AudioStreamRequest(
          sourceId: 'auth-format-video',
          config: AudioStreamConfig(
            formatPriority: [AudioFormat.aac, AudioFormat.opus],
            streamPriority: [StreamType.audioOnly],
          ),
          authHeaders: {'Authorization': 'SAPISIDHASH test'},
        ),
      );

      expect(result.url, 'https://example.com/audio-aac.mp4');
      expect(result.container, 'mp4');
      expect(result.codec, 'mp4a.40.2');
    });

    test('authenticated alternative skips failed InnerTube URL', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        expect(options.path, contains('/player'));
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            adaptiveFormats: [
              _innerTubeAudioFormat(
                url: 'https://example.com/failed-audio.webm',
                mimeType: 'audio/webm; codecs="opus"',
                bitrate: 251000,
              ),
            ],
            formats: [
              _innerTubeMuxedFormat(
                url: 'https://example.com/auth-muxed.mp4',
                bitrate: 128000,
              ),
            ],
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous alternative stream',
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final result = await source.getAlternativeAudioStream(
        const AudioStreamRequest(
          sourceId: 'auth-alternative-video',
          failedUrl: 'https://example.com/failed-audio.webm',
          config: AudioStreamConfig(
            streamPriority: [StreamType.audioOnly, StreamType.muxed],
          ),
          authHeaders: {'Authorization': 'SAPISIDHASH test'},
        ),
      );

      expect(result?.url, 'https://example.com/auth-muxed.mp4');
      expect(result?.streamType, StreamType.muxed);
    });

    test('alternative fallback preserves login-required errors', () async {
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'login_required',
            message: 'Sign in to confirm your age',
          ),
        ),
      );
      addTearDown(source.dispose);

      await expectLater(
        source.getAlternativeAudioStream(
          const AudioStreamRequest(
            sourceId: 'login-required-video',
            failedUrl: 'https://example.com/failed.webm',
            config: AudioStreamConfig(
              streamPriority: [StreamType.audioOnly, StreamType.muxed],
            ),
          ),
        ),
        throwsA(
          isA<YouTubeApiException>()
              .having(
                  (error) => error.kind, 'kind', SourceErrorKind.loginRequired)
              .having((error) => error.code, 'code', 'login_required'),
        ),
      );
    });

    test('preserves timeout errors from manifest fetches', () async {
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          DioException(
            requestOptions: RequestOptions(path: '/manifest'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );
      addTearDown(source.dispose);

      await expectLater(
        source.getAudioStream(
          const AudioStreamRequest(
            sourceId: 'timeout-video',
            config: AudioStreamConfig(
              streamPriority: [StreamType.audioOnly, StreamType.muxed],
            ),
          ),
        ),
        throwsA(
          isA<YouTubeApiException>()
              .having((error) => error.kind, 'kind', SourceErrorKind.timeout)
              .having((error) => error.code, 'code', 'timeout'),
        ),
      );
    });

    test('falls back to InnerTube after probe-level HTTP 403', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        expect(options.path, contains('/player'));
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            adaptiveFormats: [
              _innerTubeAudioFormat(
                url: 'https://example.com/auth-audio.webm',
                mimeType: 'audio/webm; codecs="opus"',
                bitrate: 251000,
              ),
            ],
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          DioException.badResponse(
            statusCode: 403,
            requestOptions: RequestOptions(path: '/manifest'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/manifest'),
              statusCode: 403,
            ),
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final result = await source.getAudioStream(
        const AudioStreamRequest(
          sourceId: 'probe-forbidden-video',
          authHeaders: {'Authorization': 'SAPISIDHASH test'},
        ),
      );

      expect(result.url, 'https://example.com/auth-audio.webm');
      expect(result.streamType, StreamType.audioOnly);
    });

    test('maps InnerTube country restriction to geo-restricted', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        return ResponseBody.fromString(
          jsonEncode({
            'playabilityStatus': {
              'status': 'UNPLAYABLE',
              'reason': 'This video is not available in your country',
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous stream',
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      await expectLater(
        source.getAudioStream(
          const AudioStreamRequest(
            sourceId: 'geo-video',
            authHeaders: {'Authorization': 'SAPISIDHASH test'},
          ),
        ),
        throwsA(
          isA<YouTubeApiException>()
              .having(
                (error) => error.kind,
                'kind',
                SourceErrorKind.geoRestricted,
              )
              .having((error) => error.code, 'code', 'geo_restricted'),
        ),
      );
    });

    test('InnerTube streams carry YouTube URL expiry metadata', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            adaptiveFormats: [
              _innerTubeAudioFormat(
                url: 'https://example.com/audio-opus.webm',
                mimeType: 'audio/webm; codecs="opus"',
                bitrate: 251000,
              ),
            ],
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous stream',
          ),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final result = await source.getAudioStream(
        const AudioStreamRequest(
          sourceId: 'auth-expiry-video',
          authHeaders: {'Authorization': 'SAPISIDHASH test'},
        ),
      );

      expect(
        result.expiry,
        const Duration(hours: AppConstants.youtubeAudioUrlExpiryHours),
      );
    });
  });

  group('YouTubeSource video detail', () {
    test('authenticated detail falls back to InnerTube when video is private',
        () async {
      Object? postedBody;
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        expect(options.path, contains('/player'));
        expect(options.headers['Authorization'], 'SAPISIDHASH test');
        postedBody = requestBody;
        return ResponseBody.fromString(
          jsonEncode(_innerTubePlayerResponse(
            videoDetails: {
              'title': 'Private Auth Video',
              'author': 'Auth Channel',
              'channelId': 'UC-auth',
              'lengthSeconds': '167',
              'viewCount': '1234',
              'shortDescription': 'Visible with auth',
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/vi/private/hqdefault.jpg'},
                ],
              },
            },
          )),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(
        youtube: _FakeYoutubeExplode(
          const YouTubeApiException(
            code: 'no_stream',
            message: 'No anonymous stream',
          ),
          videoError: yt.VideoUnplayableException('private video'),
        ),
        dio: dio,
      );
      addTearDown(source.dispose);

      final detail = await source.getVideoDetail(
        'private-auth',
        authHeaders: const {'Authorization': 'SAPISIDHASH test'},
      );

      expect(detail.title, 'Private Auth Video');
      expect(detail.ownerName, 'Auth Channel');
      expect(detail.durationSeconds, 167);
      expect(detail.viewCount, 1234);
      expect(postedBody.toString(), contains('"videoId":"private-auth"'));
    });
  });

  group('YouTubeSource playlist parsing', () {
    test('uses InnerTube pagination for anonymous playlists before fallback',
        () async {
      final dio = Dio();
      final requests = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        requests.add(
          jsonDecode(requestBody as String) as Map<String, dynamic>,
        );

        final request = requests.last;
        if (request['browseId'] == 'VLPLANON') {
          return ResponseBody.fromString(
            jsonEncode({
              'header': {
                'playlistHeaderRenderer': {
                  'title': {'simpleText': 'Anonymous Playlist'},
                  'ownerText': {
                    'runs': [
                      {
                        'text': 'Anon Channel',
                        'navigationEndpoint': {
                          'browseEndpoint': {'browseId': 'UCANON'}
                        }
                      }
                    ]
                  }
                }
              },
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'itemSectionRenderer': {
                                  'contents': [
                                    {
                                      'playlistVideoListRenderer': {
                                        'contents': [
                                          {
                                            'playlistVideoRenderer': {
                                              'videoId': 'anon-1',
                                              'isPlayable': true,
                                              'title': {
                                                'runs': [
                                                  {'text': 'Anon Track 1'}
                                                ]
                                              },
                                              'shortBylineText': {
                                                'runs': [
                                                  {'text': 'Anon Artist 1'}
                                                ]
                                              },
                                              'lengthText': {
                                                'simpleText': '1:11'
                                              }
                                            }
                                          },
                                          {
                                            'continuationItemRenderer': {
                                              'continuationEndpoint': {
                                                'continuationCommand': {
                                                  'token': 'ANON_TOKEN_2'
                                                }
                                              }
                                            }
                                          }
                                        ]
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (request['continuation'] == 'ANON_TOKEN_2') {
          return ResponseBody.fromString(
            jsonEncode({
              'onResponseReceivedActions': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      {
                        'playlistVideoRenderer': {
                          'videoId': 'anon-2',
                          'isPlayable': true,
                          'title': {
                            'runs': [
                              {'text': 'Anon Track 2'}
                            ]
                          },
                          'shortBylineText': {
                            'runs': [
                              {'text': 'Anon Artist 2'}
                            ]
                          },
                          'lengthText': {'simpleText': '2:22'}
                        }
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        throw StateError('Unexpected request: $request');
      });

      final source = YouTubeSource(dio: dio);
      final result = await source.parsePlaylist(
        'https://www.youtube.com/playlist?list=PLANON',
      );

      expect(result.title, 'Anonymous Playlist');
      expect(result.ownerName, 'Anon Channel');
      expect(result.ownerUserId, 'UCANON');
      expect(result.totalCount, 2);
      expect(result.tracks.map((track) => track.sourceId).toList(), [
        'anon-1',
        'anon-2',
      ]);
      expect(requests, hasLength(2));
      expect(requests.first['browseId'], 'VLPLANON');
      expect(requests.last['continuation'], 'ANON_TOKEN_2');
    });

    test('counts skipped unavailable videos in totalCount', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        final request =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        expect(request['browseId'], 'VLPLPARTIAL');
        return ResponseBody.fromString(
          jsonEncode({
            'header': {
              'playlistHeaderRenderer': {
                'title': {'simpleText': 'Partial Playlist'},
              }
            },
            'contents': {
              'twoColumnBrowseResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'itemSectionRenderer': {
                                'contents': [
                                  {
                                    'playlistVideoListRenderer': {
                                      'contents': [
                                        {
                                          'playlistVideoRenderer': {
                                            'videoId': 'playable-1',
                                            'isPlayable': true,
                                            'title': {
                                              'runs': [
                                                {'text': 'Playable Track'}
                                              ]
                                            },
                                            'shortBylineText': {
                                              'runs': [
                                                {'text': 'Artist'}
                                              ]
                                            },
                                            'lengthText': {'simpleText': '1:00'}
                                          }
                                        },
                                        {
                                          'playlistVideoRenderer': {
                                            'videoId': 'unavailable-1',
                                            'isPlayable': false,
                                            'title': {
                                              'runs': [
                                                {'text': 'Unavailable Track'}
                                              ]
                                            }
                                          }
                                        }
                                      ]
                                    }
                                  }
                                ]
                              }
                            }
                          ]
                        }
                      }
                    }
                  }
                ]
              }
            }
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final source = YouTubeSource(dio: dio);
      final result = await source.parsePlaylist(
        'https://www.youtube.com/playlist?list=PLPARTIAL',
      );

      expect(result.tracks.map((track) => track.sourceId), ['playable-1']);
      expect(result.totalCount, 2);
    });

    test('follows continuation pages beyond the first 100 items', () async {
      final dio = Dio();
      final requests = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        requests.add(
          jsonDecode(requestBody as String) as Map<String, dynamic>,
        );

        final request = requests.last;
        if (request['browseId'] == 'VLPL123') {
          return ResponseBody.fromString(
            jsonEncode({
              'header': {
                'playlistHeaderRenderer': {
                  'title': {'simpleText': 'Auth Playlist'},
                  'ownerText': {
                    'runs': [
                      {
                        'text': 'Channel',
                        'navigationEndpoint': {
                          'browseEndpoint': {'browseId': 'UC123'}
                        }
                      }
                    ]
                  }
                }
              },
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'itemSectionRenderer': {
                                  'contents': [
                                    {
                                      'playlistVideoListRenderer': {
                                        'contents': [
                                          {
                                            'playlistVideoRenderer': {
                                              'videoId': 'video-1',
                                              'isPlayable': true,
                                              'title': {
                                                'runs': [
                                                  {'text': 'Track 1'}
                                                ]
                                              },
                                              'shortBylineText': {
                                                'runs': [
                                                  {'text': 'Artist 1'}
                                                ]
                                              },
                                              'lengthText': {
                                                'simpleText': '1:23'
                                              }
                                            }
                                          },
                                          {
                                            'continuationItemRenderer': {
                                              'continuationEndpoint': {
                                                'continuationCommand': {
                                                  'token': 'TOKEN_2'
                                                }
                                              }
                                            }
                                          }
                                        ]
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (request['continuation'] == 'TOKEN_2') {
          return ResponseBody.fromString(
            jsonEncode({
              'onResponseReceivedActions': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      {
                        'playlistVideoRenderer': {
                          'videoId': 'video-2',
                          'isPlayable': true,
                          'title': {
                            'runs': [
                              {'text': 'Track 2'}
                            ]
                          },
                          'shortBylineText': {
                            'runs': [
                              {'text': 'Artist 2'}
                            ]
                          },
                          'lengthText': {
                            'runs': [
                              {'text': '2:34'}
                            ]
                          }
                        }
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        throw StateError('Unexpected request: $request');
      });

      final source = YouTubeSource(dio: dio);
      final result = await source.parsePlaylist(
        'https://www.youtube.com/playlist?list=PL123',
        authHeaders: const {
          'Cookie': 'SAPISID=test',
          'Authorization': 'SAPISIDHASH test',
        },
      );

      expect(result.title, 'Auth Playlist');
      expect(result.ownerName, 'Channel');
      expect(result.ownerUserId, 'UC123');
      expect(result.totalCount, 2);
      expect(result.tracks.map((track) => track.sourceId).toList(), [
        'video-1',
        'video-2',
      ]);
      expect(result.tracks[1].artist, 'Artist 2');
      expect(result.tracks[1].durationMs, 154000);
      expect(requests, hasLength(2));
      expect(requests.first['browseId'], 'VLPL123');
      expect(requests.last['continuation'], 'TOKEN_2');
    });

    test('parses playlistVideoListContinuation responses', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        final request =
            jsonDecode(requestBody as String) as Map<String, dynamic>;

        if (request['browseId'] == 'VLPL456') {
          return ResponseBody.fromString(
            jsonEncode({
              'header': {
                'playlistHeaderRenderer': {
                  'title': {'simpleText': 'Auth Playlist 2'},
                }
              },
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'itemSectionRenderer': {
                                  'contents': [
                                    {
                                      'playlistVideoListRenderer': {
                                        'contents': [
                                          {
                                            'playlistVideoRenderer': {
                                              'videoId': 'video-a',
                                              'isPlayable': true,
                                              'title': {
                                                'runs': [
                                                  {'text': 'Track A'}
                                                ]
                                              },
                                              'shortBylineText': {
                                                'runs': [
                                                  {'text': 'Artist A'}
                                                ]
                                              },
                                              'lengthText': {
                                                'simpleText': '0:45'
                                              }
                                            }
                                          },
                                          {
                                            'continuationItemRenderer': {
                                              'continuationEndpoint': {
                                                'clickTrackingParams': 'CTP_B',
                                                'continuationCommand': {
                                                  'token': 'TOKEN_B'
                                                }
                                              }
                                            }
                                          }
                                        ]
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (request['continuation'] == 'TOKEN_B') {
          expect(
            request['clickTracking'],
            {
              'clickTrackingParams': 'CTP_B',
            },
          );
          return ResponseBody.fromString(
            jsonEncode({
              'continuationContents': {
                'playlistVideoListContinuation': {
                  'contents': [
                    {
                      'playlistVideoRenderer': {
                        'videoId': 'video-b',
                        'isPlayable': true,
                        'title': {
                          'runs': [
                            {'text': 'Track B'}
                          ]
                        },
                        'shortBylineText': {
                          'runs': [
                            {'text': 'Artist B'}
                          ]
                        },
                        'lengthText': {'simpleText': '3:21'}
                      }
                    }
                  ],
                  'continuations': [
                    {
                      'nextContinuationData': {
                        'continuation': 'TOKEN_C',
                        'clickTrackingParams': 'CTP_C',
                      }
                    }
                  ]
                }
              }
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (request['continuation'] == 'TOKEN_C') {
          expect(
            request['clickTracking'],
            {
              'clickTrackingParams': 'CTP_C',
            },
          );
          return ResponseBody.fromString(
            jsonEncode({
              'onResponseReceivedEndpoints': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      {
                        'playlistVideoRenderer': {
                          'videoId': 'video-c',
                          'isPlayable': true,
                          'title': {
                            'runs': [
                              {'text': 'Track C'}
                            ]
                          },
                          'shortBylineText': {
                            'runs': [
                              {'text': 'Artist C'}
                            ]
                          },
                          'lengthText': {'simpleText': '4:56'}
                        }
                      }
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        throw StateError('Unexpected request: $request');
      });

      final source = YouTubeSource(dio: dio);
      final result = await source.parsePlaylist(
        'https://www.youtube.com/playlist?list=PL456',
        authHeaders: const {
          'Cookie': 'SAPISID=test',
          'Authorization': 'SAPISIDHASH test',
        },
      );

      expect(result.title, 'Auth Playlist 2');
      expect(result.totalCount, 3);
      expect(result.tracks.map((track) => track.sourceId).toList(), [
        'video-a',
        'video-b',
        'video-c',
      ]);
    });
  });

  group('YouTubeSource trending videos', () {
    test('retries New This Week browse once after transient server failure',
        () async {
      var browseCalls = 0;
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        final request =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        expect(request['browseId'], 'VLOLPPnm121Qlcoo7kKykmswKG0IepmDUVpag');
        expect(options.path, contains('/browse'));

        browseCalls++;
        if (browseCalls == 1) {
          return ResponseBody.fromString(
            jsonEncode({'error': 'temporary unavailable'}),
            503,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        return ResponseBody.fromString(
          jsonEncode(_newThisWeekBrowseResponse()),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(dio: dio);
      addTearDown(source.dispose);

      final tracks = await source.getTrendingVideos();

      expect(browseCalls, 2);
      expect(tracks, hasLength(1));
      expect(tracks.single.sourceId, 'retry-video');
    });

    test('retries New This Week browse when accepted response is server error',
        () async {
      var browseCalls = 0;
      final dio = Dio(BaseOptions(
        validateStatus: (status) => status != null && status < 600,
      ));
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        browseCalls++;
        if (browseCalls == 1) {
          return ResponseBody.fromString(
            jsonEncode({'error': 'temporary unavailable'}),
            500,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        return ResponseBody.fromString(
          jsonEncode(_newThisWeekBrowseResponse()),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(dio: dio);
      addTearDown(source.dispose);

      final tracks = await source.getTrendingVideos();

      expect(browseCalls, 2);
      expect(tracks.single.sourceId, 'retry-video');
    });

    test('does not immediately retry New This Week browse after rate limit',
        () async {
      var browseCalls = 0;
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        final request =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        expect(request['browseId'], 'VLOLPPnm121Qlcoo7kKykmswKG0IepmDUVpag');

        browseCalls++;
        return ResponseBody.fromString(
          jsonEncode({'error': 'too many requests'}),
          429,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final source = YouTubeSource(dio: dio);
      addTearDown(source.dispose);

      await expectLater(
        source.getTrendingVideos(),
        throwsA(
          isA<YouTubeApiException>()
              .having((error) => error.code, 'code', 'rate_limited')
              .having(
                (error) => error.kind,
                'kind',
                SourceErrorKind.rateLimited,
              ),
        ),
      );
      expect(browseCalls, 1);
    });
  });

  group('YouTubeSource static methods', () {
    group('isMixPlaylistId', () {
      test('returns true for RD prefix', () {
        expect(YouTubeSource.isMixPlaylistId('RDabcdef'), isTrue);
        expect(YouTubeSource.isMixPlaylistId('RD'), isTrue);
      });

      test('returns false for non-RD prefix', () {
        expect(YouTubeSource.isMixPlaylistId('PLabcdef'), isFalse);
        expect(YouTubeSource.isMixPlaylistId('OLabcdef'), isFalse);
        expect(YouTubeSource.isMixPlaylistId(''), isFalse);
      });
    });

    group('isMixPlaylistUrl', () {
      test('returns true for Mix URL', () {
        expect(
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/watch?v=abc&list=RDabc'),
          isTrue,
        );
      });

      test('returns false for normal playlist URL', () {
        expect(
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/playlist?list=PLabc'),
          isFalse,
        );
      });

      test('returns false for no list param', () {
        expect(
          YouTubeSource.isMixPlaylistUrl('https://www.youtube.com/watch?v=abc'),
          isFalse,
        );
      });

      test('returns false for invalid URL', () {
        expect(YouTubeSource.isMixPlaylistUrl('not a url'), isFalse);
      });
    });

    group('extractMixInfo', () {
      test('extracts playlistId and seedVideoId', () {
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ');

        expect(result.playlistId, 'RDdQw4w9WgXcQ');
        expect(result.seedVideoId, 'dQw4w9WgXcQ');
      });

      test('derives seedVideoId from playlistId when no v param', () {
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/playlist?list=RDdQw4w9WgXcQ');

        expect(result.playlistId, 'RDdQw4w9WgXcQ');
        // seed should be derived from playlist ID by removing RD prefix
        expect(result.seedVideoId, 'dQw4w9WgXcQ');
      });

      test('returns nulls for invalid URL', () {
        final result = YouTubeSource.extractMixInfo('not a url');

        expect(result.playlistId, isNull);
        expect(result.seedVideoId, isNull);
      });

      test('returns null playlistId when no list param', () {
        final result =
            YouTubeSource.extractMixInfo('https://www.youtube.com/watch?v=abc');

        expect(result.playlistId, isNull);
        expect(result.seedVideoId, 'abc');
      });
    });
  });
}

Map<String, dynamic> _innerTubePlayerResponse({
  List<Map<String, dynamic>> adaptiveFormats = const [],
  List<Map<String, dynamic>> formats = const [],
  Map<String, dynamic>? videoDetails,
}) {
  return {
    'playabilityStatus': {'status': 'OK'},
    if (videoDetails != null) 'videoDetails': videoDetails,
    'streamingData': {
      'adaptiveFormats': adaptiveFormats,
      'formats': formats,
    },
  };
}

Map<String, dynamic> _innerTubeAudioFormat({
  required String url,
  required String mimeType,
  required int bitrate,
}) {
  return {
    'url': url,
    'mimeType': mimeType,
    'bitrate': bitrate,
  };
}

Map<String, dynamic> _innerTubeMuxedFormat({
  required String url,
  required int bitrate,
}) {
  return {
    'url': url,
    'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
    'bitrate': bitrate,
  };
}

Map<String, dynamic> _newThisWeekBrowseResponse() {
  return {
    'contents': {
      'twoColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'playlistVideoListRenderer': {
                              'contents': [
                                {
                                  'playlistVideoRenderer': {
                                    'videoId': 'retry-video',
                                    'title': {
                                      'runs': [
                                        {'text': 'Retry Track'}
                                      ]
                                    },
                                    'shortBylineText': {
                                      'runs': [
                                        {'text': 'Retry Artist'}
                                      ]
                                    },
                                    'lengthText': {'simpleText': '3:21'},
                                    'videoInfo': {
                                      'runs': [
                                        {'text': '1.2M views'}
                                      ]
                                    },
                                    'thumbnail': {
                                      'thumbnails': [
                                        {
                                          'url':
                                              'https://i.ytimg.com/vi/retry-video/hqdefault.jpg'
                                        }
                                      ]
                                    },
                                  }
                                }
                              ]
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            }
          }
        ]
      }
    }
  };
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

class _FakeYoutubeExplode extends yt.YoutubeExplode {
  _FakeYoutubeExplode(Object manifestError, {Object? videoError})
      : _streams = _ThrowingStreamClient(manifestError),
        _videoError = videoError,
        super(httpClient: yt.YoutubeHttpClient());

  final _ThrowingStreamClient _streams;
  final Object? _videoError;

  @override
  late final yt.VideoClient videos =
      _FakeVideoClient(_streams, videoError: _videoError);

  @override
  void close() {}
}

class _FakeVideoClient extends yt.VideoClient {
  _FakeVideoClient(this._streams, {Object? videoError})
      : _videoError = videoError,
        super(yt.YoutubeHttpClient());

  final yt.StreamClient _streams;
  final Object? _videoError;

  @override
  yt.StreamClient get streams => _streams;

  @override
  Future<yt.Video> get(dynamic videoId) async {
    final error = _videoError;
    if (error != null) throw error;
    return super.get(videoId);
  }
}

class _ThrowingStreamClient extends yt.StreamClient {
  _ThrowingStreamClient(this.error) : super(yt.YoutubeHttpClient());

  final Object error;

  @override
  Future<yt.StreamManifest> getManifest(
    dynamic videoId, {
    bool fullManifest = false,
    List<yt.YoutubeApiClient>? ytClients,
    bool requireWatchPage = true,
  }) async {
    throw error;
  }
}
