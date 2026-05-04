import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_edit_controller.dart';
import 'package:fmp/services/library/remote_playlist_edit_planner.dart';
import 'package:fmp/services/library/remote_playlist_edit_result.dart';

void main() {
  group('RemotePlaylistEditController', () {
    test('submitSelectionEdit refreshes changed remote playlists', () async {
      final refreshed = <String>[];
      final controller = _controller(
        adapter: _FakeAdapter(addConfirmedIds: [1], changedIds: ['PL']),
        refreshRemoteIds: (sourceType, remoteIds) async =>
            refreshed.addAll(remoteIds),
      );

      final result = await controller.submitSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: [_track(SourceType.youtube, 1, 'a')],
        selectedPlaylistIds: {'PL'},
        originalPlaylistIds: const {},
        deselectedPartialPlaylistIds: const {},
        existingTrackSourceIdsByPlaylist: const {},
      );

      expect(result.confirmedAddedTrackIds, [1]);
      expect(refreshed, ['PL']);
    });

    test('syncs only confirmed remote removals to local imported playlist',
        () async {
      final playlist = Playlist()
        ..id = 9
        ..name = 'Imported'
        ..sourceUrl = 'https://www.youtube.com/playlist?list=PL'
        ..importSourceType = SourceType.youtube;
      final syncedLocalIds = <int>[];
      final refreshedIds = <String>[];
      final controller = _controller(
        adapter: _FakeAdapter(
            removeConfirmedIds: [1], skippedIds: [2], changedIds: ['PL']),
        removeLocalTracks: (_, trackIds) async =>
            syncedLocalIds.addAll(trackIds),
        refreshRemoteIds: (sourceType, remoteIds) async =>
            refreshedIds.addAll(remoteIds),
      );

      final result = await controller.removeTracksFromImportedPlaylist(
        playlist: playlist,
        tracks: [
          _track(SourceType.youtube, 1, 'ok'),
          _track(SourceType.youtube, 2, 'missing')
        ],
      );

      expect(result.confirmedRemovedTrackIds, [1]);
      expect(result.skippedTrackIds, [2]);
      expect(syncedLocalIds, [1]);
      expect(refreshedIds, ['PL']);
    });

    test(
        'keeps remote removal success and local removal when imported refresh fails',
        () async {
      final playlist = Playlist()
        ..id = 9
        ..name = 'Imported'
        ..sourceUrl = 'https://www.youtube.com/playlist?list=PL'
        ..importSourceType = SourceType.youtube;
      final syncedLocalIds = <int>[];
      final refreshedIds = <String>[];
      final controller = _controller(
        adapter: _FakeAdapter(removeConfirmedIds: [1], changedIds: ['PL']),
        removeLocalTracks: (_, trackIds) async =>
            syncedLocalIds.addAll(trackIds),
        refreshRemoteIds: (sourceType, remoteIds) async {
          refreshedIds.addAll(remoteIds);
          throw StateError('refresh failed');
        },
      );

      final result = await controller.removeTracksFromImportedPlaylist(
        playlist: playlist,
        tracks: [_track(SourceType.youtube, 1, 'ok')],
      );

      expect(result.confirmedRemovedTrackIds, [1]);
      expect(result.hasFailures, isFalse);
      expect(syncedLocalIds, [1]);
      expect(refreshedIds, ['PL']);
    });

    test('removeTracksFromImportedPlaylist skips invalid remote playlist URLs',
        () async {
      final controller = _controller(adapter: _FakeAdapter());
      final result = await controller.removeTracksFromImportedPlaylist(
        playlist: Playlist()
          ..id = 1
          ..name = 'Bad'
          ..sourceUrl = 'https://example.test/no-id'
          ..importSourceType = SourceType.youtube,
        tracks: [_track(SourceType.youtube, 7, 'yt')],
      );

      expect(result.changedRemote, isFalse);
      expect(result.skippedTrackIds, [7]);
    });
  });

  group('source adapters', () {
    test('Bilibili adapter removes tracks from parsed folder IDs', () async {
      final aidLookups = <String>[];
      final favoriteUpdates = <String>[];
      final adapter = BilibiliRemotePlaylistEditAdapter(
        getVideoAid: (track) async {
          aidLookups.add(track.sourceId);
          return switch (track.sourceId) {
            'BV1' => 101,
            'BV2' => 202,
            _ => throw StateError('unexpected track ${track.sourceId}'),
          };
        },
        updateVideoFavorites: ({
          required videoAid,
          List<int> addFolderIds = const [],
          List<int> removeFolderIds = const [],
        }) async {
          favoriteUpdates.add(
            '$videoAid:add=${addFolderIds.join(',')}:remove=${removeFolderIds.join(',')}',
          );
        },
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.bilibili,
        editableTracks: [
          _track(SourceType.bilibili, 1, 'BV1'),
          _track(SourceType.bilibili, 2, 'BV2')
        ],
        skippedTrackIds: const [],
        playlistIdsToAdd: const [],
        playlistIdsToRemove: const ['12345', '67890'],
        existingTrackSourceIdsByPlaylist: const {},
      ));

      expect(result.confirmedAddedTrackIds, isEmpty);
      expect(result.confirmedRemovedTrackIds, [1, 2]);
      expect(result.changedRemotePlaylistIds, ['12345', '67890']);
      expect(aidLookups, ['BV1', 'BV2']);
      expect(favoriteUpdates, [
        '101:add=:remove=12345,67890',
        '202:add=:remove=12345,67890',
      ]);
    });

    test('YouTube adapter skips removals when setVideoId is missing', () async {
      final removeCalls = <String>[];
      final adapter = YouTubeRemotePlaylistEditAdapter(
        addToPlaylist: (_, __) async {},
        getSetVideoId: (playlistId, videoId) async =>
            videoId == 'ok' ? 'set-ok' : null,
        removeFromPlaylist: (playlistId, videoId, setVideoId) async =>
            removeCalls.add('$playlistId:$videoId:$setVideoId'),
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.youtube,
        editableTracks: [
          _track(SourceType.youtube, 1, 'ok'),
          _track(SourceType.youtube, 2, 'missing')
        ],
        skippedTrackIds: const [],
        playlistIdsToAdd: const [],
        playlistIdsToRemove: const ['PL'],
        existingTrackSourceIdsByPlaylist: const {},
      ));

      expect(result.confirmedRemovedTrackIds, [1]);
      expect(result.skippedTrackIds, [2]);
      expect(result.changedRemotePlaylistIds, ['PL']);
      expect(removeCalls, ['PL:ok:set-ok']);
    });

    test('Netease adapter adds only missing tracks for partial playlists',
        () async {
      final addCalls = <String>[];
      final adapter = NeteaseRemotePlaylistEditAdapter(
        addTracksToPlaylist: (playlistId, trackIds) async =>
            addCalls.add('$playlistId:${trackIds.join(',')}'),
        removeTracksFromPlaylist: (_, __) async {},
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.netease,
        editableTracks: [
          _track(SourceType.netease, 1, '11'),
          _track(SourceType.netease, 2, '22')
        ],
        skippedTrackIds: const [],
        playlistIdsToAdd: const ['P'],
        playlistIdsToRemove: const [],
        existingTrackSourceIdsByPlaylist: const {
          'P': {'11'}
        },
      ));

      expect(result.confirmedAddedTrackIds, [2]);
      expect(result.changedRemotePlaylistIds, ['P']);
      expect(addCalls, ['P:22']);
    });

    test('Netease adapter removes editable tracks in a batch', () async {
      final removeCalls = <String>[];
      final adapter = NeteaseRemotePlaylistEditAdapter(
        addTracksToPlaylist: (_, __) async {},
        removeTracksFromPlaylist: (playlistId, trackIds) async =>
            removeCalls.add('$playlistId:${trackIds.join(',')}'),
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.netease,
        editableTracks: [
          _track(SourceType.netease, 1, '11'),
          _track(SourceType.netease, 2, '22')
        ],
        skippedTrackIds: const [99],
        playlistIdsToAdd: const [],
        playlistIdsToRemove: const ['P'],
        existingTrackSourceIdsByPlaylist: const {},
      ));

      expect(result.confirmedAddedTrackIds, isEmpty);
      expect(result.confirmedRemovedTrackIds, [1, 2]);
      expect(result.skippedTrackIds, [99]);
      expect(result.changedRemotePlaylistIds, ['P']);
      expect(removeCalls, ['P:11,22']);
    });
  });
}

RemotePlaylistEditController _controller({
  RemotePlaylistEditAdapter? adapter,
  Future<void> Function(SourceType sourceType, Iterable<String> remoteIds)?
      refreshRemoteIds,
  Future<void> Function(int playlistId, List<int> trackIds)? removeLocalTracks,
}) {
  final fallback = adapter ?? _FakeAdapter();
  return RemotePlaylistEditController(
    bilibiliAdapter: fallback,
    youtubeAdapter: fallback,
    neteaseAdapter: fallback,
    refreshMatchingImportedPlaylists: (
            {required sourceType, required remotePlaylistIds}) async =>
        refreshRemoteIds?.call(sourceType, remotePlaylistIds),
    removeTracksFromLocalPlaylist: removeLocalTracks ?? (_, __) async {},
    isLoggedIn: (_) => true,
  );
}

class _FakeAdapter implements RemotePlaylistEditAdapter {
  _FakeAdapter(
      {this.addConfirmedIds = const [],
      this.removeConfirmedIds = const [],
      this.skippedIds = const [],
      this.changedIds = const []});

  final List<int> addConfirmedIds;
  final List<int> removeConfirmedIds;
  final List<int> skippedIds;
  final List<String> changedIds;

  @override
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan) async {
    return RemotePlaylistEditResult(
      sourceType: plan.sourceType,
      confirmedAddedTrackIds: addConfirmedIds,
      confirmedRemovedTrackIds: removeConfirmedIds,
      skippedTrackIds: skippedIds,
      changedRemotePlaylistIds: changedIds,
    );
  }
}

Track _track(SourceType sourceType, int id, String sourceId) => Track()
  ..id = id
  ..sourceType = sourceType
  ..sourceId = sourceId
  ..title = sourceId;
