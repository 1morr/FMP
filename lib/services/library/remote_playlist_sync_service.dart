import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import 'remote_playlist_id_parser.dart';

class RemotePlaylistSyncService {
  final Future<List<Playlist>> Function() getImportedPlaylists;
  final void Function(Playlist playlist) refreshPlaylist;

  const RemotePlaylistSyncService({
    required this.getImportedPlaylists,
    required this.refreshPlaylist,
  });

  Future<List<Playlist>> refreshMatchingImportedPlaylists({
    required SourceType sourceType,
    required Iterable<String> remotePlaylistIds,
    Iterable<Playlist>? playlists,
  }) async {
    final matches = await findMatchingImportedPlaylists(
      sourceType: sourceType,
      remotePlaylistIds: remotePlaylistIds,
      playlists: playlists,
    );

    for (final playlist in matches) {
      refreshPlaylist(playlist);
    }
    return matches;
  }

  Future<List<Playlist>> findMatchingImportedPlaylists({
    required SourceType sourceType,
    required Iterable<String> remotePlaylistIds,
    Iterable<Playlist>? playlists,
  }) async {
    final remoteIds = remotePlaylistIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (remoteIds.isEmpty) return const [];

    final candidates = playlists ?? await getImportedPlaylists();
    return candidates.where((playlist) {
      if (playlist.importSourceType != sourceType) return false;
      if (playlist.isMix) return false;
      final sourceUrl = playlist.sourceUrl;
      if (sourceUrl == null || sourceUrl.isEmpty) return false;
      final remoteId = RemotePlaylistIdParser.parse(sourceType, sourceUrl);
      return remoteId != null && remoteIds.contains(remoteId);
    }).toList();
  }
}
