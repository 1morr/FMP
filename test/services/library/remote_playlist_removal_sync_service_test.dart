import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_removal_sync_service.dart';

void main() {
  test('removes local tracks and triggers matching remote playlist refresh',
      () async {
    final playlist = Playlist()
      ..id = 1
      ..name = 'Imported YouTube playlist'
      ..sourceUrl = 'https://www.youtube.com/playlist?list=PL_REMOTE'
      ..importSourceType = SourceType.youtube
      ..trackIds = [10, 11, 12];
    final removedTrackIds = <int>[];
    final refreshedIds = <int>[];

    final service = RemotePlaylistRemovalSyncService(
      removeTracksFromLocalPlaylist: (playlistId, trackIds) async {
        expect(playlistId, 1);
        removedTrackIds.addAll(trackIds);
      },
      refreshPlaylist: (playlist) => refreshedIds.add(playlist.id),
    );

    await service.syncAfterRemoval(
      playlist: playlist,
      removedTrackIds: [10, 11],
    );

    expect(removedTrackIds, [10, 11]);
    expect(refreshedIds, [1]);
  });
}
