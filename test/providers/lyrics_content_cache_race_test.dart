import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/services/lyrics/netease_source.dart';

void main() {
  test('current lyrics content skips caching stale result after match changes',
      () async {
    final track = _track('video-1');
    final matches = StreamController<LyricsMatch?>.broadcast();
    final cache = _RecordingLyricsCacheService();
    final netease = _CompletingNeteaseSource();

    final container = ProviderContainer(
      overrides: [
        currentTrackProvider.overrideWithValue(track),
        currentLyricsMatchProvider.overrideWith((ref) => matches.stream),
        lyricsCacheServiceProvider.overrideWith((ref) => cache),
        neteaseSourceProvider.overrideWith((ref) => netease),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(matches.close);

    final subscription = container.listen(
      currentLyricsContentProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    matches.add(_match(track, 'old-id'));
    await _flushMicrotasks();
    expect(netease.calls, ['old-id']);

    matches.add(_match(track, 'new-id'));
    await _flushMicrotasks();
    expect(netease.calls, ['old-id', 'new-id']);

    netease.complete('old-id', _lyricsResult('old-id'));
    await _flushMicrotasks();

    expect(cache.saved, isEmpty);
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceType = SourceType.youtube
    ..sourceId = sourceId
    ..title = 'Video Title';
}

LyricsMatch _match(Track track, String externalId) {
  return LyricsMatch()
    ..trackUniqueKey = track.uniqueKey
    ..lyricsSource = 'netease'
    ..externalId = externalId;
}

LyricsResult _lyricsResult(String id) {
  return LyricsResult(
    id: id,
    trackName: 'Song',
    artistName: 'Artist',
    albumName: 'Album',
    duration: 180,
    instrumental: false,
    syncedLyrics: '[00:01.00]line',
    source: 'netease',
  );
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _RecordingLyricsCacheService extends LyricsCacheService {
  final List<({String key, String resultId})> saved = [];

  @override
  Future<LyricsResult?> get(String trackUniqueKey) async => null;

  @override
  Future<void> put(String trackUniqueKey, LyricsResult result) async {
    saved.add((key: trackUniqueKey, resultId: result.id));
  }
}

class _CompletingNeteaseSource extends NeteaseSource {
  final List<String> calls = [];
  final Map<String, Completer<LyricsResult?>> _completers = {};

  @override
  Future<LyricsResult?> getLyricsResult(String songId) {
    calls.add(songId);
    return _completers.putIfAbsent(songId, Completer<LyricsResult?>.new).future;
  }

  void complete(String songId, LyricsResult? result) {
    _completers[songId]!.complete(result);
  }
}
