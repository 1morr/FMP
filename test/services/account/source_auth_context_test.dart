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
        ..setUseAuthForPlay(SourceIds.bilibili, true)
        ..setUseAuthForPlay(SourceIds.youtube, false)
        ..setUseAuthForPlay(SourceIds.netease, true);
      authLoader.headersBySource[SourceIds.bilibili] = const {
        'Cookie': 'SESSDATA=bilibili',
      };
      authLoader.headersBySource[SourceIds.youtube] = const {
        'Authorization': 'Bearer youtube',
      };
      authLoader.headersBySource[SourceIds.netease] = const {
        'Cookie': 'MUSIC_U=netease',
      };

      final bilibili = await context.authForPlay(SourceIds.bilibili);
      final youtube = await context.authForPlay(SourceIds.youtube);
      final netease = await context.authForPlay(SourceIds.netease);

      expect(bilibili, {'Cookie': 'SESSDATA=bilibili'});
      expect(youtube, isNull);
      expect(netease, {'Cookie': 'MUSIC_U=netease'});
      expect(authLoader.requests, [SourceIds.bilibili, SourceIds.netease]);
    });

    test('playlist import auth follows caller useAuth only', () async {
      authLoader.headersBySource[SourceIds.netease] = const {
        'Cookie': 'MUSIC_U=token',
      };

      final disabled = await context.playlistImportAuth(
        SourceIds.netease,
        useAuth: false,
      );
      final enabled = await context.playlistImportAuth(
        SourceIds.netease,
        useAuth: true,
      );

      expect(disabled, isNull);
      expect(enabled, {'Cookie': 'MUSIC_U=token'});
      expect(authLoader.requests, [SourceIds.netease]);
    });

    test(
      'playlist refresh auth follows persisted refresh setting only',
      () async {
        authLoader.headersBySource[SourceIds.bilibili] = const {
          'Cookie': 'SESSDATA=token',
        };

        final disabled = await context.playlistRefreshAuth(
          SourceIds.bilibili,
          useAuthForRefresh: false,
        );
        final enabled = await context.playlistRefreshAuth(
          SourceIds.bilibili,
          useAuthForRefresh: true,
        );

        expect(disabled, isNull);
        expect(enabled, {'Cookie': 'SESSDATA=token'});
        expect(authLoader.requests, [SourceIds.bilibili]);
      },
    );

    test(
      'playbackNetworkRequest does not leak Bilibili or YouTube media auth',
      () async {
        settings
          ..setUseAuthForPlay(SourceIds.bilibili, true)
          ..setUseAuthForPlay(SourceIds.youtube, true);
        authLoader.headersBySource[SourceIds.bilibili] = const {
          'Cookie': 'SESSDATA=bilibili',
        };
        authLoader.headersBySource[SourceIds.youtube] = const {
          'Authorization': 'Bearer youtube',
          'Cookie': 'SID=youtube',
        };

        final bilibili = await context.playbackNetworkRequest(
          _track(SourceIds.bilibili),
          'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
        );
        final youtube = await context.playbackNetworkRequest(
          _track(SourceIds.youtube),
          'https://rr1---sn.googlevideo.com/videoplayback',
        );

        expect(
          bilibili.headers,
          SourceHttpPolicy.mediaHeaders(SourceIds.bilibili),
        );
        expect(
          youtube.headers,
          SourceHttpPolicy.mediaHeaders(SourceIds.youtube),
        );
        expect(bilibili.headers!.containsKey('Cookie'), isFalse);
        expect(youtube.headers!.containsKey('Authorization'), isFalse);
        expect(youtube.headers!.containsKey('Cookie'), isFalse);
        expect(authLoader.requests, [SourceIds.bilibili, SourceIds.youtube]);
      },
    );

    test(
      'playbackNetworkRequest strips Netease auth after unsafe redirect',
      () async {
        settings.setUseAuthForPlay(SourceIds.netease, true);
        authLoader.headersBySource[SourceIds.netease] =
            SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
        final context = DefaultSourceAuthContext(
          settingsLoader: () async => settings,
          accountAuthLoader: authLoader,
          playbackUrlResolver: (sourceType, url, authHeaders) async {
            return const PlaybackUrlResolution(
              url: 'https://attacker.example/audio.m4a',
            );
          },
        );

        final request = await context.playbackNetworkRequest(
          _track(SourceIds.netease),
          'https://m701.music.126.net/audio.m4a',
        );

        expect(request.url, 'https://attacker.example/audio.m4a');
        expect(request.headers!.containsKey('Cookie'), isFalse);
        expect(
          request.headers,
          SourceHttpPolicy.mediaHeaders(SourceIds.netease),
        );
        expect(authLoader.requests, [SourceIds.netease]);
      },
    );

    test(
      'playbackNetworkRequest delegates media request to MediaHandoff',
      () async {
        settings.setUseAuthForPlay(SourceIds.netease, true);
        final authHeaders = SourceHttpPolicy.neteaseAuthHeaders(
          'MUSIC_U=delegate',
        );
        authLoader.headersBySource[SourceIds.netease] = authHeaders;
        final mediaHandoff = _RecordingMediaHandoff(
          result: MediaHandoffResult(
            url: Uri.parse('https://m801.music.126.net/delegated.m4a'),
            headers: const {'User-Agent': 'delegated-media'},
          ),
        );
        final context = DefaultSourceAuthContext(
          settingsLoader: () async => settings,
          accountAuthLoader: authLoader,
          mediaHandoff: mediaHandoff,
        );

        final request = await context.playbackNetworkRequest(
          _track(SourceIds.netease),
          'https://m701.music.126.net/original.m4a',
        );

        expect(request.url, 'https://m801.music.126.net/delegated.m4a');
        expect(request.headers, {'User-Agent': 'delegated-media'});
        expect(mediaHandoff.requests, hasLength(1));
        expect(mediaHandoff.requests.single.sourceType, SourceIds.netease);
        expect(
          mediaHandoff.requests.single.url.toString(),
          'https://m701.music.126.net/original.m4a',
        );
        expect(mediaHandoff.requests.single.streamResolutionAuth, authHeaders);
      },
    );

    test('image headers never include credentials', () {
      for (final sourceType in SourceIds.values) {
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
      final authContextSource = File(
        'lib/services/account/source_auth_context.dart',
      ).readAsStringSync();
      final streamResolutionSource = File(
        'lib/services/audio/stream_resolution_service.dart',
      ).readAsStringSync();
      final audioStreamManagerSource = File(
        'lib/services/audio/audio_stream_manager.dart',
      ).readAsStringSync();
      final downloadServiceSource = File(
        'lib/services/download/download_service.dart',
      ).readAsStringSync();
      final importServiceSource = File(
        'lib/services/import/import_service.dart',
      ).readAsStringSync();
      final trackDetailSource = File(
        'lib/providers/library/track_detail_provider.dart',
      ).readAsStringSync();

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
        contains('late SourcePlaybackAuthContext _sourceAuthContext'),
      );
    });
  });
}

Track _track(String sourceType) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = '${sourceType}-id'
    ..title = '${sourceType} title';
}

class _RecordingAccountAuthLoader implements SourceAccountAuthLoader {
  final headersBySource = <String, Map<String, String>?>{};
  final requests = <String>[];

  @override
  Future<Map<String, String>?> load(String sourceType) async {
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
