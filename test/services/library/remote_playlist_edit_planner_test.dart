import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_edit_planner.dart';
import 'package:fmp/services/library/remote_playlist_edit_result.dart';

void main() {
  group('RemotePlaylistEditResult', () {
    test('summary counts dedupe duplicate track and playlist IDs', () {
      final result = RemotePlaylistEditResult(
        sourceType: SourceType.youtube,
        confirmedAddedTrackIds: [1, 1, 2],
        confirmedRemovedTrackIds: [3, 3, 4],
        skippedTrackIds: [5, 5, 6],
        failures: [
          RemotePlaylistEditFailure(
            trackId: 7,
            remotePlaylistId: 'A',
            error: Exception('first'),
          ),
          RemotePlaylistEditFailure(
            trackId: 7,
            remotePlaylistId: 'B',
            error: Exception('second'),
          ),
          RemotePlaylistEditFailure(
            trackId: 8,
            remotePlaylistId: 'B',
            error: Exception('third'),
          ),
        ],
        changedRemotePlaylistIds: ['PL1', 'PL1', 'PL2'],
      );

      expect(result.summary.changedPlaylistCount, 2);
      expect(result.summary.addedTrackCount, 2);
      expect(result.summary.removedTrackCount, 2);
      expect(result.summary.skippedTrackCount, 2);
      expect(result.summary.failedTrackCount, 2);
    });

    test('failedTrackIds dedupes duplicate failures', () {
      final result = RemotePlaylistEditResult(
        sourceType: SourceType.youtube,
        failures: [
          RemotePlaylistEditFailure(
            trackId: 1,
            remotePlaylistId: 'A',
            error: Exception('first'),
          ),
          RemotePlaylistEditFailure(
            trackId: 1,
            remotePlaylistId: 'B',
            error: Exception('second'),
          ),
          RemotePlaylistEditFailure(
            trackId: 2,
            remotePlaylistId: 'B',
            error: Exception('third'),
          ),
        ],
      );

      expect(result.failedTrackIds, [1, 2]);
    });

    test(
        'merge preserves deterministic first-result-then-other-result ordering',
        () {
      final result = RemotePlaylistEditResult(
        sourceType: SourceType.youtube,
        confirmedAddedTrackIds: [2, 1],
        confirmedRemovedTrackIds: [4, 3],
        skippedTrackIds: [6, 5],
        failures: [
          RemotePlaylistEditFailure(
            trackId: 8,
            remotePlaylistId: 'A',
            error: Exception('first'),
          ),
        ],
        changedRemotePlaylistIds: ['B', 'A'],
      ).merge(
        RemotePlaylistEditResult(
          sourceType: SourceType.youtube,
          confirmedAddedTrackIds: [1, 9],
          confirmedRemovedTrackIds: [3, 10],
          skippedTrackIds: [5, 11],
          failures: [
            RemotePlaylistEditFailure(
              trackId: 12,
              remotePlaylistId: 'C',
              error: Exception('second'),
            ),
          ],
          changedRemotePlaylistIds: ['A', 'C'],
        ),
      );

      expect(result.confirmedAddedTrackIds, [2, 1, 9]);
      expect(result.confirmedRemovedTrackIds, [4, 3, 10]);
      expect(result.skippedTrackIds, [6, 5, 11]);
      expect(result.failures.map((failure) => failure.trackId), [8, 12]);
      expect(result.changedRemotePlaylistIds, ['B', 'A', 'C']);
    });

    test('merge rejects different SourceTypes', () {
      final result = RemotePlaylistEditResult(sourceType: SourceType.youtube);

      expect(
        () => result.merge(
          RemotePlaylistEditResult(sourceType: SourceType.bilibili),
        ),
        throwsArgumentError,
      );
    });

    test('constructor defensively copies list inputs', () {
      final confirmedAddedTrackIds = [1];
      final confirmedRemovedTrackIds = [2];
      final skippedTrackIds = [3];
      final failures = [
        RemotePlaylistEditFailure(
          trackId: 4,
          remotePlaylistId: 'A',
          error: Exception('first'),
        ),
      ];
      final changedRemotePlaylistIds = ['PL1'];

      final result = RemotePlaylistEditResult(
        sourceType: SourceType.youtube,
        confirmedAddedTrackIds: confirmedAddedTrackIds,
        confirmedRemovedTrackIds: confirmedRemovedTrackIds,
        skippedTrackIds: skippedTrackIds,
        failures: failures,
        changedRemotePlaylistIds: changedRemotePlaylistIds,
      );

      confirmedAddedTrackIds.add(9);
      confirmedRemovedTrackIds.add(9);
      skippedTrackIds.add(9);
      failures.add(
        RemotePlaylistEditFailure(
          trackId: 9,
          remotePlaylistId: 'B',
          error: Exception('second'),
        ),
      );
      changedRemotePlaylistIds.add('PL2');

      expect(result.confirmedAddedTrackIds, [1]);
      expect(result.confirmedRemovedTrackIds, [2]);
      expect(result.skippedTrackIds, [3]);
      expect(result.failures.map((failure) => failure.trackId), [4]);
      expect(result.changedRemotePlaylistIds, ['PL1']);
      expect(
          () => result.confirmedAddedTrackIds.add(10), throwsUnsupportedError);
      expect(() => result.confirmedRemovedTrackIds.add(10),
          throwsUnsupportedError);
      expect(() => result.skippedTrackIds.add(10), throwsUnsupportedError);
      expect(
        () => result.failures.add(
          RemotePlaylistEditFailure(
            trackId: 10,
            remotePlaylistId: 'C',
            error: Exception('third'),
          ),
        ),
        throwsUnsupportedError,
      );
      expect(() => result.changedRemotePlaylistIds.add('PL3'),
          throwsUnsupportedError);
    });
  });

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
    test('constructor defensively copies list map and nested set inputs', () {
      final editableTracks = [_track(SourceType.youtube, 1, 'a')];
      final skippedTrackIds = [2];
      final playlistIdsToAdd = ['add'];
      final playlistIdsToRemove = ['remove'];
      final existingTrackIds = {'a'};
      final existingTrackSourceIdsByPlaylist = {'partial': existingTrackIds};

      final plan = RemotePlaylistEditPlan(
        sourceType: SourceType.youtube,
        editableTracks: editableTracks,
        skippedTrackIds: skippedTrackIds,
        playlistIdsToAdd: playlistIdsToAdd,
        playlistIdsToRemove: playlistIdsToRemove,
        existingTrackSourceIdsByPlaylist: existingTrackSourceIdsByPlaylist,
      );

      editableTracks.add(_track(SourceType.youtube, 3, 'b'));
      skippedTrackIds.add(3);
      playlistIdsToAdd.add('new-add');
      playlistIdsToRemove.add('new-remove');
      existingTrackSourceIdsByPlaylist['new-partial'] = {'b'};
      existingTrackIds.add('b');

      expect(plan.editableTracks.map((track) => track.id), [1]);
      expect(plan.skippedTrackIds, [2]);
      expect(plan.playlistIdsToAdd, ['add']);
      expect(plan.playlistIdsToRemove, ['remove']);
      expect(plan.existingTrackSourceIdsByPlaylist.keys, ['partial']);
      expect(plan.existingTrackSourceIdsByPlaylist['partial'], {'a'});
      expect(() => plan.editableTracks.add(_track(SourceType.youtube, 4, 'c')),
          throwsUnsupportedError);
      expect(() => plan.skippedTrackIds.add(4), throwsUnsupportedError);
      expect(
          () => plan.playlistIdsToAdd.add('blocked'), throwsUnsupportedError);
      expect(() => plan.playlistIdsToRemove.add('blocked'),
          throwsUnsupportedError);
      expect(
        () => plan.existingTrackSourceIdsByPlaylist['blocked'] = {'c'},
        throwsUnsupportedError,
      );
      expect(
        () => plan.existingTrackSourceIdsByPlaylist['partial']!.add('c'),
        throwsUnsupportedError,
      );
    });
  });
}

Track _track(SourceType sourceType, int id, String sourceId) => Track()
  ..id = id
  ..sourceType = sourceType
  ..sourceId = sourceId
  ..title = sourceId;
