import '../../data/models/track.dart';
import 'remote_playlist_id_parser.dart';

class RemotePlaylistActionsService {
  final Future<int> Function(Track track) getBilibiliAid;
  final Future<void> Function({
    required int folderId,
    required List<int> videoAids,
  }) removeBilibiliTracks;
  final Future<void> Function({
    required int videoAid,
    required int folderId,
  }) removeBilibiliTrack;
  final Future<String?> Function(String playlistId, String videoId)
      getYoutubeSetVideoId;
  final Future<void> Function(
    String playlistId,
    String videoId,
    String setVideoId,
  ) removeYoutubeTrack;
  final Future<void> Function(String playlistId, List<String> trackIds)
      removeNeteaseTracks;

  const RemotePlaylistActionsService({
    required this.getBilibiliAid,
    required this.removeBilibiliTracks,
    required this.removeBilibiliTrack,
    required this.getYoutubeSetVideoId,
    required this.removeYoutubeTrack,
    required this.removeNeteaseTracks,
  });

  Future<bool> removeTrackFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required Track track,
  }) async {
    if (track.sourceType != importSourceType) return false;

    switch (importSourceType) {
      case SourceType.bilibili:
        final folderId =
            RemotePlaylistIdParser.parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return false;
        final videoAid = await getBilibiliAid(track);
        await removeBilibiliTrack(videoAid: videoAid, folderId: folderId);
        return true;
      case SourceType.youtube:
        final playlistId =
            RemotePlaylistIdParser.parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return false;
        final setVideoId =
            await getYoutubeSetVideoId(playlistId, track.sourceId);
        if (setVideoId == null) return false;
        await removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
        return true;
      case SourceType.netease:
        final playlistId =
            RemotePlaylistIdParser.parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return false;
        await removeNeteaseTracks(playlistId, [track.sourceId]);
        return true;
    }
  }

  Future<bool> removeTracksFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required List<Track> tracks,
  }) async {
    final matchingTracks =
        tracks.where((track) => track.sourceType == importSourceType).toList();
    if (matchingTracks.isEmpty) return false;

    switch (importSourceType) {
      case SourceType.bilibili:
        final folderId =
            RemotePlaylistIdParser.parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return false;
        final videoAids = <int>[];
        for (final track in matchingTracks) {
          videoAids.add(await getBilibiliAid(track));
        }
        await removeBilibiliTracks(folderId: folderId, videoAids: videoAids);
        return true;
      case SourceType.youtube:
        final playlistId =
            RemotePlaylistIdParser.parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return false;
        var removedAny = false;
        for (final track in matchingTracks) {
          final setVideoId = await getYoutubeSetVideoId(
            playlistId,
            track.sourceId,
          );
          if (setVideoId == null) continue;
          await removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
          removedAny = true;
        }
        return removedAny;
      case SourceType.netease:
        final playlistId =
            RemotePlaylistIdParser.parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return false;
        await removeNeteaseTracks(
          playlistId,
          matchingTracks.map((track) => track.sourceId).toList(),
        );
        return true;
    }
  }
}
