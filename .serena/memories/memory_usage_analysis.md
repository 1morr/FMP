# FMP Memory Usage Analysis

## Executive Summary

FMP is a Flutter music player with careful memory optimization across multiple layers:
- **Image caching**: 50-100 images, 15-30 MB (mobile/desktop)
- **Audio playback**: ~4-8 MB (libmpv with audio-only optimization)
- **Database**: 128 MB LMDB mmap (virtual address space, not all resident)
- **Queue**: In-memory list of Track objects (~1-2 KB per track)
- **Providers**: Riverpod state management with selective watching

---

## 1. Image Caching System

### Configuration (main.dart)
```dart
// Mobile: 50 images / 15 MB
// Desktop: 100 images / 30 MB
PaintingBinding.instance.imageCache.maximumSize = 50/100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 15/30 * 1024 * 1024;
```

### NetworkImageCacheService (lib/core/services/network_image_cache_service.dart)

**Key Features:**
- **Disk cache**: 7-day staleness period
- **Dynamic max objects**: `(maxCacheSizeMB * 1024 / 30).clamp(500, 10000)`
  - Assumes ~30 KB per optimized image
  - Mobile: 500-533 files, Desktop: 1000-1066 files
- **Preemptive cleanup**: Triggers at 90% capacity
- **Debounced trimming**: 300ms debounce to avoid excessive I/O
- **Isolate-based operations**: File scanning/deletion runs in background thread

**Memory Optimization:**
- `onImageLoaded()` called after each image loads
- Tracks estimated cache size in memory
- Triggers cleanup check every 50 images or when approaching 90% threshold
- Uses `compute()` to run file operations in separate Isolate (non-blocking)

**Cleanup Strategy:**
- Scans cache directory in Isolate
- Sorts files by modification time (LRU)
- Deletes oldest files until under limit
- Estimated file size: 50 KB (average after optimization)

---

## 2. Audio Playback (media_kit)

### MediaKitAudioService (lib/services/audio/media_kit_audio_service.dart)

**Memory Optimization:**
```dart
// Demuxer buffer sizes (optimized for audio-only)
bufferSize: Platform.isAndroid || Platform.isIOS
    ? 2 * 1024 * 1024   // 2 MB (mobile)
    : 4 * 1024 * 1024;  // 4 MB (desktop)
```

**libmpv Configuration (audio-only mode):**
```dart
// Disable video decoding completely
await nativePlayer.setProperty('vid', 'no');
await nativePlayer.setProperty('sid', 'no');

// Limit demuxer buffers
await nativePlayer.setProperty('demuxer-max-bytes', '1048576');      // 1 MB forward
await nativePlayer.setProperty('demuxer-max-back-bytes', '262144');  // 256 KB backward

// Disable extra caching
await nativePlayer.setProperty('cache', 'no');
```

**Memory Impact:**
- **Without optimization**: 200-400 MB (video frames decoded even if not rendered)
- **With optimization**: 4-8 MB (audio-only, no video decoding)
- **Muxed streams**: Still decoded but video frames discarded immediately (vid=no)

**State Management:**
- 11 BehaviorSubject streams (position, duration, volume, etc.)
- Each holds current value in memory
- Minimal overhead (~1-2 KB per stream)

**Subscriptions:**
- 11 stream subscriptions to media_kit events
- All properly disposed in `dispose()`
- No memory leaks if dispose is called

---

## 3. Database (Isar)

### Configuration (lib/providers/database_provider.dart)

```dart
Isar.open(
  [...schemas...],
  maxSizeMiB: 128,  // LMDB mmap size
  compactOnLaunch: CompactCondition(
    minFileSize: 8 * 1024 * 1024,  // Compact if > 8 MB
    minRatio: 2.0,                  // And > 50% fragmentation
  ),
)
```

**Memory Characteristics:**
- **LMDB mmap**: 128 MB virtual address space allocated
- **Resident memory**: Only accessed pages count toward RSS
- **Typical usage**: 10-30 MB resident (depends on query patterns)
- **Compaction**: Runs on startup if file > 8 MB and > 50% fragmented

**Collections:**
1. Track (largest)
2. Playlist
3. PlayQueue
4. Settings
5. SearchHistory
6. DownloadTask
7. PlayHistory
8. RadioStation
9. LyricsMatch

**Track Model Size:**
```dart
// Approximate per-track memory (Isar storage):
- id: 8 bytes
- sourceId: ~20 bytes (string)
- sourceType: 1 byte (enum)
- title: ~50 bytes (average)
- artist: ~30 bytes
- durationMs: 4 bytes
- thumbnailUrl: ~100 bytes
- audioUrl: ~200 bytes (can be large)
- playlistInfo: ~50 bytes per playlist (embedded list)
- Other fields: ~100 bytes
Total: ~600-800 bytes per track in database
```

**In-Memory Track Objects:**
- Queue holds List<Track> in memory
- Typical queue: 50-200 tracks
- Memory: 50-200 tracks × ~1-2 KB (Dart object overhead) = 50-400 KB

---

## 4. Queue Management (QueueManager)

### Data Structures (lib/services/audio/queue_manager.dart)

```dart
class QueueManager {
  List<Track> _tracks = [];           // Main queue
  int _currentIndex = 0;              // Current position
  List<int> _shuffleOrder = [];       // Shuffle permutation
  int _shuffleIndex = 0;              // Current position in shuffle
  Set<int> _fetchingUrlTrackIds = {}; // Prevent duplicate URL fetches
  Timer? _savePositionTimer;          // Position save timer
}
```

**Memory Usage:**
- **_tracks**: 50-200 tracks × 1-2 KB = 50-400 KB
- **_shuffleOrder**: Same size as _tracks (list of ints)
- **_fetchingUrlTrackIds**: Set of ints, typically 0-5 items
- **Total**: ~100-800 KB for typical queue

**Position Saving:**
- Saves every 10 seconds (AppConstants.positionSaveInterval)
- Only writes to database, doesn't hold extra memory
- Timer properly cancelled in dispose()

**URL Fetching:**
- Tracks which tracks are currently fetching URLs
- Prevents duplicate concurrent requests
- Set cleared after fetch completes

---

## 5. Riverpod Providers

### Key Providers (lib/providers/)

**Audio-related:**
- `audioControllerProvider` - Main audio state (PlayerState)
- `audioSettingsProvider` - Audio quality/format settings
- `playlistProvider` - Playlist list
- `playlistDetailProvider` - Single playlist with tracks
- `searchProvider` - Search results

**Memory Characteristics:**
- **StateNotifier**: Holds state in memory
- **FutureProvider**: Caches result until invalidated
- **StreamProvider**: Holds latest value
- **Selective watching**: UI only watches needed providers

### Playlist Provider (lib/providers/playlist_provider.dart)

```dart
class PlaylistDetailState {
  final Playlist playlist;
  final List<Track> tracks;  // Can be large (100-1000 tracks)
  final bool isLoading;
  final String? error;
}
```

**Memory Impact:**
- Playlist detail page loads all tracks into memory
- Typical: 100-500 tracks × 1-2 KB = 100-1000 KB
- Only one playlist detail loaded at a time (single provider)

### Search Provider

**Memory Pattern:**
- Holds search results in memory
- Typical: 20-50 results × 1-2 KB = 20-100 KB
- Results cleared when search changes

---

## 6. Startup Initialization

### main.dart Initialization Order

```dart
// 1. Image cache limits (immediate)
PaintingBinding.instance.imageCache.maximumSize = 50/100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 15/30 * 1024 * 1024;

// 2. Audio service (Android/iOS only)
audioHandler = await AudioService.init(...);

// 3. media_kit initialization
MediaKit.ensureInitialized();

// 4. Windows SMTC + WindowManager (parallel)
await Future.wait([
  _initializeSmtc(),
  _initializeWindowManager(),
]);

// 5. Background services (non-blocking)
RankingCacheService.instance.initialize();  // Background
RadioRefreshService.instance = RadioRefreshService();

// 6. i18n
LocaleSettings.useDeviceLocale();

// 7. App launch
runApp(ProviderScope(...));
```

**Memory Timeline:**
- **T=0**: Image cache limits set
- **T=0-100ms**: Audio service init (if mobile)
- **T=0-100ms**: media_kit init
- **T=0-200ms**: SMTC + WindowManager (parallel)
- **T=0-500ms**: App UI starts rendering
- **T=500ms+**: Background services load (non-blocking)

---

## 7. Memory Leak Prevention

### Proper Cleanup

**MediaKitAudioService.dispose():**
```dart
// Cancel all subscriptions
for (final subscription in _subscriptions) {
  await subscription.cancel();
}

// Close all controllers
await _completedController.close();
await _playerStateController.close();
// ... (11 controllers total)

// Dispose player
await _player.dispose();
```

**QueueManager.dispose():**
```dart
_savePositionTimer?.cancel();
_fetchingUrlTrackIds.clear();
_stateController.close();
```

**NetworkImageCacheService:**
- Debounce timer cancelled before new one created
- No persistent timers (all cancelled in cleanup)

### Subscription Management

**Pattern Used:**
```dart
final List<StreamSubscription> _subscriptions = [];

// Add subscription
_subscriptions.add(stream.listen(...));

// Cleanup
for (final subscription in _subscriptions) {
  await subscription.cancel();
}
```

---

## 8. Platform-Specific Optimizations

### Mobile (Android/iOS)

**Image Cache:**
- 50 images max
- 15 MB max size
- Smaller screen = fewer visible images

**Audio Buffer:**
- 2 MB demuxer buffer
- Assumes ~1 minute of 256 kbps audio

**Database:**
- Same 128 MB LMDB mmap
- Actual resident memory lower due to smaller queries

### Desktop (Windows/Linux/macOS)

**Image Cache:**
- 100 images max
- 30 MB max size
- Larger screen = more visible images

**Audio Buffer:**
- 4 MB demuxer buffer
- Assumes ~2 minutes of 256 kbps audio

**Database:**
- Same 128 MB LMDB mmap
- Larger resident memory due to more complex queries

---

## 9. Common Memory Issues & Solutions

### Issue: Image Cache Growing Unbounded
**Solution:** NetworkImageCacheService preemptive cleanup at 90% threshold
- Debounced to avoid excessive I/O
- Runs in Isolate to avoid UI blocking

### Issue: Queue Growing Too Large
**Solution:** AppConstants.maxQueueSize limit
- Prevents adding beyond limit
- Returns false if queue full

### Issue: Orphan Tracks Accumulating
**Solution:** _cleanupOrphanTracks() on startup
- Deletes tracks not in any playlist or queue
- Runs async, doesn't block initialization

### Issue: Position Save Blocking UI
**Solution:** Timer-based periodic saves
- Saves every 10 seconds
- Runs in background (Isar handles async)

### Issue: URL Fetching Duplicates
**Solution:** _fetchingUrlTrackIds set
- Tracks which tracks are currently fetching
- Prevents concurrent duplicate requests

---

## 10. Monitoring & Debugging

### Cache Statistics
```dart
final stats = await NetworkImageCacheService.getCacheStats();
// Returns: {
//   'sizeMB': '12.34',
//   'maxSizeMB': 30,
//   'stalePeriodDays': 7,
//   'maxNrOfCacheObjects': 1000,
// }
```

### Database Size
```dart
final sizeMB = await getCacheSizeMB();
```

### Memory Profiling
- Use Flutter DevTools Memory tab
- Check for growing object counts
- Monitor subscription count

---

## 11. Key Constants

### AppConstants (lib/core/constants/app_constants.dart)
- `maxQueueSize` - Queue size limit
- `positionSaveInterval` - Position save frequency (10 seconds)
- `audioServicePollingDelay` - Polling interval for audio state
- `seekDurationSeconds` - Skip forward/backward duration

### UI Constants (lib/core/constants/ui_constants.dart)
- `DebounceDurations.long` - 300ms (used for cache trimming)
- `DebounceDurations.standard` - 300ms (general debounce)

---

## 12. Best Practices for Developers

### When Adding New Features

1. **Image Loading**: Use `ImageLoadingService` (handles optimization)
2. **Database Queries**: Use indexed fields for large collections
3. **Streams**: Always cancel subscriptions in dispose()
4. **Timers**: Always cancel in dispose()
5. **Large Lists**: Consider pagination or virtual scrolling
6. **Caching**: Use Riverpod providers with proper invalidation

### Memory-Conscious Patterns

```dart
// ✓ Good: Selective watching
final data = ref.watch(provider.select((state) => state.data));

// ✗ Bad: Watching entire state
final state = ref.watch(provider);

// ✓ Good: Proper cleanup
@override
void dispose() {
  _subscription.cancel();
  _timer.cancel();
  super.dispose();
}

// ✗ Bad: No cleanup
// Subscriptions/timers leak
```

---

## Summary Table

| Component | Mobile | Desktop | Notes |
|-----------|--------|---------|-------|
| Image Cache | 15 MB / 50 imgs | 30 MB / 100 imgs | Preemptive cleanup at 90% |
| Audio Buffer | 2 MB | 4 MB | libmpv demuxer |
| LMDB mmap | 128 MB virtual | 128 MB virtual | Only accessed pages resident |
| Typical Queue | 50-200 tracks | 50-200 tracks | ~100-400 KB in memory |
| Playlist Detail | 100-500 tracks | 100-500 tracks | ~100-1000 KB in memory |
| Startup Time | ~500ms | ~500ms | Background services non-blocking |
| Resident Memory | 50-150 MB | 100-250 MB | Depends on usage patterns |
