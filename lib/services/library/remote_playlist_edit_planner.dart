import '../../data/models/track.dart';
import 'remote_playlist_selection_changes.dart';

class RemotePlaylistEditPlan {
  final SourceType sourceType;
  final List<Track> editableTracks;
  final List<int> skippedTrackIds;
  final List<String> playlistIdsToAdd;
  final List<String> playlistIdsToRemove;
  final Map<String, Set<String>> existingTrackSourceIdsByPlaylist;

  RemotePlaylistEditPlan({
    required this.sourceType,
    required List<Track> editableTracks,
    required List<int> skippedTrackIds,
    required List<String> playlistIdsToAdd,
    required List<String> playlistIdsToRemove,
    required Map<String, Set<String>> existingTrackSourceIdsByPlaylist,
  })  : editableTracks = List.unmodifiable(editableTracks),
        skippedTrackIds = List.unmodifiable(skippedTrackIds),
        playlistIdsToAdd = List.unmodifiable(playlistIdsToAdd),
        playlistIdsToRemove = List.unmodifiable(playlistIdsToRemove),
        existingTrackSourceIdsByPlaylist = Map.unmodifiable(
          existingTrackSourceIdsByPlaylist.map(
            (playlistId, sourceIds) => MapEntry(
              playlistId,
              Set.unmodifiable(sourceIds),
            ),
          ),
        );

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
    final sourceLoggedIn = isLoggedIn(sourceType);
    for (final track in tracks) {
      if (track.sourceType == sourceType && sourceLoggedIn) {
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
