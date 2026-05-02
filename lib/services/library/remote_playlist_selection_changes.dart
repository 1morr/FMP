({List<T> toAdd, List<T> toRemove}) computeRemotePlaylistSelectionChanges<T>({
  required Set<T> selectedIds,
  required Set<T> originalIds,
  required Set<T> deselectedPartialIds,
}) {
  return (
    toAdd: selectedIds.difference(originalIds).toList(),
    toRemove: [
      ...originalIds.difference(selectedIds),
      ...deselectedPartialIds,
    ],
  );
}

List<T> missingRemoteTrackIds<T>({
  required Iterable<T> allTrackIds,
  required Set<T> existingTrackIds,
}) {
  return allTrackIds
      .where((trackId) => !existingTrackIds.contains(trackId))
      .toList(growable: false);
}
