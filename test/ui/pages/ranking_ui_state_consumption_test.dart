import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/ui/selection_provider.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
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
              () => _StaticRankingCacheService(
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
          container.read(exploreSelectionProvider).isSelectionMode,
          isTrue,
        );

        await tester.tap(find.text('YouTube'));
        await tester.pumpAndSettle();
        expect(find.text('YT A'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pump();

        expect(
          container
              .read(exploreSelectionProvider)
              .selectedTracks
              .map((track) => track.sourceId),
          orderedEquals(['yt-a', 'yt-b', 'yt-c']),
        );

        await tester.tap(find.text(t.importPlatform.netease));
        await tester.pumpAndSettle();
        expect(find.text('NE A'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.select_all));
        await tester.pump();

        expect(
          container
              .read(exploreSelectionProvider)
              .selectedTracks
              .map((track) => track.sourceId),
          orderedEquals(['ne-a', 'ne-b', 'ne-c', 'ne-d']),
        );
      },
    );
  });
}

/// 不呼叫 `super.build()`：真的那個會接線音源、啟動初次載入與網路監聽。
class _StaticRankingCacheService extends RankingCacheService {
  _StaticRankingCacheService({
    required this.bilibiliTracks,
    required this.youtubeTracks,
    required this.neteaseTracks,
  });

  final List<Track> bilibiliTracks;
  final List<Track> youtubeTracks;
  final List<Track> neteaseTracks;

  @override
  RankingCacheState build() {
    return RankingCacheState(
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

Track _track(String sourceId, String sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = 'Tester';
}
