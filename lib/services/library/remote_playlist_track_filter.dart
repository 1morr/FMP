import '../../data/models/track.dart';

List<Track> filterLoggedInRemoteTracks(
  Iterable<Track> tracks, {
  required bool Function(SourceType sourceType) isLoggedIn,
}) {
  return tracks
      .where((track) => isLoggedIn(track.sourceType))
      .toList(growable: false);
}
