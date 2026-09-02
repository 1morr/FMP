import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart';
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
    test('state exposes source-indexed cache accessors', () {
      final bilibiliTrack = _track('bv-indexed', SourceType.bilibili);
      final youtubeTrack = _track('yt-indexed', SourceType.youtube);
      final state = RankingCacheState(
        tracksBySource: {
          SourceType.bilibili: [bilibiliTrack],
          SourceType.youtube: [youtubeTrack],
        },
        loadedBySource: const {
          SourceType.bilibili: true,
          SourceType.youtube: false,
        },
        errorsBySource: const {
          SourceType.youtube: 'youtube offline',
        },
      );

      expect(state.tracksFor(SourceType.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceType.youtube), [youtubeTrack]);
      expect(state.tracksFor(SourceType.netease), isEmpty);
      expect(state.isLoaded(SourceType.bilibili), isTrue);
      expect(state.isLoaded(SourceType.youtube), isFalse);
      expect(state.errorFor(SourceType.youtube), 'youtube offline');
      expect(state.errorFor(SourceType.netease), isNull);
      expect(state.tracksFor(SourceType.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceType.youtube), [youtubeTrack]);
      expect(
        () => state.tracksFor(SourceType.bilibili).add(
              _track('mutate-indexed', SourceType.bilibili),
            ),
        throwsUnsupportedError,
      );
    });

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
      expect(state.tracksFor(SourceType.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceType.youtube), [youtubeTrack]);
      expect(state.tracksFor(SourceType.netease), [neteaseTrack]);
      expect(state.isLoaded(SourceType.bilibili), isTrue);
      expect(state.isLoaded(SourceType.youtube), isTrue);
      expect(state.isLoaded(SourceType.netease), isTrue);

      expect(
        () => state
            .tracksFor(SourceType.bilibili)
            .add(_track('mutate', SourceType.bilibili)),
        throwsUnsupportedError,
      );
      expect(
        () => state
            .tracksFor(SourceType.youtube)
            .add(_track('mutate', SourceType.youtube)),
        throwsUnsupportedError,
      );
      expect(
        () => state
            .tracksFor(SourceType.netease)
            .add(_track('mutate', SourceType.netease)),
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
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
      );

      await service.refreshSource(SourceType.bilibili);
      expect(service.state.tracksFor(SourceType.bilibili), [oldTrack]);
      expect(service.state.errorFor(SourceType.bilibili), isNull);

      bilibiliSource.nextError = Exception('network down');
      await service.refreshSource(SourceType.bilibili);

      expect(service.state.tracksFor(SourceType.bilibili), [oldTrack]);
      expect(service.state.errorFor(SourceType.bilibili),
          contains('network down'));

      service.dispose();
    });

    test('refreshSource sends source-specific requests and stores by source',
        () async {
      final low = _track('yt-low-indexed', SourceType.youtube, viewCount: 1);
      final high = _track('yt-high-indexed', SourceType.youtube, viewCount: 10);
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube)
        ..tracks = [low, high];
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
      );

      await service.refreshSource(SourceType.youtube);

      _expectRankingRequest(youtubeSource.lastRequest, category: 'music');
      // 順序原樣來自 adapter（排序責任已移入 YouTubeSource）。
      expect(service.state.tracksFor(SourceType.youtube), [low, high]);
      expect(service.state.isLoaded(SourceType.youtube), isTrue);
      expect(service.state.errorFor(SourceType.youtube), isNull);
      expect(bilibiliSource.fetchCount, 0);
      expect(neteaseSource.fetchCount, 0);

      service.dispose();
    });

    test('refresh methods send source-specific ranking requests', () async {
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
      );

      await service.refreshSource(SourceType.bilibili);
      await service.refreshSource(SourceType.youtube);
      await service.refreshSource(SourceType.netease);

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
        rankingSources: {
          SourceType.bilibili: _FakeRankingSource(SourceType.bilibili),
          SourceType.youtube: _FakeRankingSource(SourceType.youtube),
          SourceType.netease: neteaseSource,
        },
      );

      await service.refreshSource(SourceType.netease);
      expect(service.state.tracksFor(SourceType.netease), [oldTrack]);
      expect(service.state.errorFor(SourceType.netease), isNull);

      neteaseSource.nextError = Exception('network down');
      await service.refreshSource(SourceType.netease);

      expect(service.state.tracksFor(SourceType.netease), [oldTrack]);
      expect(
          service.state.errorFor(SourceType.netease), contains('network down'));

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
        rankingSources: {
          SourceType.bilibili: _FakeRankingSource(SourceType.bilibili),
          SourceType.youtube: _FakeRankingSource(SourceType.youtube),
          SourceType.netease: neteaseSource,
        },
      );

      final oldRefresh = service.refreshSource(SourceType.netease);
      await pumpEventQueue();

      await service.refreshSource(SourceType.netease);
      expect(service.state.tracksFor(SourceType.netease), [newTrack]);
      expect(service.state.isLoaded(SourceType.netease), isTrue);
      expect(service.state.errorFor(SourceType.netease), isNull);

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.tracksFor(SourceType.netease), [newTrack]);
      expect(service.state.isLoaded(SourceType.netease), isTrue);
      expect(service.state.errorFor(SourceType.netease), isNull);

      service.dispose();
    });

    test('refreshNetease stale success does not clear newer error', () async {
      final oldTrack = _track('old-ne', SourceType.netease);
      final oldCompleter = Completer<void>();
      final neteaseSource = _FakeRankingSource(SourceType.netease)
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(error: Exception('new failure'));
      final service = RankingCacheService(
        rankingSources: {
          SourceType.bilibili: _FakeRankingSource(SourceType.bilibili),
          SourceType.youtube: _FakeRankingSource(SourceType.youtube),
          SourceType.netease: neteaseSource,
        },
      );

      final oldRefresh = service.refreshSource(SourceType.netease);
      await pumpEventQueue();

      await service.refreshSource(SourceType.netease);
      expect(service.state.tracksFor(SourceType.netease), isEmpty);
      expect(service.state.isLoaded(SourceType.netease), isFalse);
      expect(
          service.state.errorFor(SourceType.netease), contains('new failure'));

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.tracksFor(SourceType.netease), isEmpty);
      expect(service.state.isLoaded(SourceType.netease), isFalse);
      expect(
          service.state.errorFor(SourceType.netease), contains('new failure'));

      service.dispose();
    });

    test('setupNetworkMonitoring rebinds to the latest connectivity notifier',
        () async {
      final bilibiliSource = _FakeRankingSource(SourceType.bilibili);
      final youtubeSource = _FakeRankingSource(SourceType.youtube);
      final neteaseSource = _FakeRankingSource(SourceType.netease);
      final service = RankingCacheService(
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
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
        rankingSources: {
          SourceType.bilibili: _FakeRankingSource(SourceType.bilibili),
          SourceType.youtube: _FakeRankingSource(SourceType.youtube),
          SourceType.netease: _FakeRankingSource(SourceType.netease),
        },
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
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
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
        rankingSources: {
          SourceType.bilibili: bilibiliSource,
          SourceType.youtube: youtubeSource,
          SourceType.netease: neteaseSource,
        },
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

    test('refresh preserves the order the ranking source returns', () async {
      final low = _track('yt-low', SourceType.youtube, viewCount: 1);
      final high = _track('yt-high', SourceType.youtube, viewCount: 100);
      final middle = _track('yt-middle', SourceType.youtube, viewCount: 50);
      final service = RankingCacheService(
        rankingSources: {
          SourceType.bilibili: _FakeRankingSource(SourceType.bilibili),
          SourceType.youtube: _FakeRankingSource(SourceType.youtube)
            ..tracks = [low, high, middle],
          SourceType.netease: _FakeRankingSource(SourceType.netease),
        },
      );

      await service.refreshSource(SourceType.youtube);

      // 快取層不再對任何音源做排序特判：它原樣保留 adapter 回傳的順序。
      // YouTube 依播放數降序的規則已移入 YouTubeSource.getRankingTracks，
      // 由 test/data/sources/youtube_source_test.dart 覆蓋。
      expect(service.state.tracksFor(SourceType.youtube), [low, high, middle]);

      service.dispose();
    });

    test('provider only refreshes sources that expose a RankingSource', () {
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [_FakeRankingSource(SourceType.bilibili)],
            ),
          ),
          connectivityProvider
              .overrideWith((ref) => _TestConnectivityNotifier()),
        ],
      );

      // 註冊表驅動：沒有排行榜能力的音源被略過，不再是啟動時的硬性錯誤。
      final service = container.read(rankingCacheServiceProvider.notifier);
      expect(service.rankedSourceTypes, [SourceType.bilibili]);

      container.dispose();
    });

    test('provider throws when no source exposes a RankingSource', () {
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(sources: const []),
          ),
        ],
      );

      // Riverpod 3 把 provider 拋出的例外包成 ProviderException，
      // 原始例外在 .exception。斷言仍然釘住同一個 StateError。
      expect(
        () => container.read(rankingCacheServiceProvider),
        throwsA(
          isA<ProviderException>().having(
            (wrapped) => wrapped.exception,
            'exception',
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'No ranking source registered',
            ),
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

  @override
  SourceRankingRequest get defaultRankingRequest => switch (sourceType) {
        SourceType.bilibili => const SourceRankingRequest(regionId: 1003),
        SourceType.youtube => const SourceRankingRequest(category: 'music'),
        SourceType.netease => const SourceRankingRequest(limit: 50),
      };

  @override
  String get rankingLabel => '${sourceType.name} ranking';

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
