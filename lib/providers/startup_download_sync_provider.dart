import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger.dart';
import 'download/download_providers.dart' show downloadedCategoriesProvider;
import 'download/file_exists_cache.dart';
import 'download_path_provider.dart';
import 'library_invalidation_coordinator.dart';
import 'playlist_provider.dart' show allPlaylistsProvider;

final startupDownloadSyncProvider = FutureProvider<void>((ref) async {
  try {
    final pathManager = ref.read(downloadPathManagerProvider);
    if (!await pathManager.hasConfiguredPath()) {
      AppLogger.info(
        'Skipping startup download sync: download path not configured',
        'StartupDownloadSync',
      );
      return;
    }

    final syncService = ref.read(downloadPathSyncServiceProvider);
    final (added, removed) = await syncService.syncLocalFiles();

    ref.invalidate(downloadedCategoriesProvider);

    if (added > 0 || removed > 0) {
      ref.invalidate(fileExistsCacheProvider);
      final coordinator = ref.read(libraryInvalidationCoordinatorProvider);
      final playlists = await ref.read(allPlaylistsProvider.future);
      coordinator.playlistsChanged(
        playlists.map((playlist) => playlist.id),
        tracksChanged: false,
        coverChanged: true,
        includeAll: false,
      );
    }

    AppLogger.info(
      'Startup download sync complete: added $added, removed $removed',
      'StartupDownloadSync',
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Startup download sync failed',
      error,
      stackTrace,
      'StartupDownloadSync',
    );
  }
});
