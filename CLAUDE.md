# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

FMP (Flutter Music Player) is a cross-platform music player supporting **Bilibili**, **YouTube**, and **NetEase Cloud Music (网易云音乐)** audio sources. Target platforms: Android and Windows.

## Documentation Maintenance

After significant code changes, update this file accordingly:

| Change Type | Section to Update |
|------------|-------------------|
| Audio architecture | "Audio System" |
| New model fields | "Data Models", "Database Migration" |
| New source / service | "File Structure", "Audio Sources" |
| Design decisions | "Key Design Decisions" |
| UI patterns | "UI Development Guidelines" |

Keep `.serena/memories/` for narrow supplemental notes only. Do not duplicate this file; when information becomes core/current, merge it here and delete the memory.

Current supplemental memories:
- `code_style.md` - coding style details not worth duplicating in this file
- `debugging_vm_service.md` - Flutter VM Service / DevTools API quick reference
- `download_system.md` - detailed download path, metadata, and Android storage notes
- `memory_usage_analysis.md` - memory/cache limits and profiling notes
- `refactoring_lessons.md` - non-obvious project-specific pitfalls
- `ui_coding_patterns.md` - detailed UI implementation patterns
- `update_system.md` - in-app update flow details

## Common Commands

```bash
flutter run                          # Run the app
flutter build apk                    # Android APK
flutter build windows                # Windows executable
flutter pub run build_runner build --delete-conflicting-outputs  # Isar code generation
dart run slang                       # Regenerate i18n files (after modifying lib/i18n/**/*.json)
flutter analyze                      # Static analysis
flutter test                         # Run tests
```

---

## Architecture

### Audio System (Three-Layer + Platform-Split)

```
UI (player_page, mini_player)
         │
         ▼
┌─────────────────────────────────────┐
│         AudioController             │  ← UI uses ONLY this
│   (audio_provider.dart)             │
│   - State management (PlayerState)  │
│   - Business logic                  │
│   - Temporary play, mute memory     │
└─────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│  AudioService   │  │  QueueManager   │
│  (abstract)     │  │ (queue logic)   │
└────────┬────────┘  │ Shuffle, loop   │
    ┌────┴────┐      │ Persistence     │
    ▼         ▼      └─────────────────┘
┌────────┐ ┌──────────┐
│just_   │ │media_kit │
│audio   │ │AudioSvc  │
│Service │ │(Desktop) │
│(Android│ │          │
│)       │ │          │
└────────┘ └──────────┘
```

**Key Rule:** UI must call `AudioController` methods, never `AudioService` directly.

**Platform-split backend:**
- **Android**: `JustAudioService` (ExoPlayer via `just_audio`, ~10-15MB lighter)
- **Windows/Linux**: `MediaKitAudioService` (libmpv via `media_kit`, supports device switching)
- `audioServiceProvider` selects implementation based on `Platform.isAndroid`
- `MediaKit.ensureInitialized()` only called on desktop platforms

**Custom types** (`audio_types.dart`):
- `FmpAudioProcessingState`, `FmpPlayerState`, `FmpAudioDevice`

**Volume conversion**: media_kit uses 0-100 range, just_audio uses 0-1 range.

### State Management: Riverpod

**Key providers:**
- `audioControllerProvider` - Main audio state (PlayerState)
- `playlistProvider` / `playlistDetailProvider` - Playlist management
- `searchProvider` - Search state (supports 3 sources)
- `neteaseSourceProvider` - NeteaseSource singleton
- `neteaseAccountProvider` / `neteaseAccountServiceProvider` - Netease account
- `lyricsSearchProvider` - Multi-source lyrics search (lrclib + netease + qqmusic)
- `audioSettingsProvider` - Audio quality settings

**Data Loading Patterns:**

| Source | Pattern | Example |
|--------|---------|---------|
| DB collection (multi-writer) | Isar `watchAll()` + `StateNotifier` | Playlists, radio, history |
| DB join query | `StateNotifier` + optimistic update | Playlist detail |
| File system scan | `FutureProvider` + `invalidate` | Downloaded page |
| API + cache | `CacheService` + `StreamProvider` | Home/explore rankings |
| Settings | `StateNotifier` + direct state update | Settings page |

**Rules:**
- Pages using `isLoading` must guard: `isLoading && data.isEmpty`
- FutureProvider: must `invalidate` after mutations
- Optimistic updates: must rollback on failure
- List/grid items: add `ValueKey(item.id)`

### Data Layer

- **Models:** Isar collections in `lib/data/models/`
- **Repositories:** CRUD operations in `lib/data/repositories/`
- **Sources:** Audio source parsers in `lib/data/sources/` (BilibiliSource, YouTubeSource, NeteaseSource, with unified SourceApiException base class)

**Data Models:**

| Model | Description |
|-------|-------------|
| Track | Song entity (bilibili/youtube/netease SourceType, isVip, originalSongId/originalSource, bilibiliAid populated on demand) |
| Playlist | Playlist (ownerName, ownerUserId, useAuthForRefresh) |
| PlayQueue | Play queue (Mix mode state, position persistence, volume persistence) |
| Settings | App settings (quality, auth, lyrics, refresh intervals, stream priority per source) |
| Account | Platform account (login state, VIP status) |
| RadioStation | Radio/live station |
| PlayHistory | Play history record |
| SearchHistory | Search history |
| DownloadTask | Download task |
| LyricsMatch | Lyrics match record (Track ↔ lrclib/netease/qqmusic) |
| LyricsTitleParseCache | AI-parsed title cache for video-source lyrics matching |

### Database Migration (Isar)

**⚠️ CRITICAL: When modifying Isar models, check whether migration logic is needed.**

Isar uses type default values for new fields on upgrade: `int` → `0`, `bool` → `false`, `String?` → `null`, `List` → `[]`.

**判断是否需要迁移：** 如果 Isar 的类型默认值与业务期望的默认值**一致**，则**不需要**迁移。例如 `bool isVip = false` — Isar 升级后自动为 `false`，与期望一致，无需迁移。只有当两者不一致时才需要（如 `useNeteaseAuthForPlay` 期望 `true` 但 Isar 给 `false`）。

**Migration function:** `_migrateDatabase()` in `lib/providers/database_provider.dart`

**When adding a new field:**
1. Modify the model in `lib/data/models/`
2. **判断是否需要迁移** — 若 Isar 默认值 ≠ 业务期望值，在 `_migrateDatabase()` 中添加修正逻辑
3. Run `flutter pub run build_runner build --delete-conflicting-outputs`
4. Test upgrade path: old version → new version

**Current migrated/default-repaired fields include:**
- `maxConcurrentDownloads`, `maxCacheSizeMB`, `audioQualityLevelIndex`, `downloadImageOptionIndex`
- `lyricsDisplayModeIndex`, `maxLyricsCacheFiles`, `lyricsSourcePriority`, `disabledLyricsSources`
- `lyricsAiTitleParsingModeIndex` (default `fallbackAfterRules`), `lyricsAiTimeoutSeconds` (default `10s`)
- `audioFormatPriority`, `youtubeStreamPriority`, `bilibiliStreamPriority`, `neteaseStreamPriority`
- `enabledSources`, `rankingRefreshIntervalMinutes`, `radioRefreshIntervalMinutes`
- `useNeteaseAuthForPlay` (default `true`, but Isar gives `false` on upgrade)
- Legacy default-signature repair for `rememberPlaybackPosition`, `tempPlayRewindSeconds`, and disabled lrclib auto-match defaults
- Legacy queue default repair for `PlayQueue.lastVolume`

---

## Audio Sources

### Bilibili (Direct Source)
- Video audio extraction (DASH audio-only / durl muxed)
- Multi-page video (多P) support
- Live room audio stream (HLS)
- Favorites folder import
- Requires `Referer: https://www.bilibili.com` header
- Audio URLs expire → periodic refresh via `ensureAudioUrl()`
- Rate limiting: codes -412, -509, -799

### YouTube (Direct Source)
- Video audio extraction (`youtube_explode_dart` + InnerTube API)
- YouTube Mix/Radio dynamic infinite playlists (RD prefix, InnerTube `/next` API)
- Playlist import via InnerTube `/browse` API
- **Stream format priority:** audio-only (androidVr) > muxed > HLS
- Only `YoutubeApiClient.androidVr` produces accessible audio-only URLs (others return 403)
- Supports Opus / AAC format selection
- Rate limiting: HTTP 429

### Netease Cloud Music (Direct Source)
- Song search (`/api/cloudsearch/pc`, plain form-encoded)
- Song detail + batch fetch (`/api/v3/song/detail`, max 400 per request)
- Audio stream (`/eapi/song/enhance/player/url/v1`, eapi encrypted, requires login)
- Playlist import (`/api/v6/playlist/detail` + batch song detail)
- Short URL resolution (`163cn.tv` → HEAD/GET redirect)
- VIP detection: `fee == 1 || fee == 4` → `Track.isVip = true`
- Availability: `st == -200` → unavailable
- Audio URL expiry: 16 minutes
- Requires `Referer: https://music.163.com/` header
- **Encryption:** `NeteaseCrypto` in `lib/core/utils/netease_crypto.dart` (eapi + weapi)
- **Account:** QR code login / WebView cookie extraction, MUSIC_U long-lived token
- Default `useNeteaseAuthForPlay = true` (most content requires login)

### External Playlist Import (Search-Match Mode)
- **Netease** - standard links / short links (`163cn.tv`)
- **QQ Music** - multiple URL formats, custom signature encryption (`QQMusicSign`)
- **Spotify** - Embed page parsing (`__NEXT_DATA__`), no auth needed

### Unified Source Exception Handling
`BilibiliApiException`, `YouTubeApiException`, and `NeteaseApiException` all extend `SourceApiException` (in `lib/data/sources/source_exception.dart`).

- `AudioController` catches `on SourceApiException` for unified error handling
- `_handleSourceError()` uses base class getters: `isUnavailable`, `isRateLimited`, `isGeoRestricted`
- `BilibiliApiException` uses `numericCode` (int) with semantic `code` getter
- `YouTubeApiException` uses `code` (String) directly
- `NeteaseApiException` uses `numericCode` (int), adds `isVipRequired` getter
- `SourceApiException.classifyDioError()` provides shared Dio error classification

### Audio Quality Settings
User-configurable per source:

- `AudioQualityLevel` enum: high, medium, low (global, all sources)
- `AudioFormat` enum: opus, aac (YouTube only — Bilibili/Netease only have AAC)
- `StreamType` enum: audioOnly, muxed, hls

**Per-source stream priority:**
- YouTube: audioOnly > muxed > hls
- Bilibili: audioOnly > muxed (live streams always muxed)
- Netease: audioOnly (only option)

`AudioStreamConfig` passed to source `getAudioUrl()`, returns `AudioStreamResult` with bitrate/codec info.

### Auth for Playback
Per-platform toggle for using login credentials when fetching audio streams:

| Setting | Default | Rationale |
|---------|---------|-----------|
| `useBilibiliAuthForPlay` | `false` | Most content accessible without login |
| `useYoutubeAuthForPlay` | `false` | Most content accessible without login |
| `useNeteaseAuthForPlay` | `true` | Most songs require login for audio URLs |

UI: Toggle button on each platform card in account management page. `FilledButton.tonal` when enabled, `OutlinedButton` when disabled.

Backend: `QueueManager.ensureAudioUrl()` / `DownloadService._startDownload()` read `settings.useAuthForPlay(track.sourceType)`.

### Lyrics System
Multi-source auto-match priority (`LyricsAutoMatchService.tryAutoMatch()`):

1. Existing match → use cache
2. Netease source track → direct lyrics fetch by `sourceId` (skip search)
3. Original platform ID direct fetch (imported `originalSongId` for netease/qqmusic)
4. User-configured enabled source order from `Settings.lyricsSourcePriorityList`
   - default order: Netease → QQ Music → lrclib
   - `disabledLyricsSources` are skipped (default disables lrclib for auto-match)
5. Manual lyrics search supports filters: All / Netease / QQ Music / lrclib

AI title parsing can improve Bilibili/YouTube auto-match by extracting likely song metadata from video titles. Modes: `off`, `fallbackAfterRules`, `alwaysForVideoSources`. Requests send only minimal metadata (title, artist/uploader, source type, duration) to the configured OpenAI-compatible endpoint, and successful parses are stored in `LyricsTitleParseCache` for reuse. AI output is used only to generate bounded candidate search terms; actual matching still queries the enabled lyrics sources and saves a normal source-backed `LyricsMatch` only when a source result passes matching rules.

Desktop lyrics popup window uses an independent Flutter engine and hide-instead-of-destroy lifecycle.

### Account System

| Platform | Login Method | Token |
|----------|-------------|-------|
| Bilibili | WebView cookie extraction | Cookie auto-refresh |
| YouTube | WebView cookie extraction | SAPISIDHASH |
| Netease | QR code / WebView cookie | MUSIC_U (long-lived) |

---

## Key Design Decisions

### Temporary Play
Click a song in search/playlist → plays temporarily without modifying queue. After completion, original queue position restored (minus 10 seconds).

- Uses `playTemporary()`, NOT `playTrack()`
- Saved state in `_context`: `savedQueueIndex`, `savedPosition`, `savedWasPlaying`
- Uses `_executePlayRequest()` with `mode: PlayMode.temporary`
- Position restore controlled by `rememberPlaybackPosition` setting

### PlaybackContext and Play Lock (Race Condition Prevention)
`AudioController` uses `_PlaybackContext` class to manage playback state and prevent race conditions.

```dart
enum PlayMode { queue, temporary, detached, mix }

class _PlaybackContext {
  final PlayMode mode;
  final int activeRequestId;  // > 0 = loading
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;
}
```

**Key rule:** Any method that fetches URLs outside `_executePlayRequest()` must:
1. Increment `_playRequestId` at start
2. Check `_isSuperseded(requestId)` after each `await`
3. Abort if superseded

### Radio Return and Ownership
Distinguishes **retained radio context** vs **active radio ownership of shared player**:
- `hasCurrentStation` = retaining radio context
- `hasActivePlaybackOwnership` = actually controlling player
- `isRadioPlayingProvider` exposes active ownership
- Home "Now Playing" uses retained context for tap actions
- `RadioController.play()` must pause music BEFORE setting radio loading state

### Mute Toggle
Must use `controller.toggleMute()`, NOT `setVolume(0)`. Remembers previous volume in `_volumeBeforeMute`.

### Shuffle Mode
Managed in `QueueManager` with `_shuffleOrder` list. UI must use `upcomingTracks`, never manually calculate next track.

### Mix Playlist Mode (YouTube Mix/Radio)
YouTube Mix/Radio playlists (ID starts with "RD") are dynamic infinite playlists.
- Shuffle disabled, addToQueue/addNext blocked
- Auto-loads more tracks near queue end
- State persisted via `PlayQueue` model fields

### Remember Playback Position
`Settings.rememberPlaybackPosition` (default `true`):
- **Saving:** always active (every 10s + on seek)
- **Restoring:** controlled by setting (app restart + temporary play restore)

### Progress Bar Dragging
Slider `onChanged` must NOT call `seekToProgress()`. Only call seek in `onChangeEnd`.

### Download System
- Path deduplication by `savePath` (not trackId)
- File verification before saving path
- Windows downloads run in an isolate and progress is kept in memory first (avoids PostMessage queue overflow and Isar watch churn)
- Audio, metadata, cover, and avatar live inside each video folder:
  - `audio.m4a` or `P{NN}.m4a`
  - `metadata.json` or `metadata_P{NN}.json`
  - `cover.jpg`
  - `avatar.jpg`
- Per-source `Referer` header: bilibili → `bilibili.com`, youtube → `youtube.com`, netease → `music.163.com`
- Android custom download directories require storage permission (`MANAGE_EXTERNAL_STORAGE` on Android 11+); default base dir is `Music/FMP` via external storage fallback logic.

### Playlist Import - Original Platform Song ID
Imported tracks save original platform song ID for direct lyrics fetch:
- `ImportedTrack.sourceId` → `Track.originalSongId` (Isar, nullable)
- `ImportedTrack.source` → `Track.originalSource` ("netease" / "qqmusic" / "spotify")

### Sub-Window Plugin Registration (Windows)
`desktop_multi_window` sub-windows use `RegisterPluginsForSubWindow()` which excludes `tray_manager` and `hotkey_manager` (global static C++ channels would overwrite main window). When adding new plugins, check for global static channel variables.

### Image Thumbnail Optimization
`ThumbnailUrlUtils` auto-optimizes image URLs by platform:
- Bilibili: `@{size}w_{size}h.jpg` suffix
- YouTube: quality tier (default/mq/hq/sd/maxres) + webp; small UI should pass size to avoid unavailable `maxresdefault`
- YouTube avatar: `=s{size}` parameter
- Netease: `?param={size}y{size}` parameter


## Claude Code Subagent Coordination

- **Root cause of the recent coordination failure**: when resuming a standalone spawned agent after review feedback, the follow-up message was sent to a human-friendly label instead of the actual resumable agent identity returned by the `Agent` tool result. The message appeared to send, but the implementer was not actually resumed to continue work.
- **Correct method**: for standalone `Agent(...)` subagents, prefer sending follow-up work to the exact `agentId` returned in the agent result when you need to resume a completed or idle agent. This is the most reliable resumable identifier.
- **Important distinction**: teammate names are for swarm/team workflows. For one-off spawned agents outside a team, treat the returned `agentId` as the source of truth for resuming work.
- **Verification rule**: after `SendMessage`, read the tool result carefully. If Claude reports only inbox delivery and you need immediate continued execution, resend to the actual `agentId` and confirm the result explicitly says the agent was resumed from transcript/background.
- **Do not mark delegation as active** until the messaging result confirms the intended agent has actually resumed.

---

## UI Development Guidelines

### Code Consistency ⚠️ CRITICAL

1. **Unified image components:**
   - Song cover → `TrackThumbnail` / `TrackCover`
   - Avatar → `ImageLoadingService.loadAvatar()`
   - Other images → `ImageLoadingService.loadImage()`
   - **NEVER** use `Image.network()` or `Image.file()` directly
   - Pass `width`/`height` or `targetDisplaySize` to `loadImage()` so thumbnail URL optimization selects reliable sizes

2. **FileExistsCache pattern:**
   ```dart
   ref.watch(fileExistsCacheProvider);  // watch for changes
   final cache = ref.read(fileExistsCacheProvider.notifier);
   final localPath = track.getLocalCoverPath(cache);
   ```

3. **Play state check** (unified logic):
   ```dart
   final currentTrack = ref.watch(currentTrackProvider);
   final isPlaying = currentTrack != null &&
       currentTrack.sourceId == track.sourceId &&
       currentTrack.pageNum == track.pageNum;
   ```

4. **Menu actions:** Reference `ExplorePage` or `HomePage` `_handleMenuAction`

5. **Refresh:** Use `RefreshIndicator` + `ref.invalidate()` or cache service

### AppBar Actions Trailing Spacing
All `AppBar` actions lists must end with `const SizedBox(width: 8)` when last action is `IconButton`. Not needed for `PopupMenuButton` (has built-in padding).

### ListTile Performance
**Avoid `Row` inside `ListTile.leading`** — causes layout jitter. Use flat `InkWell` + `Padding` + `Row` instead.

### UI Constants
All UI magic numbers centralized in `lib/core/constants/ui_constants.dart`:
`AppRadius`, `AnimationDurations`, `AppSizes`, `ToastDurations`, `DebounceDurations`.

Note: `AppRadius.borderRadiusXl` etc. are `static final` (not `const`), cannot use in `const` context.

---

## File Structure Highlights

```
lib/
├── services/
│   ├── audio/
│   │   ├── audio_provider.dart          # AudioController + PlayerState
│   │   ├── audio_service.dart           # Abstract AudioService interface
│   │   ├── media_kit_audio_service.dart # Desktop: media_kit (libmpv)
│   │   ├── just_audio_service.dart      # Android: just_audio (ExoPlayer)
│   │   ├── audio_types.dart             # Unified player state types
│   │   ├── audio_handler.dart           # Android notification (audio_service)
│   │   └── queue_manager.dart           # Queue, shuffle, loop, persistence
│   ├── account/
│   │   ├── bilibili_account_service.dart
│   │   ├── youtube_account_service.dart
│   │   ├── netease_account_service.dart  # QR login, cookie auth, MUSIC_U
│   │   └── netease_playlist_service.dart # User playlist operations
│   ├── lyrics/
│   │   ├── lyrics_auto_match_service.dart # Multi-source auto-match
│   │   ├── ai_title_parser.dart         # OpenAI-compatible video title parser
│   │   ├── lyrics_ai_config_service.dart # AI parser settings + secure API key
│   │   ├── lrclib_source.dart           # lrclib.net
│   │   ├── netease_source.dart          # Netease lyrics (search + fetch)
│   │   ├── qqmusic_source.dart          # QQ Music lyrics
│   │   ├── lyrics_cache_service.dart    # LRU cache
│   │   ├── lyrics_window_service.dart   # Desktop popup (hide-instead-of-destroy)
│   │   ├── lrc_parser.dart / title_parser.dart
│   │   └── lyrics_result.dart
│   ├── cache/
│   │   └── ranking_cache_service.dart   # Home ranking cache (hourly refresh)
│   ├── download/
│   │   ├── download_service.dart        # Task scheduling
│   │   ├── download_path_manager.dart   # Path selection
│   │   └── download_path_utils.dart     # Path calculation
│   ├── import/
│   │   ├── import_service.dart          # URL import (useAuth parameter)
│   │   └── playlist_import_service.dart # External playlist import (search-match)
│   ├── library/
│   │   └── remote_playlist_actions_service.dart # Remote playlist remove actions
│   ├── radio/                           # Live/radio control
│   └── update/                          # In-app update (GitHub Releases, APK/Windows installer/ZIP)
├── data/
│   ├── models/                          # Isar collections (includes lyrics_title_parse_cache.dart)
│   ├── repositories/                    # Data access layer (includes lyrics_title_parse_cache_repository.dart)
│   └── sources/
│       ├── base_source.dart             # Abstract base class
│       ├── source_exception.dart        # Unified SourceApiException
│       ├── bilibili_source.dart         # Bilibili audio source
│       ├── youtube_source.dart          # YouTube audio source
│       ├── netease_source.dart          # Netease audio source
│       ├── netease_exception.dart       # NeteaseApiException
│       ├── source_provider.dart         # SourceManager + providers
│       └── playlist_import/             # External playlist import sources
│           ├── netease_playlist_source.dart
│           ├── qq_music_playlist_source.dart
│           └── spotify_playlist_source.dart
├── core/
│   ├── constants/
│   │   ├── app_constants.dart           # App-level constants
│   │   └── ui_constants.dart            # UI constants
│   ├── utils/
│   │   ├── netease_crypto.dart          # Netease eapi/weapi encryption
│   │   └── thumbnail_url_utils.dart     # Image URL optimization
│   └── services/                        # Core services (Toast, ImageLoading)
├── ui/
│   ├── pages/
│   │   ├── home/                        # Home (quick actions, ranking preview)
│   │   ├── explore/                     # Explore (full rankings)
│   │   ├── search/                      # Search (3-source)
│   │   ├── player/                      # Full-screen player
│   │   ├── queue/                       # Play queue
│   │   ├── history/                     # Play history
│   │   ├── library/                     # Library, playlist detail, downloaded
│   │   ├── live_room/                   # Live room (lyrics search)
│   │   ├── radio/                       # Radio
│   │   └── settings/                    # Settings + sub-pages
│   │       ├── account_management_page.dart  # Multi-platform account
│   │       ├── bilibili_login_page.dart
│   │       ├── youtube_login_page.dart
│   │       ├── netease_login_page.dart  # QR code + WebView
│   │       ├── audio_settings_page.dart
│   │       └── ...
│   ├── widgets/                         # Shared widgets
│   ├── windows/                         # Sub-window entry points
│   └── layouts/                         # Responsive layouts
├── i18n/                                # zh-CN, zh-TW, en
├── providers/                           # Riverpod providers
├── app.dart                             # Router configuration
└── main.dart                            # Main entry point
```

## Responsive Breakpoints

- Mobile: < 600dp (bottom navigation)
- Tablet: 600-1200dp (side navigation)
- Desktop: > 1200dp (three-column layout)
