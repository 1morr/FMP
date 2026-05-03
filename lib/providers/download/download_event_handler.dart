import 'dart:async';

import '../../services/download/download_service.dart';

class DownloadEventHandler {
  DownloadEventHandler({
    required this.markFileExisting,
    required this.removeProgress,
    required this.downloadStateChanged,
    required this.showFailure,
    required this.debounceDuration,
  });

  final void Function(String path) markFileExisting;
  final void Function(int taskId) removeProgress;
  final void Function({
    required Iterable<String> savePaths,
    required Iterable<int> affectedPlaylistIds,
  }) downloadStateChanged;
  final void Function(DownloadFailureEvent event) showFailure;
  final Duration debounceDuration;

  final Set<int> _pendingPlaylistIds = <int>{};
  final List<String> _pendingSavePaths = <String>[];
  Timer? _debounceTimer;

  void handleCompletion(DownloadCompletionEvent event) {
    markFileExisting(event.savePath);
    removeProgress(event.taskId);

    _pendingSavePaths.add(event.savePath);
    final playlistId = event.playlistId;
    if (playlistId != null) {
      _pendingPlaylistIds.add(playlistId);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      Future.microtask(flushInvalidations);
    });
  }

  void handleFailure(DownloadFailureEvent event) {
    showFailure(event);
  }

  void flushInvalidations() {
    if (_pendingSavePaths.isEmpty && _pendingPlaylistIds.isEmpty) return;

    downloadStateChanged(
      savePaths: List.unmodifiable(_pendingSavePaths),
      affectedPlaylistIds: List.unmodifiable(_pendingPlaylistIds),
    );
    _pendingSavePaths.clear();
    _pendingPlaylistIds.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
