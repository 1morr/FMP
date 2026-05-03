import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_edit_planner.dart';

void main() {
  group('RemotePlaylistEditPlanner', () {
    test('plans add/remove transitions and missing tracks per playlist', () {
      final tracks = [
        _track(SourceType.youtube, 1, 'a'),
        _track(SourceType.youtube, 2, 'b'),
      ];
      final plan = RemotePlaylistEditPlanner.planSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: tracks,
        selectedPlaylistIds: {'full', 'partial'},
        originalPlaylistIds: {'full', 'removed'},
        deselectedPartialPlaylistIds: {'partial-removed'},
        existingTrackSourceIdsByPlaylist: {
          'partial': {'a'}
        },
        isLoggedIn: (_) => true,
      );

      expect(plan.playlistIdsToAdd, ['partial']);
      expect(plan.playlistIdsToRemove, ['removed', 'partial-removed']);
      expect(plan.missingSourceIdsFor('partial'), ['b']);
      expect(plan.editableTracks.map((track) => track.id), [1, 2]);
      expect(plan.skippedTrackIds, isEmpty);
    });

    test('represents mixed-source and logged-out tracks as skipped', () {
      final plan = RemotePlaylistEditPlanner.planSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: [
          _track(SourceType.youtube, 1, 'yt'),
          _track(SourceType.bilibili, 2, 'BV'),
          _track(SourceType.netease, 3, 'ne'),
        ],
        selectedPlaylistIds: {'PL'},
        originalPlaylistIds: const {},
        deselectedPartialPlaylistIds: const {},
        existingTrackSourceIdsByPlaylist: const {},
        isLoggedIn: (sourceType) => sourceType == SourceType.youtube,
      );

      expect(plan.editableTracks.map((track) => track.id), [1]);
      expect(plan.skippedTrackIds, [2, 3]);
    });
  });
}

Track _track(SourceType sourceType, int id, String sourceId) => Track()
  ..id = id
  ..sourceType = sourceType
  ..sourceId = sourceId
  ..title = sourceId;
