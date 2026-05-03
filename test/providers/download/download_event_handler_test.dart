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
        final changedDownloads =
            <({List<String> savePaths, List<int> playlistIds})>[];
        final shownFailures = <DownloadFailureEvent>[];
        final handler = DownloadEventHandler(
          markFileExisting: markedPaths.add,
          removeProgress: removedProgressTaskIds.add,
          downloadStateChanged: ({
            required savePaths,
            required affectedPlaylistIds,
          }) {
            changedDownloads.add((
              savePaths: savePaths.toList(),
              playlistIds: affectedPlaylistIds.toList(),
            ));
          },
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
        expect(changedDownloads, hasLength(1));
        expect(changedDownloads.single.savePaths, [
          '/downloads/Playlist A/Video 1/audio.m4a',
        ]);
        expect(changedDownloads.single.playlistIds, [11]);
        expect(shownFailures, isEmpty);
      },
    );

    test(
      'failure delegates to failure presenter without completion side effects',
      () async {
        final markedPaths = <String>[];
        final removedProgressTaskIds = <int>[];
        final changedDownloads =
            <({List<String> savePaths, List<int> playlistIds})>[];
        final shownFailures = <DownloadFailureEvent>[];
        final handler = DownloadEventHandler(
          markFileExisting: markedPaths.add,
          removeProgress: removedProgressTaskIds.add,
          downloadStateChanged: ({
            required savePaths,
            required affectedPlaylistIds,
          }) {
            changedDownloads.add((
              savePaths: savePaths.toList(),
              playlistIds: affectedPlaylistIds.toList(),
            ));
          },
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
        expect(changedDownloads, isEmpty);
      },
    );
  });
}
