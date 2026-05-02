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

  Future<Track?> _findTrackByIdentity(Track track) {
    if (track.cid == null) {
      return _isar.tracks
          .where()
          .sourceIdEqualTo(track.sourceId)
          .filter()
          .sourceTypeEqualTo(track.sourceType)
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
        ..downloadPath = existingInfo?.downloadPath ?? '',
    );
    track.playlistInfo = newInfos;
    return true;
  }
}
