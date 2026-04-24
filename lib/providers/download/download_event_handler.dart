import 'dart:async';

import 'package:path/path.dart' as p;

import '../../services/download/download_service.dart';

class DownloadEventHandler {
  DownloadEventHandler({
    required this.markFileExisting,
    required this.removeProgress,
    required this.invalidateCategories,
    required this.invalidateCategoryTracks,
    required this.refreshPlaylist,
    required this.showFailure,
    required this.debounceDuration,
  });

  final void Function(String path) markFileExisting;
  final void Function(int taskId) removeProgress;
  final void Function() invalidateCategories;
  final void Function(String categoryPath) invalidateCategoryTracks;
  final void Function(int playlistId) refreshPlaylist;
  final void Function(DownloadFailureEvent event) showFailure;
  final Duration debounceDuration;

  final Set<int> _pendingPlaylistIds = <int>{};
  final Set<String> _pendingCategoryPaths = <String>{};
  bool _categoriesNeedRefresh = false;
  Timer? _debounceTimer;

  void handleCompletion(DownloadCompletionEvent event) {
    markFileExisting(event.savePath);
    removeProgress(event.taskId);

    _categoriesNeedRefresh = true;
    _pendingCategoryPaths.add(p.dirname(p.dirname(event.savePath)));
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
    if (_categoriesNeedRefresh) {
      invalidateCategories();
      _categoriesNeedRefresh = false;
    }

    for (final categoryPath in _pendingCategoryPaths) {
      invalidateCategoryTracks(categoryPath);
    }
    _pendingCategoryPaths.clear();

    for (final playlistId in _pendingPlaylistIds) {
      refreshPlaylist(playlistId);
    }
    _pendingPlaylistIds.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
