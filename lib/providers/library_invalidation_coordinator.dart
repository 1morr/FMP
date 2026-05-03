import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logger.dart';
import '../services/library/playlist_mutation_service.dart';
import 'download/download_providers.dart';
import 'download/file_exists_cache.dart';
import 'playlist_provider.dart';

typedef LogBackgroundError = void Function(
  String message,
  Object error,
  StackTrace? stackTrace,
);

class LibraryInvalidationCoordinator {
  const LibraryInvalidationCoordinator({
    required this.invalidateAllPlaylists,
    required this.invalidatePlaylistDetail,
    required this.invalidatePlaylistCover,
    required this.invalidateDownloadedCategories,
    required this.invalidateDownloadedCategoryTracks,
    required this.invalidateFileExistsCache,
    required this.refreshLoadedPlaylistDetail,
    required this.startRefreshLoadedPlaylistDetail,
    required this.logBackgroundError,
  });

  final void Function() invalidateAllPlaylists;
  final void Function(int playlistId) invalidatePlaylistDetail;
  final void Function(int playlistId) invalidatePlaylistCover;
  final void Function() invalidateDownloadedCategories;
  final void Function(String categoryPath) invalidateDownloadedCategoryTracks;
  final void Function() invalidateFileExistsCache;
  final Future<void> Function(int playlistId) refreshLoadedPlaylistDetail;
  final void Function(int playlistId) startRefreshLoadedPlaylistDetail;
  final LogBackgroundError logBackgroundError;

  void playlistChanged(
    int playlistId, {
    bool tracksChanged = true,
    bool coverChanged = true,
    bool includeAll = true,
  }) {
    playlistsChanged(
      [playlistId],
      tracksChanged: tracksChanged,
      coverChanged: coverChanged,
      includeAll: includeAll,
    );
  }

  void playlistsChanged(
    Iterable<int> playlistIds, {
    bool tracksChanged = true,
    bool coverChanged = true,
    bool includeAll = true,
  }) {
    final ids = _dedupeInOrder(playlistIds);
    if (includeAll) {
      invalidateAllPlaylists();
    }
    for (final playlistId in ids) {
      if (tracksChanged) {
        invalidatePlaylistDetail(playlistId);
      }
      if (coverChanged) {
        invalidatePlaylistCover(playlistId);
      }
    }
  }

  void playlistMutationCompleted(PlaylistMutationResult result) {
    final ids = result.affectedPlaylistIds.isEmpty
        ? [result.playlistId]
        : [result.playlistId, ...result.affectedPlaylistIds];
    playlistsChanged(
      ids,
      tracksChanged: result.playlistChanged,
      coverChanged: result.coverChanged,
      includeAll: result.playlistChanged || result.coverChanged,
    );
  }

  void downloadStateChanged({
    Iterable<String> savePaths = const [],
    Iterable<String> categoryPaths = const [],
    Iterable<int> affectedPlaylistIds = const [],
    bool includeDownloadedCategories = true,
    bool fileExistsChanged = true,
  }) {
    if (fileExistsChanged) {
      invalidateFileExistsCache();
    }
    if (includeDownloadedCategories) {
      invalidateDownloadedCategories();
    }

    final derivedCategoryPaths =
        savePaths.map((path) => p.dirname(p.dirname(path)));
    for (final categoryPath in _dedupeInOrder([
      ...categoryPaths,
      ...derivedCategoryPaths,
    ])) {
      invalidateDownloadedCategoryTracks(categoryPath);
    }

    final playlistIds = _dedupeInOrder(affectedPlaylistIds);
    for (final playlistId in playlistIds) {
      startRefreshLoadedPlaylistDetail(playlistId);
    }
    playlistsChanged(
      playlistIds,
      tracksChanged: false,
      coverChanged: true,
      includeAll: false,
    );
  }

  Future<void> refreshLoadedPlaylistDetails(
    Iterable<int> playlistIds, {
    required String reason,
  }) async {
    for (final playlistId in _dedupeInOrder(playlistIds)) {
      try {
        await refreshLoadedPlaylistDetail(playlistId);
      } catch (error, stackTrace) {
        logBackgroundError(
          'Failed to refresh loaded playlist detail after $reason: $playlistId',
          error,
          stackTrace,
        );
      }
    }
  }

  void startRefreshLoadedPlaylistDetails(
    Iterable<int> playlistIds, {
    required String reason,
  }) {
    unawaited(refreshLoadedPlaylistDetails(playlistIds, reason: reason));
  }
}

final libraryInvalidationCoordinatorProvider =
    Provider<LibraryInvalidationCoordinator>((ref) {
  return LibraryInvalidationCoordinator(
    invalidateAllPlaylists: () => ref.invalidate(allPlaylistsProvider),
    invalidatePlaylistDetail: (playlistId) {
      ref.invalidate(playlistDetailProvider(playlistId));
    },
    invalidatePlaylistCover: (playlistId) {
      ref.invalidate(playlistCoverProvider(playlistId));
    },
    invalidateDownloadedCategories: () {
      ref.invalidate(downloadedCategoriesProvider);
    },
    invalidateDownloadedCategoryTracks: (categoryPath) {
      ref.invalidate(downloadedCategoryTracksProvider(categoryPath));
    },
    invalidateFileExistsCache: () => ref.invalidate(fileExistsCacheProvider),
    refreshLoadedPlaylistDetail: (playlistId) {
      final provider = playlistDetailProvider(playlistId);
      if (!ref.exists(provider)) {
        return Future.value();
      }
      return ref.read(provider.notifier).refreshTracks();
    },
    startRefreshLoadedPlaylistDetail: (playlistId) {
      final provider = playlistDetailProvider(playlistId);
      if (!ref.exists(provider)) {
        return;
      }
      unawaited(
        ref.read(provider.notifier).refreshTracks().catchError(
          (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'Failed to refresh loaded playlist detail in background: $playlistId',
              error,
              stackTrace,
              'LibraryInvalidation',
            );
          },
        ),
      );
    },
    logBackgroundError: (message, error, stackTrace) {
      AppLogger.error(message, error, stackTrace, 'LibraryInvalidation');
    },
  );
});

List<T> _dedupeInOrder<T>(Iterable<T> values) {
  final seen = <T>{};
  final result = <T>[];
  for (final value in values) {
    if (seen.add(value)) {
      result.add(value);
    }
  }
  return result;
}
