import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/ui/selection_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/ui/pages/explore/explore_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ranking UI state consumption', () {
    testWidgets(
      'select all uses visible ranking tab after switching tabs in selection mode',
      (tester) async {
        final bilibiliTracks = [
          _track('bv-a', SourceIds.bilibili, 'Bili A'),
          _track('bv-b', SourceIds.bilibili, 'Bili B'),
        ];
        final youtubeTracks = [
          _track('yt-a', SourceIds.youtube, 'YT A'),
          _track('yt-b', SourceIds.youtube, 'YT B'),
          _track('yt-c', SourceIds.youtube, 'YT C'),
        ];
        final neteaseTracks = [
          _track('ne-a', SourceIds.netease, 'NE A'),
          _track('ne-b', SourceIds.netease, 'NE B'),
          _track('ne-c', SourceIds.netease, 'NE C'),
          _track('ne-d', SourceIds.netease, 'NE D'),
        ];
        final container = ProviderContainer(
          overrides: [
            rankingCacheServiceProvider.overrideWith(
              (ref) => _StaticRankingCacheService(
                bilibiliTracks: bilibiliTracks,
                youtubeTracks: youtubeTracks,
                neteaseTracks: neteaseTracks,
              ),
            ),
            currentTrackProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        LocaleSettings.setLocale(AppLocale.en);
        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(
          TranslationProvider(
            child: UncontrolledProviderScope(
              container: container,
              child: const MaterialApp(home: ExplorePage()),
            ),
          ),
        );
        await tester.pump();

        await tester.longPress(find.text('Bili A'));
        await tester.pump();
        expect(
            container.read(exploreSelectionProvider).isSelectionMode, isTrue);

        await tester.tap(find.text('YouTube'));
        await tester.pumpAndSettle();
        expect(find.text('YT A'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pump();

        expect(
          container.read(exploreSelectionProvider).selectedTracks.map(
                (track) => track.sourceId,
              ),
          orderedEquals(['yt-a', 'yt-b', 'yt-c']),
        );

        await tester.tap(find.text(t.importPlatform.netease));
        await tester.pumpAndSettle();
        expect(find.text('NE A'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pump();

        expect(
          container.read(exploreSelectionProvider).selectedTracks.map(
                (track) => track.sourceId,
              ),
          orderedEquals(['ne-a', 'ne-b', 'ne-c', 'ne-d']),
        );
      },
    );

    test('home rankings select only the initial loading flag', () {
      final homePageSource = File(
        'lib/ui/pages/home/home_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'ref\.watch\(\s*rankingCacheServiceProvider\.select\(\(state\)\s*=>\s*state\.isInitialLoading\)\s*,?\s*\)',
          dotAll: true,
        ).hasMatch(homePageSource),
        isTrue,
        reason:
            'Home rankings should not rebuild for unrelated ranking cache state changes.',
      );
    });

    test('explore tabs select only source-specific ranking cache fields', () {
      final source = File(
        'lib/ui/pages/explore/explore_page.dart',
      ).readAsStringSync();

      // 只比對 select 片段，不含 provider 名稱：`dart format` 會把長行折在
      // provider 與 .select 之間，把兩者綁在同一個字串會讓這條測試隨格式化紅燈。
      expect(
          source, isNot(contains('ref.watch(rankingCacheServiceProvider);')));
      expect(
        source,
        contains(
            'rankingCacheServiceProvider.select((state) => state.isInitialLoading)'),
      );
      expect(
        source,
        contains('.select((state) => state.errorFor(SourceIds.bilibili))'),
      );
      expect(
        source,
        contains('.select((state) => state.errorFor(SourceIds.youtube))'),
      );
      expect(
        source,
        contains('.select((state) => state.errorFor(SourceIds.netease))'),
      );
    });
  });
}

class _StaticRankingCacheService extends RankingCacheService {
  _StaticRankingCacheService({
    required List<Track> bilibiliTracks,
    required List<Track> youtubeTracks,
    required List<Track> neteaseTracks,
  }) : super(
          rankingSources: {
            SourceIds.bilibili: _FakeRankingSource(SourceIds.bilibili),
            SourceIds.youtube: _FakeRankingSource(SourceIds.youtube),
            SourceIds.netease: _FakeRankingSource(SourceIds.netease),
          },
        ) {
    state = RankingCacheState(
      tracksBySource: {
        SourceIds.bilibili: bilibiliTracks,
        SourceIds.youtube: youtubeTracks,
        SourceIds.netease: neteaseTracks,
      },
      loadedBySource: const {
        SourceIds.bilibili: true,
        SourceIds.youtube: true,
        SourceIds.netease: true,
      },
      isInitialLoading: false,
    );
  }

  @override
  Future<void> refreshSource(String sourceType) async {}
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

Track _track(String sourceId, String sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = 'Tester';
}
