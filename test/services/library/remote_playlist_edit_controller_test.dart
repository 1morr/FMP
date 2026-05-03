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
