import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
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
          'bilibili': [_track('bili', SourceIds.bilibili)],
          'youtube': [_track('yt', SourceIds.youtube)],
          'netease': [_track('ne', SourceIds.netease)],
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
          'bilibili': [_track('bili', SourceIds.bilibili)],
          'youtube': [_track('yt', SourceIds.youtube)],
          'netease': [_track('ne', SourceIds.netease)],
        },
      );

      expect(plan.sources.map((source) => source.id), ['netease', 'bilibili']);
    });

    test('empty source is backfilled by later source', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 800,
        enabledSourceOrder: const ['netease', 'youtube', 'bilibili'],
        tracksBySource: {
          'bilibili': [_track('bili', SourceIds.bilibili)],
          'youtube': [_track('yt', SourceIds.youtube)],
          'netease': const <Track>[],
        },
      );

      expect(plan.columns, 2);
      expect(plan.sources.map((source) => source.id), ['youtube', 'bilibili']);
    });

    test('narrow screens stack every source, one per row', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 599,
        enabledSourceOrder: const ['bilibili', 'youtube', 'netease'],
        tracksBySource: _allTracks,
      );

      // 垂直堆疊沒有任何寬度限制，所以沒有理由藏起第三個。這裡原本斷言
      // 「手機最多兩個」—— 那條斷言釘住的就是這個缺陷本身。
      expect(plan.columns, 1);
      expect(plan.rows.map((row) => row.length), [1, 1, 1]);
      expect(plan.sources.map((source) => source.id), [
        'bilibili',
        'youtube',
        'netease',
      ]);
    });

    test('desktop screens fit all three rankings on one row', () {
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 1200,
        enabledSourceOrder: const ['bilibili', 'youtube', 'netease'],
        tracksBySource: _allTracks,
      );

      expect(plan.columns, 3);
      expect(plan.rows, hasLength(1));
      expect(plan.sources.map((source) => source.id), [
        'bilibili',
        'youtube',
        'netease',
      ]);
    });

    test(
      'a panel that shrinks the content wraps a source instead of dropping it',
      () {
        // P0-1：1280dp 平板開啟曲目詳情面板（約 412dp）之後，內容區只剩約 868dp，
        // 斷點從 desktop 掉到 tablet。以前第三個音源會整個消失。
        final plan = buildHomeRankingLayoutPlan(
          maxWidth: 1280 - 412,
          enabledSourceOrder: const ['bilibili', 'youtube', 'netease'],
          tracksBySource: _allTracks,
        );

        expect(plan.columns, 2);
        expect(plan.rows.map((row) => row.length), [2, 1]);
        expect(plan.sources.map((source) => source.id), [
          'bilibili',
          'youtube',
          'netease',
        ]);
      },
    );

    test('the plan reports enabled sources that have no data yet', () {
      // 載入中要顯示佔位符而不是把整段藏起來，靠的是這個旗標而不是 sources。
      final plan = buildHomeRankingLayoutPlan(
        maxWidth: 1200,
        enabledSourceOrder: const ['bilibili', 'youtube'],
        tracksBySource: const {'bilibili': <Track>[], 'youtube': <Track>[]},
      );

      expect(plan.hasCandidateSources, isTrue);
      expect(plan.sources, isEmpty);
      expect(plan.rows, isEmpty);
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
                () => _StaticRankingCacheService(isInitialLoading: true),
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
              () => _StaticRankingCacheService(isInitialLoading: false),
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
  'bilibili': [_track('bili', SourceIds.bilibili)],
  'youtube': [_track('yt', SourceIds.youtube)],
  'netease': [_track('ne', SourceIds.netease)],
};

Track _track(String sourceId, String sourceType) {
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
      child: const MaterialApp(home: Scaffold(body: HomeRankingsSection())),
    ),
  );
}

/// 不呼叫 `super.build()`：真的那個會接線音源、啟動初次載入與網路監聽。
class _StaticRankingCacheService extends RankingCacheService {
  _StaticRankingCacheService({required this.isInitialLoading});

  final bool isInitialLoading;

  @override
  RankingCacheState build() =>
      RankingCacheState(isInitialLoading: isInitialLoading);
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

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) async {
    return const <Track>[];
  }
}
