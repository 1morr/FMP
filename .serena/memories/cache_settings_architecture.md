# Cache Settings Architecture

## Overview
FMP has a two-tier cache system: **image cache** (network thumbnails) and **lyrics cache** (LRC files). Both are configurable via Settings page.

## Settings Model Fields
**File:** `lib/data/models/settings.dart`

```dart
// Image cache limit (default 32MB)
int maxCacheSizeMB = 32;

// Lyrics cache file limit (default 50 files)
int maxLyricsCacheFiles = 50;
```

Both fields are persisted to Isar database and survive app restarts.

---

## Image Cache System

### Architecture
```
Settings.maxCacheSizeMB (Isar)
         ↓
DownloadSettingsProvider (StateNotifier)
         ↓
NetworkImageCacheService (static methods)
         ↓
Flutter's ImageCache + disk cache (~/.cache/fmp_image_cache/)
```

### Key Components

#### 1. NetworkImageCacheService (`lib/core/services/network_image_cache_service.dart`)
Static service managing image cache lifecycle:

**Initialization (app startup):**
```dart
// Called in DownloadSettingsProvider._initialize()
NetworkImageCacheService.setMaxCacheSizeMB(_settings!.maxCacheSizeMB);
await NetworkImageCacheService.trimCacheIfNeeded(_settings!.maxCacheSizeMB);
await NetworkImageCacheService.initializeCacheSizeEstimate();
```

**Key Methods:**
- `setMaxCacheSizeMB(int value)` - Sets the limit (called on startup + when user changes setting)
- `trimCacheIfNeeded(int maxSizeMB)` - Deletes oldest files if cache exceeds limit (runs in background Isolate)
- `initializeCacheSizeEstimate()` - Reads actual cache size from disk for predictive cleanup
- `onImageLoaded({int estimatedFileSize = 50000})` - Called after each image loads; triggers periodic cleanup check
- `getCacheSizeMB()` - Returns current cache size in MB
- `getCacheSizeBytes()` - Returns current cache size in bytes
- `clearCache()` - Clears all cached images

**Cleanup Logic:**
- Triggered every 10 image loads (via `_loadCounter`)
- Uses LRU (Least Recently Used) eviction
- Runs in background Isolate to avoid UI blocking
- Deletes oldest files until cache < limit

#### 2. DownloadSettingsProvider (`lib/providers/download_settings_provider.dart`)
StateNotifier managing cache settings:

**Initialization:**
```dart
// Loads Settings from Isar, syncs to services
NetworkImageCacheService.setMaxCacheSizeMB(_settings!.maxCacheSizeMB);
_lyricsCacheService.setMaxCacheFiles(_settings!.maxLyricsCacheFiles);
await NetworkImageCacheService.trimCacheIfNeeded(_settings!.maxCacheSizeMB);
await NetworkImageCacheService.initializeCacheSizeEstimate();
```

**User Changes Setting:**
```dart
Future<void> setMaxCacheSizeMB(int value) async {
  if (value < 16) return; // Minimum 16MB
  
  // Save to Isar
  _settings!.maxCacheSizeMB = value;
  await _settingsRepository.updateSettings(_settings!);
  
  // Update state
  state = state.copyWith(maxCacheSizeMB: value);
  
  // Sync to service
  NetworkImageCacheService.setMaxCacheSizeMB(value);
  
  // Cleanup if needed
  await NetworkImageCacheService.trimCacheIfNeeded(value);
}
```

#### 3. ImageLoadingService (`lib/core/services/image_loading_service.dart`)
High-level image loading with cache integration:

```dart
// After image loads successfully
NetworkImageCacheService.onImageLoaded();
```

#### 4. Settings Page UI (`lib/ui/pages/settings/settings_page.dart`)

**Max Cache Size Tile:**
- Shows current limit (e.g., "32 MB")
- Tap opens dialog with radio options: 16, 32, 64, 128, 256 MB
- User selection calls `setMaxCacheSizeMB(value)`

**Clear Cache Tile:**
- Shows current cache usage (e.g., "2.5 MB")
- Tap shows confirmation dialog
- Calls `NetworkImageCacheService.clearCache()`

---

## Lyrics Cache System

### Architecture
```
Settings.maxLyricsCacheFiles (Isar)
         ↓
DownloadSettingsProvider (StateNotifier)
         ↓
LyricsCacheService (singleton)
         ↓
Disk cache (~/.cache/fmp_lyrics_cache/)
```

### Key Components

#### 1. LyricsCacheService (`lib/services/lyrics/lyrics_cache_service.dart`)
Manages LRC file cache with LRU eviction:

**Constants:**
```dart
static const int defaultMaxCacheFiles = 50;
static const int maxCacheSizeBytes = 5 * 1024 * 1024; // 5MB total
```

**Initialization:**
```dart
// Called in DownloadSettingsProvider._initialize()
_lyricsCacheService.setMaxCacheFiles(_settings!.maxLyricsCacheFiles);
```

**Key Methods:**
- `setMaxCacheFiles(int value)` - Updates limit and evicts if needed
- `put(String key, String content)` - Saves LRC file (with LRU eviction)
- `get(String key)` - Retrieves cached LRC
- `remove(String key)` - Removes a specific cached LRC (used when re-matching lyrics)
- `getStats()` - Returns cache statistics (file count, total size, limits)
- `clear()` - Clears all cached lyrics

**Eviction Logic:**
- Tracks file access time (LRU)
- When adding new file: evicts oldest if `fileCount >= maxCacheFiles`
- When changing limit: evicts oldest if `fileCount > maxCacheFiles`
- Also respects 5MB total size limit

#### 2. DownloadSettingsProvider Integration
```dart
Future<void> setMaxLyricsCacheFiles(int value) async {
  if (_settings == null) return;
  
  // Save to Isar
  _settings!.maxLyricsCacheFiles = value;
  await _settingsRepository.updateSettings(_settings!);
  
  // Update state
  state = state.copyWith(maxLyricsCacheFiles: value);
  
  // Sync to service
  await _lyricsCacheService.setMaxCacheFiles(value);
}
```

#### 3. Settings Page UI
**Max Lyrics Cache Files Tile:**
- Shows current limit (e.g., "50 files")
- Tap opens dialog with radio options: 10, 25, 50, 100, 200 files
- User selection calls `setMaxLyricsCacheFiles(value)`

---

## Data Flow: User Changes Cache Setting

### Image Cache Example (32MB → 64MB)
1. User taps "Max Cache Size" in Settings
2. Dialog shows options: 16, 32, 64, 128, 256 MB
3. User selects 64 MB
4. `setMaxCacheSizeMB(64)` called:
   - Saves to `Settings.maxCacheSizeMB` in Isar
   - Updates `DownloadSettingsProvider` state
   - Calls `NetworkImageCacheService.setMaxCacheSizeMB(64)`
   - Calls `NetworkImageCacheService.trimCacheIfNeeded(64)` (no-op if already < 64MB)
5. UI updates to show "64 MB"

### Lyrics Cache Example (50 → 100 files)
1. User taps "Max Lyrics Cache" in Settings
2. Dialog shows options: 10, 25, 50, 100, 200 files
3. User selects 100 files
4. `setMaxLyricsCacheFiles(100)` called:
   - Saves to `Settings.maxLyricsCacheFiles` in Isar
   - Updates `DownloadSettingsProvider` state
   - Calls `_lyricsCacheService.setMaxCacheFiles(100)`
   - Service evicts oldest files if needed (no-op if already ≤ 100 files)
5. UI updates to show "100 files"

---

## Cache Cleanup Triggers

### Image Cache
1. **App Startup:** `trimCacheIfNeeded()` called in `DownloadSettingsProvider._initialize()`
2. **User Changes Setting:** `trimCacheIfNeeded()` called in `setMaxCacheSizeMB()`
3. **Periodic (Every 10 images):** `onImageLoaded()` triggers cleanup check
4. **Manual Clear:** User taps "Clear Cache" button

### Lyrics Cache
1. **App Startup:** `setMaxCacheFiles()` called in `DownloadSettingsProvider._initialize()`
2. **User Changes Setting:** `setMaxCacheFiles()` called in `setMaxLyricsCacheFiles()`
3. **New File Added:** `put()` method evicts if needed
4. **Manual Clear:** User taps "Clear Lyrics Cache" button (if available)

---

## Important Notes

### Minimum Limits
- Image cache: **16 MB minimum** (enforced in `setMaxCacheSizeMB()`)
- Image cache: `maxNrOfCacheObjects` is dynamically calculated from `maxCacheSizeMB` (~30KB per file, clamped 500-10000)
- Lyrics cache: **10 files minimum** (UI only offers 10+)
- Lyrics cache: `_loadAccessTimes()` cleans ghost entries (files deleted externally) on startup
- Lyrics cache: `remove()` method used in `saveMatch()` to clear stale cache before writing new match

### Disk Locations
- Image cache: `~/.cache/fmp_image_cache/` (managed by Flutter's ImageCache)
- Lyrics cache: `~/.cache/fmp_lyrics_cache/` (custom implementation)

### Performance
- Image cache cleanup runs in background Isolate (non-blocking)
- Lyrics cache cleanup is synchronous but fast (small files)
- Predictive cleanup: `initializeCacheSizeEstimate()` reads actual size for better predictions

### Persistence
- Both settings saved to Isar `Settings` model
- Survive app restarts
- Synced to services on app startup

---

## Related Files
- `lib/data/models/settings.dart` - Settings model with cache fields
- `lib/core/services/network_image_cache_service.dart` - Image cache service
- `lib/services/lyrics/lyrics_cache_service.dart` - Lyrics cache service
- `lib/providers/download_settings_provider.dart` - Settings provider
- `lib/ui/pages/settings/settings_page.dart` - Settings UI
- `lib/core/services/image_loading_service.dart` - Image loading integration
