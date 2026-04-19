class MixPlaylistSession {
  MixPlaylistSession({
    required this.playlistId,
    required this.seedVideoId,
    required this.title,
    Set<String>? seenVideoIds,
  }) : seenVideoIds = seenVideoIds ?? {};

  final String playlistId;
  final String seedVideoId;
  final String title;
  final Set<String> seenVideoIds;

  bool isLoadingMore = false;

  void addSeenVideoIds(Iterable<String> ids) {
    seenVideoIds.addAll(ids);
  }
}

class MixPlaylistHandler {
  MixPlaylistSession? _current;

  MixPlaylistSession? get current => _current;

  MixPlaylistSession start({
    required String playlistId,
    required String seedVideoId,
    required String title,
  }) {
    _current = MixPlaylistSession(
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: title,
    );
    return _current!;
  }

  bool isCurrent(MixPlaylistSession session) => identical(_current, session);

  bool markLoading(MixPlaylistSession session) {
    if (!isCurrent(session) || session.isLoadingMore) {
      return false;
    }
    session.isLoadingMore = true;
    return true;
  }

  void finishLoading(MixPlaylistSession session) {
    if (isCurrent(session)) {
      session.isLoadingMore = false;
    }
  }

  void clear() {
    _current = null;
  }
}
