import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import 'remote_playlist_edit_planner.dart';
import 'remote_playlist_edit_result.dart';
import 'remote_playlist_id_parser.dart';

typedef RefreshMatchingImportedPlaylists = Future<void> Function({
  required SourceType sourceType,
  required Iterable<String> remotePlaylistIds,
});

typedef RemoveTracksFromLocalPlaylist = Future<void> Function(
  int playlistId,
  List<int> trackIds,
);

typedef IsRemoteSourceLoggedIn = bool Function(SourceType sourceType);

abstract class RemotePlaylistEditAdapter {
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan);
}

class RemotePlaylistEditController {
  final RemotePlaylistEditAdapter bilibiliAdapter;
  final RemotePlaylistEditAdapter youtubeAdapter;
  final RemotePlaylistEditAdapter neteaseAdapter;
  final RefreshMatchingImportedPlaylists refreshMatchingImportedPlaylists;
  final RemoveTracksFromLocalPlaylist removeTracksFromLocalPlaylist;
  final IsRemoteSourceLoggedIn isLoggedIn;

  const RemotePlaylistEditController({
    required this.bilibiliAdapter,
    required this.youtubeAdapter,
    required this.neteaseAdapter,
    required this.refreshMatchingImportedPlaylists,
    required this.removeTracksFromLocalPlaylist,
    required this.isLoggedIn,
  });

  Future<RemotePlaylistEditResult> submitSelectionEdit({
    required SourceType sourceType,
    required List<Track> tracks,
    required Set<String> selectedPlaylistIds,
    required Set<String> originalPlaylistIds,
    required Set<String> deselectedPartialPlaylistIds,
    required Map<String, Set<String>> existingTrackSourceIdsByPlaylist,
  }) async {
    final plan = RemotePlaylistEditPlanner.planSelectionEdit(
      sourceType: sourceType,
      tracks: tracks,
      selectedPlaylistIds: selectedPlaylistIds,
      originalPlaylistIds: originalPlaylistIds,
      deselectedPartialPlaylistIds: deselectedPartialPlaylistIds,
      existingTrackSourceIdsByPlaylist: existingTrackSourceIdsByPlaylist,
      isLoggedIn: isLoggedIn,
    );

    return _submitPlan(plan);
  }

  Future<RemotePlaylistEditResult> removeTracksFromImportedPlaylist({
    required Playlist playlist,
    required List<Track> tracks,
  }) async {
    final sourceType = _sourceTypeForImportedPlaylist(playlist, tracks);
    final sourceUrl = playlist.sourceUrl;
    final remotePlaylistId = sourceUrl == null || sourceUrl.isEmpty
        ? null
        : RemotePlaylistIdParser.parse(sourceType, sourceUrl);

    if (remotePlaylistId == null || remotePlaylistId.isEmpty) {
      return RemotePlaylistEditResult(
        sourceType: sourceType,
        skippedTrackIds: _matchingTrackIds(tracks, sourceType),
      );
    }

    final plan = RemotePlaylistEditPlanner.planSelectionEdit(
      sourceType: sourceType,
      tracks: tracks,
      selectedPlaylistIds: const <String>{},
      originalPlaylistIds: {remotePlaylistId},
      deselectedPartialPlaylistIds: const <String>{},
      existingTrackSourceIdsByPlaylist: const <String, Set<String>>{},
      isLoggedIn: isLoggedIn,
    );

    final result = await _submitPlan(
      plan,
      localRemovalPlaylistId: playlist.id,
    );
    return result;
  }

  Future<RemotePlaylistEditResult> _submitPlan(
    RemotePlaylistEditPlan plan, {
    int? localRemovalPlaylistId,
  }) async {
    final result = await _adapterFor(plan.sourceType).submit(plan);
    if (localRemovalPlaylistId != null &&
        result.confirmedRemovedTrackIds.isNotEmpty) {
      await removeTracksFromLocalPlaylist(
        localRemovalPlaylistId,
        result.confirmedRemovedTrackIds,
      );
    }
    if (result.changedRemote) {
      try {
        await refreshMatchingImportedPlaylists(
          sourceType: plan.sourceType,
          remotePlaylistIds: result.changedRemotePlaylistIds,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Failed to refresh imported playlists after remote edit',
          error,
          stackTrace,
          'RemotePlaylistEditController',
        );
      }
    }
    return result;
  }

  RemotePlaylistEditAdapter _adapterFor(SourceType sourceType) {
    switch (sourceType) {
      case SourceType.bilibili:
        return bilibiliAdapter;
      case SourceType.youtube:
        return youtubeAdapter;
      case SourceType.netease:
        return neteaseAdapter;
    }
  }

  SourceType _sourceTypeForImportedPlaylist(
    Playlist playlist,
    List<Track> tracks,
  ) {
    final sourceType = playlist.importSourceType;
    if (sourceType != null) return sourceType;
    if (tracks.isNotEmpty) return tracks.first.sourceType;
    return SourceType.youtube;
  }

  List<int> _matchingTrackIds(List<Track> tracks, SourceType sourceType) {
    return tracks
        .where((track) => track.sourceType == sourceType)
        .map((track) => track.id)
        .toList(growable: false);
  }
}

typedef GetBilibiliVideoAid = Future<int> Function(Track track);
typedef UpdateBilibiliVideoFavorites = Future<void> Function({
  required int videoAid,
  List<int> addFolderIds,
  List<int> removeFolderIds,
});

class BilibiliRemotePlaylistEditAdapter implements RemotePlaylistEditAdapter {
  final GetBilibiliVideoAid getVideoAid;
  final UpdateBilibiliVideoFavorites updateVideoFavorites;

  const BilibiliRemotePlaylistEditAdapter({
    required this.getVideoAid,
    required this.updateVideoFavorites,
  });

  @override
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan) async {
    final result = _RemotePlaylistEditResultBuilder(plan.sourceType)
      ..skipTrackIds(plan.skippedTrackIds);

    for (final track in plan.editableTracks) {
      final addFolderIds = <int>[];
      final addPlaylistIds = <String>[];
      final invalidPlaylistIds = <String>[];

      for (final playlistId in plan.playlistIdsToAdd) {
        final existingIds = plan.existingTrackSourceIdsByPlaylist[playlistId] ??
            const <String>{};
        if (existingIds.contains(track.sourceId)) continue;

        final folderId = int.tryParse(playlistId);
        if (folderId == null) {
          invalidPlaylistIds.add(playlistId);
        } else {
          addFolderIds.add(folderId);
          addPlaylistIds.add(playlistId);
        }
      }

      final removeFolderIds = <int>[];
      final removePlaylistIds = <String>[];
      for (final playlistId in plan.playlistIdsToRemove) {
        final folderId = int.tryParse(playlistId);
        if (folderId == null) {
          invalidPlaylistIds.add(playlistId);
        } else {
          removeFolderIds.add(folderId);
          removePlaylistIds.add(playlistId);
        }
      }

      for (final playlistId in invalidPlaylistIds) {
        result.addFailure(
          track.id,
          playlistId,
          FormatException('Invalid Bilibili folder ID: $playlistId'),
        );
      }

      if (addFolderIds.isEmpty && removeFolderIds.isEmpty) continue;

      try {
        final aid = await getVideoAid(track);
        await updateVideoFavorites(
          videoAid: aid,
          addFolderIds: addFolderIds,
          removeFolderIds: removeFolderIds,
        );
        if (addFolderIds.isNotEmpty) result.confirmAdded(track.id);
        if (removeFolderIds.isNotEmpty) result.confirmRemoved(track.id);
        result.markChanged(addPlaylistIds);
        result.markChanged(removePlaylistIds);
      } catch (error) {
        for (final playlistId in [...addPlaylistIds, ...removePlaylistIds]) {
          result.addFailure(track.id, playlistId, error);
        }
      }
    }

    return result.build();
  }
}

typedef AddYouTubeVideoToPlaylist = Future<void> Function(
  String playlistId,
  String videoId,
);
typedef GetYouTubeSetVideoId = Future<String?> Function(
  String playlistId,
  String videoId,
);
typedef RemoveYouTubeVideoFromPlaylist = Future<void> Function(
  String playlistId,
  String videoId,
  String setVideoId,
);

class YouTubeRemotePlaylistEditAdapter implements RemotePlaylistEditAdapter {
  final AddYouTubeVideoToPlaylist addToPlaylist;
  final GetYouTubeSetVideoId getSetVideoId;
  final RemoveYouTubeVideoFromPlaylist removeFromPlaylist;

  const YouTubeRemotePlaylistEditAdapter({
    required this.addToPlaylist,
    required this.getSetVideoId,
    required this.removeFromPlaylist,
  });

  @override
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan) async {
    final result = _RemotePlaylistEditResultBuilder(plan.sourceType)
      ..skipTrackIds(plan.skippedTrackIds);

    for (final playlistId in plan.playlistIdsToAdd) {
      for (final track in plan.editableTracks) {
        if (!_isMissingForPlaylist(plan, playlistId, track)) continue;

        try {
          await addToPlaylist(playlistId, track.sourceId);
          result.confirmAdded(track.id);
          result.markChanged([playlistId]);
        } catch (error) {
          result.addFailure(track.id, playlistId, error);
        }
      }
    }

    for (final playlistId in plan.playlistIdsToRemove) {
      for (final track in plan.editableTracks) {
        try {
          final setVideoId = await getSetVideoId(playlistId, track.sourceId);
          if (setVideoId == null) {
            result.skipTrack(track.id);
            continue;
          }

          await removeFromPlaylist(playlistId, track.sourceId, setVideoId);
          result.confirmRemoved(track.id);
          result.markChanged([playlistId]);
        } catch (error) {
          result.addFailure(track.id, playlistId, error);
        }
      }
    }

    return result.build();
  }
}

typedef AddNeteaseTracksToPlaylist = Future<void> Function(
  String playlistId,
  List<String> trackIds,
);
typedef RemoveNeteaseTracksFromPlaylist = Future<void> Function(
  String playlistId,
  List<String> trackIds,
);

class NeteaseRemotePlaylistEditAdapter implements RemotePlaylistEditAdapter {
  final AddNeteaseTracksToPlaylist addTracksToPlaylist;
  final RemoveNeteaseTracksFromPlaylist removeTracksFromPlaylist;

  const NeteaseRemotePlaylistEditAdapter({
    required this.addTracksToPlaylist,
    required this.removeTracksFromPlaylist,
  });

  @override
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan) async {
    final result = _RemotePlaylistEditResultBuilder(plan.sourceType)
      ..skipTrackIds(plan.skippedTrackIds);

    for (final playlistId in plan.playlistIdsToAdd) {
      final missingSourceIds = plan.missingSourceIdsFor(playlistId).toSet();
      if (missingSourceIds.isEmpty) continue;

      final tracksToAdd = plan.editableTracks
          .where((track) => missingSourceIds.contains(track.sourceId))
          .toList(growable: false);
      final sourceIdsToAdd = tracksToAdd
          .map((track) => track.sourceId)
          .toSet()
          .toList(growable: false);

      try {
        await addTracksToPlaylist(playlistId, sourceIdsToAdd);
        for (final track in tracksToAdd) {
          result.confirmAdded(track.id);
        }
        result.markChanged([playlistId]);
      } catch (error) {
        for (final track in tracksToAdd) {
          result.addFailure(track.id, playlistId, error);
        }
      }
    }

    final allSourceIds = plan.editableTracks
        .map((track) => track.sourceId)
        .toSet()
        .toList(growable: false);
    for (final playlistId in plan.playlistIdsToRemove) {
      if (allSourceIds.isEmpty) continue;

      try {
        await removeTracksFromPlaylist(playlistId, allSourceIds);
        for (final track in plan.editableTracks) {
          result.confirmRemoved(track.id);
        }
        result.markChanged([playlistId]);
      } catch (error) {
        for (final track in plan.editableTracks) {
          result.addFailure(track.id, playlistId, error);
        }
      }
    }

    return result.build();
  }
}

bool _isMissingForPlaylist(
  RemotePlaylistEditPlan plan,
  String playlistId,
  Track track,
) {
  final existingIds =
      plan.existingTrackSourceIdsByPlaylist[playlistId] ?? const <String>{};
  return !existingIds.contains(track.sourceId);
}

class _RemotePlaylistEditResultBuilder {
  final SourceType sourceType;
  final Set<int> _confirmedAddedTrackIds = <int>{};
  final Set<int> _confirmedRemovedTrackIds = <int>{};
  final Set<int> _skippedTrackIds = <int>{};
  final List<RemotePlaylistEditFailure> _failures =
      <RemotePlaylistEditFailure>[];
  final Set<String> _changedRemotePlaylistIds = <String>{};

  _RemotePlaylistEditResultBuilder(this.sourceType);

  void confirmAdded(int trackId) {
    _confirmedAddedTrackIds.add(trackId);
  }

  void confirmRemoved(int trackId) {
    _confirmedRemovedTrackIds.add(trackId);
  }

  void skipTrack(int trackId) {
    _skippedTrackIds.add(trackId);
  }

  void skipTrackIds(Iterable<int> trackIds) {
    _skippedTrackIds.addAll(trackIds);
  }

  void addFailure(int trackId, String remotePlaylistId, Object error) {
    _failures.add(RemotePlaylistEditFailure(
      trackId: trackId,
      remotePlaylistId: remotePlaylistId,
      error: error,
    ));
  }

  void markChanged(Iterable<String> playlistIds) {
    _changedRemotePlaylistIds.addAll(playlistIds);
  }

  RemotePlaylistEditResult build() {
    return RemotePlaylistEditResult(
      sourceType: sourceType,
      confirmedAddedTrackIds: _confirmedAddedTrackIds.toList(growable: false),
      confirmedRemovedTrackIds:
          _confirmedRemovedTrackIds.toList(growable: false),
      skippedTrackIds: _skippedTrackIds.toList(growable: false),
      failures: _failures,
      changedRemotePlaylistIds:
          _changedRemotePlaylistIds.toList(growable: false),
    );
  }
}
