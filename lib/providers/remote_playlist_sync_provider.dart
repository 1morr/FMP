import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library/remote_playlist_edit_controller.dart';
import '../services/library/remote_playlist_sync_service.dart';
import 'account_provider.dart';
import 'playlist_provider.dart';
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

final remotePlaylistEditControllerProvider =
    Provider<RemotePlaylistEditController>((ref) {
  final bilibiliService = ref.watch(bilibiliFavoritesServiceProvider);
  final youtubeService = ref.watch(youtubePlaylistServiceProvider);
  final neteaseService = ref.watch(neteasePlaylistServiceProvider);

  return RemotePlaylistEditController(
    bilibiliAdapter: BilibiliRemotePlaylistEditAdapter(
      getVideoAid: bilibiliService.getVideoAid,
      updateVideoFavorites: bilibiliService.updateVideoFavorites,
    ),
    youtubeAdapter: YouTubeRemotePlaylistEditAdapter(
      addToPlaylist: youtubeService.addToPlaylist,
      getSetVideoId: youtubeService.getSetVideoId,
      removeFromPlaylist: youtubeService.removeFromPlaylist,
    ),
    neteaseAdapter: NeteaseRemotePlaylistEditAdapter(
      addTracksToPlaylist: neteaseService.addTracksToPlaylist,
      removeTracksFromPlaylist: neteaseService.removeTracksFromPlaylist,
    ),
    refreshMatchingImportedPlaylists: ({
      required sourceType,
      required remotePlaylistIds,
    }) {
      return ref
          .read(remotePlaylistSyncServiceProvider)
          .refreshMatchingImportedPlaylists(
            sourceType: sourceType,
            remotePlaylistIds: remotePlaylistIds,
          );
    },
    removeTracksFromLocalPlaylist: (playlistId, trackIds) {
      return ref
          .read(playlistDetailProvider(playlistId).notifier)
          .removeTracks(trackIds);
    },
    isLoggedIn: (sourceType) => ref.read(isLoggedInProvider(sourceType)),
  );
});
