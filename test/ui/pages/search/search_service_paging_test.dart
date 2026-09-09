import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/search/search_service.dart';

import '../../../support/fakes/fake_isar.dart';

void main() {
  group('search service paging boundaries', () {
    test('search service returns empty pages when the source lacks paged-video '
        'capability (capability-based, not source identity)', () async {
      // A bilibili paged source is registered, but the track is youtube, so
      // pagedVideoSource(youtube) is null: pages must be empty and the
      // registered paged source must not be queried.
      final pagedSource = _RecordingPagedVideoSource(SourceIds.bilibili);
      final sourceManager = _PagedVideoSourceManager(pagedSource);
      final service = SearchService(
        sourceManager: sourceManager,
        trackRepository: TrackRepository(FakeIsar()),
        searchHistoryRepository: SearchHistoryRepository(FakeIsar()),
      );
      final track = Track()
        ..sourceType = SourceIds.youtube
        ..sourceId = 'youtube-video';

      final pages = await service.loadVideoPagesForTrack(track);

      expect(pages, isEmpty);
      expect(sourceManager.pagedVideoLookupCount, 1);
      expect(pagedSource.getVideoPagesCallCount, 0);
    });

    test('search service does not pass auth to page lookup', () async {
      final pagedSource = _RecordingPagedVideoSource(SourceIds.bilibili);
      final sourceManager = _PagedVideoSourceManager(pagedSource);
      final service = SearchService(
        sourceManager: sourceManager,
        trackRepository: TrackRepository(FakeIsar()),
        searchHistoryRepository: SearchHistoryRepository(FakeIsar()),
      );
      final track = Track()
        ..sourceType = SourceIds.bilibili
        ..sourceId = 'BV-no-auth';

      await service.loadVideoPagesForTrack(track);

      expect(pagedSource.lastAuthHeaders, isNull);
    });
  });
}

class _PagedVideoSourceManager extends SourceManager {
  _PagedVideoSourceManager(this.source) : super(sources: const []);

  final PagedVideoSource source;
  int pagedVideoLookupCount = 0;

  @override
  PagedVideoSource? pagedVideoSource(String type) {
    pagedVideoLookupCount++;
    // Only serve the registered source's own type, mirroring real
    // SourceManager behaviour where a capability belongs to a specific source.
    return type == source.sourceType ? source : null;
  }
}

class _RecordingPagedVideoSource implements PagedVideoSource {
  _RecordingPagedVideoSource(this.sourceType);

  @override
  final String sourceType;
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
