import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
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
        final container = ProviderContainer(
          overrides: [
            rankingCacheServiceProvider.overrideWith(
              (ref) => _StaticRankingCacheService(
                bilibiliTracks: bilibiliTracks,
                youtubeTracks: youtubeTracks,
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
  });
}

class _StaticRankingCacheService extends RankingCacheService {
  _StaticRankingCacheService({
    required List<Track> bilibiliTracks,
    required List<Track> youtubeTracks,
  }) : super(
          bilibiliSource: _FakeBilibiliSource(),
          youtubeSource: _FakeYouTubeSource(),
        ) {
    state = RankingCacheState(
      bilibiliTracks: List.unmodifiable(bilibiliTracks),
      youtubeTracks: List.unmodifiable(youtubeTracks),
      isInitialLoading: false,
      bilibiliLoaded: true,
      youtubeLoaded: true,
    );
  }

  @override
  Future<void> refreshBilibili() async {}

  @override
  Future<void> refreshYouTube() async {}
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

Track _track(String sourceId, SourceType sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = 'Tester';
}
