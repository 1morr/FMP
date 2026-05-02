import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/library/remote_playlist_selection_changes.dart';

void main() {
  group('computeRemotePlaylistSelectionChanges', () {
    test('selected partial playlists are added so missing tracks can be filled',
        () {
      final changes = computeRemotePlaylistSelectionChanges(
        selectedIds: {'full', 'partial'},
        originalIds: {'full'},
        deselectedPartialIds: const <String>{},
      );

      expect(changes.toAdd, ['partial']);
      expect(changes.toRemove, isEmpty);
    });

    test('deselected partial playlists are removed', () {
      final changes = computeRemotePlaylistSelectionChanges(
        selectedIds: {'full'},
        originalIds: {'full'},
        deselectedPartialIds: {'partial'},
      );

      expect(changes.toAdd, isEmpty);
      expect(changes.toRemove, ['partial']);
    });
  });

  group('missingRemoteTrackIds', () {
    test('returns only tracks absent from a partial playlist', () {
      final missing = missingRemoteTrackIds(
        allTrackIds: ['a', 'b', 'c'],
        existingTrackIds: {'a', 'c'},
      );

      expect(missing, ['b']);
    });
  });
}
