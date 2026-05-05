import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/providers/popular_provider.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RankingCacheService lifecycle hardening', () {
    test('provider exposes immutable ranking state after refresh', () async {
      final bilibiliTrack = _track('bv-1', SourceType.bilibili);
      final youtubeTrack = _track('yt-1', SourceType.youtube, viewCount: 20);
      final bilibiliSource = _FakeBilibiliSource()..tracks = [bilibiliTrack];
      final youtubeSource = _FakeYouTubeSource()..tracks = [youtubeTrack];
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => bilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => youtubeSource),
          connectivityProvider.overrideWith((ref) => notifier),
        ],
      );

      expect(
          container.read(rankingCacheServiceProvider).isInitialLoading, isTrue);

      await pumpEventQueue(times: 5);
      final state = container.read(rankingCacheServiceProvider);

      expect(state.isInitialLoading, isFalse);
      expect(state.bilibiliTracks, [bilibiliTrack]);
      expect(state.youtubeTracks, [youtubeTrack]);
      expect(state.bilibiliLoaded, isTrue);
      expect(state.youtubeLoaded, isTrue);

      expect(
        () => state.bilibiliTracks.add(_track('mutate', SourceType.bilibili)),
        throwsUnsupportedError,
      );

      container.dispose();
      await notifier.closeStream();
    });

    test('derived ranking providers expose preview and full immutable lists',
        () async {
      final bilibiliTracks = List.generate(
        12,
        (index) => _track('bv-$index', SourceType.bilibili),
      );
      final youtubeTracks = List.generate(
        12,
        (index) => _track('yt-$index', SourceType.youtube, viewCount: index),
      );
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith(
            (ref) => _FakeBilibiliSource()..tracks = bilibiliTracks,
          ),
          youtubeSourceProvider.overrideWith(
            (ref) => _FakeYouTubeSource()..tracks = youtubeTracks,
          ),
          connectivityProvider.overrideWith((ref) => notifier),
        ],
      );

      container.read(rankingCacheServiceProvider);
      await pumpEventQueue(times: 5);

      final bilibiliPreview = container.read(homeBilibiliMusicRankingProvider);
      final cachedBilibili = container.read(cachedBilibiliRankingProvider);

      expect(bilibiliPreview, bilibiliTracks.take(10));
      expect(cachedBilibili, bilibiliTracks);
      expect(container.read(homeYouTubeMusicRankingProvider), hasLength(10));
      expect(container.read(cachedYouTubeRankingProvider), hasLength(12));
      expect(
        () =>
            bilibiliPreview.add(_track('mutate-preview', SourceType.bilibili)),
        throwsUnsupportedError,
      );
      expect(
        () => cachedBilibili.add(_track('mutate-full', SourceType.bilibili)),
        throwsUnsupportedError,
      );
      expect(
        () => bilibiliPreview[0] = _track(
          'replace-preview',
          SourceType.bilibili,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => cachedBilibili[0] = _track('replace-full', SourceType.bilibili),
        throwsUnsupportedError,
      );

      container.dispose();
      await notifier.closeStream();
    });

    test('refresh failure keeps old tracks and records source error', () async {
      final oldTrack = _track('old-bv', SourceType.bilibili);
      final bilibiliSource = _FakeBilibiliSource()..tracks = [oldTrack];
      final youtubeSource = _FakeYouTubeSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
      );

      await service.refreshBilibili();
      expect(service.state.bilibiliTracks, [oldTrack]);
      expect(service.state.bilibiliError, isNull);

      bilibiliSource.nextError = Exception('network down');
      await service.refreshBilibili();

      expect(service.state.bilibiliTracks, [oldTrack]);
      expect(service.state.bilibiliError, contains('network down'));

      service.dispose();
    });

    test('setupNetworkMonitoring rebinds to the latest connectivity notifier',
        () async {
      final bilibiliSource = _FakeBilibiliSource();
      final youtubeSource = _FakeYouTubeSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
      );
      final firstNotifier = _TestConnectivityNotifier();
      final secondNotifier = _TestConnectivityNotifier();

      service.setupNetworkMonitoring(firstNotifier);
      service.setupNetworkMonitoring(secondNotifier);

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 0);
      expect(youtubeSource.fetchCount, 0);

      secondNotifier.emitNetworkRecovered();
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);

      service.dispose();
      firstNotifier.dispose();
      secondNotifier.dispose();
      firstNotifier.closeStream();
      secondNotifier.closeStream();
    });

    test('dispose is idempotent', () {
      final service = RankingCacheService(
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource(),
      );

      service.dispose();

      expect(service.dispose, returnsNormally);
    });

    test('provider teardown allows rebinding to a fresh connectivity notifier',
        () async {
      final firstBilibiliSource = _FakeBilibiliSource();
      final firstYouTubeSource = _FakeYouTubeSource();
      final firstNotifier = _TestConnectivityNotifier();
      final firstContainer = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => firstBilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => firstYouTubeSource),
          connectivityProvider.overrideWith((ref) => firstNotifier),
        ],
      );
      final firstService =
          firstContainer.read(rankingCacheServiceProvider.notifier);
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      firstContainer.dispose();

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      expect(firstService.dispose, returnsNormally);

      final secondBilibiliSource = _FakeBilibiliSource();
      final secondYouTubeSource = _FakeYouTubeSource();
      final secondNotifier = _TestConnectivityNotifier();
      final secondContainer = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => secondBilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => secondYouTubeSource),
          connectivityProvider.overrideWith((ref) => secondNotifier),
        ],
      );
      final secondService =
          secondContainer.read(rankingCacheServiceProvider.notifier);

      expect(identical(firstService, secondService), isFalse);

      await pumpEventQueue(times: 5);
      expect(secondBilibiliSource.fetchCount, 1);
      expect(secondYouTubeSource.fetchCount, 1);

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      expect(secondBilibiliSource.fetchCount, 1);
      expect(secondYouTubeSource.fetchCount, 1);

      secondNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);

      expect(secondBilibiliSource.fetchCount, 2);
      expect(secondYouTubeSource.fetchCount, 2);

      secondContainer.dispose();
      firstNotifier.closeStream();
      secondNotifier.closeStream();
    });

    test('updateRefreshInterval before initialize uses one latest timer',
        () async {
      final bilibiliSource = _FakeBilibiliSource();
      final youtubeSource = _FakeYouTubeSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
      );

      service.updateRefreshInterval(const Duration(milliseconds: 20));
      await service.initialize(refreshInterval: const Duration(days: 1));
      await Future<void>.delayed(const Duration(milliseconds: 70));

      service.dispose();

      expect(bilibiliSource.fetchCount, greaterThanOrEqualTo(2));
      expect(bilibiliSource.fetchCount, lessThanOrEqualTo(6));
      expect(youtubeSource.fetchCount, greaterThanOrEqualTo(2));
      expect(youtubeSource.fetchCount, lessThanOrEqualTo(6));
    });

    test('dispose before initialize completes prevents later refreshes',
        () async {
      final bilibiliSource = _FakeBilibiliSource()
        ..nextFetchCompleter = Completer<void>();
      final youtubeSource = _FakeYouTubeSource()
        ..nextFetchCompleter = Completer<void>();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
      );

      final initializeFuture = service.initialize(
        refreshInterval: const Duration(milliseconds: 20),
      );
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);

      service.dispose();
      bilibiliSource.nextFetchCompleter?.complete();
      youtubeSource.nextFetchCompleter?.complete();
      await initializeFuture;
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);
    });
  });
}

class _FakeBilibiliSource extends BilibiliSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];

  @override
  Future<List<Track>> getRankingVideos({int rid = 0}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return List<Track>.of(tracks);
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];

  @override
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return List<Track>.of(tracks);
  }
}

Track _track(String id, SourceType sourceType, {int? viewCount}) {
  return Track()
    ..sourceId = id
    ..sourceType = sourceType
    ..title = id
    ..artist = 'Tester'
    ..viewCount = viewCount;
}

class _TestConnectivityNotifier extends StateNotifier<ConnectivityState>
    with Logging
    implements ConnectivityNotifier {
  _TestConnectivityNotifier() : super(ConnectivityState.initial);

  final _networkRecoveredController = StreamController<void>.broadcast();

  @override
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;

  void emitNetworkRecovered() {
    _networkRecoveredController.add(null);
  }

  Future<void> closeStream() {
    return _networkRecoveredController.close();
  }
}
