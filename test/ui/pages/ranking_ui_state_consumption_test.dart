import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_source.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/selection_provider.dart';
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
          _track('bv-a', SourceType.bilibili, 'Bili A'),
          _track('bv-b', SourceType.bilibili, 'Bili B'),
        ];
        final youtubeTracks = [
          _track('yt-a', SourceType.youtube, 'YT A'),
          _track('yt-b', SourceType.youtube, 'YT B'),
          _track('yt-c', SourceType.youtube, 'YT C'),
        ];
        final neteaseTracks = [
          _track('ne-a', SourceType.netease, 'NE A'),
          _track('ne-b', SourceType.netease, 'NE B'),
          _track('ne-c', SourceType.netease, 'NE C'),
          _track('ne-d', SourceType.netease, 'NE D'),
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

      expect(
          source, isNot(contains('ref.watch(rankingCacheServiceProvider);')));
      expect(
        source,
        contains(
            'rankingCacheServiceProvider.select((state) => state.isInitialLoading)'),
      );
      expect(
        source,
        contains(
            'rankingCacheServiceProvider.select((state) => state.bilibiliError)'),
      );
      expect(
        source,
        contains(
            'rankingCacheServiceProvider.select((state) => state.youtubeError)'),
      );
      expect(
        source,
        contains(
            'rankingCacheServiceProvider.select((state) => state.neteaseError)'),
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
          bilibiliSource: _FakeBilibiliSource(),
          youtubeSource: _FakeYouTubeSource(),
          neteaseSource: _FakeNeteaseSource(),
        ) {
    state = RankingCacheState(
      bilibiliTracks: List.unmodifiable(bilibiliTracks),
      youtubeTracks: List.unmodifiable(youtubeTracks),
      neteaseTracks: List.unmodifiable(neteaseTracks),
      isInitialLoading: false,
      bilibiliLoaded: true,
      youtubeLoaded: true,
      neteaseLoaded: true,
    );
  }

  @override
  Future<void> refreshBilibili() async {}

  @override
  Future<void> refreshYouTube() async {}

  @override
  Future<void> refreshNetease() async {}
}

class _FakeBilibiliSource extends BilibiliSource {
  @override
  Future<List<Track>> getRankingVideos({int rid = 0}) async => const <Track>[];
}

class _FakeYouTubeSource extends YouTubeSource {
  @override
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    return const <Track>[];
  }
}

class _FakeNeteaseSource extends NeteaseSource {
  @override
  Future<List<Track>> getHotRankingTracks({int limit = 50}) async {
    return const <Track>[];
  }
}

Track _track(String sourceId, SourceType sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = 'Tester';
}
