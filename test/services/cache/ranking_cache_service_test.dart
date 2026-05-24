import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_source.dart';
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
      final neteaseTrack = _track('ne-1', SourceType.netease);
      final bilibiliSource = _FakeBilibiliSource()..tracks = [bilibiliTrack];
      final youtubeSource = _FakeYouTubeSource()..tracks = [youtubeTrack];
      final neteaseSource = _FakeNeteaseSource()..tracks = [neteaseTrack];
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => bilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => youtubeSource),
          neteaseAudioSourceProvider.overrideWith((ref) => neteaseSource),
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
          bilibiliSourceProvider.overrideWith(
            (ref) => _FakeBilibiliSource()..tracks = bilibiliTracks,
          ),
          youtubeSourceProvider.overrideWith(
            (ref) => _FakeYouTubeSource()..tracks = youtubeTracks,
          ),
          neteaseAudioSourceProvider.overrideWith(
            (ref) => _FakeNeteaseSource()..tracks = neteaseTracks,
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
      final bilibiliSource = _FakeBilibiliSource()..tracks = [oldTrack];
      final youtubeSource = _FakeYouTubeSource();
      final neteaseSource = _FakeNeteaseSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
        neteaseSource: neteaseSource,
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

    test('refreshNetease failure keeps old tracks and records source error',
        () async {
      final oldTrack = _track('old-ne', SourceType.netease);
      final neteaseSource = _FakeNeteaseSource()..tracks = [oldTrack];
      final service = RankingCacheService(
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource(),
        neteaseSource: neteaseSource,
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
      final neteaseSource = _FakeNeteaseSource()
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(tracks: [newTrack]);
      final service = RankingCacheService(
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource(),
        neteaseSource: neteaseSource,
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
      final neteaseSource = _FakeNeteaseSource()
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(error: Exception('new failure'));
      final service = RankingCacheService(
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource(),
        neteaseSource: neteaseSource,
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
      final bilibiliSource = _FakeBilibiliSource();
      final youtubeSource = _FakeYouTubeSource();
      final neteaseSource = _FakeNeteaseSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
        neteaseSource: neteaseSource,
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
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource(),
        neteaseSource: _FakeNeteaseSource(),
      );

      service.dispose();

      expect(service.dispose, returnsNormally);
    });

    test('provider teardown allows rebinding to a fresh connectivity notifier',
        () async {
      final firstBilibiliSource = _FakeBilibiliSource();
      final firstYouTubeSource = _FakeYouTubeSource();
      final firstNeteaseSource = _FakeNeteaseSource();
      final firstNotifier = _TestConnectivityNotifier();
      final firstContainer = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => firstBilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => firstYouTubeSource),
          neteaseAudioSourceProvider.overrideWith((ref) => firstNeteaseSource),
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

      final secondBilibiliSource = _FakeBilibiliSource();
      final secondYouTubeSource = _FakeYouTubeSource();
      final secondNeteaseSource = _FakeNeteaseSource();
      final secondNotifier = _TestConnectivityNotifier();
      final secondContainer = ProviderContainer(
        overrides: [
          bilibiliSourceProvider.overrideWith((ref) => secondBilibiliSource),
          youtubeSourceProvider.overrideWith((ref) => secondYouTubeSource),
          neteaseAudioSourceProvider.overrideWith((ref) => secondNeteaseSource),
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
      final bilibiliSource = _FakeBilibiliSource();
      final youtubeSource = _FakeYouTubeSource();
      final neteaseSource = _FakeNeteaseSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
        neteaseSource: neteaseSource,
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
      final bilibiliSource = _FakeBilibiliSource()
        ..nextFetchCompleter = bilibiliCompleter;
      final youtubeSource = _FakeYouTubeSource()
        ..nextFetchCompleter = youtubeCompleter;
      final neteaseSource = _FakeNeteaseSource()
        ..nextFetchCompleter = neteaseCompleter;
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
        neteaseSource: neteaseSource,
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
        bilibiliSource: _FakeBilibiliSource(),
        youtubeSource: _FakeYouTubeSource()..tracks = [low, high, middle],
        neteaseSource: _FakeNeteaseSource(),
      );

      await service.refreshYouTube();

      expect(service.state.youtubeTracks, [high, middle, low]);

      service.dispose();
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

class _FakeNeteaseSource extends NeteaseSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];
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
  Future<List<Track>> getHotRankingTracks({int limit = 50}) async {
    fetchCount++;
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
