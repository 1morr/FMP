import '../../data/models/track.dart';
import 'remote_playlist_selection_changes.dart';

class RemotePlaylistEditPlan {
  final SourceType sourceType;
  final List<Track> editableTracks;
  final List<int> skippedTrackIds;
  final List<String> playlistIdsToAdd;
  final List<String> playlistIdsToRemove;
  final Map<String, Set<String>> existingTrackSourceIdsByPlaylist;

  const RemotePlaylistEditPlan({
    required this.sourceType,
    required this.editableTracks,
    required this.skippedTrackIds,
    required this.playlistIdsToAdd,
    required this.playlistIdsToRemove,
    required this.existingTrackSourceIdsByPlaylist,
  });

  List<String> sourceIdsFor(Iterable<Track> tracks) {
    return tracks.map((track) => track.sourceId).toList(growable: false);
  }

  List<String> missingSourceIdsFor(String playlistId) {
    return missingRemoteTrackIds<String>(
      allTrackIds: sourceIdsFor(editableTracks),
      existingTrackIds:
          existingTrackSourceIdsByPlaylist[playlistId] ?? const <String>{},
    );
  }
}

class RemotePlaylistEditPlanner {
  const RemotePlaylistEditPlanner._();

  static RemotePlaylistEditPlan planSelectionEdit({
    required SourceType sourceType,
    required List<Track> tracks,
    required Set<String> selectedPlaylistIds,
    required Set<String> originalPlaylistIds,
    required Set<String> deselectedPartialPlaylistIds,
    required Map<String, Set<String>> existingTrackSourceIdsByPlaylist,
    required bool Function(SourceType sourceType) isLoggedIn,
  }) {
    final editable = <Track>[];
    final skipped = <int>[];
    for (final track in tracks) {
      if (track.sourceType == sourceType && isLoggedIn(track.sourceType)) {
        editable.add(track);
      } else {
        skipped.add(track.id);
      }
    }

    final changes = computeRemotePlaylistSelectionChanges<String>(
      selectedIds: selectedPlaylistIds,
      originalIds: originalPlaylistIds,
      deselectedPartialIds: deselectedPartialPlaylistIds,
    );

    return RemotePlaylistEditPlan(
      sourceType: sourceType,
      editableTracks: editable,
      skippedTrackIds: skipped,
      playlistIdsToAdd: changes.toAdd,
      playlistIdsToRemove: changes.toRemove,
      existingTrackSourceIdsByPlaylist: existingTrackSourceIdsByPlaylist,
    );
  }
}
