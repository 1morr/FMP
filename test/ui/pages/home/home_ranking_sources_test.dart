import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/settings/home_ranking_settings_provider.dart';
import 'package:fmp/providers/search/popular_provider.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/ui/pages/home/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('home ranking source selection', () {
    test('priority order decides display order', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 1200,
        enabledSourceOrder: const ['netease', 'youtube', 'bilibili'],
        tracksBySource: {
          'bilibili': [_track('bili', SourceType.bilibili)],
          'youtube': [_track('yt', SourceType.youtube)],
          'netease': [_track('ne', SourceType.netease)],
        },
      );

      expect(plan.sources.map((source) => source.id), [
        'netease',
        'youtube',
        'bilibili',
      ]);
    });

    test('disabled source does not display', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 1200,
        enabledSourceOrder: const ['netease', 'bilibili'],
        tracksBySource: {
          'bilibili': [_track('bili', SourceType.bilibili)],
          'youtube': [_track('yt', SourceType.youtube)],
          'netease': [_track('ne', SourceType.netease)],
        },
      );

      expect(plan.sources.map((source) => source.id), [
        'netease',
        'bilibili',
      ]);
    });

    test('empty source is backfilled by later source', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 800,
        enabledSourceOrder: const ['netease', 'youtube', 'bilibili'],
        tracksBySource: {
          'bilibili': [_track('bili', SourceType.bilibili)],
          'youtube': [_track('yt', SourceType.youtube)],
          'netease': const <Track>[],
        },
      );

      expect(plan.axis, Axis.horizontal);
      expect(plan.sources.map((source) => source.id), [
        'youtube',
        'bilibili',
      ]);
    });

    test('narrow screens show at most two rankings vertically', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 599,
        enabledSourceOrder: const ['bilibili', 'youtube', 'netease'],
        tracksBySource: _allTracks,
      );

      expect(plan.axis, Axis.vertical);
      expect(plan.sources.map((source) => source.id), [
        'bilibili',
        'youtube',
      ]);
    });

    test('desktop screens show at most three rankings horizontally', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 1200,
        enabledSourceOrder: const ['bilibili', 'youtube', 'netease'],
        tracksBySource: _allTracks,
      );

      expect(plan.axis, Axis.horizontal);
      expect(plan.sources.map((source) => source.id), [
        'bilibili',
        'youtube',
        'netease',
      ]);
    });

    testWidgets(
      'all disabled sources hide the section during initial loading',
      (tester) async {
        LocaleSettings.setLocale(AppLocale.en);

        await tester.pumpWidget(
          _testApp(
            overrides: [
              enabledHomeRankingSourceOrderProvider.overrideWith(
                (ref) => const <String>[],
              ),
              rankingCacheServiceProvider.overrideWith(
                (ref) => _StaticRankingCacheService(isInitialLoading: true),
              ),
              homeBilibiliMusicRankingProvider.overrideWith(
                (ref) => throw StateError('bilibili should not be watched'),
              ),
              homeYouTubeMusicRankingProvider.overrideWith(
                (ref) => throw StateError('youtube should not be watched'),
              ),
              homeNeteaseHotRankingProvider.overrideWith(
                (ref) => throw StateError('netease should not be watched'),
              ),
            ],
          ),
        );

        expect(find.text(t.home.recentTrending), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('disabled ranking providers are not watched', (tester) async {
      LocaleSettings.setLocale(AppLocale.en);

      await tester.pumpWidget(
        _testApp(
          overrides: [
            enabledHomeRankingSourceOrderProvider.overrideWith(
              (ref) => const ['youtube'],
            ),
            rankingCacheServiceProvider.overrideWith(
              (ref) => _StaticRankingCacheService(isInitialLoading: false),
            ),
            homeBilibiliMusicRankingProvider.overrideWith(
              (ref) => throw StateError('bilibili should not be watched'),
            ),
            homeYouTubeMusicRankingProvider.overrideWith(
              (ref) => const <Track>[],
            ),
            homeNeteaseHotRankingProvider.overrideWith(
              (ref) => throw StateError('netease should not be watched'),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(t.home.recentTrending), findsNothing);
    });
  });
}

Map<String, List<Track>> get _allTracks => {
      'bilibili': [_track('bili', SourceType.bilibili)],
      'youtube': [_track('yt', SourceType.youtube)],
      'netease': [_track('ne', SourceType.netease)],
    };

Track _track(String sourceId, SourceType sourceType) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = sourceId
    ..artist = 'Tester';
}

Widget _testApp({required List<Override> overrides}) {
  return TranslationProvider(
    child: ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        home: Scaffold(body: HomeRankingsSection()),
      ),
    ),
  );
}

class _StaticRankingCacheService extends RankingCacheService {
  _StaticRankingCacheService({required bool isInitialLoading})
      : super(
          bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
          youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
          neteaseRankingSource: _FakeRankingSource(SourceType.netease),
        ) {
    state = RankingCacheState(isInitialLoading: isInitialLoading);
  }
}

class _FakeRankingSource implements RankingSource {
  _FakeRankingSource(this.sourceType);

  @override
  final SourceType sourceType;

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) async {
    return const <Track>[];
  }
}
