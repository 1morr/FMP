import 'package:isar/isar.dart';

import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import 'playlist_exceptions.dart';

class PlaylistMutationResult {
  final int playlistId;
  final List<int> affectedPlaylistIds;
  final List<int> addedTrackIds;
  final List<int> repairedTrackIds;
  final List<int> skippedTrackIds;
  final List<int> removedTrackIds;
  final List<int> deletedTrackIds;
  final List<int> updatedTrackIds;
  final List<Object> errors;
  final bool playlistChanged;
  final bool coverChanged;
  final bool pruningSkipped;

  const PlaylistMutationResult({
    required this.playlistId,
    this.affectedPlaylistIds = const [],
    this.addedTrackIds = const [],
    this.repairedTrackIds = const [],
    this.skippedTrackIds = const [],
    this.removedTrackIds = const [],
    this.deletedTrackIds = const [],
    this.updatedTrackIds = const [],
    this.errors = const [],
    this.playlistChanged = false,
    this.coverChanged = false,
    this.pruningSkipped = false,
  });

  int get addedCount => addedTrackIds.length;
  int get repairedCount => repairedTrackIds.length;
  int get skippedCount => skippedTrackIds.length;
  int get removedCount => removedTrackIds.length;
  bool get hasErrors => errors.isNotEmpty;
}

class RemoteRefreshMutationPolicy {
  final bool sourceDataComplete;
  final String? platformCoverUrl;

  const RemoteRefreshMutationPolicy({
    required this.sourceDataComplete,
    this.platformCoverUrl,
  });
}

class PlaylistMutationService with Logging {
  final Isar _isar;

  PlaylistMutationService({required Isar isar}) : _isar = isar;

  Future<PlaylistMutationResult> addTrack(int playlistId, Track track) {
    return addTracks(playlistId, [track]);
  }

  Future<PlaylistMutationResult> removeTrack(int playlistId, int trackId) {
    return removeTracks(playlistId, [trackId]);
  }

  Future<PlaylistMutationResult> removeTracks(
    int playlistId,
    List<int> trackIds,
  ) async {
    if (trackIds.isEmpty) {
      return PlaylistMutationResult(playlistId: playlistId);
    }

    return _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        return PlaylistMutationResult(playlistId: playlistId);
      }

      final requestedIds = trackIds.toSet();
      final originalTrackIds = List<int>.from(playlist.trackIds);
      final playlistRemovedTrackIds = originalTrackIds
          .where((trackId) => requestedIds.contains(trackId))
          .toList();
      final playlistChanged = playlistRemovedTrackIds.isNotEmpty;
      final originalCoverUrl = playlist.coverUrl;
      final now = DateTime.now();
      var coverChanged = false;
      if (playlistChanged) {
        playlist.trackIds = originalTrackIds
            .where((trackId) => !requestedIds.contains(trackId))
            .toList();
        coverChanged = await _updateDefaultCover(playlist);
        playlist.updatedAt = now;
        await _isar.playlists.put(playlist);
      }

      final tracks =
          (await _isar.tracks.getAll(requestedIds.toList())).whereType<Track>();
      final removedTrackIds = {...playlistRemovedTrackIds};
      final deletedTrackIds = <int>[];
      final updatedTrackIds = <int>[];
      final tracksToUpdate = <Track>[];
      for (final track in tracks) {
        if (!track.belongsToPlaylist(playlistId)) {
          continue;
        }

        removedTrackIds.add(track.id);
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          deletedTrackIds.add(track.id);
        } else {
          track.updatedAt = now;
          updatedTrackIds.add(track.id);
          tracksToUpdate.add(track);
        }
      }

      if (!playlistChanged && removedTrackIds.isEmpty) {
        return PlaylistMutationResult(
          playlistId: playlistId,
          affectedPlaylistIds: [playlistId],
        );
      }

      if (deletedTrackIds.isNotEmpty) {
        await _isar.tracks.deleteAll(deletedTrackIds);
        logDebug('Deleted ${deletedTrackIds.length} orphan tracks');
      }
      if (tracksToUpdate.isNotEmpty) {
        await _isar.tracks.putAll(tracksToUpdate);
      }

      return PlaylistMutationResult(
        playlistId: playlistId,
        affectedPlaylistIds: [playlistId],
        removedTrackIds: removedTrackIds.toList(),
        deletedTrackIds: deletedTrackIds,
        updatedTrackIds: updatedTrackIds,
        playlistChanged: playlistChanged,
        coverChanged: coverChanged || playlist.coverUrl != originalCoverUrl,
      );
    });
  }

  Future<PlaylistMutationResult> reorderTracks(
    int playlistId,
    List<int> orderedTrackIds,
  ) async {
    return _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        return PlaylistMutationResult(playlistId: playlistId);
      }

      final originalCoverUrl = playlist.coverUrl;
      final originalTrackIds = List<int>.from(playlist.trackIds);
      playlist.trackIds = List<int>.from(orderedTrackIds);
      final coverChanged = await _updateDefaultCover(playlist);
      final playlistChanged =
          !_listEquals(originalTrackIds, playlist.trackIds) ||
              coverChanged ||
              playlist.coverUrl != originalCoverUrl;
      if (playlistChanged) {
        playlist.updatedAt = DateTime.now();
        await _isar.playlists.put(playlist);
      }

      return PlaylistMutationResult(
        playlistId: playlistId,
        affectedPlaylistIds: [playlistId],
        playlistChanged: playlistChanged,
        coverChanged: coverChanged || playlist.coverUrl != originalCoverUrl,
      );
    });
  }

  Future<PlaylistMutationResult> deletePlaylist(int playlistId) async {
    return _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        return PlaylistMutationResult(playlistId: playlistId);
      }

      final trackIds = List<int>.from(playlist.trackIds);
      await _isar.playlists.delete(playlistId);

      final staleReverseTracks = await _isar.tracks
          .filter()
          .playlistInfoElement((q) => q.playlistIdEqualTo(playlistId))
          .findAll();
      final cleanupTrackIds = {
        ...trackIds,
        ...staleReverseTracks.map((track) => track.id),
      }.toList();
      final tracks =
          (await _isar.tracks.getAll(cleanupTrackIds)).whereType<Track>();
      final removedTrackIds = <int>[];
      final deletedTrackIds = <int>[];
      final updatedTrackIds = <int>[];
      final tracksToUpdate = <Track>[];
      final now = DateTime.now();
      for (final track in tracks) {
        if (!track.belongsToPlaylist(playlistId)) {
          continue;
        }

        removedTrackIds.add(track.id);
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          deletedTrackIds.add(track.id);
        } else {
          track.updatedAt = now;
          updatedTrackIds.add(track.id);
          tracksToUpdate.add(track);
        }
      }

      if (deletedTrackIds.isNotEmpty) {
        await _isar.tracks.deleteAll(deletedTrackIds);
        logDebug('Deleted ${deletedTrackIds.length} orphan tracks');
      }
      if (tracksToUpdate.isNotEmpty) {
        await _isar.tracks.putAll(tracksToUpdate);
      }

      return PlaylistMutationResult(
        playlistId: playlistId,
        affectedPlaylistIds: [playlistId],
        removedTrackIds: removedTrackIds,
        deletedTrackIds: deletedTrackIds,
        updatedTrackIds: updatedTrackIds,
        playlistChanged: true,
      );
    });
  }

  Future<Playlist> duplicatePlaylist(int originalPlaylistId, Playlist copy) {
    return _isar.writeTxn(() async {
      final original = await _isar.playlists.get(originalPlaylistId);
      if (original == null) {
        throw PlaylistNotFoundException(originalPlaylistId);
      }

      copy
        ..description = original.description
        ..coverUrl = original.coverUrl
        ..hasCustomCover = original.hasCustomCover
        ..trackIds = List<int>.from(original.trackIds)
        ..updatedAt = DateTime.now();
      copy.id = await _isar.playlists.put(copy);

      final copiedTracks = (await _isar.tracks.getAll(copy.trackIds))
          .whereType<Track>()
          .toList();
      for (final track in copiedTracks) {
        track.addToPlaylist(copy.id, playlistName: copy.name);
        track.updatedAt = copy.updatedAt;
      }
      if (copiedTracks.isNotEmpty) {
        await _isar.tracks.putAll(copiedTracks);
      }

      return copy;
    });
  }

  Future<PlaylistMutationResult> addTracks(
    int playlistId,
    List<Track> tracks,
  ) async {
    final candidateTracks = _dedupeTracksByUniqueKey(tracks);

    return _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      if (candidateTracks.isEmpty) {
        return PlaylistMutationResult(
          playlistId: playlistId,
          affectedPlaylistIds: [playlistId],
        );
      }

      final now = DateTime.now();
      final trackIds = List<int>.from(playlist.trackIds);
      final trackIdSet = trackIds.toSet();
      final addedTrackIds = <int>[];
      final repairedTrackIds = <int>[];
      final skippedTrackIds = <int>[];
      final updatedTrackIds = <int>[];
      Track? firstNewPlaylistTrack;
      final wasEmpty = trackIds.isEmpty;
      var playlistChanged = false;
      var coverChanged = false;

      for (final inputTrack in candidateTracks) {
        final existingTrack = await _findTrackByIdentity(inputTrack);
        final trackToSave = existingTrack ?? inputTrack;
        final metadataChanged = existingTrack != null &&
            _mergeTrackMetadataIfNeeded(existingTrack, inputTrack);
        final trackLinked = trackToSave.belongsToPlaylist(playlistId);
        final playlistLinked =
            existingTrack != null && trackIdSet.contains(trackToSave.id);

        final trackMembershipChanged = _ensureSinglePlaylistInfo(
          trackToSave,
          playlistId,
          playlist.name,
        );
        var trackChanged = metadataChanged || trackMembershipChanged;

        if (existingTrack == null) {
          trackToSave.updatedAt = now;
          trackToSave.id = await _isar.tracks.put(trackToSave);
          addedTrackIds.add(trackToSave.id);
          trackChanged = false;
        } else if (trackChanged) {
          trackToSave.updatedAt = now;
          trackToSave.id = await _isar.tracks.put(trackToSave);
          if (metadataChanged) {
            updatedTrackIds.add(trackToSave.id);
          }
        }
        if (!playlistLinked && trackIdSet.add(trackToSave.id)) {
          trackIds.add(trackToSave.id);
          firstNewPlaylistTrack ??= trackToSave;
          playlistChanged = true;
        }

        if (existingTrack != null) {
          if (!trackLinked && !playlistLinked) {
            addedTrackIds.add(trackToSave.id);
          } else if (trackMembershipChanged || !playlistLinked) {
            repairedTrackIds.add(trackToSave.id);
          } else if (!metadataChanged) {
            skippedTrackIds.add(trackToSave.id);
          }
        }
      }

      if (playlistChanged) {
        playlist.trackIds = trackIds;
      }
      if (wasEmpty &&
          !playlist.hasCustomCover &&
          firstNewPlaylistTrack != null) {
        final newCoverUrl = firstNewPlaylistTrack.thumbnailUrl;
        if (playlist.coverUrl != newCoverUrl) {
          playlist.coverUrl = newCoverUrl;
          coverChanged = true;
        }
      }
      if (playlistChanged || coverChanged) {
        playlist.updatedAt = now;
        await _isar.playlists.put(playlist);
      }

      if (addedTrackIds.isNotEmpty || repairedTrackIds.isNotEmpty) {
        logDebug(
          'Mutated playlist $playlistId: added ${addedTrackIds.length}, repaired ${repairedTrackIds.length}',
        );
      }

      return PlaylistMutationResult(
        playlistId: playlistId,
        affectedPlaylistIds: [playlistId],
        addedTrackIds: addedTrackIds,
        repairedTrackIds: repairedTrackIds,
        skippedTrackIds: skippedTrackIds,
        updatedTrackIds: updatedTrackIds,
        playlistChanged: playlistChanged,
        coverChanged: coverChanged,
      );
    });
  }

  Future<PlaylistMutationResult> replaceTracksFromRemoteRefresh(
    int playlistId,
    List<Track> refreshedTracks,
    RemoteRefreshMutationPolicy policy,
  ) async {
    final candidateTracks = _dedupeTracksByUniqueKey(refreshedTracks);

    return _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      final now = DateTime.now();
      final originalTrackIds = List<int>.from(playlist.trackIds);
      final originalTrackIdSet = originalTrackIds.toSet();
      final originalCoverUrl = playlist.coverUrl;
      final refreshedTrackIds = <int>[];
      final refreshedTrackIdSet = <int>{};
      final addedTrackIds = <int>[];
      final repairedTrackIds = <int>[];
      final skippedTrackIds = <int>[];
      final updatedTrackIds = <int>[];
      final errors = <Object>[];

      for (final inputTrack in candidateTracks) {
        try {
          final existingTrack = await _findTrackByIdentity(inputTrack);
          final trackToSave = existingTrack ?? inputTrack;
          final metadataChanged = existingTrack != null &&
              _mergeTrackMetadataIfNeeded(existingTrack, inputTrack);
          final trackLinked = trackToSave.belongsToPlaylist(playlistId);
          final playlistLinked = existingTrack != null &&
              originalTrackIdSet.contains(trackToSave.id);

          final trackMembershipChanged = _ensureSinglePlaylistInfo(
            trackToSave,
            playlistId,
            playlist.name,
          );
          final needsSave = existingTrack == null ||
              metadataChanged ||
              trackMembershipChanged;

          if (needsSave) {
            trackToSave.updatedAt = now;
            trackToSave.id = await _isar.tracks.put(trackToSave);
          }

          if (refreshedTrackIdSet.add(trackToSave.id)) {
            refreshedTrackIds.add(trackToSave.id);
          }

          if (existingTrack == null) {
            addedTrackIds.add(trackToSave.id);
          } else {
            if (metadataChanged) {
              updatedTrackIds.add(trackToSave.id);
            }
            if (!trackLinked && !playlistLinked) {
              addedTrackIds.add(trackToSave.id);
            } else if (trackMembershipChanged || !playlistLinked) {
              repairedTrackIds.add(trackToSave.id);
            } else if (!metadataChanged) {
              skippedTrackIds.add(trackToSave.id);
            }
          }
        } catch (error) {
          errors.add(error);
          logWarning('Failed to persist refreshed track: $error');
        }
      }

      final canPruneRemovedTracks = policy.sourceDataComplete && errors.isEmpty;
      final pruningSkipped = !canPruneRemovedTracks;
      final finalTrackIds = canPruneRemovedTracks
          ? refreshedTrackIds
          : _mergePreservingExistingTrackOrder(
              originalTrackIds,
              refreshedTrackIds,
            );
      final finalTrackIdSet = finalTrackIds.toSet();
      final removedTrackIdSet = <int>{};
      final deletedTrackIds = <int>[];
      final tracksToUpdate = <Track>[];
      final updatedTrackIdSet = updatedTrackIds.toSet();

      if (canPruneRemovedTracks) {
        final removalCandidates = originalTrackIds
            .where((trackId) => !finalTrackIdSet.contains(trackId))
            .toSet();
        removedTrackIdSet.addAll(removalCandidates);
        final reverseLinkedTracks = await _isar.tracks
            .filter()
            .playlistInfoElement((q) => q.playlistIdEqualTo(playlistId))
            .findAll();
        for (final track in reverseLinkedTracks) {
          if (!finalTrackIdSet.contains(track.id)) {
            removalCandidates.add(track.id);
          }
        }

        final tracks = (await _isar.tracks.getAll(removalCandidates.toList()))
            .whereType<Track>();
        for (final track in tracks) {
          if (!track.belongsToPlaylist(playlistId)) {
            continue;
          }

          removedTrackIdSet.add(track.id);
          track.removeFromPlaylist(playlistId);
          if (track.playlistInfo.isEmpty) {
            deletedTrackIds.add(track.id);
            updatedTrackIdSet.remove(track.id);
          } else {
            track.updatedAt = now;
            updatedTrackIdSet.add(track.id);
            tracksToUpdate.add(track);
          }
        }

        if (deletedTrackIds.isNotEmpty) {
          await _isar.tracks.deleteAll(deletedTrackIds);
          logDebug('Deleted ${deletedTrackIds.length} orphan tracks');
        }
        if (tracksToUpdate.isNotEmpty) {
          await _isar.tracks.putAll(tracksToUpdate);
        }
      }

      playlist.trackIds = finalTrackIds;
      playlist.lastRefreshed = now;
      final coverChanged = await _updateRefreshCover(
        playlist,
        policy.platformCoverUrl,
      );
      playlist.updatedAt = now;
      await _isar.playlists.put(playlist);

      return PlaylistMutationResult(
        playlistId: playlistId,
        affectedPlaylistIds: [playlistId],
        addedTrackIds: addedTrackIds,
        repairedTrackIds: repairedTrackIds,
        skippedTrackIds: skippedTrackIds,
        removedTrackIds: removedTrackIdSet.toList(),
        deletedTrackIds: deletedTrackIds,
        updatedTrackIds: updatedTrackIdSet.toList(),
        errors: errors,
        playlistChanged: true,
        coverChanged: coverChanged || playlist.coverUrl != originalCoverUrl,
        pruningSkipped: pruningSkipped,
      );
    });
  }

  Future<void> remapPlaylistTrackReferencesInTxn(Map<int, int> remap) async {
    if (remap.isEmpty) return;

    final now = DateTime.now();
    final playlists = await _isar.playlists.where().findAll();
    final changedPlaylists = <Playlist>[];
    for (final playlist in playlists) {
      final remappedTrackIds = _remapAndDedupeIds(playlist.trackIds, remap);
      if (_listEquals(playlist.trackIds, remappedTrackIds)) {
        continue;
      }
      playlist
        ..trackIds = remappedTrackIds
        ..updatedAt = now;
      changedPlaylists.add(playlist);
    }

    if (changedPlaylists.isNotEmpty) {
      await _isar.playlists.putAll(changedPlaylists);
    }
  }

  Future<Track?> _findTrackByIdentity(Track track) {
    if (track.cid == null) {
      return _isar.tracks
          .where()
          .sourceIdEqualTo(track.sourceId)
          .filter()
          .sourceTypeEqualTo(track.sourceType)
          .and()
          .cidIsNull()
          .findFirst();
    }

    return _isar.tracks
        .where()
        .sourceIdEqualTo(track.sourceId)
        .filter()
        .sourceTypeEqualTo(track.sourceType)
        .and()
        .cidEqualTo(track.cid)
        .findFirst();
  }

  List<Track> _dedupeTracksByUniqueKey(List<Track> tracks) {
    final keyToIndex = <String, int>{};
    final uniqueTracks = <Track>[];

    for (final track in tracks) {
      final key = track.uniqueKey;
      final existingIndex = keyToIndex[key];
      if (existingIndex == null) {
        keyToIndex[key] = uniqueTracks.length;
        uniqueTracks.add(track);
      } else if (_hasMoreCompleteTrackData(
        track,
        uniqueTracks[existingIndex],
      )) {
        uniqueTracks[existingIndex] = track;
      }
    }

    return uniqueTracks;
  }

  bool _hasMoreCompleteTrackData(Track a, Track b) {
    return _trackCompletenessScore(a) > _trackCompletenessScore(b);
  }

  int _trackCompletenessScore(Track track) {
    var score = 0;
    if (track.audioUrl != null && track.audioUrl!.isNotEmpty) score += 10;
    if (track.thumbnailUrl != null) score += 5;
    if (track.durationMs != null && track.durationMs! > 0) score += 3;
    if (track.artist != null && track.artist!.isNotEmpty) score += 2;
    return score;
  }

  bool _mergeTrackMetadataIfNeeded(Track target, Track incoming) {
    var changed = false;

    if (incoming.audioUrl != null && incoming.audioUrl!.isNotEmpty) {
      if (target.audioUrl == null ||
          target.audioUrl!.isEmpty ||
          !target.hasValidAudioUrl) {
        target.audioUrl = incoming.audioUrl;
        target.audioUrlExpiry = incoming.audioUrlExpiry;
        changed = true;
      }
    }
    if (target.thumbnailUrl == null && incoming.thumbnailUrl != null) {
      target.thumbnailUrl = incoming.thumbnailUrl;
      changed = true;
    }
    if (target.durationMs == null && incoming.durationMs != null) {
      target.durationMs = incoming.durationMs;
      changed = true;
    }
    if (target.artist == null && incoming.artist != null) {
      target.artist = incoming.artist;
      changed = true;
    }

    return changed;
  }

  bool _ensureSinglePlaylistInfo(
    Track track,
    int playlistId,
    String playlistName,
  ) {
    final matchingInfos = track.playlistInfo
        .where((info) => info.playlistId == playlistId)
        .toList();
    final existingInfo = matchingInfos.firstOrNull;
    final downloadPath = matchingInfos
        .map((info) => info.downloadPath)
        .firstWhere((path) => path.isNotEmpty, orElse: () => '');
    final matchingInfoAlreadyCorrect = matchingInfos.length == 1 &&
        existingInfo != null &&
        existingInfo.playlistName == playlistName;

    if (matchingInfoAlreadyCorrect) {
      return false;
    }

    final newInfos = track.playlistInfo
        .where((info) => info.playlistId != playlistId)
        .map((info) => info.copy())
        .toList();
    newInfos.add(
      PlaylistDownloadInfo()
        ..playlistId = playlistId
        ..playlistName = playlistName
        ..downloadPath = downloadPath,
    );
    track.playlistInfo = newInfos;
    return true;
  }

  Future<bool> _updateDefaultCover(Playlist playlist) async {
    if (playlist.hasCustomCover) {
      return false;
    }

    final oldCoverUrl = playlist.coverUrl;
    String? newCoverUrl;
    if (playlist.trackIds.isNotEmpty) {
      final firstTrack = await _isar.tracks.get(playlist.trackIds.first);
      newCoverUrl = firstTrack?.thumbnailUrl;
    }

    if (oldCoverUrl == newCoverUrl) {
      return false;
    }

    playlist.coverUrl = newCoverUrl;
    return true;
  }

  Future<bool> _updateRefreshCover(
    Playlist playlist,
    String? platformCoverUrl,
  ) async {
    if (playlist.hasCustomCover) {
      return false;
    }

    final oldCoverUrl = playlist.coverUrl;
    String? newCoverUrl = platformCoverUrl;
    if (newCoverUrl == null && playlist.trackIds.isNotEmpty) {
      final firstTrack = await _isar.tracks.get(playlist.trackIds.first);
      newCoverUrl = firstTrack?.thumbnailUrl;
    }

    if (oldCoverUrl == newCoverUrl) {
      return false;
    }

    playlist.coverUrl = newCoverUrl;
    return true;
  }

  List<int> _mergePreservingExistingTrackOrder(
    List<int> existingTrackIds,
    List<int> refreshedTrackIds,
  ) {
    final merged = List<int>.from(existingTrackIds);
    final seen = merged.toSet();
    for (final trackId in refreshedTrackIds) {
      if (seen.add(trackId)) {
        merged.add(trackId);
      }
    }
    return merged;
  }

  List<int> _remapAndDedupeIds(List<int> ids, Map<int, int> remap) {
    final result = <int>[];
    final seen = <int>{};
    for (final id in ids) {
      final mapped = remap[id] ?? id;
      if (seen.add(mapped)) {
        result.add(mapped);
      }
    }
    return result;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
