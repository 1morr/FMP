import '../../data/models/playlist.dart';

class RemotePlaylistRemovalSyncService {
  final Future<void> Function(int playlistId, List<int> trackIds)
      removeTracksFromLocalPlaylist;
  final void Function(Playlist playlist) refreshPlaylist;

  const RemotePlaylistRemovalSyncService({
    required this.removeTracksFromLocalPlaylist,
    required this.refreshPlaylist,
  });

  Future<void> syncAfterRemoval({
    required Playlist playlist,
    required List<int> removedTrackIds,
  }) async {
    if (removedTrackIds.isEmpty) return;

    await removeTracksFromLocalPlaylist(playlist.id, removedTrackIds);
    refreshPlaylist(playlist);
  }
}
