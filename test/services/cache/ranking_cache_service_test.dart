import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/search/popular_provider.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RankingCacheService lifecycle hardening', () {
    test('provider exposes immutable ranking state after refresh', () async {
      final bilibiliTrack = _track('bv-1', SourceType.bilibili);
      final youtubeTrack = _track('yt-1', SourceType.youtube, viewCount: 20);
      final neteaseTrack = _track('ne-1', SourceType.netease);
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili)
        ..tracks = [bilibiliTrack];
      final youtubeSource = _FakeRankingSource(SourceType.youtube)
        ..tracks = [youtubeTrack];
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..tracks = [neteaseTrack];
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [bilibiliSource, youtubeSource, neteaseSource],
            ),
          ),
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
      expect(state.neteaseTracks, [neteaseTrack]);
      expect(state.bilibiliLoaded, isTrue);
      expect(state.youtubeLoaded, isTrue);
      expect(state.neteaseLoaded, isTrue);

      expect(
        () => state.bilibiliTracks.add(_track('mutate', SourceType.bilibili)),
        throwsUnsupportedError,
      );
      expect(
        () => state.youtubeTracks.add(_track('mutate', SourceType.youtube)),
        throwsUnsupportedError,
      );
      expect(
        () => state.neteaseTracks.add(_track('mutate', SourceType.netease)),
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
      final neteaseTracks = List.generate(
        12,
        (index) => _track('ne-$index', SourceType.netease),
      );
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [
                _FakeRankingSource(SourceType.bilibili)
                  ..tracks = bilibiliTracks,
                _FakeRankingSource(SourceType.youtube)..tracks = youtubeTracks,
                _FakeRankingSource(SourceType.netease)..tracks = neteaseTracks,
              ],
            ),
          ),
          connectivityProvider.overrideWith((ref) => notifier),
        ],
      );

      container.read(rankingCacheServiceProvider);
      await pumpEventQueue(times: 5);

      final bilibiliPreview = container.read(homeBilibiliMusicRankingProvider);
      final cachedBilibili = container.read(cachedBilibiliRankingProvider);
      final youtubePreview = container.read(homeYouTubeMusicRankingProvider);
      final cachedYouTube = container.read(cachedYouTubeRankingProvider);
      final neteasePreview = container.read(homeNeteaseHotRankingProvider);
      final cachedNetease = container.read(cachedNeteaseRankingProvider);

      expect(bilibiliPreview, bilibiliTracks.take(10));
      expect(cachedBilibili, bilibiliTracks);
      expect(youtubePreview, hasLength(10));
      expect(cachedYouTube, hasLength(12));
      expect(neteasePreview, neteaseTracks.take(10));
      expect(cachedNetease, neteaseTracks);
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
      expect(
        () => youtubePreview.add(_track('mutate-preview', SourceType.youtube)),
        throwsUnsupportedError,
      );
      expect(
        () => cachedYouTube.add(_track('mutate-full', SourceType.youtube)),
        throwsUnsupportedError,
      );
      expect(
        () => youtubePreview[0] = _track(
          'replace-preview',
          SourceType.youtube,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => cachedYouTube[0] = _track('replace-full', SourceType.youtube),
        throwsUnsupportedError,
      );
      expect(
        () => neteasePreview.add(_track('mutate-preview', SourceType.netease)),
        throwsUnsupportedError,
      );
      expect(
        () => cachedNetease.add(_track('mutate-full', SourceType.netease)),
        throwsUnsupportedError,
      );
      expect(
        () => neteasePreview[0] = _track(
          'replace-preview',
          SourceType.netease,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => cachedNetease[0] = _track('replace-full', SourceType.netease),
        throwsUnsupportedError,
      );

      container.dispose();
      await notifier.closeStream();
    });

    test('refresh failure keeps old tracks and records source error', () async {
      final oldTrack = _track('old-bv', SourceType.bilibili);
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili)
        ..tracks = [oldTrack];
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        bilibiliRankingSource: bilibiliSource,
        youtubeRankingSource: youtubeSource,
        neteaseRankingSource: neteaseSource,
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

    test('refresh methods send source-specific ranking requests', () async {
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        bilibiliRankingSource: bilibiliSource,
        youtubeRankingSource: youtubeSource,
        neteaseRankingSource: neteaseSource,
      );

      await service.refreshBilibili();
      await service.refreshYouTube();
      await service.refreshNetease();

      _expectRankingRequest(bilibiliSource.lastRequest, regionId: 1003);
      _expectRankingRequest(youtubeSource.lastRequest, category: 'music');
      _expectRankingRequest(neteaseSource.lastRequest, limit: 50);

      service.dispose();
    });

    test('refreshNetease failure keeps old tracks and records source error',
        () async {
      final oldTrack = _track('old-ne', SourceType.netease);
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..tracks = [oldTrack];
      final service = RankingCacheService(
        bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
        youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
        neteaseRankingSource: neteaseSource,
      );

      await service.refreshNetease();
      expect(service.state.neteaseTracks, [oldTrack]);
      expect(service.state.neteaseError, isNull);

      neteaseSource.nextError = Exception('network down');
      await service.refreshNetease();

      expect(service.state.neteaseTracks, [oldTrack]);
      expect(service.state.neteaseError, contains('network down'));

      service.dispose();
    });

    test('refreshNetease ignores stale out-of-order completion', () async {
      final oldTrack = _track('old-ne', SourceType.netease);
      final newTrack = _track('new-ne', SourceType.netease);
      final oldCompleter = Completer<void>();
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(tracks: [newTrack]);
      final service = RankingCacheService(
        bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
        youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
        neteaseRankingSource: neteaseSource,
      );

      final oldRefresh = service.refreshNetease();
      await pumpEventQueue();

      await service.refreshNetease();
      expect(service.state.neteaseTracks, [newTrack]);
      expect(service.state.neteaseLoaded, isTrue);
      expect(service.state.neteaseError, isNull);

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.neteaseTracks, [newTrack]);
      expect(service.state.neteaseLoaded, isTrue);
      expect(service.state.neteaseError, isNull);

      service.dispose();
    });

    test('refreshNetease stale success does not clear newer error', () async {
      final oldTrack = _track('old-ne', SourceType.netease);
      final oldCompleter = Completer<void>();
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(error: Exception('new failure'));
      final service = RankingCacheService(
        bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
        youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
        neteaseRankingSource: neteaseSource,
      );

      final oldRefresh = service.refreshNetease();
      await pumpEventQueue();

      await service.refreshNetease();
      expect(service.state.neteaseTracks, isEmpty);
      expect(service.state.neteaseLoaded, isFalse);
      expect(service.state.neteaseError, contains('new failure'));

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.neteaseTracks, isEmpty);
      expect(service.state.neteaseLoaded, isFalse);
      expect(service.state.neteaseError, contains('new failure'));

      service.dispose();
    });

    test('setupNetworkMonitoring rebinds to the latest connectivity notifier',
        () async {
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        bilibiliRankingSource: bilibiliSource,
        youtubeRankingSource: youtubeSource,
        neteaseRankingSource: neteaseSource,
      );
      final firstNotifier = _TestConnectivityNotifier();
      final secondNotifier = _TestConnectivityNotifier();

      service.setupNetworkMonitoring(firstNotifier);
      service.setupNetworkMonitoring(secondNotifier);

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 0);
      expect(youtubeSource.fetchCount, 0);
      expect(neteaseSource.fetchCount, 0);

      secondNotifier.emitNetworkRecovered();
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);
      expect(neteaseSource.fetchCount, 1);

      service.dispose();
      firstNotifier.dispose();
      secondNotifier.dispose();
      firstNotifier.closeStream();
      secondNotifier.closeStream();
    });

    test('dispose is idempotent', () {
      final service = RankingCacheService(
        bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
        youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
        neteaseRankingSource: _FakeRankingSource(SourceType.netease),
      );

      service.dispose();

      expect(service.dispose, returnsNormally);
    });

    test('provider teardown allows rebinding to a fresh connectivity notifier',
        () async {
      final firstBilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final firstYouTubeSource = _FakeRankingSource(SourceType.youtube);
      final firstNeteaseSource = _FakeRankingSource(SourceType.netease);
      final firstNotifier = _TestConnectivityNotifier();
      final firstContainer = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [
                firstBilibiliSource,
                firstYouTubeSource,
                firstNeteaseSource,
              ],
            ),
          ),
          connectivityProvider.overrideWith((ref) => firstNotifier),
        ],
      );
      final firstService =
          firstContainer.read(rankingCacheServiceProvider.notifier);
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      expect(firstNeteaseSource.fetchCount, 1);
      firstContainer.dispose();

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      expect(firstNeteaseSource.fetchCount, 1);
      expect(firstService.dispose, returnsNormally);

      final secondBilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final secondYouTubeSource = _FakeRankingSource(SourceType.youtube);
      final secondNeteaseSource = _FakeRankingSource(SourceType.netease);
      final secondNotifier = _TestConnectivityNotifier();
      final secondContainer = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [
                secondBilibiliSource,
                secondYouTubeSource,
                secondNeteaseSource,
              ],
            ),
          ),
          connectivityProvider.overrideWith((ref) => secondNotifier),
        ],
      );
      final secondService =
          secondContainer.read(rankingCacheServiceProvider.notifier);

      expect(identical(firstService, secondService), isFalse);

      await pumpEventQueue(times: 5);
      expect(secondBilibiliSource.fetchCount, 1);
      expect(secondYouTubeSource.fetchCount, 1);
      expect(secondNeteaseSource.fetchCount, 1);

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(firstBilibiliSource.fetchCount, 1);
      expect(firstYouTubeSource.fetchCount, 1);
      expect(firstNeteaseSource.fetchCount, 1);
      expect(secondBilibiliSource.fetchCount, 1);
      expect(secondYouTubeSource.fetchCount, 1);
      expect(secondNeteaseSource.fetchCount, 1);

      secondNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);

      expect(secondBilibiliSource.fetchCount, 2);
      expect(secondYouTubeSource.fetchCount, 2);
      expect(secondNeteaseSource.fetchCount, 2);

      secondContainer.dispose();
      firstNotifier.closeStream();
      secondNotifier.closeStream();
    });

    test('updateRefreshInterval before initialize uses one latest timer',
        () async {
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        bilibiliRankingSource: bilibiliSource,
        youtubeRankingSource: youtubeSource,
        neteaseRankingSource: neteaseSource,
      );

      service.updateRefreshInterval(const Duration(milliseconds: 20));
      await service.initialize(refreshInterval: const Duration(days: 1));
      await Future<void>.delayed(const Duration(milliseconds: 70));

      service.dispose();

      expect(bilibiliSource.fetchCount, greaterThanOrEqualTo(2));
      expect(bilibiliSource.fetchCount, lessThanOrEqualTo(6));
      expect(youtubeSource.fetchCount, greaterThanOrEqualTo(2));
      expect(youtubeSource.fetchCount, lessThanOrEqualTo(6));
      expect(neteaseSource.fetchCount, greaterThanOrEqualTo(2));
      expect(neteaseSource.fetchCount, lessThanOrEqualTo(6));
    });

    test('dispose before initialize completes prevents later refreshes',
        () async {
      final bilibiliCompleter = Completer<void>();
      final youtubeCompleter = Completer<void>();
      final neteaseCompleter = Completer<void>();
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili)
        ..nextFetchCompleter = bilibiliCompleter;
      final youtubeSource = _FakeRankingSource(SourceType.youtube)
        ..nextFetchCompleter = youtubeCompleter;
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..nextFetchCompleter = neteaseCompleter;
      final service = RankingCacheService(
        bilibiliRankingSource: bilibiliSource,
        youtubeRankingSource: youtubeSource,
        neteaseRankingSource: neteaseSource,
        initialLoadTimeout: const Duration(milliseconds: 10),
      );

      final initializeFuture = service.initialize(
        refreshInterval: const Duration(milliseconds: 20),
      );
      await pumpEventQueue();
      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);
      expect(neteaseSource.fetchCount, 1);

      service.dispose();
      bilibiliCompleter.complete();
      youtubeCompleter.complete();
      neteaseCompleter.complete();
      await initializeFuture;
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);
      expect(neteaseSource.fetchCount, 1);
    });

    test('refreshYouTube keeps sorting by view count descending', () async {
      final low = _track('yt-low', SourceType.youtube, viewCount: 1);
      final high = _track('yt-high', SourceType.youtube, viewCount: 100);
      final middle = _track('yt-middle', SourceType.youtube, viewCount: 50);
      final service = RankingCacheService(
        bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
        youtubeRankingSource: _FakeRankingSource(SourceType.youtube)
          ..tracks = [low, high, middle],
        neteaseRankingSource: _FakeRankingSource(SourceType.netease),
      );

      await service.refreshYouTube();

      expect(service.state.youtubeTracks, [high, middle, low]);

      service.dispose();
    });

    test('provider error names missing ranking sources', () {
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [_FakeRankingSource(SourceType.bilibili)],
            ),
          ),
        ],
      );

      expect(
        () => container.read(rankingCacheServiceProvider),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Ranking source not registered: youtube, netease',
          ),
        ),
      );

      container.dispose();
    });
  });

  group('Popular ranking providers', () {
    test('rankingVideosProvider sends selected category rid', () async {
      final source = _FakeRankingSource(SourceType.bilibili);
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(sources: [source]),
          ),
        ],
      );

      await container
          .read(rankingVideosProvider.notifier)
          .loadCategory(BilibiliCategory.dance);

      _expectRankingRequest(
        source.lastRequest,
        regionId: BilibiliCategory.dance.rid,
      );

      container.dispose();
    });

    test('youtubeTrendingProvider sends selected category id', () async {
      final source = _FakeRankingSource(SourceType.youtube);
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(sources: [source]),
          ),
        ],
      );

      await container
          .read(youtubeTrendingProvider.notifier)
          .loadCategory(YouTubeCategory.music);

      _expectRankingRequest(
        source.lastRequest,
        category: YouTubeCategory.music.id,
      );

      container.dispose();
    });
  });
}

class _FakeRankingSource implements RankingSource {
  _FakeRankingSource(this.sourceType);

  @override
  final SourceType sourceType;

  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];
  SourceRankingRequest? lastRequest;
  final Queue<_QueuedFetch> _queuedFetches = Queue<_QueuedFetch>();

  void enqueueFetch({
    Completer<void>? completer,
    Object? error,
    List<Track> tracks = const [],
  }) {
    _queuedFetches.add(
      _QueuedFetch(completer: completer, error: error, tracks: tracks),
    );
  }

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) async {
    fetchCount++;
    lastRequest = request;
    if (_queuedFetches.isNotEmpty) {
      final fetch = _queuedFetches.removeFirst();
      await fetch.completer?.future;
      if (fetch.error != null) {
        throw fetch.error!;
      }
      return List<Track>.of(fetch.tracks);
    }
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

class _QueuedFetch {
  final Completer<void>? completer;
  final Object? error;
  final List<Track> tracks;

  const _QueuedFetch({
    this.completer,
    this.error,
    required this.tracks,
  });
}

Track _track(String id, SourceType sourceType, {int? viewCount}) {
  return Track()
    ..sourceId = id
    ..sourceType = sourceType
    ..title = id
    ..artist = 'Tester'
    ..viewCount = viewCount;
}

void _expectRankingRequest(
  SourceRankingRequest? request, {
  int? regionId,
  String? category,
  int? limit,
}) {
  final actual = request;
  expect(actual, isNotNull);
  expect(actual!.regionId, regionId);
  expect(actual.category, category);
  expect(actual.limit, limit);
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
