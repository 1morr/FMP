import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/library_invalidation_coordinator.dart';
import 'package:fmp/providers/playlist_provider.dart';
import 'package:fmp/services/library/playlist_mutation_service.dart';

void main() {
  group('LibraryInvalidationCoordinator', () {
    test('playlistChanged invalidates detail, cover, and all snapshots', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistChanged(7);

      expect(recorder.detailIds, [7]);
      expect(recorder.coverIds, [7]);
      expect(recorder.allPlaylistInvalidations, 1);
      expect(recorder.downloadCategoryInvalidations, 0);
    });

    test('playlistsChanged deduplicates playlist ids in first-seen order', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistsChanged([3, 3, 5, 3, 8], includeAll: false);

      expect(recorder.detailIds, [3, 5, 8]);
      expect(recorder.coverIds, [3, 5, 8]);
      expect(recorder.allPlaylistInvalidations, 0);
    });

    test('playlistMutationCompleted uses affected ids and cover flag', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistMutationCompleted(
        const PlaylistMutationResult(
          playlistId: 4,
          affectedPlaylistIds: [9, 4],
          addedTrackIds: [11],
          coverChanged: true,
          playlistChanged: true,
        ),
      );

      expect(recorder.detailIds, [4, 9]);
      expect(recorder.coverIds, [4, 9]);
      expect(recorder.allPlaylistInvalidations, 1);
    });

    test('downloadStateChanged derives category paths and refreshes playlists',
        () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.downloadStateChanged(
        savePaths: ['/downloads/List A/Video 1/audio.m4a'],
        affectedPlaylistIds: [6, 6, 7],
      );

      expect(recorder.fileCacheInvalidations, 1);
      expect(recorder.downloadCategoryInvalidations, 1);
      expect(recorder.downloadCategoryTrackPaths, ['/downloads/List A']);
      expect(recorder.startedRefreshIds, [6, 7]);
      expect(recorder.coverIds, [6, 7]);
    });

    test('refreshLoadedPlaylistDetails logs failed silent refreshes', () async {
      final recorder = _InvalidationRecorder(failingRefreshIds: {5});
      final coordinator = recorder.createCoordinator();

      await coordinator.refreshLoadedPlaylistDetails([5], reason: 'test');

      expect(recorder.refreshIds, [5]);
      expect(recorder.loggedErrors.single.$1, contains('test'));
      expect(recorder.loggedErrors.single.$2, isA<StateError>());
    });

    test('provider skips unloaded playlist details during download refresh',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator =
          container.read(libraryInvalidationCoordinatorProvider);

      coordinator.downloadStateChanged(affectedPlaylistIds: [12]);

      expect(container.exists(playlistDetailProvider(12)), isFalse);
    });

    test('Task 5 UI mutation sites use the library invalidation coordinator', () {
      final sources = _task5SourceFiles();

      for (final entry in sources.entries) {
        final source = entry.value;
        expect(
          source,
          contains('libraryInvalidationCoordinatorProvider'),
          reason: '${entry.key} should route UI mutation refreshes through the coordinator',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(allPlaylistsProvider)')),
          reason: '${entry.key} should not directly invalidate allPlaylistsProvider',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(playlistDetailProvider')),
          reason: '${entry.key} should not directly invalidate playlistDetailProvider',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(playlistCoverProvider')),
          reason: '${entry.key} should not directly invalidate playlistCoverProvider',
        );
        expect(
          source,
          isNot(contains('invalidatePlaylistProviders')),
          reason: '${entry.key} should not use legacy playlist invalidation helpers',
        );
      }
    });
  });
}

Map<String, String> _task5SourceFiles() {
  const paths = [
    'lib/ui/pages/library/widgets/import_playlist_dialog.dart',
    'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
    'lib/ui/pages/library/import_preview_page.dart',
    'lib/ui/pages/library/playlist_detail_page.dart',
    'lib/ui/pages/settings/widgets/account_playlists_sheet.dart',
    'lib/ui/pages/settings/settings_page.dart',
  ];

  return {
    for (final path in paths)
      path: File('${Directory.current.path}/$path').readAsStringSync(),
  };
}

class _InvalidationRecorder {
  _InvalidationRecorder({this.failingRefreshIds = const {}});

  final Set<int> failingRefreshIds;
  final detailIds = <int>[];
  final coverIds = <int>[];
  final downloadCategoryTrackPaths = <String>[];
  final refreshIds = <int>[];
  final startedRefreshIds = <int>[];
  final loggedErrors = <(String, Object)>[];
  int allPlaylistInvalidations = 0;
  int downloadCategoryInvalidations = 0;
  int fileCacheInvalidations = 0;

  LibraryInvalidationCoordinator createCoordinator() {
    return LibraryInvalidationCoordinator(
      invalidateAllPlaylists: () => allPlaylistInvalidations++,
      invalidatePlaylistDetail: detailIds.add,
      invalidatePlaylistCover: coverIds.add,
      invalidateDownloadedCategories: () => downloadCategoryInvalidations++,
      invalidateDownloadedCategoryTracks: downloadCategoryTrackPaths.add,
      invalidateFileExistsCache: () => fileCacheInvalidations++,
      refreshLoadedPlaylistDetail: (playlistId) async {
        refreshIds.add(playlistId);
        if (failingRefreshIds.contains(playlistId)) {
          throw StateError('refresh failed for $playlistId');
        }
      },
      startRefreshLoadedPlaylistDetail: (playlistId) {
        startedRefreshIds.add(playlistId);
      },
      logBackgroundError: (message, error, stackTrace) {
        loggedErrors.add((message, error));
      },
    );
  }
}
