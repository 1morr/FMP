import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/download/download_event_handler.dart';
import 'package:fmp/services/download/download_service.dart';

void main() {
  group('DownloadEventHandler', () {
    test(
      'completion marks file existing, removes progress, and batches invalidations',
      () async {
        final markedPaths = <String>[];
        final removedProgressTaskIds = <int>[];
        var categoriesInvalidationCount = 0;
        final invalidatedCategoryPaths = <String>[];
        final refreshedPlaylistIds = <int>[];
        final shownFailures = <DownloadFailureEvent>[];
        final handler = DownloadEventHandler(
          markFileExisting: markedPaths.add,
          removeProgress: removedProgressTaskIds.add,
          invalidateCategories: () => categoriesInvalidationCount++,
          invalidateCategoryTracks: invalidatedCategoryPaths.add,
          refreshPlaylist: refreshedPlaylistIds.add,
          showFailure: shownFailures.add,
          debounceDuration: const Duration(milliseconds: 1),
        );
        addTearDown(handler.dispose);

        handler.handleCompletion(
          DownloadCompletionEvent(
            taskId: 7,
            trackId: 9,
            playlistId: 11,
            savePath: '/downloads/Playlist A/Video 1/audio.m4a',
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(markedPaths, ['/downloads/Playlist A/Video 1/audio.m4a']);
        expect(removedProgressTaskIds, [7]);
        expect(categoriesInvalidationCount, 1);
        expect(invalidatedCategoryPaths, ['/downloads/Playlist A']);
        expect(refreshedPlaylistIds, [11]);
        expect(shownFailures, isEmpty);
      },
    );

    test(
      'failure delegates to failure presenter without completion side effects',
      () async {
        final markedPaths = <String>[];
        final removedProgressTaskIds = <int>[];
        var categoriesInvalidationCount = 0;
        final invalidatedCategoryPaths = <String>[];
        final refreshedPlaylistIds = <int>[];
        final shownFailures = <DownloadFailureEvent>[];
        final handler = DownloadEventHandler(
          markFileExisting: markedPaths.add,
          removeProgress: removedProgressTaskIds.add,
          invalidateCategories: () => categoriesInvalidationCount++,
          invalidateCategoryTracks: invalidatedCategoryPaths.add,
          refreshPlaylist: refreshedPlaylistIds.add,
          showFailure: shownFailures.add,
          debounceDuration: const Duration(milliseconds: 1),
        );
        addTearDown(handler.dispose);
        final event = DownloadFailureEvent(
          taskId: 3,
          trackId: 4,
          trackTitle: 'Broken Song',
          errorMessage: 'network failed',
        );

        handler.handleFailure(event);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(shownFailures, [same(event)]);
        expect(markedPaths, isEmpty);
        expect(removedProgressTaskIds, isEmpty);
        expect(categoriesInvalidationCount, 0);
        expect(invalidatedCategoryPaths, isEmpty);
        expect(refreshedPlaylistIds, isEmpty);
      },
    );
  });
}
