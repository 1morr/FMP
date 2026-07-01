import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/search/search_service.dart';
import 'package:isar/isar.dart';

void main() {
  group('Phase 2 key and boundary coverage', () {
    test('dynamic row widgets accept keys via super.key', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final playlistDetailSource = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_SearchResultTile\s*\(\s*\{\s*super\.key,',
                dotAll: true)
            .hasMatch(searchPageSource),
        isTrue,
        reason:
            '_SearchResultTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(r'const\s+_LocalTrackTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(searchPageSource),
        isTrue,
        reason:
            '_LocalTrackTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(r'const\s+_TrackListTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(playlistDetailSource),
        isTrue,
        reason:
            '_TrackListTile should expose super.key before keyed call sites are added.',
      );
    });

    test('dynamic search and playlist rows use stable ValueKeys', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final playlistDetailSource = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'_SearchResultTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            'Online search result rows should use a stable key derived from track identity.',
      );

      expect(
        RegExp(
          r'_LocalTrackTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            'Expanded local track rows should use a stable key derived from track identity.',
      );

      final playlistKeyMatches = RegExp(
        r'_TrackListTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
        dotAll: true,
      ).allMatches(playlistDetailSource);

      expect(
        playlistKeyMatches.length,
        greaterThanOrEqualTo(2),
        reason:
            'Playlist detail rows should key both single-track and expanded multi-part rows.',
      );
    });

    test(
        'search page delegates bilibili page loading to notifier and service APIs',
        () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final searchProviderSource = File(
        'lib/providers/search/search_provider.dart',
      ).readAsStringSync();
      final searchServiceSource = File(
        'lib/services/search/search_service.dart',
      ).readAsStringSync();

      expect(
        searchProviderSource.contains(
            'Future<List<VideoPage>> loadVideoPagesForTrack(Track track)'),
        isTrue,
        reason:
            'SearchNotifier should expose a track-owned video-page entry for the search page.',
      );

      expect(
        searchServiceSource.contains(
            'Future<List<VideoPage>> loadVideoPagesForTrack(Track track)'),
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

    test(
        'search service returns empty pages when the source lacks paged-video '
        'capability (capability-based, not source identity)',
        () async {
      // A bilibili paged source is registered, but the track is youtube, so
      // pagedVideoSource(youtube) is null: pages must be empty and the
      // registered paged source must not be queried.
      final pagedSource = _RecordingPagedVideoSource(SourceType.bilibili);
      final sourceManager = _PagedVideoSourceManager(pagedSource);
      final service = SearchService(
        sourceManager: sourceManager,
        trackRepository: TrackRepository(_FakeIsar()),
        isar: _FakeIsar(),
      );
      final track = Track()
        ..sourceType = SourceType.youtube
        ..sourceId = 'youtube-video';

      final pages = await service.loadVideoPagesForTrack(track);

      expect(pages, isEmpty);
      expect(sourceManager.pagedVideoLookupCount, 1);
      expect(pagedSource.getVideoPagesCallCount, 0);
    });

    test('search service does not pass auth to page lookup', () async {
      final pagedSource = _RecordingPagedVideoSource(SourceType.bilibili);
      final sourceManager = _PagedVideoSourceManager(pagedSource);
      final service = SearchService(
        sourceManager: sourceManager,
        trackRepository: TrackRepository(_FakeIsar()),
        isar: _FakeIsar(),
      );
      final track = Track()
        ..sourceType = SourceType.bilibili
        ..sourceId = 'BV-no-auth';

      await service.loadVideoPagesForTrack(track);

      expect(pagedSource.lastAuthHeaders, isNull);
    });

    test('playlist mix bootstrap goes through the audio controller boundary',
        () {
      final playlistCardActionsSource = File(
        'lib/ui/widgets/menus/playlist_card_actions.dart',
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
        audioProviderSource.contains('YouTubeSource? _youtubeSource'),
        isFalse,
        reason:
            'AudioController should not keep a concrete YouTube source fallback.',
      );

      expect(
        audioProviderSource.contains('youtubeSourceProvider'),
        isFalse,
        reason:
            'Audio provider wiring should inject a MixTracksFetcher from a capability.',
      );

      expect(
        playlistCardActionsSource
            .contains('await controller.startMixFromPlaylist(playlist);'),
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

class _PagedVideoSourceManager extends SourceManager {
  _PagedVideoSourceManager(this.source) : super(sources: const []);

  final PagedVideoSource source;
  int pagedVideoLookupCount = 0;

  @override
  PagedVideoSource? pagedVideoSource(SourceType type) {
    pagedVideoLookupCount++;
    // Only serve the registered source's own type, mirroring real
    // SourceManager behaviour where a capability belongs to a specific source.
    return type == source.sourceType ? source : null;
  }
}

class _RecordingPagedVideoSource implements PagedVideoSource {
  _RecordingPagedVideoSource(this.sourceType);

  @override
  final SourceType sourceType;
  int getVideoPagesCallCount = 0;
  Map<String, String>? lastAuthHeaders;

  @override
  Future<List<VideoPage>> getVideoPages(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    lastAuthHeaders = authHeaders;
    getVideoPagesCallCount++;
    return const [
      VideoPage(cid: 1, page: 1, part: 'Unexpected page', duration: 1),
    ];
  }
}

class _FakeIsar extends Fake implements Isar {}
