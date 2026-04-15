import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RankingCacheService lifecycle hardening', () {
    test('setupNetworkMonitoring rebinds to the latest connectivity notifier', () async {
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

    test('provider teardown allows rebinding to a fresh connectivity notifier', () async {
      final bilibiliSource = _FakeBilibiliSource();
      final youtubeSource = _FakeYouTubeSource();
      final service = RankingCacheService(
        bilibiliSource: bilibiliSource,
        youtubeSource: youtubeSource,
      );
      RankingCacheService.instance = service;

      final firstNotifier = _TestConnectivityNotifier();
      final firstContainer = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => firstNotifier),
        ],
      );
      firstContainer.read(rankingCacheServiceProvider);
      firstContainer.dispose();

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(bilibiliSource.fetchCount, 0);
      expect(youtubeSource.fetchCount, 0);

      final secondNotifier = _TestConnectivityNotifier();
      final secondContainer = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => secondNotifier),
        ],
      );
      secondContainer.read(rankingCacheServiceProvider);

      firstNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);
      expect(bilibiliSource.fetchCount, 0);
      expect(youtubeSource.fetchCount, 0);

      secondNotifier.emitNetworkRecovered();
      await pumpEventQueue(times: 5);

      expect(bilibiliSource.fetchCount, 1);
      expect(youtubeSource.fetchCount, 1);

      secondContainer.dispose();
      service.dispose();
      firstNotifier.closeStream();
      secondNotifier.closeStream();
    });
  });
}

class _FakeBilibiliSource extends BilibiliSource {
  int fetchCount = 0;

  @override
  Future<List<Track>> getRankingVideos({int rid = 0}) async {
    fetchCount++;
    return [];
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  int fetchCount = 0;

  @override
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    fetchCount++;
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

  @override
  void dispose() {
    super.dispose();
  }
}
