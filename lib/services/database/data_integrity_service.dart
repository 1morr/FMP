import 'package:isar/isar.dart';

import '../../data/models/account.dart';
import '../../data/models/download_task.dart';
import '../../data/models/play_queue.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';

class DataIntegrityReport {
  const DataIntegrityReport({
    required this.duplicateTrackKeys,
    required this.duplicateDownloadSavePaths,
    required this.duplicateAccountPlatforms,
    required this.playQueueCount,
  });

  final List<String> duplicateTrackKeys;
  final List<String> duplicateDownloadSavePaths;
  final List<SourceType> duplicateAccountPlatforms;
  final int playQueueCount;

  bool get hasIssues =>
      duplicateTrackKeys.isNotEmpty ||
      duplicateDownloadSavePaths.isNotEmpty ||
      duplicateAccountPlatforms.isNotEmpty ||
      playQueueCount > 1;
}

class DataIntegrityRepairResult {
  const DataIntegrityRepairResult({
    required this.removedTrackIds,
    required this.removedDownloadTaskIds,
    required this.removedAccountIds,
    required this.removedPlayQueueIds,
  });

  final List<int> removedTrackIds;
  final List<int> removedDownloadTaskIds;
  final List<int> removedAccountIds;
  final List<int> removedPlayQueueIds;
}

class DataIntegrityService {
  DataIntegrityService(this._isar);

  final Isar _isar;

  Future<DataIntegrityReport> scan() async {
    final tracks = await _isar.tracks.where().findAll();
    final tasks = await _isar.downloadTasks.where().findAll();
    final accounts = await _isar.accounts.where().findAll();
    final queues = await _isar.playQueues.where().findAll();

    return DataIntegrityReport(
      duplicateTrackKeys: _duplicateKeys(
        tracks,
        (track) => track.uniqueKey,
      ),
      duplicateDownloadSavePaths: _duplicateKeys(
        tasks.where(
            (task) => task.savePath != null && task.savePath!.isNotEmpty),
        (task) => task.savePath!,
      ),
      duplicateAccountPlatforms: _duplicateKeys(
        accounts,
        (account) => account.platform,
      ),
      playQueueCount: queues.length,
    );
  }

  Future<DataIntegrityRepairResult> repair() async {
    final removedTrackIds = <int>[];
    final removedDownloadTaskIds = <int>[];
    final removedAccountIds = <int>[];
    final removedPlayQueueIds = <int>[];

    await _isar.writeTxn(() async {
      final trackIdRemap = <int, int>{};
      final tracks = await _isar.tracks.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        tracks,
        (track) => track.uniqueKey,
      )) {
        final keep = duplicateGroup.reduce(_preferTrack);
        final remove =
            duplicateGroup.where((track) => track.id != keep.id).toList();
        for (final track in remove) {
          trackIdRemap[track.id] = keep.id;
        }
        removedTrackIds.addAll(remove.map((track) => track.id));
      }
      await _remapTrackReferences(trackIdRemap);
      await _isar.tracks.deleteAll(removedTrackIds);

      final tasks = await _isar.downloadTasks.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        tasks.where(
          (task) => task.savePath != null && task.savePath!.isNotEmpty,
        ),
        (task) => task.savePath!,
      )) {
        final keep = duplicateGroup.reduce(_preferDownloadTask);
        final remove =
            duplicateGroup.where((task) => task.id != keep.id).toList();
        removedDownloadTaskIds.addAll(remove.map((task) => task.id));
        await _isar.downloadTasks.deleteAll(
          remove.map((task) => task.id).toList(),
        );
      }

      final accounts = await _isar.accounts.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        accounts,
        (account) => account.platform,
      )) {
        final keep = duplicateGroup.reduce(_preferAccount);
        final remove =
            duplicateGroup.where((account) => account.id != keep.id).toList();
        removedAccountIds.addAll(remove.map((account) => account.id));
        await _isar.accounts.deleteAll(
          remove.map((account) => account.id).toList(),
        );
      }

      final queues = await _isar.playQueues.where().findAll();
      if (queues.length > 1) {
        final keep = queues.reduce(_preferPlayQueue);
        final remove = queues.where((queue) => queue.id != keep.id).toList();
        removedPlayQueueIds.addAll(remove.map((queue) => queue.id));
        await _isar.playQueues.deleteAll(
          remove.map((queue) => queue.id).toList(),
        );
      }
    });

    return DataIntegrityRepairResult(
      removedTrackIds: removedTrackIds,
      removedDownloadTaskIds: removedDownloadTaskIds,
      removedAccountIds: removedAccountIds,
      removedPlayQueueIds: removedPlayQueueIds,
    );
  }

  Future<void> _remapTrackReferences(Map<int, int> remap) async {
    if (remap.isEmpty) return;

    final playlists = await _isar.playlists.where().findAll();
    for (final playlist in playlists) {
      playlist.trackIds = _remapAndDedupeIds(playlist.trackIds, remap);
    }
    await _isar.playlists.putAll(playlists);

    final tasks = await _isar.downloadTasks.where().findAll();
    for (final task in tasks) {
      task.trackId = remap[task.trackId] ?? task.trackId;
    }
    await _isar.downloadTasks.putAll(tasks);

    final queues = await _isar.playQueues.where().findAll();
    for (final queue in queues) {
      queue.trackIds = _remapAndDedupeIds(queue.trackIds, remap);
    }
    await _isar.playQueues.putAll(queues);
  }

  static List<int> _remapAndDedupeIds(List<int> ids, Map<int, int> remap) {
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

  static List<K> _duplicateKeys<T, K>(
    Iterable<T> items,
    K Function(T item) keyOf,
  ) {
    return _duplicateGroups(items, keyOf)
        .map((group) => keyOf(group.first))
        .toList();
  }

  static List<List<T>> _duplicateGroups<T, K>(
    Iterable<T> items,
    K Function(T item) keyOf,
  ) {
    final groups = <K, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(keyOf(item), () => <T>[]).add(item);
    }
    return groups.values.where((group) => group.length > 1).toList();
  }

  static Track _preferTrack(Track a, Track b) {
    final scoreA = _trackCompletenessScore(a);
    final scoreB = _trackCompletenessScore(b);
    if (scoreA != scoreB) return scoreA > scoreB ? a : b;
    return (a.updatedAt ?? a.createdAt).isAfter(b.updatedAt ?? b.createdAt)
        ? a
        : b;
  }

  static int _trackCompletenessScore(Track track) {
    var score = 0;
    if (track.audioUrl != null && track.audioUrl!.isNotEmpty) score += 8;
    if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
      score += 4;
    if (track.durationMs != null && track.durationMs! > 0) score += 2;
    if (track.artist != null && track.artist!.isNotEmpty) score += 1;
    if (track.playlistInfo.isNotEmpty) score += 1;
    return score;
  }

  static DownloadTask _preferDownloadTask(DownloadTask a, DownloadTask b) {
    final scoreA = _downloadTaskScore(a);
    final scoreB = _downloadTaskScore(b);
    if (scoreA != scoreB) return scoreA > scoreB ? a : b;
    return a.createdAt.isAfter(b.createdAt) ? a : b;
  }

  static int _downloadTaskScore(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.completed:
        return 4;
      case DownloadStatus.downloading:
        return 3;
      case DownloadStatus.pending:
        return 2;
      case DownloadStatus.paused:
        return 1;
      case DownloadStatus.failed:
        return 0;
    }
  }

  static Account _preferAccount(Account a, Account b) {
    if (a.isLoggedIn != b.isLoggedIn) {
      return a.isLoggedIn ? a : b;
    }
    final refreshedA =
        a.lastRefreshed ?? a.loginAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final refreshedB =
        b.lastRefreshed ?? b.loginAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return refreshedA.isAfter(refreshedB) ? a : b;
  }

  static PlayQueue _preferPlayQueue(PlayQueue a, PlayQueue b) {
    final updatedA = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
    final updatedB = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (!updatedA.isAtSameMomentAs(updatedB)) {
      return updatedA.isAfter(updatedB) ? a : b;
    }
    return a.trackIds.length >= b.trackIds.length ? a : b;
  }
}
