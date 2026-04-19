# FMP Staged Refactor Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finalize the audio refactor by promoting the Phase 3 seams into stable collaborators while keeping `AudioController` as the only UI entry point and narrowing `QueueManager` to queue-domain work.

**Architecture:** Phase 4 is a parity-preserving promotion pass. Promote `QueuePersistenceHelpers`, `_PlaybackRequestExecutor`, `_TemporaryPlayStateHelper`, and `_MixSessionStateHelper` into stable files, and wrap the existing `AudioStreamDelegate` behind `AudioStreamManager` without deleting the delegate in this phase. `AudioController` remains the facade/coordinator; `QueueManager` keeps queue ordering, navigation, shuffle/loop, repository-backed queue mutations, timer lifecycle, and queue notifications, while persistence operations, stream work, request execution, temporary-play state, and Mix session ownership move out.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, flutter_test

---

## File Structure

- Create `lib/services/audio/audio_playback_types.dart` to hold `PlayMode` and `lib/services/audio/mix_playlist_types.dart` to hold `MixTracksFetcher`, so the new handlers do not import `audio_provider.dart`.
- Create `lib/services/audio/queue_persistence_manager.dart`, `lib/services/audio/audio_stream_manager.dart`, `lib/services/audio/playback_request_executor.dart`, `lib/services/audio/temporary_play_handler.dart`, and `lib/services/audio/mix_playlist_handler.dart`.
- Keep `lib/services/audio/internal/audio_stream_delegate.dart` in Phase 4 as the internal implementation behind `AudioStreamManager`.
- Retire `lib/services/audio/internal/queue_persistence_helpers.dart` after all imports are updated.
- Modify `lib/services/audio/audio_provider.dart` to import the shared type files, inject the new collaborators, and delete the file-local Phase 3 helpers.
- Modify `lib/services/audio/queue_manager.dart` to remove persistence helper ownership and direct stream/helper wiring while preserving queue-domain behavior plus timer lifecycle.
- Modify `test/services/audio/queue_persistence_helpers_test.dart`, `test/services/audio/audio_stream_delegate_test.dart`, `test/services/audio/playback_request_executor_test.dart`, `test/services/audio/temporary_play_handler_test.dart`, `test/services/audio/mix_session_handler_test.dart`, `test/services/audio/audio_controller_phase1_test.dart`, `test/services/audio/queue_manager_test.dart`, and `CLAUDE.md`.

---

### Task 0: Extract shared playback and Mix types before externalizing handlers

**Files:**
- Create: `lib/services/audio/audio_playback_types.dart`
- Create: `lib/services/audio/mix_playlist_types.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Add a compile-oriented guard by importing the new shared type files in the audio test**
```dart
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';

test('shared playback types are available outside audio_provider', () {
  expect(PlayMode.queue, isNotNull);
  MixTracksFetcher? fetcher;
  expect(fetcher, isNull);
});
```
- [ ] **Step 2: Run the test to verify it fails**
Run: `flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: compile/test failure because the shared type files do not exist yet.
- [ ] **Step 3: Create `lib/services/audio/audio_playback_types.dart`**
```dart
enum PlayMode {
  queue,
  temporary,
  detached,
  mix,
}
```
- [ ] **Step 4: Create `lib/services/audio/mix_playlist_types.dart`**
```dart
import '../../data/sources/youtube_source.dart';

typedef MixTracksFetcher = Future<MixFetchResult> Function({
  required String playlistId,
  required String currentVideoId,
});
```
- [ ] **Step 5: Rewire `audio_provider.dart` to import the shared types and remove the local definitions**
```dart
import 'audio_playback_types.dart';
import 'mix_playlist_types.dart';

// remove local typedef MixTracksFetcher
// remove local enum PlayMode
```
- [ ] **Step 6: Run the shared-type regression**
Run: `flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 7: Commit**
```bash
git add test/services/audio/audio_controller_phase1_test.dart lib/services/audio/audio_playback_types.dart lib/services/audio/mix_playlist_types.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): extract shared playback boundary types

Move PlayMode and MixTracksFetcher into shared files so externalized handlers can depend on stable types instead of audio_provider internals.
EOF
)"
```

---

### Task 1: Promote `QueuePersistenceHelpers` into `QueuePersistenceManager`

**Files:**
- Create: `lib/services/audio/queue_persistence_manager.dart`
- Modify: `lib/services/audio/queue_manager.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `test/services/audio/queue_persistence_helpers_test.dart`
- Modify: `test/services/audio/queue_manager_test.dart`
- Test: `test/services/audio/queue_persistence_helpers_test.dart`
- Test: `test/services/audio/queue_manager_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Expand the test harness and add the failing restore regression**
```dart
late TrackRepository trackRepository;
late QueuePersistenceManager manager;

setUp(() async {
  tempDir = await Directory.systemTemp.createTemp('queue_persistence_manager_');
  isar = await Isar.open(
    [TrackSchema, PlayQueueSchema, SettingsSchema],
    directory: tempDir.path,
    name: 'queue_persistence_manager_test',
  );
  queueRepository = QueueRepository(isar);
  settingsRepository = SettingsRepository(isar);
  trackRepository = TrackRepository(isar);
  currentQueue = await queueRepository.getOrCreate();
  manager = QueuePersistenceManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
  );
});

test('restoreState returns queue snapshot, saved position, volume, and mix metadata', () async {
  final first = await trackRepository.save(_track('queue-a', title: 'Queue A'));
  final second = await trackRepository.save(_track('queue-b', title: 'Queue B'));
  currentQueue
    ..trackIds = [first.id, second.id]
    ..currentIndex = 1
    ..lastPositionMs = 42000
    ..lastVolume = 0.6
    ..isMixMode = true
    ..mixPlaylistId = 'RDmix'
    ..mixSeedVideoId = 'seed-1'
    ..mixTitle = 'My Mix';
  await queueRepository.save(currentQueue);

  final restored = await manager.restoreState();

  expect(restored.tracks.map((track) => track.sourceId), ['queue-a', 'queue-b']);
  expect(restored.currentIndex, 1);
  expect(restored.savedPosition, const Duration(seconds: 42));
  expect(restored.savedVolume, 0.6);
  expect(restored.mixPlaylistId, 'RDmix');
  expect(restored.mixSeedVideoId, 'seed-1');
  expect(restored.mixTitle, 'My Mix');
});
```
- [ ] **Step 2: Add the failing lifecycle regression for timer ownership staying in `QueueManager`**
```dart
test('queue manager dispose still cancels its periodic saver after persistence promotion', () async {
  final manager = QueueManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: _FakeSourceManager(),
    queuePersistenceManager: persistenceManager,
  );

  await manager.initialize();
  manager.dispose();

  expect(() => manager.dispose(), returnsNormally);
});
```
- [ ] **Step 3: Run the tests to verify they fail**
Run: `flutter test test/services/audio/queue_persistence_helpers_test.dart && flutter test test/services/audio/queue_manager_test.dart`
Expected: compile/test failure because `QueuePersistenceManager` and the new constructor shape do not exist yet.
- [ ] **Step 4: Create `lib/services/audio/queue_persistence_manager.dart` and keep timer lifecycle in `QueueManager`**
```dart
class QueueRestoreState {
  const QueueRestoreState({
    required this.queue,
    required this.tracks,
    required this.currentIndex,
    required this.savedPosition,
    required this.savedVolume,
    required this.mixPlaylistId,
    required this.mixSeedVideoId,
    required this.mixTitle,
  });

  final PlayQueue queue;
  final List<Track> tracks;
  final int currentIndex;
  final Duration savedPosition;
  final double savedVolume;
  final String? mixPlaylistId;
  final String? mixSeedVideoId;
  final String? mixTitle;
}

class QueuePersistenceManager {
  QueuePersistenceManager({
    required QueueRepository queueRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
  })  : _queueRepository = queueRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository;

  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;

  Future<QueueRestoreState> restoreState() async {
    final queue = await _queueRepository.getOrCreate();
    final settings = await _settingsRepository.get();
    final tracks = queue.trackIds.isEmpty
        ? <Track>[]
        : await _trackRepository.getByIds(queue.trackIds);
    final currentIndex = tracks.isEmpty
        ? 0
        : queue.currentIndex.clamp(0, tracks.length - 1);
    final savedPosition = settings.rememberPlaybackPosition
        ? Duration(milliseconds: queue.lastPositionMs)
        : Duration.zero;
    return QueueRestoreState(
      queue: queue,
      tracks: tracks,
      currentIndex: currentIndex,
      savedPosition: savedPosition,
      savedVolume: queue.lastVolume,
      mixPlaylistId: queue.mixPlaylistId,
      mixSeedVideoId: queue.mixSeedVideoId,
      mixTitle: queue.mixTitle,
    );
  }

  Future<void> persistQueue(
    PlayQueue queue,
    List<Track> tracks,
    int currentIndex,
    Duration currentPosition,
  ) async {
    queue.trackIds = tracks.map((track) => track.id).toList();
    queue.currentIndex = tracks.isEmpty ? 0 : currentIndex;
    queue.lastPositionMs = currentPosition.inMilliseconds;
    queue.lastUpdated = DateTime.now();
    await _queueRepository.save(queue);
  }

  Future<void> savePositionNow(
    PlayQueue? queue,
    int currentIndex,
    Duration currentPosition,
  ) async {
    if (queue == null) return;
    queue.currentIndex = currentIndex;
    queue.lastPositionMs = currentPosition.inMilliseconds;
    await _queueRepository.save(queue);
  }

  Future<void> saveVolume(PlayQueue? queue, double volume) async {
    if (queue == null) return;
    queue.lastVolume = volume.clamp(0.0, 1.0);
    await _queueRepository.save(queue);
  }

  Future<void> setMixMode(
    PlayQueue? queue, {
    required bool enabled,
    String? playlistId,
    String? seedVideoId,
    String? title,
  }) async {
    if (queue == null) return;
    queue.isMixMode = enabled;
    queue.mixPlaylistId = enabled ? playlistId : null;
    queue.mixSeedVideoId = enabled ? seedVideoId : null;
    queue.mixTitle = enabled ? title : null;
    await _queueRepository.save(queue);
  }

  Future<({bool enabled, int restartRewindSeconds, int tempPlayRewindSeconds})>
      getPositionRestoreSettings() async {
    final settings = await _settingsRepository.get();
    return (
      enabled: settings.rememberPlaybackPosition,
      restartRewindSeconds: settings.restartRewindSeconds,
      tempPlayRewindSeconds: settings.tempPlayRewindSeconds,
    );
  }
}
```
- [ ] **Step 5: Rewire `QueueManager` without moving `_savePositionTimer` / `_startPositionSaver()` / `dispose()` timer cleanup**
```dart
final queuePersistenceManagerProvider = Provider<QueuePersistenceManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return QueuePersistenceManager(
    queueRepository: QueueRepository(db),
    trackRepository: TrackRepository(db),
    settingsRepository: SettingsRepository(db),
  );
});

QueueManager({
  required QueueRepository queueRepository,
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required QueuePersistenceManager queuePersistenceManager,
  BilibiliAccountService? bilibiliAccountService,
  YouTubeAccountService? youtubeAccountService,
  NeteaseAccountService? neteaseAccountService,
})  : _queueRepository = queueRepository,
      _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _sourceManager = sourceManager,
      _queuePersistenceManager = queuePersistenceManager,
      _bilibiliAccountService = bilibiliAccountService,
      _youtubeAccountService = youtubeAccountService,
      _neteaseAccountService = neteaseAccountService;

final restored = await _queuePersistenceManager.restoreState();
_currentQueue = restored.queue;
_tracks = restored.tracks;
_currentIndex = restored.currentIndex;
_currentPosition = restored.savedPosition;
if (isShuffleEnabled) {
  _generateShuffleOrder();
}
_startPositionSaver();

Future<void> savePositionNow() =>
    _queuePersistenceManager.savePositionNow(_currentQueue, _currentIndex, _currentPosition);
Future<void> saveVolume(double volume) =>
    _queuePersistenceManager.saveVolume(_currentQueue, volume);
Future<void> setMixMode({required bool enabled, String? playlistId, String? seedVideoId, String? title}) =>
    _queuePersistenceManager.setMixMode(_currentQueue, enabled: enabled, playlistId: playlistId, seedVideoId: seedVideoId, title: title);
Future<void> _persistQueue() => _currentQueue == null
    ? Future.value()
    : _queuePersistenceManager.persistQueue(_currentQueue!, _tracks, _currentIndex, _currentPosition);
```
- [ ] **Step 6: Run the persistence regressions**
Run: `flutter test test/services/audio/queue_persistence_helpers_test.dart && flutter test test/services/audio/queue_manager_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 7: Commit**
```bash
git add test/services/audio/queue_persistence_helpers_test.dart test/services/audio/queue_manager_test.dart lib/services/audio/queue_persistence_manager.dart lib/services/audio/queue_manager.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(queue): promote queue persistence manager

Move persistence operations out of QueueManager while keeping timer lifecycle in QueueManager and preserving restore, position, volume, and mix metadata behavior.
EOF
)"
```

### Task 2: Promote `AudioStreamDelegate` behind `AudioStreamManager`

**Phase-4 scope note:** In this phase, `AudioStreamManager` fully owns stream resolution, URL refresh, playback headers, and prefetch, while `AudioStreamDelegate` remains the internal implementation for `ensureAudioStream()` / fallback selection. `PlaybackRequestStreamAccess` is introduced in this task so Task 2 remains compilable on its own; Task 3 only consumes that already-defined contract.

**Files:**
- Create: `lib/services/audio/audio_stream_manager.dart`
- Modify: `lib/services/audio/queue_manager.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `test/services/audio/audio_stream_delegate_test.dart`
- Test: `test/services/audio/audio_stream_delegate_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Write the failing parity regression with explicit harness setup**
```dart
late AudioStreamManager manager;
late List<Track> queueTracks;

setUp(() async {
  queueTracks = <Track>[];
  manager = AudioStreamManager(
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: sourceManager,
    bilibiliAccountService: null,
    youtubeAccountService: null,
    neteaseAccountService: null,
    updateQueueTrack: (updatedTrack) => queueTracks[0] = updatedTrack,
  );
});

test('ensureAudioStream keeps local-file-first behavior and clears invalid download paths', () async {
  final savedTrack = await trackRepository.save(
    _track('stream-1', title: 'Stream One')
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 1
          ..playlistName = 'Playlist'
          ..downloadPath = '${tempDir.path}/missing-file.m4a',
      ],
  );
  queueTracks = [savedTrack];

  final (updatedTrack, localPath, streamResult) =
      await manager.ensureAudioStream(savedTrack);

  expect(localPath, isNull);
  expect(streamResult!.url, 'https://example.com/stream-1.m4a');
  expect(updatedTrack.playlistInfo.single.downloadPath, isEmpty);
});
```
- [ ] **Step 2: Run the test to verify it fails**
Run: `flutter test test/services/audio/audio_stream_delegate_test.dart`
Expected: compile/test failure because `AudioStreamManager` does not exist yet.
- [ ] **Step 3: Create `lib/services/audio/audio_stream_manager.dart` and define the stream-access contract here so Task 2 compiles independently**
```dart
abstract class PlaybackRequestStreamAccess {
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  });
  Future<Map<String, String>?> getPlaybackHeaders(Track track);
  Future<void> prefetchTrack(Track track);
}

class AudioStreamManager implements PlaybackRequestStreamAccess {
  AudioStreamManager({
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
    required BilibiliAccountService? bilibiliAccountService,
    required YouTubeAccountService? youtubeAccountService,
    required NeteaseAccountService? neteaseAccountService,
    required void Function(Track updatedTrack) updateQueueTrack,
  })  : _delegate = AudioStreamDelegate(
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
          sourceManager: sourceManager,
          getAuthHeaders: (sourceType) => buildAuthHeaders(
            sourceType,
            bilibiliAccountService: bilibiliAccountService,
            youtubeAccountService: youtubeAccountService,
            neteaseAccountService: neteaseAccountService,
          ),
          updateQueueTrack: updateQueueTrack,
        ),
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _bilibiliAccountService = bilibiliAccountService,
        _youtubeAccountService = youtubeAccountService,
        _neteaseAccountService = neteaseAccountService;

  final AudioStreamDelegate _delegate;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  final BilibiliAccountService? _bilibiliAccountService;
  final YouTubeAccountService? _youtubeAccountService;
  final NeteaseAccountService? _neteaseAccountService;
  final Set<int> _fetchingTrackIds = <int>{};

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) => _delegate.ensureAudioStream(
        track,
        retryCount: retryCount,
        persist: persist,
      );

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) => _delegate.getAlternativeAudioStream(track, failedUrl: failedUrl);

  Future<(Track, String?)> ensureAudioUrl(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    String? localPath;
    final invalidPaths = <String>[];

    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath = path;
        break;
      }
      invalidPaths.add(path);
    }

    if (localPath != null) {
      if (invalidPaths.isNotEmpty && persist) {
        track.playlistInfo = track.playlistInfo
            .map((info) => PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = invalidPaths.contains(info.downloadPath)
                  ? ''
                  : info.downloadPath)
            .toList();
        await _trackRepository.save(track);
      }
      return (track, localPath);
    }

    if (invalidPaths.isNotEmpty && persist) {
      track.playlistInfo = track.playlistInfo
          .map((info) => PlaylistDownloadInfo()
            ..playlistId = info.playlistId
            ..playlistName = info.playlistName
            ..downloadPath = '')
          .toList();
      await _trackRepository.save(track);
    }

    if (track.hasValidAudioUrl) {
      return (track, null);
    }

    final source = _sourceManager.getSource(track.sourceType)!;
    final settings = await _settingsRepository.get();
    final authHeaders = settings.useAuthForPlay(track.sourceType)
        ? await buildAuthHeaders(
            track.sourceType,
            bilibiliAccountService: _bilibiliAccountService,
            youtubeAccountService: _youtubeAccountService,
            neteaseAccountService: _neteaseAccountService,
          )
        : null;
    final refreshedTrack = await source.refreshAudioUrl(
      track,
      authHeaders: authHeaders,
    );
    if (persist) {
      await _trackRepository.save(refreshedTrack);
    }
    _updateQueueTrack(refreshedTrack);
    return (refreshedTrack, null);
  }

  Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
    return switch (track.sourceType) {
      SourceType.bilibili => {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      SourceType.youtube => {
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      SourceType.netease =>
        await _neteaseAccountService?.getAuthHeaders() ??
            {
              'Origin': 'https://music.163.com',
              'Referer': 'https://music.163.com/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
    };
  }

  Future<void> prefetchTrack(Track track) async {
    if (track.hasLocalAudio ||
        track.hasValidAudioUrl ||
        !_fetchingTrackIds.add(track.id)) {
      return;
    }
    try {
      await ensureAudioUrl(track);
    } finally {
      _fetchingTrackIds.remove(track.id);
    }
  }
}
```
- [ ] **Step 4: Preserve auth/header parity and define `QueueManager.replaceTrack()` before wiring**
```dart
void replaceTrack(Track updatedTrack) {
  final index = _tracks.indexWhere((track) => track.id == updatedTrack.id);
  if (index >= 0) {
    _tracks[index] = updatedTrack;
  }
}

final authHeaders = settings.useAuthForPlay(track.sourceType)
    ? await buildAuthHeaders(
        track.sourceType,
        bilibiliAccountService: _bilibiliAccountService,
        youtubeAccountService: _youtubeAccountService,
        neteaseAccountService: _neteaseAccountService,
      )
    : null;

return switch (track.sourceType) {
  SourceType.bilibili => {
      'Referer': 'https://www.bilibili.com',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  SourceType.youtube => {
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  SourceType.netease => await _neteaseAccountService?.getAuthHeaders() ?? {
      'Origin': 'https://music.163.com',
      'Referer': 'https://music.163.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
};
```
- [ ] **Step 5: Rewire all current consumers without deleting `audio_stream_delegate.dart` and inject the manager explicitly**
```dart
final audioStreamManagerProvider = Provider<AudioStreamManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final queueManager = ref.watch(queueManagerProvider);
  return AudioStreamManager(
    trackRepository: TrackRepository(db),
    settingsRepository: SettingsRepository(db),
    sourceManager: ref.watch(sourceManagerProvider),
    bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
    youtubeAccountService: ref.read(youtubeAccountServiceProvider),
    neteaseAccountService: ref.read(neteaseAccountServiceProvider),
    updateQueueTrack: queueManager.replaceTrack,
  );
});

class AudioController extends StateNotifier<PlayerState> with Logging {
  AudioController({
    required FmpAudioService audioService,
    required QueueManager queueManager,
    required AudioStreamManager audioStreamManager,
    required ToastService toastService,
    required FmpAudioHandler audioHandler,
    required WindowsSmtcHandler windowsSmtcHandler,
    ...
  })  : _audioService = audioService,
        _queueManager = queueManager,
        _audioStreamManager = audioStreamManager,
        _toastService = toastService,
        _audioHandler = audioHandler,
        _windowsSmtcHandler = windowsSmtcHandler,
        super(const PlayerState());

  final AudioStreamManager _audioStreamManager;
}

final controller = AudioController(
  audioService: audioService,
  queueManager: queueManager,
  audioStreamManager: ref.watch(audioStreamManagerProvider),
  toastService: toastService,
  audioHandler: audioHandler,
  windowsSmtcHandler: windowsSmtcHandler,
  ...
);

final (trackWithUrl, localPath) =
    await _audioStreamManager.ensureAudioUrl(currentTrack);
final headers = await _audioStreamManager.getPlaybackHeaders(trackWithUrl);
await _audioStreamManager.prefetchTrack(_queueManager.tracks[nextIndex]);
```
- [ ] **Step 6: Explicitly migrate every remaining `AudioController` stream consumer**
```dart
// _prepareCurrentTrack()
final (trackWithUrl, localPath) =
    await _audioStreamManager.ensureAudioUrl(track);

// _restoreQueuePlayback()
final (trackWithUrl, localPath) =
    await _audioStreamManager.ensureAudioUrl(currentTrack);

// _resumeWithFreshUrlIfNeeded()
if (track.audioUrl != null && !track.hasValidAudioUrl) {
  await _playTrack(track);
}

// fallback path inside _executePlayRequest()
final fallbackResult = await _audioStreamManager.getAlternativeAudioStream(
  track,
  failedUrl: attemptedUrl,
);
final headers = await _audioStreamManager.getPlaybackHeaders(track);
```
- [ ] **Step 7: Run the stream regressions**
Run: `flutter test test/services/audio/audio_stream_delegate_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 8: Commit**
```bash
git add test/services/audio/audio_stream_delegate_test.dart lib/services/audio/audio_stream_manager.dart lib/services/audio/queue_manager.dart lib/services/audio/audio_provider.dart
 git commit -m "$(cat <<'EOF'
refactor(audio): promote audio stream manager

Wrap the Phase 3 stream delegate behind a stable audio stream manager while preserving auth, header, fallback, and prefetch parity.
EOF
)"
```

### Task 3: Promote `_PlaybackRequestExecutor` into `PlaybackRequestExecutor`

**Files:**
- Create: `lib/services/audio/playback_request_executor.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `test/services/audio/playback_request_executor_test.dart`
- Test: `test/services/audio/playback_request_executor_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Replace the structural assertion with a failing direct executor test**
```dart
class _ExecutorHarnessAudioStreamManager {
  _ExecutorHarnessAudioStreamManager(this.headersGate);

  final Completer<void> headersGate;

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    return (
      track,
      null,
      AudioStreamResult(
        url: track.audioUrl!,
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      ),
    );
  }

  Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
    await headersGate.future;
    return {'Cookie': 'x'};
  }

  Future<void> prefetchTrack(Track track) async {}
}

test('execute aborts after async header resolution when superseded', () async {
  final headersGate = Completer<void>();
  var activeRequestId = 1;
  final streamManager = _ExecutorHarnessAudioStreamManager(headersGate);
  final executor = PlaybackRequestExecutor(
    audioService: audioService,
    audioStreamManager: streamManager,
    getNextTrack: () => null,
    isSuperseded: (requestId) => requestId != activeRequestId,
  );

  final future = executor.execute(
    requestId: 1,
    track: _track('first', title: 'First'),
    persist: true,
    prefetchNext: false,
  );

  activeRequestId = 2;
  headersGate.complete();

  expect(await future, isNull);
  expect(audioService.playUrlCalls, isEmpty);
});
```
- [ ] **Step 2: Run the test to verify it fails**
Run: `flutter test test/services/audio/playback_request_executor_test.dart`
Expected: compile/test failure because the external `PlaybackRequestExecutor` does not exist yet.
- [ ] **Step 3: Create `lib/services/audio/playback_request_executor.dart` using the contract already introduced in Task 2**
```dart
class PlaybackRequestExecution {
  const PlaybackRequestExecution({required this.track, required this.attemptedUrl, required this.streamResult});
  final Track track;
  final String attemptedUrl;
  final AudioStreamResult? streamResult;
}

class PlaybackRequestExecutor {
  PlaybackRequestExecutor({
    required FmpAudioService audioService,
    required PlaybackRequestStreamAccess audioStreamManager,
    required Track? Function() getNextTrack,
    required bool Function(int requestId) isSuperseded,
  })  : _audioService = audioService,
        _audioStreamManager = audioStreamManager,
        _getNextTrack = getNextTrack,
        _isSuperseded = isSuperseded;

  final FmpAudioService _audioService;
  final PlaybackRequestStreamAccess _audioStreamManager;
  final Track? Function() _getNextTrack;
  final bool Function(int requestId) _isSuperseded;

  Future<PlaybackRequestExecution?> execute({
    required int requestId,
    required Track track,
    required bool persist,
    required bool prefetchNext,
  }) async {
    final (trackWithUrl, localPath, streamResult) =
        await _audioStreamManager.ensureAudioStream(track, persist: persist);
    if (_isSuperseded(requestId)) return null;

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw StateError('No audio URL available for ${track.title}');
    }

    if (localPath != null) {
      await _audioService.playFile(url, track: trackWithUrl);
    } else {
      final headers = await _audioStreamManager.getPlaybackHeaders(trackWithUrl);
      if (_isSuperseded(requestId)) return null;
      await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
    }

    if (_isSuperseded(requestId)) return null;

    if (prefetchNext) {
      final nextTrack = _getNextTrack();
      if (nextTrack != null) {
        await _audioStreamManager.prefetchTrack(nextTrack);
      }
    }

    return PlaybackRequestExecution(
      track: trackWithUrl,
      attemptedUrl: url,
      streamResult: streamResult,
    );
  }
}
```
- [ ] **Step 4: Rewire `AudioController._executePlayRequest()`**
```dart
_playbackRequestExecutor = PlaybackRequestExecutor(
  audioService: _audioService,
  audioStreamManager: _audioStreamManager,
  getNextTrack: () {
    final nextIndex = _queueManager.getNextIndex();
    return nextIndex == null ? null : _queueManager.tracks[nextIndex];
  },
  isSuperseded: _isSuperseded,
);

final execution = await _playbackRequestExecutor.execute(
  requestId: requestId,
  track: track,
  persist: persist,
  prefetchNext: prefetchNext,
);
if (execution == null) return;
attemptedUrl = execution.attemptedUrl;
_exitLoadingState(
  requestId,
  execution.track,
  mode: mode,
  recordHistory: recordHistory,
  streamResult: execution.streamResult,
);
```
- [ ] **Step 5: Run the executor regressions**
Run: `flutter test test/services/audio/playback_request_executor_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit**
```bash
git add test/services/audio/playback_request_executor_test.dart lib/services/audio/playback_request_executor.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): externalize playback request executor

Promote the Phase 3 request executor into a typed stable collaborator while preserving supersede behavior.
EOF
)"
```

### Task 4: Promote the temporary-play seam into `TemporaryPlayHandler`

**Files:**
- Create: `lib/services/audio/temporary_play_handler.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `test/services/audio/temporary_play_handler_test.dart`
- Test: `test/services/audio/temporary_play_handler_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Write the failing restore-plan regression**
```dart
test('buildRestorePlan keeps original queue target across chained temporary play', () {
  const handler = TemporaryPlayHandler();
  final first = handler.enterTemporary(
    currentMode: PlayMode.queue,
    currentState: const TemporaryPlaybackState(),
    hasQueueTrack: true,
    currentIndex: 3,
    currentPosition: const Duration(seconds: 45),
    currentWasPlaying: true,
  );
  final second = handler.enterTemporary(
    currentMode: PlayMode.temporary,
    currentState: first,
    hasQueueTrack: true,
    currentIndex: 7,
    currentPosition: const Duration(seconds: 12),
    currentWasPlaying: false,
  );
  final plan = handler.buildRestorePlan(
    state: second,
    rememberPosition: true,
    rewindSeconds: 10,
  )!;
  expect(plan.savedIndex, 3);
  expect(plan.savedPosition, const Duration(seconds: 45));
  expect(plan.savedWasPlaying, isTrue);
});
```
- [ ] **Step 2: Run the test to verify it fails**
Run: `flutter test test/services/audio/temporary_play_handler_test.dart`
Expected: compile/test failure because `TemporaryPlayHandler.buildRestorePlan()` does not exist yet.
- [ ] **Step 3: Create `lib/services/audio/temporary_play_handler.dart`**
```dart
class TemporaryPlaybackState {
  const TemporaryPlaybackState({this.savedQueueIndex, this.savedPosition, this.savedWasPlaying});
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;
  bool get hasSavedState => savedQueueIndex != null;
}

class RestorePlaybackPlan {
  const RestorePlaybackPlan({required this.savedIndex, required this.savedPosition, required this.savedWasPlaying, required this.rewindSeconds});
  final int savedIndex;
  final Duration savedPosition;
  final bool savedWasPlaying;
  final int rewindSeconds;
}

class TemporaryPlayHandler {
  const TemporaryPlayHandler();

  TemporaryPlaybackState enterTemporary({
    required PlayMode currentMode,
    required TemporaryPlaybackState currentState,
    required bool hasQueueTrack,
    required int currentIndex,
    required Duration currentPosition,
    required bool currentWasPlaying,
  }) {
    if (currentMode == PlayMode.temporary) {
      return currentState;
    }
    if (!hasQueueTrack) {
      return const TemporaryPlaybackState();
    }
    return TemporaryPlaybackState(
      savedQueueIndex: currentIndex,
      savedPosition: currentPosition,
      savedWasPlaying: currentWasPlaying,
    );
  }

  RestorePlaybackPlan? buildRestorePlan({
    required TemporaryPlaybackState state,
    required bool rememberPosition,
    required int rewindSeconds,
  }) {
    if (!state.hasSavedState) {
      return null;
    }
    return RestorePlaybackPlan(
      savedIndex: state.savedQueueIndex!,
      savedPosition:
          rememberPosition ? (state.savedPosition ?? Duration.zero) : Duration.zero,
      savedWasPlaying: state.savedWasPlaying ?? false,
      rewindSeconds: rememberPosition ? rewindSeconds : 0,
    );
  }
}
```
- [ ] **Step 4: Rewire `AudioController` and explicitly write the handler state back into `_context`**
```dart
_temporaryPlayHandler = const TemporaryPlayHandler();
final nextState = _temporaryPlayHandler.enterTemporary(
  currentMode: _context.mode,
  currentState: TemporaryPlaybackState(
    savedQueueIndex: _context.savedQueueIndex,
    savedPosition: _context.savedPosition,
    savedWasPlaying: _context.savedWasPlaying,
  ),
  hasQueueTrack: _queueManager.currentTrack != null,
  currentIndex: _queueManager.currentIndex,
  currentPosition: _audioService.position,
  currentWasPlaying: _audioService.isPlaying,
);
_context = _context.copyWith(
  mode: PlayMode.temporary,
  savedQueueIndex: nextState.savedQueueIndex,
  savedPosition: nextState.savedPosition,
  savedWasPlaying: nextState.savedWasPlaying,
  clearSavedState: !nextState.hasSavedState,
);
final plan = _temporaryPlayHandler.buildRestorePlan(
  state: nextState,
  rememberPosition: positionSettings.enabled,
  rewindSeconds: positionSettings.tempPlayRewindSeconds,
);
if (plan != null) {
  await _restoreQueuePlayback(
    savedIndex: plan.savedIndex,
    savedPosition: plan.savedPosition,
    savedWasPlaying: plan.savedWasPlaying,
    rewindSeconds: plan.rewindSeconds,
    debugLabel: '_restoreSavedState',
    clearSavedState: true,
  );
}
```
- [ ] **Step 5: Run the temporary-play regressions**
Run: `flutter test test/services/audio/temporary_play_handler_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit**
```bash
git add test/services/audio/temporary_play_handler_test.dart lib/services/audio/temporary_play_handler.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): externalize temporary play handler

Promote the temporary-play seam into a stable handler with explicit restore-plan generation.
EOF
)"
```

### Task 5: Promote the Mix seam into `MixPlaylistHandler`

**Phase-4 scope note:** In this phase, `MixPlaylistHandler` becomes the owner of Mix session state, current session identity, loading-state gating, startup restore state, and exit cleanup parity. The actual remote fetch loop may still be orchestrated by `AudioController`, but the plan now treats that as controller-side orchestration over handler-owned session state rather than claiming full fetch ownership has already moved.

**Files:**
- Create: `lib/services/audio/mix_playlist_handler.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `test/services/audio/mix_session_handler_test.dart`
- Test: `test/services/audio/mix_session_handler_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Write the failing stale-session regression**
```dart
test('finishLoading ignores stale session and leaves active session loading', () {
  final handler = MixPlaylistHandler(
    fetchTracks: ({required playlistId, required currentVideoId}) async =>
        const MixFetchResult(title: 'Mix', tracks: []),
  );
  final first = handler.start(
    playlistId: 'RDmix-old',
    seedVideoId: 'seed-old',
    title: 'Old Mix',
  );
  final second = handler.start(
    playlistId: 'RDmix-new',
    seedVideoId: 'seed-new',
    title: 'New Mix',
  );
  handler.markLoading(second);
  handler.finishLoading(first);
  expect(second.isLoadingMore, isTrue);
  expect(handler.current, same(second));
  expect(handler.isCurrent(second), isTrue);
});
```
- [ ] **Step 2: Run the test to verify it fails**
Run: `flutter test test/services/audio/mix_session_handler_test.dart`
Expected: compile/test failure because `MixPlaylistHandler` does not exist yet.
- [ ] **Step 3: Create `lib/services/audio/mix_playlist_handler.dart` with the missing `current` getter**
```dart
class MixPlaylistSession {
  MixPlaylistSession({required this.playlistId, required this.seedVideoId, required this.title});
  final String playlistId;
  final String seedVideoId;
  final String title;
  final Set<String> seenVideoIds = <String>{};
  bool isLoadingMore = false;
  void addSeenVideoIds(Iterable<String> ids) => seenVideoIds.addAll(ids);
}

class MixPlaylistHandler {
  MixPlaylistHandler({required MixTracksFetcher fetchTracks})
      : _fetchTracks = fetchTracks;
  final MixTracksFetcher _fetchTracks;
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
```
- [ ] **Step 4: Rewire Mix entry/exit/load-more, startup restore, and queue guards**
```dart
_mixPlaylistHandler = MixPlaylistHandler(
  fetchTracks: _mixTracksFetcher ??
      ({required playlistId, required currentVideoId}) =>
          YouTubeSource().fetchMixTracks(
            playlistId: playlistId,
            currentVideoId: currentVideoId,
          ),
);

// startup restore parity inside initialize()
if (_queueManager.isMixMode &&
    _queueManager.mixPlaylistId != null &&
    _queueManager.mixSeedVideoId != null &&
    _queueManager.mixTitle != null) {
  if (_queueManager.isShuffleEnabled) {
    await _queueManager.setShuffle(false);
    state = state.copyWith(isShuffleEnabled: false);
  }
  final restoredSession = _mixPlaylistHandler.start(
    playlistId: _queueManager.mixPlaylistId!,
    seedVideoId: _queueManager.mixSeedVideoId!,
    title: _queueManager.mixTitle!,
  );
  restoredSession.addSeenVideoIds(
    _queueManager.tracks.map((track) => track.sourceId),
  );
  _context = _context.copyWith(mode: PlayMode.mix);
  state = state.copyWith(
    isMixMode: true,
    mixTitle: _queueManager.mixTitle,
  );
}

if (_mixPlaylistHandler.current != null) {
  _toastService.showInfo(t.audio.mixPlaylistNoAdd);
  return false;
}

final session = _mixPlaylistHandler.start(
  playlistId: playlistId,
  seedVideoId: seedVideoId,
  title: title,
);
session.addSeenVideoIds(tracks.map((track) => track.sourceId));
if (!_mixPlaylistHandler.markLoading(session)) return;
_context = _context.copyWith(mode: PlayMode.mix);
state = state.copyWith(
  isMixMode: true,
  mixTitle: title,
  isLoadingMoreMix: true,
);
try {
  final result = await (_mixTracksFetcher?.call(
        playlistId: session.playlistId,
        currentVideoId: _queueManager.tracks.last.sourceId,
      ) ??
      YouTubeSource().fetchMixTracks(
        playlistId: session.playlistId,
        currentVideoId: _queueManager.tracks.last.sourceId,
      ));
  if (_mixPlaylistHandler.isCurrent(session)) {
    final fresh = result.tracks
        .where((track) => !session.seenVideoIds.contains(track.sourceId))
        .toList();
    session.addSeenVideoIds(fresh.map((track) => track.sourceId));
    if (fresh.isNotEmpty) {
      await _queueManager.addAll(fresh);
      _updateQueueState();
    }
  }
} finally {
  _mixPlaylistHandler.finishLoading(session);
  if (_mixPlaylistHandler.isCurrent(session)) {
    state = state.copyWith(isLoadingMoreMix: false);
  }
}

// exit parity inside _exitMixMode()
_mixPlaylistHandler.clear();
_context = _context.copyWith(mode: PlayMode.queue);
await _queueManager.clearMixMode();
state = state.copyWith(
  isLoadingMoreMix: false,
  isMixMode: false,
  clearMixTitle: true,
);
```
- [ ] **Step 5: Run the Mix regressions**
Run: `flutter test test/services/audio/mix_session_handler_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit**
```bash
git add test/services/audio/mix_session_handler_test.dart lib/services/audio/mix_playlist_handler.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): externalize mix playlist handler

Promote the Mix session seam into a stable handler while preserving stale-session and loading-state protections.
EOF
)"
```

### Task 6: Cleanup, docs, and final verification

**Files:**
- Modify: `CLAUDE.md`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `lib/services/audio/queue_manager.dart`
- Modify: `test/services/audio/audio_stream_delegate_test.dart`
- Modify: `test/services/audio/queue_persistence_helpers_test.dart`

- [ ] **Step 1: Update `CLAUDE.md`**
```md
### Phase-4 Final Audio Boundary Note (2026-04-19)
- `AudioController` remains the only UI entry point and now delegates request execution, temporary-play state, and Mix session coordination.
- `QueueManager` keeps repository-backed queue mutations, ordering, shuffle/loop, timer lifecycle, and queue notifications.
- `AudioStreamManager` owns URL refresh, stream selection, playback headers, fallback streams, and prefetch while `AudioStreamDelegate` remains its Phase-4 internal implementation.
- `QueuePersistenceManager` owns queue snapshot restore/persist, playback position save/restore, and Mix persistence operations.
```
- [ ] **Step 2: Rename the manager-focused tests and remove only `queue_persistence_helpers.dart` after all imports are updated**
Run: `git mv test/services/audio/audio_stream_delegate_test.dart test/services/audio/audio_stream_manager_test.dart && git mv test/services/audio/queue_persistence_helpers_test.dart test/services/audio/queue_persistence_manager_test.dart && git rm lib/services/audio/internal/queue_persistence_helpers.dart`
Expected: `audio_stream_delegate.dart` remains in use under `AudioStreamManager`; only the persistence helper file is retired.
- [ ] **Step 3: Run the focused Phase 4 verification suite**
Run: `flutter test test/services/audio/queue_persistence_manager_test.dart && flutter test test/services/audio/audio_stream_manager_test.dart && flutter test test/services/audio/playback_request_executor_test.dart && flutter test test/services/audio/temporary_play_handler_test.dart && flutter test test/services/audio/mix_session_handler_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart && flutter test test/services/audio/queue_manager_test.dart && flutter test test/services/audio/audio_service_dispose_test.dart`
Expected: PASS.
- [ ] **Step 4: Run static analysis**
Run: `flutter analyze`
Expected: no new diagnostics in touched audio files.
- [ ] **Step 5: Commit**
```bash
git add CLAUDE.md lib/services/audio/audio_provider.dart lib/services/audio/queue_manager.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/queue_persistence_manager_test.dart
git commit -m "$(cat <<'EOF'
docs: record final audio boundary split

Document the final Phase 4 audio boundaries and verify the promoted managers and handlers before retiring the old persistence helper file.
EOF
)"
```

---

## Self-Review

- **Spec coverage:** each Phase 4 boundary from the approved design has a dedicated task, and `AudioController` plus `QueueManager` keep their intended public roles.
- **Placeholder scan:** no `TODO`, `TBD`, ellipsis placeholders, or undefined helper APIs remain in the plan body.
- **Type consistency:** the promoted types are introduced before later tasks use them, timer ownership is explicitly kept in `QueueManager`, and `AudioStreamDelegate` is no longer deleted prematurely.
