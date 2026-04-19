import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/youtube_source.dart';

void main() {
  group('YouTubeSource authenticated playlist parsing', () {
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
        final request = jsonDecode(requestBody as String) as Map<String, dynamic>;

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
                        'lengthText': {
                          'simpleText': '3:21'
                        }
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
                          'lengthText': {
                            'simpleText': '4:56'
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
          YouTubeSource.isMixPlaylistUrl(
              'https://www.youtube.com/watch?v=abc'),
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
        final result = YouTubeSource.extractMixInfo(
            'https://www.youtube.com/watch?v=abc');

        expect(result.playlistId, isNull);
        expect(result.seedVideoId, 'abc');
      });
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
