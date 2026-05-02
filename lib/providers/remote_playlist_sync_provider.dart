import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library/remote_playlist_sync_service.dart';
import 'refresh_provider.dart';
import 'repository_providers.dart';

final remotePlaylistSyncServiceProvider =
    Provider<RemotePlaylistSyncService>((ref) {
  final playlistRepository = ref.watch(playlistRepositoryProvider);
  return RemotePlaylistSyncService(
    getImportedPlaylists: playlistRepository.getImported,
    refreshPlaylist: (playlist) {
      unawaited(
        ref
            .read(refreshManagerProvider.notifier)
            .refreshPlaylist(playlist)
            .catchError((_) => null),
      );
    },
  );
});
