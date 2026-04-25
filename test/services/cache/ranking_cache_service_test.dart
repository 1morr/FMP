import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RankingCacheService lifecycle hardening', () {
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
      final firstService = firstContainer.read(rankingCacheServiceProvider);
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
      final secondService = secondContainer.read(rankingCacheServiceProvider);

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

  @override
  Future<List<Track>> getRankingVideos({int rid = 0}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    return [];
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;

  @override
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    return [];
  }
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
