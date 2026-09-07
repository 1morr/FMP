import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/search/popular_provider.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';
import '../../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RankingCacheService lifecycle hardening', () {
    test('state exposes source-indexed cache accessors', () {
      final bilibiliTrack = _track('bv-indexed', SourceIds.bilibili);
      final youtubeTrack = _track('yt-indexed', SourceIds.youtube);
      final state = RankingCacheState(
        tracksBySource: {
          SourceIds.bilibili: [bilibiliTrack],
          SourceIds.youtube: [youtubeTrack],
        },
        loadedBySource: const {
          SourceIds.bilibili: true,
          SourceIds.youtube: false,
        },
        errorsBySource: const {SourceIds.youtube: 'youtube offline'},
      );

      expect(state.tracksFor(SourceIds.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceIds.youtube), [youtubeTrack]);
      expect(state.tracksFor(SourceIds.netease), isEmpty);
      expect(state.isLoaded(SourceIds.bilibili), isTrue);
      expect(state.isLoaded(SourceIds.youtube), isFalse);
      expect(state.errorFor(SourceIds.youtube), 'youtube offline');
      expect(state.errorFor(SourceIds.netease), isNull);
      expect(state.tracksFor(SourceIds.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceIds.youtube), [youtubeTrack]);
      expect(
        () => state
            .tracksFor(SourceIds.bilibili)
            .add(_track('mutate-indexed', SourceIds.bilibili)),
        throwsUnsupportedError,
      );
    });

    test('provider exposes immutable ranking state after refresh', () async {
      final bilibiliTrack = _track('bv-1', SourceIds.bilibili);
      final youtubeTrack = _track('yt-1', SourceIds.youtube, viewCount: 20);
      final neteaseTrack = _track('ne-1', SourceIds.netease);
      final bilibiliSource = _FakeRankingSource(SourceIds.bilibili)
        ..tracks = [bilibiliTrack];
      final youtubeSource = _FakeRankingSource(SourceIds.youtube)
        ..tracks = [youtubeTrack];
      final neteaseSource = _FakeRankingSource(SourceIds.netease)
        ..tracks = [neteaseTrack];
      final notifier = _TestConnectivityNotifier();
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [bilibiliSource, youtubeSource, neteaseSource],
            ),
          ),
          connectivityProvider.overrideWith(() => notifier),
        ],
      );

      expect(
        container.read(rankingCacheServiceProvider).isInitialLoading,
        isTrue,
      );

      await pumpUntil(
        () => !container.read(rankingCacheServiceProvider).isInitialLoading,
        reason: 'the initial ranking load should finish',
      );
      final state = container.read(rankingCacheServiceProvider);

      expect(state.isInitialLoading, isFalse);
      expect(state.tracksFor(SourceIds.bilibili), [bilibiliTrack]);
      expect(state.tracksFor(SourceIds.youtube), [youtubeTrack]);
      expect(state.tracksFor(SourceIds.netease), [neteaseTrack]);
      expect(state.isLoaded(SourceIds.bilibili), isTrue);
      expect(state.isLoaded(SourceIds.youtube), isTrue);
      expect(state.isLoaded(SourceIds.netease), isTrue);

      expect(
        () => state
            .tracksFor(SourceIds.bilibili)
            .add(_track('mutate', SourceIds.bilibili)),
        throwsUnsupportedError,
      );
      expect(
        () => state
            .tracksFor(SourceIds.youtube)
            .add(_track('mutate', SourceIds.youtube)),
        throwsUnsupportedError,
      );
      expect(
        () => state
            .tracksFor(SourceIds.netease)
            .add(_track('mutate', SourceIds.netease)),
        throwsUnsupportedError,
      );

      container.dispose();
      await notifier.closeStream();
    });

    test(
      'derived ranking providers expose preview and full immutable lists',
      () async {
        final bilibiliTracks = List.generate(
          12,
          (index) => _track('bv-$index', SourceIds.bilibili),
        );
        final youtubeTracks = List.generate(
          12,
          (index) => _track('yt-$index', SourceIds.youtube, viewCount: index),
        );
        final neteaseTracks = List.generate(
          12,
          (index) => _track('ne-$index', SourceIds.netease),
        );
        final notifier = _TestConnectivityNotifier();
        final container = ProviderContainer(
          overrides: [
            sourceManagerProvider.overrideWith(
              (ref) => SourceManager(
                sources: [
                  _FakeRankingSource(SourceIds.bilibili)
                    ..tracks = bilibiliTracks,
                  _FakeRankingSource(SourceIds.youtube)..tracks = youtubeTracks,
                  _FakeRankingSource(SourceIds.netease)..tracks = neteaseTracks,
                ],
              ),
            ),
            connectivityProvider.overrideWith(() => notifier),
          ],
        );

        container.read(rankingCacheServiceProvider);
        await pumpUntil(
          () => !container.read(rankingCacheServiceProvider).isInitialLoading,
          reason: 'the initial ranking load should finish',
        );

        final bilibiliPreview = container.read(
          homeBilibiliMusicRankingProvider,
        );
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
              bilibiliPreview.add(_track('mutate-preview', SourceIds.bilibili)),
          throwsUnsupportedError,
        );
        expect(
          () => cachedBilibili.add(_track('mutate-full', SourceIds.bilibili)),
          throwsUnsupportedError,
        );
        expect(
          () => bilibiliPreview[0] = _track(
            'replace-preview',
            SourceIds.bilibili,
          ),
          throwsUnsupportedError,
        );
        expect(
          () => cachedBilibili[0] = _track('replace-full', SourceIds.bilibili),
          throwsUnsupportedError,
        );
        expect(
          () => youtubePreview.add(_track('mutate-preview', SourceIds.youtube)),
          throwsUnsupportedError,
        );
        expect(
          () => cachedYouTube.add(_track('mutate-full', SourceIds.youtube)),
          throwsUnsupportedError,
        );
        expect(
          () =>
              youtubePreview[0] = _track('replace-preview', SourceIds.youtube),
          throwsUnsupportedError,
        );
        expect(
          () => cachedYouTube[0] = _track('replace-full', SourceIds.youtube),
          throwsUnsupportedError,
        );
        expect(
          () => neteasePreview.add(_track('mutate-preview', SourceIds.netease)),
          throwsUnsupportedError,
        );
        expect(
          () => cachedNetease.add(_track('mutate-full', SourceIds.netease)),
          throwsUnsupportedError,
        );
        expect(
          () =>
              neteasePreview[0] = _track('replace-preview', SourceIds.netease),
          throwsUnsupportedError,
        );
        expect(
          () => cachedNetease[0] = _track('replace-full', SourceIds.netease),
          throwsUnsupportedError,
        );

        container.dispose();
        await notifier.closeStream();
      },
    );

    test('refresh failure keeps old tracks and records source error', () async {
      final oldTrack = _track('old-bv', SourceIds.bilibili);
      final bilibiliSource = _FakeRankingSource(SourceIds.bilibili)
        ..tracks = [oldTrack];
      final youtubeSource = _FakeRankingSource(SourceIds.youtube);
      final neteaseSource = _FakeRankingSource(SourceIds.netease);
      final service = _bareService([
        bilibiliSource,
        youtubeSource,
        neteaseSource,
      ]);

      await service.refreshSource(SourceIds.bilibili);
      expect(service.state.tracksFor(SourceIds.bilibili), [oldTrack]);
      expect(service.state.errorFor(SourceIds.bilibili), isNull);

      bilibiliSource.nextError = Exception('network down');
      await service.refreshSource(SourceIds.bilibili);

      expect(service.state.tracksFor(SourceIds.bilibili), [oldTrack]);
      expect(
        service.state.errorFor(SourceIds.bilibili),
        contains('network down'),
      );
    });

    test(
      'refreshSource sends source-specific requests and stores by source',
      () async {
        final low = _track('yt-low-indexed', SourceIds.youtube, viewCount: 1);
        final high = _track(
          'yt-high-indexed',
          SourceIds.youtube,
          viewCount: 10,
        );
        final bilibiliSource = _FakeRankingSource(SourceIds.bilibili);
        final youtubeSource = _FakeRankingSource(SourceIds.youtube)
          ..tracks = [low, high];
        final neteaseSource = _FakeRankingSource(SourceIds.netease);
        final service = _bareService([
          bilibiliSource,
          youtubeSource,
          neteaseSource,
        ]);

        await service.refreshSource(SourceIds.youtube);

        _expectRankingRequest(youtubeSource.lastRequest, category: 'music');
        // 順序原樣來自 adapter（排序責任已移入 YouTubeSource）。
        expect(service.state.tracksFor(SourceIds.youtube), [low, high]);
        expect(service.state.isLoaded(SourceIds.youtube), isTrue);
        expect(service.state.errorFor(SourceIds.youtube), isNull);
        expect(bilibiliSource.fetchCount, 0);
        expect(neteaseSource.fetchCount, 0);
      },
    );

    test('refresh methods send source-specific ranking requests', () async {
      final bilibiliSource = _FakeRankingSource(SourceIds.bilibili);
      final youtubeSource = _FakeRankingSource(SourceIds.youtube);
      final neteaseSource = _FakeRankingSource(SourceIds.netease);
      final service = _bareService([
        bilibiliSource,
        youtubeSource,
        neteaseSource,
      ]);

      await service.refreshSource(SourceIds.bilibili);
      await service.refreshSource(SourceIds.youtube);
      await service.refreshSource(SourceIds.netease);

      _expectRankingRequest(bilibiliSource.lastRequest, regionId: 1003);
      _expectRankingRequest(youtubeSource.lastRequest, category: 'music');
      _expectRankingRequest(neteaseSource.lastRequest, limit: 50);
    });

    test(
      'refreshNetease failure keeps old tracks and records source error',
      () async {
        final oldTrack = _track('old-ne', SourceIds.netease);
        final neteaseSource = _FakeRankingSource(SourceIds.netease)
          ..tracks = [oldTrack];
        final service = _bareService([
          _FakeRankingSource(SourceIds.bilibili),
          _FakeRankingSource(SourceIds.youtube),
          neteaseSource,
        ]);

        await service.refreshSource(SourceIds.netease);
        expect(service.state.tracksFor(SourceIds.netease), [oldTrack]);
        expect(service.state.errorFor(SourceIds.netease), isNull);

        neteaseSource.nextError = Exception('network down');
        await service.refreshSource(SourceIds.netease);

        expect(service.state.tracksFor(SourceIds.netease), [oldTrack]);
        expect(
          service.state.errorFor(SourceIds.netease),
          contains('network down'),
        );
      },
    );

    test('refreshNetease ignores stale out-of-order completion', () async {
      final oldTrack = _track('old-ne', SourceIds.netease);
      final newTrack = _track('new-ne', SourceIds.netease);
      final oldCompleter = Completer<void>();
      final neteaseSource = _FakeRankingSource(SourceIds.netease)
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(tracks: [newTrack]);
      final service = _bareService([
        _FakeRankingSource(SourceIds.bilibili),
        _FakeRankingSource(SourceIds.youtube),
        neteaseSource,
      ]);

      final oldRefresh = service.refreshSource(SourceIds.netease);
      await drainEventQueue(
        reason: 'let the first refresh reach its gated fetch',
      );

      await service.refreshSource(SourceIds.netease);
      expect(service.state.tracksFor(SourceIds.netease), [newTrack]);
      expect(service.state.isLoaded(SourceIds.netease), isTrue);
      expect(service.state.errorFor(SourceIds.netease), isNull);

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.tracksFor(SourceIds.netease), [newTrack]);
      expect(service.state.isLoaded(SourceIds.netease), isTrue);
      expect(service.state.errorFor(SourceIds.netease), isNull);
    });

    test('refreshNetease stale success does not clear newer error', () async {
      final oldTrack = _track('old-ne', SourceIds.netease);
      final oldCompleter = Completer<void>();
      final neteaseSource = _FakeRankingSource(SourceIds.netease)
        ..enqueueFetch(completer: oldCompleter, tracks: [oldTrack])
        ..enqueueFetch(error: Exception('new failure'));
      final service = _bareService([
        _FakeRankingSource(SourceIds.bilibili),
        _FakeRankingSource(SourceIds.youtube),
        neteaseSource,
      ]);

      final oldRefresh = service.refreshSource(SourceIds.netease);
      await drainEventQueue(
        reason: 'let the first refresh reach its gated fetch',
      );

      await service.refreshSource(SourceIds.netease);
      expect(service.state.tracksFor(SourceIds.netease), isEmpty);
      expect(service.state.isLoaded(SourceIds.netease), isFalse);
      expect(
        service.state.errorFor(SourceIds.netease),
        contains('new failure'),
      );

      oldCompleter.complete();
      await oldRefresh;

      expect(service.state.tracksFor(SourceIds.netease), isEmpty);
      expect(service.state.isLoaded(SourceIds.netease), isFalse);
      expect(
        service.state.errorFor(SourceIds.netease),
        contains('new failure'),
      );
    });

    test(
      'setupNetworkMonitoring rebinds to the latest connectivity notifier',
      () async {
        final bilibiliSource = _FakeRankingSource(SourceIds.bilibili);
        final youtubeSource = _FakeRankingSource(SourceIds.youtube);
        final neteaseSource = _FakeRankingSource(SourceIds.netease);
        final service = _bareService([
          bilibiliSource,
          youtubeSource,
          neteaseSource,
        ]);
        final firstNotifier = _TestConnectivityNotifier();
        final secondNotifier = _TestConnectivityNotifier();

        service.setupNetworkMonitoring(firstNotifier);
        service.setupNetworkMonitoring(secondNotifier);

        firstNotifier.emitNetworkRecovered();
        await drainEventQueue(
          reason: 'a superseded monitor must not trigger a refetch',
        );
        expect(bilibiliSource.fetchCount, 0);
        expect(youtubeSource.fetchCount, 0);
        expect(neteaseSource.fetchCount, 0);

        secondNotifier.emitNetworkRecovered();
        await pumpUntil(
          () => neteaseSource.fetchCount == 1,
          reason: 'the live monitor should trigger one refetch',
        );
        expect(bilibiliSource.fetchCount, 1);
        expect(youtubeSource.fetchCount, 1);
        expect(neteaseSource.fetchCount, 1);

        firstNotifier.closeStream();
        secondNotifier.closeStream();
      },
    );

    test('dispose is idempotent', () {
      final service = _bareService([
        _FakeRankingSource(SourceIds.bilibili),
        _FakeRankingSource(SourceIds.youtube),
        _FakeRankingSource(SourceIds.netease),
      ]);

      // 釋放現在由 container 負責；`_teardown` 的 `_isDisposed` 守衛仍在，
      // 這條就變成「重複釋放 container 不會炸」。
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [
                _FakeRankingSource(SourceIds.bilibili),
                _FakeRankingSource(SourceIds.youtube),
                _FakeRankingSource(SourceIds.netease),
              ],
            ),
          ),
          connectivityProvider.overrideWith(_TestConnectivityNotifier.new),
          rankingCacheServiceProvider.overrideWith(
            _BareRankingCacheService.new,
          ),
        ],
      );
      container.read(rankingCacheServiceProvider.notifier);
      container.dispose();

      expect(container.dispose, returnsNormally);
    });

    test(
      'provider teardown allows rebinding to a fresh connectivity notifier',
      () async {
        final firstBilibiliSource = _FakeRankingSource(SourceIds.bilibili);
        final firstYouTubeSource = _FakeRankingSource(SourceIds.youtube);
        final firstNeteaseSource = _FakeRankingSource(SourceIds.netease);
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
            connectivityProvider.overrideWith(() => firstNotifier),
          ],
        );
        final firstService = firstContainer.read(
          rankingCacheServiceProvider.notifier,
        );
        await pumpUntil(
          () => firstNeteaseSource.fetchCount == 1,
          reason: 'the first container should fetch every source once',
        );
        expect(firstBilibiliSource.fetchCount, 1);
        expect(firstYouTubeSource.fetchCount, 1);
        expect(firstNeteaseSource.fetchCount, 1);
        firstContainer.dispose();

        firstNotifier.emitNetworkRecovered();
        await drainEventQueue(
          reason: 'a disposed container must not refetch on network recovery',
        );
        expect(firstBilibiliSource.fetchCount, 1);
        expect(firstYouTubeSource.fetchCount, 1);
        expect(firstNeteaseSource.fetchCount, 1);
        expect(firstContainer.dispose, returnsNormally);

        final secondBilibiliSource = _FakeRankingSource(SourceIds.bilibili);
        final secondYouTubeSource = _FakeRankingSource(SourceIds.youtube);
        final secondNeteaseSource = _FakeRankingSource(SourceIds.netease);
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
            connectivityProvider.overrideWith(() => secondNotifier),
          ],
        );
        final secondService = secondContainer.read(
          rankingCacheServiceProvider.notifier,
        );

        expect(identical(firstService, secondService), isFalse);

        await pumpUntil(
          () => secondNeteaseSource.fetchCount == 1,
          reason: 'the second container should fetch every source once',
        );
        expect(secondBilibiliSource.fetchCount, 1);
        expect(secondYouTubeSource.fetchCount, 1);
        expect(secondNeteaseSource.fetchCount, 1);

        firstNotifier.emitNetworkRecovered();
        await drainEventQueue(
          reason: 'the disposed container must not refetch either container',
        );
        expect(firstBilibiliSource.fetchCount, 1);
        expect(firstYouTubeSource.fetchCount, 1);
        expect(firstNeteaseSource.fetchCount, 1);
        expect(secondBilibiliSource.fetchCount, 1);
        expect(secondYouTubeSource.fetchCount, 1);
        expect(secondNeteaseSource.fetchCount, 1);

        secondNotifier.emitNetworkRecovered();
        await pumpUntil(
          () => secondNeteaseSource.fetchCount == 2,
          reason: 'the live container should refetch on network recovery',
        );

        expect(secondBilibiliSource.fetchCount, 2);
        expect(secondYouTubeSource.fetchCount, 2);
        expect(secondNeteaseSource.fetchCount, 2);

        secondContainer.dispose();
        firstNotifier.closeStream();
        secondNotifier.closeStream();
      },
    );

    test(
      'updateRefreshInterval before initialize uses one latest timer',
      () async {
        final bilibiliSource = _FakeRankingSource(SourceIds.bilibili);
        final youtubeSource = _FakeRankingSource(SourceIds.youtube);
        final neteaseSource = _FakeRankingSource(SourceIds.netease);
        final bare = _bareServiceIn([
          bilibiliSource,
          youtubeSource,
          neteaseSource,
        ]);
        final service = bare.service;

        service.updateRefreshInterval(const Duration(milliseconds: 20));
        await service.initialize(refreshInterval: const Duration(days: 1));
        await Future<void>.delayed(const Duration(milliseconds: 70));
        bare.container.dispose();

        expect(bilibiliSource.fetchCount, greaterThanOrEqualTo(2));
        expect(bilibiliSource.fetchCount, lessThanOrEqualTo(6));
        expect(youtubeSource.fetchCount, greaterThanOrEqualTo(2));
        expect(youtubeSource.fetchCount, lessThanOrEqualTo(6));
        expect(neteaseSource.fetchCount, greaterThanOrEqualTo(2));
        expect(neteaseSource.fetchCount, lessThanOrEqualTo(6));
      },
    );

    test(
      'dispose before initialize completes prevents later refreshes',
      () async {
        final bilibiliCompleter = Completer<void>();
        final youtubeCompleter = Completer<void>();
        final neteaseCompleter = Completer<void>();
        final bilibiliSource = _FakeRankingSource(SourceIds.bilibili)
          ..nextFetchCompleter = bilibiliCompleter;
        final youtubeSource = _FakeRankingSource(SourceIds.youtube)
          ..nextFetchCompleter = youtubeCompleter;
        final neteaseSource = _FakeRankingSource(SourceIds.netease)
          ..nextFetchCompleter = neteaseCompleter;
        final bare = _bareServiceIn([
          bilibiliSource,
          youtubeSource,
          neteaseSource,
        ], initialLoadTimeout: const Duration(milliseconds: 10));
        final service = bare.service;

        final initializeFuture = service.initialize(
          refreshInterval: const Duration(milliseconds: 20),
        );
        await pumpUntil(
          () => neteaseSource.fetchCount == 1,
          reason: 'initialize should fetch every source once',
        );
        expect(bilibiliSource.fetchCount, 1);
        expect(youtubeSource.fetchCount, 1);
        expect(neteaseSource.fetchCount, 1);

        bare.container.dispose();
        bilibiliCompleter.complete();
        youtubeCompleter.complete();
        neteaseCompleter.complete();
        await initializeFuture;
        await Future<void>.delayed(const Duration(milliseconds: 70));

        expect(bilibiliSource.fetchCount, 1);
        expect(youtubeSource.fetchCount, 1);
        expect(neteaseSource.fetchCount, 1);
      },
    );

    test('refresh preserves the order the ranking source returns', () async {
      final low = _track('yt-low', SourceIds.youtube, viewCount: 1);
      final high = _track('yt-high', SourceIds.youtube, viewCount: 100);
      final middle = _track('yt-middle', SourceIds.youtube, viewCount: 50);
      final service = _bareService([
        _FakeRankingSource(SourceIds.bilibili),
        _FakeRankingSource(SourceIds.youtube)..tracks = [low, high, middle],
        _FakeRankingSource(SourceIds.netease),
      ]);

      await service.refreshSource(SourceIds.youtube);

      // 快取層不再對任何音源做排序特判：它原樣保留 adapter 回傳的順序。
      // YouTube 依播放數降序的規則已移入 YouTubeSource.getRankingTracks，
      // 由 test/data/sources/youtube_source_test.dart 覆蓋。
      expect(service.state.tracksFor(SourceIds.youtube), [low, high, middle]);
    });

    test('provider only refreshes sources that expose a RankingSource', () {
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(
              sources: [_FakeRankingSource(SourceIds.bilibili)],
            ),
          ),
          connectivityProvider.overrideWith(_TestConnectivityNotifier.new),
        ],
      );

      // 註冊表驅動：沒有排行榜能力的音源被略過，不再是啟動時的硬性錯誤。
      final service = container.read(rankingCacheServiceProvider.notifier);
      expect(service.rankedSourceTypes, [SourceIds.bilibili]);

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
      final source = _FakeRankingSource(SourceIds.bilibili);
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
      final source = _FakeRankingSource(SourceIds.youtube);
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
  final String sourceType;

  @override
  SourceRankingRequest get defaultRankingRequest => switch (sourceType) {
    SourceIds.bilibili => const SourceRankingRequest(regionId: 1003),
    SourceIds.youtube => const SourceRankingRequest(category: 'music'),
    SourceIds.netease => const SourceRankingRequest(limit: 50),
    _ => throw StateError('unconfigured fake source: $sourceType'),
  };

  @override
  String get rankingLabel => '${sourceType} ranking';

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

  const _QueuedFetch({this.completer, this.error, required this.tracks});
}

Track _track(String id, String sourceType, {int? viewCount}) {
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

/// `RankingCacheService` 以前用建構子吃音源表；`Notifier.new` 不吃參數，音源
/// 改由 `sourceManagerProvider` 進來。這組測試手動驅動刷新並數次數，所以用
/// 一個只接線、不啟動初次載入與網路監聽的子類。
RankingCacheService _bareService(
  List<SourceCapability> sources, {
  Duration? initialLoadTimeout,
}) => _bareServiceIn(sources, initialLoadTimeout: initialLoadTimeout).service;

/// 需要在測試中途主動釋放時用這個 —— 釋放現在是 container 的事。
({RankingCacheService service, ProviderContainer container}) _bareServiceIn(
  List<SourceCapability> sources, {
  Duration? initialLoadTimeout,
}) {
  final container = ProviderContainer(
    overrides: [
      sourceManagerProvider.overrideWith(
        (ref) => SourceManager(sources: sources),
      ),
      connectivityProvider.overrideWith(_TestConnectivityNotifier.new),
      rankingCacheServiceProvider.overrideWith(
        () => initialLoadTimeout == null
            ? _BareRankingCacheService()
            : _BareRankingCacheService(initialLoadTimeout: initialLoadTimeout),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    service: container.read(rankingCacheServiceProvider.notifier),
    container: container,
  );
}

class _BareRankingCacheService extends RankingCacheService {
  _BareRankingCacheService({super.initialLoadTimeout});

  @override
  RankingCacheState build() => bindSources();
}

/// 不呼叫 `super.build()`：真的那個會做 DNS 查詢並開一個輪詢計時器。
class _TestConnectivityNotifier extends ConnectivityNotifier {
  @override
  ConnectivityState build() => ConnectivityState.initial;

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
