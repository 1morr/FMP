import '../../data/models/track.dart';

class RemotePlaylistEditFailure {
  final int trackId;
  final String remotePlaylistId;
  final Object error;

  const RemotePlaylistEditFailure({
    required this.trackId,
    required this.remotePlaylistId,
    required this.error,
  });
}

class RemotePlaylistEditSummary {
  final int changedPlaylistCount;
  final int addedTrackCount;
  final int removedTrackCount;
  final int skippedTrackCount;
  final int failedTrackCount;

  const RemotePlaylistEditSummary({
    required this.changedPlaylistCount,
    required this.addedTrackCount,
    required this.removedTrackCount,
    required this.skippedTrackCount,
    required this.failedTrackCount,
  });
}

class RemotePlaylistEditResult {
  final SourceType sourceType;
  final List<int> confirmedAddedTrackIds;
  final List<int> confirmedRemovedTrackIds;
  final List<int> skippedTrackIds;
  final List<RemotePlaylistEditFailure> failures;
  final List<String> changedRemotePlaylistIds;

  const RemotePlaylistEditResult({
    required this.sourceType,
    this.confirmedAddedTrackIds = const [],
    this.confirmedRemovedTrackIds = const [],
    this.skippedTrackIds = const [],
    this.failures = const [],
    this.changedRemotePlaylistIds = const [],
  });

  bool get changedRemote => changedRemotePlaylistIds.isNotEmpty;

  bool get hasFailures => failures.isNotEmpty;

  List<int> get failedTrackIds => failures
      .map((failure) => failure.trackId)
      .toSet()
      .toList(growable: false);

  RemotePlaylistEditSummary get summary => RemotePlaylistEditSummary(
        changedPlaylistCount: changedRemotePlaylistIds.toSet().length,
        addedTrackCount: confirmedAddedTrackIds.toSet().length,
        removedTrackCount: confirmedRemovedTrackIds.toSet().length,
        skippedTrackCount: skippedTrackIds.toSet().length,
        failedTrackCount: failedTrackIds.length,
      );

  RemotePlaylistEditResult merge(RemotePlaylistEditResult other) {
    assert(sourceType == other.sourceType);
    return RemotePlaylistEditResult(
      sourceType: sourceType,
      confirmedAddedTrackIds: {
        ...confirmedAddedTrackIds,
        ...other.confirmedAddedTrackIds,
      }.toList(),
      confirmedRemovedTrackIds: {
        ...confirmedRemovedTrackIds,
        ...other.confirmedRemovedTrackIds,
      }.toList(),
      skippedTrackIds: {...skippedTrackIds, ...other.skippedTrackIds}.toList(),
      failures: [...failures, ...other.failures],
      changedRemotePlaylistIds: {
        ...changedRemotePlaylistIds,
        ...other.changedRemotePlaylistIds,
      }.toList(),
    );
  }
}
