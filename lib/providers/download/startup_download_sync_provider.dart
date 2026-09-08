import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/providers/download/download_path_provider.dart';
import 'package:fmp/providers/library/library_invalidation_coordinator.dart';
import 'package:fmp/providers/library/playlist_provider.dart'
    show allPlaylistsProvider;

final startupDownloadSyncProvider = FutureProvider<void>((ref) async {
  try {
    // 三個 Provider 都不依賴任何 await 的結果，在第一個 await 之前一次讀完 ——
    // Riverpod 3 對 dispose 之後的 Ref 會拋 UnmountedRefException。
    final pathManager = ref.read(downloadPathManagerProvider);
    final syncService = ref.read(downloadPathSyncServiceProvider);
    final coordinator = ref.read(libraryInvalidationCoordinatorProvider);

    if (!await pathManager.hasConfiguredPath()) {
      AppLogger.info(
        'Skipping startup download sync: download path not configured',
        'StartupDownloadSync',
      );
      return;
    }

    final (added, removed) = await syncService.syncLocalFiles();

    if (added > 0 || removed > 0) {
      if (!ref.mounted) return;
      final playlists = await ref.read(allPlaylistsProvider.future);
      coordinator.downloadStateChanged(
        affectedPlaylistIds: playlists.map((playlist) => playlist.id),
      );
    } else {
      coordinator.downloadStateChanged(fileExistsChanged: false);
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
