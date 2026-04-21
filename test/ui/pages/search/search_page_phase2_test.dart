import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2 Task 4 boundary coverage', () {
    test('search page delegates bilibili page loading to notifier and service APIs', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final searchProviderSource = File(
        'lib/providers/search_provider.dart',
      ).readAsStringSync();
      final searchServiceSource = File(
        'lib/services/search/search_service.dart',
      ).readAsStringSync();

      expect(
        searchProviderSource.contains('Future<List<VideoPage>> loadVideoPagesForTrack(Track track)'),
        isTrue,
        reason:
            'SearchNotifier should expose a track-owned video-page entry for the search page.',
      );

      expect(
        searchServiceSource.contains('Future<List<VideoPage>> loadVideoPagesForTrack(Track track)'),
        isTrue,
        reason:
            'SearchService should own bilibili video-page loading behind a helper API.',
      );

      expect(
        searchPageSource.contains(
          'ref.read(searchProvider.notifier).loadVideoPagesForTrack(track)',
        ),
        isTrue,
        reason:
            'SearchPage should delegate video-page loading to the notifier boundary.',
      );

      expect(
        searchPageSource.contains('sourceManagerProvider'),
        isFalse,
        reason:
            'SearchPage should no longer assemble source-manager lookups for bilibili page loading.',
      );

      expect(
        searchPageSource.contains('buildAuthHeaders('),
        isFalse,
        reason:
            'SearchPage should no longer build auth headers for bilibili page loading.',
      );

      expect(
        searchPageSource.contains('getVideoPages(track.sourceId'),
        isFalse,
        reason:
            'SearchPage should no longer call BilibiliSource.getVideoPages directly.',
      );
    });

    test('playlist mix bootstrap goes through the audio controller boundary', () {
      final playlistCardActionsSource = File(
        'lib/ui/widgets/playlist_card_actions.dart',
      ).readAsStringSync();
      final audioProviderSource = File(
        'lib/services/audio/audio_provider.dart',
      ).readAsStringSync();

      expect(
        audioProviderSource.contains(
          'Future<void> startMixFromPlaylist(Playlist playlist)',
        ),
        isTrue,
        reason:
            'AudioController should expose a narrow app entry for starting mix playback from a playlist.',
      );

      expect(
        playlistCardActionsSource.contains('await controller.startMixFromPlaylist(playlist);'),
        isTrue,
        reason:
            'PlaylistCardActions should call only the audio controller mix entry.',
      );

      expect(
        playlistCardActionsSource.contains('youtubeSourceProvider'),
        isFalse,
        reason:
            'PlaylistCardActions should not read youtube sources directly for mix bootstrap.',
      );

      expect(
        playlistCardActionsSource.contains('fetchMixTracks('),
        isFalse,
        reason:
            'PlaylistCardActions should not fetch mix tracks directly once the controller owns the flow.',
      );
    });
  });
}
