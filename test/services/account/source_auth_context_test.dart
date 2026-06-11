import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/media/media_handoff.dart';

void main() {
  group('SourceAuthContext', () {
    late Settings settings;
    late _RecordingAccountAuthLoader authLoader;
    late DefaultSourceAuthContext context;

    setUp(() {
      settings = Settings();
      authLoader = _RecordingAccountAuthLoader();
      context = DefaultSourceAuthContext(
        settingsLoader: () async => settings,
        accountAuthLoader: authLoader,
        playbackUrlResolver: (sourceType, url, authHeaders) async {
          return PlaybackUrlResolution(url: url);
        },
      );
    });

    test('authForPlay follows per-source useAuthForPlay settings', () async {
      settings
        ..useBilibiliAuthForPlay = true
        ..useYoutubeAuthForPlay = false
        ..useNeteaseAuthForPlay = true;
      authLoader.headersBySource[SourceType.bilibili] = const {
        'Cookie': 'SESSDATA=bilibili',
      };
      authLoader.headersBySource[SourceType.youtube] = const {
        'Authorization': 'Bearer youtube',
      };
      authLoader.headersBySource[SourceType.netease] = const {
        'Cookie': 'MUSIC_U=netease',
      };

      final bilibili = await context.authForPlay(SourceType.bilibili);
      final youtube = await context.authForPlay(SourceType.youtube);
      final netease = await context.authForPlay(SourceType.netease);

      expect(bilibili, {'Cookie': 'SESSDATA=bilibili'});
      expect(youtube, isNull);
      expect(netease, {'Cookie': 'MUSIC_U=netease'});
      expect(authLoader.requests, [
        SourceType.bilibili,
        SourceType.netease,
      ]);
    });

    test('playlist import auth follows caller useAuth only', () async {
      authLoader.headersBySource[SourceType.netease] = const {
        'Cookie': 'MUSIC_U=token',
      };

      final disabled = await context.playlistImportAuth(
        SourceType.netease,
        useAuth: false,
      );
      final enabled = await context.playlistImportAuth(
        SourceType.netease,
        useAuth: true,
      );

      expect(disabled, isNull);
      expect(enabled, {'Cookie': 'MUSIC_U=token'});
      expect(authLoader.requests, [SourceType.netease]);
    });

    test('playlist refresh auth follows persisted refresh setting only',
        () async {
      authLoader.headersBySource[SourceType.bilibili] = const {
        'Cookie': 'SESSDATA=token',
      };

      final disabled = await context.playlistRefreshAuth(
        SourceType.bilibili,
        useAuthForRefresh: false,
      );
      final enabled = await context.playlistRefreshAuth(
        SourceType.bilibili,
        useAuthForRefresh: true,
      );

      expect(disabled, isNull);
      expect(enabled, {'Cookie': 'SESSDATA=token'});
      expect(authLoader.requests, [SourceType.bilibili]);
    });

    test('playbackNetworkRequest does not leak Bilibili or YouTube media auth',
        () async {
      settings
        ..useBilibiliAuthForPlay = true
        ..useYoutubeAuthForPlay = true;
      authLoader.headersBySource[SourceType.bilibili] = const {
        'Cookie': 'SESSDATA=bilibili',
      };
      authLoader.headersBySource[SourceType.youtube] = const {
        'Authorization': 'Bearer youtube',
        'Cookie': 'SID=youtube',
      };

      final bilibili = await context.playbackNetworkRequest(
        _track(SourceType.bilibili),
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
      );
      final youtube = await context.playbackNetworkRequest(
        _track(SourceType.youtube),
        'https://rr1---sn.googlevideo.com/videoplayback',
      );

      expect(
          bilibili.headers,
          SourceHttpPolicy.mediaHeaders(
            SourceType.bilibili,
          ));
      expect(
          youtube.headers,
          SourceHttpPolicy.mediaHeaders(
            SourceType.youtube,
          ));
      expect(bilibili.headers!.containsKey('Cookie'), isFalse);
      expect(youtube.headers!.containsKey('Authorization'), isFalse);
      expect(youtube.headers!.containsKey('Cookie'), isFalse);
      expect(authLoader.requests, [
        SourceType.bilibili,
        SourceType.youtube,
      ]);
    });

    test('playbackNetworkRequest strips Netease auth after unsafe redirect',
        () async {
      settings.useNeteaseAuthForPlay = true;
      authLoader.headersBySource[SourceType.netease] =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final context = DefaultSourceAuthContext(
        settingsLoader: () async => settings,
        accountAuthLoader: authLoader,
        playbackUrlResolver: (sourceType, url, authHeaders) async {
          return const PlaybackUrlResolution(
            url: 'https://attacker.example/audio.m4a',
            includeCredentials: false,
          );
        },
      );

      final request = await context.playbackNetworkRequest(
        _track(SourceType.netease),
        'https://m701.music.126.net/audio.m4a',
      );

      expect(request.url, 'https://attacker.example/audio.m4a');
      expect(request.headers!.containsKey('Cookie'), isFalse);
      expect(
          request.headers,
          SourceHttpPolicy.mediaHeaders(
            SourceType.netease,
            authHeaders: SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token'),
            requestUrl: 'https://attacker.example/audio.m4a',
            includeCredentials: false,
          ));
      expect(authLoader.requests, [SourceType.netease]);
    });

    test(
        'default playbackNetworkRequest preflights Netease redirects and strips unsafe auth',
        () async {
      settings.useNeteaseAuthForPlay = true;
      final authHeaders = SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      authLoader.headersBySource[SourceType.netease] = authHeaders;
      var preflightCalls = 0;
      String? preflightUrl;
      Map<String, String>? preflightAuthHeaders;
      final context = DefaultSourceAuthContext(
        settingsLoader: () async => settings,
        accountAuthLoader: authLoader,
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          preflightCalls++;
          preflightUrl = url;
          preflightAuthHeaders = authHeaders;
          return const PlaybackUrlResolution(
            url: 'https://attacker.example/audio.m4a',
            includeCredentials: false,
          );
        },
      );

      final request = await context.playbackNetworkRequest(
        _track(SourceType.netease),
        'https://m701.music.126.net/audio.m4a',
      );

      expect(preflightCalls, 1);
      expect(preflightUrl, 'https://m701.music.126.net/audio.m4a');
      expect(preflightAuthHeaders, authHeaders);
      expect(request.url, 'https://attacker.example/audio.m4a');
      expect(request.headers!.containsKey('Cookie'), isFalse);
      expect(
        request.headers,
        SourceHttpPolicy.mediaHeaders(
          SourceType.netease,
          authHeaders: authHeaders,
          requestUrl: 'https://attacker.example/audio.m4a',
          includeCredentials: false,
        ),
      );
      expect(authLoader.requests, [SourceType.netease]);
    });

    test('playbackNetworkRequest delegates media request to MediaHandoff',
        () async {
      settings.useNeteaseAuthForPlay = true;
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=delegate');
      authLoader.headersBySource[SourceType.netease] = authHeaders;
      final mediaHandoff = _RecordingMediaHandoff(
        result: MediaHandoffResult(
          url: Uri.parse('https://m801.music.126.net/delegated.m4a'),
          headers: const {'User-Agent': 'delegated-media'},
          credentialsIncluded: true,
        ),
      );
      final context = DefaultSourceAuthContext(
        settingsLoader: () async => settings,
        accountAuthLoader: authLoader,
        mediaHandoff: mediaHandoff,
      );

      final request = await context.playbackNetworkRequest(
        _track(SourceType.netease),
        'https://m701.music.126.net/original.m4a',
      );

      expect(request.url, 'https://m801.music.126.net/delegated.m4a');
      expect(request.headers, {'User-Agent': 'delegated-media'});
      expect(mediaHandoff.requests, hasLength(1));
      expect(mediaHandoff.requests.single.sourceType, SourceType.netease);
      expect(
        mediaHandoff.requests.single.url.toString(),
        'https://m701.music.126.net/original.m4a',
      );
      expect(mediaHandoff.requests.single.streamResolutionAuth, authHeaders);
    });

    test('image headers never include credentials', () {
      for (final sourceType in SourceType.values) {
        final headers = context.imageHeaders(sourceType);

        expect(headers.containsKey('Cookie'), isFalse);
        expect(headers.containsKey('Authorization'), isFalse);
      }

      final urlHeaders = context.imageHeadersForUrl(
        'https://p3.music.126.net/image.jpg',
        includeUserAgent: true,
      );

      expect(urlHeaders, isNotNull);
      expect(urlHeaders!.containsKey('Cookie'), isFalse);
      expect(urlHeaders.containsKey('Authorization'), isFalse);
    });

    test('production modules depend on purpose-specific auth interfaces', () {
      final authContextSource =
          File('lib/services/account/source_auth_context.dart')
              .readAsStringSync();
      final streamResolutionSource =
          File('lib/services/audio/stream_resolution_service.dart')
              .readAsStringSync();
      final audioStreamManagerSource =
          File('lib/services/audio/audio_stream_manager.dart')
              .readAsStringSync();
      final downloadServiceSource =
          File('lib/services/download/download_service.dart')
              .readAsStringSync();
      final importServiceSource =
          File('lib/services/import/import_service.dart').readAsStringSync();
      final trackDetailSource =
          File('lib/providers/library/track_detail_provider.dart')
              .readAsStringSync();

      expect(
        authContextSource,
        contains('abstract interface class SourcePlaybackAuthContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class PlaybackMediaRequestContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class DownloadSourceAuthContext'),
      );
      expect(
        authContextSource,
        contains('abstract interface class PlaylistAuthContext'),
      );
      expect(
        streamResolutionSource,
        contains('required SourcePlaybackAuthContext sourceAuthContext'),
      );
      expect(
        audioStreamManagerSource,
        contains('required PlaybackMediaRequestContext sourceAuthContext'),
      );
      expect(
        downloadServiceSource,
        contains('DownloadSourceAuthContext? sourceAuthContext'),
      );
      expect(
        importServiceSource,
        contains('final PlaylistAuthContext _sourceAuthContext'),
      );
      expect(
        trackDetailSource,
        contains('final SourcePlaybackAuthContext _sourceAuthContext'),
      );
    });
  });
}

Track _track(SourceType sourceType) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = '${sourceType.name}-id'
    ..title = '${sourceType.name} title';
}

class _RecordingAccountAuthLoader implements SourceAccountAuthLoader {
  final headersBySource = <SourceType, Map<String, String>?>{};
  final requests = <SourceType>[];

  @override
  Future<Map<String, String>?> load(SourceType sourceType) async {
    requests.add(sourceType);
    return headersBySource[sourceType];
  }
}

class _RecordingMediaHandoff implements MediaHandoff {
  _RecordingMediaHandoff({required this.result});

  final MediaHandoffResult result;
  final requests = <MediaHandoffRequest>[];

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    requests.add(request);
    return result;
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    throw UnimplementedError('download hops are not used by this test');
  }
}
