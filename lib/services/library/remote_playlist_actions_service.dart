import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';

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

  Future<void> removeTrackFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required Track track,
  }) async {
    if (track.sourceType != importSourceType) return;

    switch (importSourceType) {
      case SourceType.bilibili:
        final folderId = _parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return;
        final videoAid = await getBilibiliAid(track);
        await removeBilibiliTrack(videoAid: videoAid, folderId: folderId);
      case SourceType.youtube:
        final playlistId = _parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return;
        final setVideoId =
            await getYoutubeSetVideoId(playlistId, track.sourceId);
        if (setVideoId == null) return;
        await removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
      case SourceType.netease:
        final playlistId = _parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return;
        await removeNeteaseTracks(playlistId, [track.sourceId]);
    }
  }

  Future<void> removeTracksFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required List<Track> tracks,
  }) async {
    final matchingTracks =
        tracks.where((track) => track.sourceType == importSourceType).toList();
    if (matchingTracks.isEmpty) return;

    switch (importSourceType) {
      case SourceType.bilibili:
        final folderId = _parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return;
        final videoAids = <int>[];
        for (final track in matchingTracks) {
          videoAids.add(await getBilibiliAid(track));
        }
        await removeBilibiliTracks(folderId: folderId, videoAids: videoAids);
      case SourceType.youtube:
        final playlistId = _parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return;
        for (final track in matchingTracks) {
          final setVideoId = await getYoutubeSetVideoId(
            playlistId,
            track.sourceId,
          );
          if (setVideoId == null) continue;
          await removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
        }
      case SourceType.netease:
        final playlistId = _parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return;
        await removeNeteaseTracks(
          playlistId,
          matchingTracks.map((track) => track.sourceId).toList(),
        );
    }
  }

  int? _parseBilibiliFolderId(String url) {
    final fid = BilibiliSource.parseFavoritesId(url);
    return fid == null ? null : int.tryParse(fid);
  }

  String? _parseYoutubePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['list'];
  }

  String? _parseNeteasePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    final id = uri?.queryParameters['id'];
    if (id != null) return id;
    final match = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
    return match?.group(1);
  }
}
