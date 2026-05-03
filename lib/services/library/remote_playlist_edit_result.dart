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

  RemotePlaylistEditResult({
    required this.sourceType,
    List<int> confirmedAddedTrackIds = const [],
    List<int> confirmedRemovedTrackIds = const [],
    List<int> skippedTrackIds = const [],
    List<RemotePlaylistEditFailure> failures = const [],
    List<String> changedRemotePlaylistIds = const [],
  })  : confirmedAddedTrackIds = List.unmodifiable(confirmedAddedTrackIds),
        confirmedRemovedTrackIds = List.unmodifiable(confirmedRemovedTrackIds),
        skippedTrackIds = List.unmodifiable(skippedTrackIds),
        failures = List.unmodifiable(failures),
        changedRemotePlaylistIds = List.unmodifiable(changedRemotePlaylistIds);

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
    if (sourceType != other.sourceType) {
      throw ArgumentError.value(
        other.sourceType,
        'other.sourceType',
        'Cannot merge remote playlist edit results for different source types',
      );
    }

    return RemotePlaylistEditResult(
      sourceType: sourceType,
      confirmedAddedTrackIds: _dedupeInOrder([
        ...confirmedAddedTrackIds,
        ...other.confirmedAddedTrackIds,
      ]),
      confirmedRemovedTrackIds: _dedupeInOrder([
        ...confirmedRemovedTrackIds,
        ...other.confirmedRemovedTrackIds,
      ]),
      skippedTrackIds: _dedupeInOrder([
        ...skippedTrackIds,
        ...other.skippedTrackIds,
      ]),
      failures: [...failures, ...other.failures],
      changedRemotePlaylistIds: _dedupeInOrder([
        ...changedRemotePlaylistIds,
        ...other.changedRemotePlaylistIds,
      ]),
    );
  }
}

List<T> _dedupeInOrder<T>(Iterable<T> values) {
  return values.toSet().toList(growable: false);
}
