import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/download_filenames.dart';
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';
import '../../providers/download/download_scanner.dart';
import 'download_path_manager.dart';

class ChangeBasePathMaintenanceResult {
  const ChangeBasePathMaintenanceResult({
    required this.affectedPlaylistIds,
    required this.clearedDownloadTrackCount,
    required this.clearedTaskCount,
  });

  final List<int> affectedPlaylistIds;
  final int clearedDownloadTrackCount;
  final int clearedTaskCount;
}

class DownloadPathDeletionResult {
  const DownloadPathDeletionResult({
    required this.affectedPlaylistIds,
    required this.clearedPathCount,
  });

  final List<int> affectedPlaylistIds;
  final int clearedPathCount;
}

class DownloadPathMaintenanceService {
  DownloadPathMaintenanceService({
    required TrackRepository trackRepository,
    required DownloadPathManager pathManager,
    required Future<int> Function() clearCompletedAndErrorTasks,
  })  : _trackRepository = trackRepository,
        _pathManager = pathManager,
        _clearCompletedAndErrorTasks = clearCompletedAndErrorTasks;

  final TrackRepository _trackRepository;
  final DownloadPathManager _pathManager;
  final Future<int> Function() _clearCompletedAndErrorTasks;

  Future<ChangeBasePathMaintenanceResult> changeBasePathAndResetDownloads(
    String newPath,
  ) async {
    final tracksWithDownloads =
        await _trackRepository.getAllTracksWithDownloads();
    final affectedPlaylistIds =
        _collectAffectedPlaylistIds(tracksWithDownloads);

    if (tracksWithDownloads.isNotEmpty) {
      await _trackRepository.clearAllDownloadPaths();
    }

    final clearedTaskCount = await _clearCompletedAndErrorTasks();
    await _pathManager.saveDownloadPath(newPath);

    return ChangeBasePathMaintenanceResult(
      affectedPlaylistIds: affectedPlaylistIds,
      clearedDownloadTrackCount: tracksWithDownloads.length,
      clearedTaskCount: clearedTaskCount,
    );
  }

  Future<DownloadPathDeletionResult> deleteDownloadedCategory(
    String folderPath,
  ) async {
    final scannedTracks = await DownloadScanner.scanFolderForTracks(folderPath);
    final trackedPaths = _collectTrackedPaths(scannedTracks);

    await compute(_deleteFolderInIsolate, folderPath);

    return _clearDeletedPaths(scannedTracks, trackedPaths);
  }

  Future<DownloadPathDeletionResult> deleteDownloadedTracks(
    List<Track> scannedTracks,
  ) async {
    final trackedPaths = _collectTrackedPaths(scannedTracks);

    await compute(_deleteFilesInIsolate, trackedPaths.toList());

    return _clearDeletedPaths(scannedTracks, trackedPaths);
  }

  Future<DownloadPathDeletionResult> _clearDeletedPaths(
    List<Track> scannedTracks,
    Set<String> trackedPaths,
  ) async {
    if (scannedTracks.isEmpty || trackedPaths.isEmpty) {
      return const DownloadPathDeletionResult(
        affectedPlaylistIds: [],
        clearedPathCount: 0,
      );
    }

    final deletedPaths = <String>{};
    for (final path in trackedPaths) {
      if (!await File(path).exists()) {
        deletedPaths.add(_normalizePath(path));
      }
    }

    if (deletedPaths.isEmpty) {
      return const DownloadPathDeletionResult(
        affectedPlaylistIds: [],
        clearedPathCount: 0,
      );
    }

    final persistedTracks = await _trackRepository.getAllTracksWithDownloads();
    final tracksBySourceKey = <String, List<Track>>{};
    for (final track in persistedTracks) {
      tracksBySourceKey.putIfAbsent(_sourceKey(track), () => []).add(track);
    }

    final affectedPlaylistIds = <int>{};
    var clearedPathCount = 0;

    for (final scannedTrack in scannedTracks) {
      final persistedTrack = _findMatchingPersistedTrack(
        scannedTrack,
        tracksBySourceKey[_sourceKey(scannedTrack)] ?? const [],
      );
      if (persistedTrack == null) {
        continue;
      }

      final scannedPathsForTrack = _matchDeletedPathsForTrack(
        scannedTrack: scannedTrack,
        deletedPaths: deletedPaths,
      );
      if (scannedPathsForTrack.isEmpty) {
        continue;
      }

      var changed = false;
      final nextPlaylistInfo = <PlaylistDownloadInfo>[];
      for (final info in persistedTrack.playlistInfo) {
        final shouldClear = info.downloadPath.isNotEmpty &&
            scannedPathsForTrack.contains(_normalizePath(info.downloadPath));
        nextPlaylistInfo.add(
          PlaylistDownloadInfo()
            ..playlistId = info.playlistId
            ..playlistName = info.playlistName
            ..downloadPath = shouldClear ? '' : info.downloadPath,
        );
        if (shouldClear) {
          changed = true;
          clearedPathCount++;
          if (info.playlistId > 0) {
            affectedPlaylistIds.add(info.playlistId);
          }
        }
      }

      if (changed) {
        persistedTrack.playlistInfo = nextPlaylistInfo;
        await _trackRepository.save(persistedTrack);
      }
    }

    return DownloadPathDeletionResult(
      affectedPlaylistIds: _sortIds(affectedPlaylistIds),
      clearedPathCount: clearedPathCount,
    );
  }

  Set<String> _collectTrackedPaths(List<Track> scannedTracks) {
    return scannedTracks
        .expand((track) => track.allDownloadPaths)
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  Set<String> _matchDeletedPathsForTrack({
    required Track scannedTrack,
    required Set<String> deletedPaths,
  }) {
    final matchedPaths = <String>{};
    for (final path in scannedTrack.allDownloadPaths) {
      final normalizedPath = _normalizePath(path);
      if (path.isNotEmpty && deletedPaths.contains(normalizedPath)) {
        matchedPaths.add(normalizedPath);
        continue;
      }

      final folderPath = p.dirname(path);
      if (folderPath.isNotEmpty && !Directory(folderPath).existsSync()) {
        matchedPaths.add(normalizedPath);
      }
    }
    return matchedPaths;
  }

  Track? _findMatchingPersistedTrack(
      Track scannedTrack, List<Track> candidates) {
    if (candidates.isEmpty) {
      return null;
    }

    if (scannedTrack.cid != null) {
      return candidates
          .where((track) => track.cid == scannedTrack.cid)
          .firstOrNull;
    }

    if (scannedTrack.pageNum != null) {
      return candidates
          .where((track) => track.pageNum == scannedTrack.pageNum)
          .firstOrNull;
    }

    if (candidates.length == 1) {
      return candidates.first;
    }

    return candidates
        .where((track) => track.cid == null && track.pageNum == null)
        .firstOrNull;
  }

  List<int> _collectAffectedPlaylistIds(List<Track> tracks) {
    final playlistIds = <int>{};
    for (final track in tracks) {
      for (final info in track.playlistInfo) {
        if (info.downloadPath.isNotEmpty && info.playlistId > 0) {
          playlistIds.add(info.playlistId);
        }
      }
    }
    return _sortIds(playlistIds);
  }

  String _sourceKey(Track track) =>
      '${track.sourceType.name}:${track.sourceId}';

  String _normalizePath(String path) {
    if (path.isEmpty) {
      return path;
    }
    return p.normalize(path.replaceAll('\\', '/'));
  }

  List<int> _sortIds(Set<int> ids) {
    final sorted = ids.toList()..sort();
    return sorted;
  }
}

Future<void> _deleteFolderInIsolate(String folderPath) async {
  try {
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  } on FileSystemException {
    // Keep best-effort deletion behavior for UI flows.
  }
}

Future<void> _deleteFilesInIsolate(List<String> paths) async {
  final foldersToDelete = <String>{};
  for (final path in paths) {
    try {
      final file = File(path);
      if (!await file.exists()) continue;

      final parentDir = file.parent;
      foldersToDelete.add(parentDir.path);
      await file.delete();
      await _deleteMetadataForAudioFile(parentDir, file.path);
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }

  for (final folderPath in foldersToDelete) {
    try {
      final dir = Directory(folderPath);
      if (await dir.exists() && !await _hasRemainingAudioFiles(dir)) {
        await dir.delete(recursive: true);
        await _deleteParentIfEmpty(dir.parent);
      }
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }
}

Future<void> _deleteMetadataForAudioFile(
  Directory parentDir,
  String audioPath,
) async {
  final audioFileName = p.basename(audioPath);
  final metadataName = audioFileName.startsWith('P') &&
          audioFileName.contains('.')
      ? 'metadata_P${audioFileName.substring(1, audioFileName.indexOf('.'))}.json'
      : DownloadFileNames.metadata;
  final metadataFile = File(p.join(parentDir.path, metadataName));
  if (await metadataFile.exists()) {
    await metadataFile.delete();
  }
}

Future<bool> _hasRemainingAudioFiles(Directory dir) async {
  final entities = await dir.list().toList();
  return entities.any((entity) {
    if (entity is! File) return false;
    final name = p.basename(entity.path).toLowerCase();
    return name.endsWith('.m4a') ||
        name.endsWith('.mp3') ||
        name.endsWith('.aac') ||
        name.endsWith('.opus');
  });
}

Future<void> _deleteParentIfEmpty(Directory dir) async {
  if (!await dir.exists()) return;
  final remaining = await dir.list().toList();
  if (remaining.isEmpty) {
    await dir.delete();
  }
}
