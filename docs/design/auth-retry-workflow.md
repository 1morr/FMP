# Implementation Workflow: Auth Retry for Private Content

Based on: `docs/design/auth-retry-private-content.md`

## Phase 1: Foundation Layer

### Step 1.1 — Exception: `isPermissionDenied`
**Files:** `source_exception.dart`, `bilibili_source.dart`, `youtube_source.dart`
**Changes:**
- Add `bool get isPermissionDenied;` to `SourceApiException`
- `BilibiliApiException`: `numericCode == -403`
- `YouTubeApiException`: `code == 'login_required' || code == 'private_or_inaccessible' || code == 'age_restricted'`
- Update `BilibiliApiException._mapCode`: add `-403 → 'permission_denied'`
**Depends on:** nothing
**Risk:** Low

### Step 1.2 — Auth Retry Utility
**Files:** `lib/core/utils/auth_retry_utils.dart` (new)
**Changes:**
- `getAuthHeadersForPlatform(SourceType, Ref)`
- `withAuthRetry<T>(action, platform, ref)` — Ref-based variant
- `withAuthRetryDirect<T>(action, getAuthHeaders)` — service-based variant
**Depends on:** 1.1
**Risk:** Low

## Phase 2: Bilibili Source Auth Support

### Step 2.1 — BilibiliSource `authHeaders` param
**File:** `bilibili_source.dart`
**Changes:**
- Add `_withAuth(Map<String, String> authHeaders)` helper (cookie merge)
- Add `authHeaders` optional param to: `getTrackInfo`, `getAudioStream`, `getAudioStreamWithCid`, `parsePlaylist`, `getVideoPages`, `getVideoDetail`, `refreshAudioUrl`
- Pass `options: authHeaders != null ? _withAuth(authHeaders) : null` to each `_dio` call
**Depends on:** 1.1
**Risk:** Low — mechanical changes, Dio handles header merging

### Step 2.2 — BaseSource interface update
**File:** `lib/data/sources/base_source.dart` (or wherever abstract signatures live)
**Changes:**
- Add `authHeaders` optional param to abstract method signatures
**Depends on:** 2.1
**Risk:** Low — may require updating other source implementations to match

## Phase 3: YouTube InnerTube Auth Fallback

### Step 3.1 — InnerTube `/player` for track info
**File:** `youtube_source.dart`
**Changes:**
- Add `_getTrackInfoViaInnerTube(videoId, authHeaders)` private method
- POST `/youtubei/v1/player` with WEB client context + auth headers
- Parse `videoDetails` → `Track`
- Route in `getTrackInfo()`: if `authHeaders != null` → InnerTube path
**Depends on:** 1.1
**Risk:** Medium — new InnerTube response parsing, needs testing with real private videos

### Step 3.2 — InnerTube `/player` for audio streams
**File:** `youtube_source.dart`
**Changes:**
- Add `_getAudioStreamViaInnerTube(videoId, authHeaders, config)` private method
- POST `/youtubei/v1/player` with androidVr client context + auth headers
- Parse `streamingData.adaptiveFormats` → select best audio stream
- Reuse existing quality/format selection logic where possible
- Route in `getAudioStream()`: if `authHeaders != null` → InnerTube path
**Depends on:** 1.1
**Risk:** Medium — stream format parsing, androidVr + auth combination untested

### Step 3.3 — InnerTube `/browse` for playlists
**File:** `youtube_source.dart`
**Changes:**
- Add `_parsePlaylistViaInnerTube(playlistId, authHeaders, page, pageSize)` private method
- POST `/youtubei/v1/browse` with `browseId: 'VL$playlistId'` + WEB client + auth headers
- Parse playlist contents, handle continuation tokens
- Route in `parsePlaylist()`: if `authHeaders != null` → InnerTube path
**Depends on:** 1.1
**Risk:** Medium — playlist response structure may differ from mix playlist parsing

### Step 3.4 — YouTube error code refinement
**File:** `youtube_source.dart`
**Changes:**
- In `getTrackInfo()` catch block: detect `VideoUnavailableException` → throw with code `'private_or_unavailable'` (distinct from `'unavailable'` for deleted videos)
- In `parsePlaylist()`: detect private playlist errors → throw with code `'private_or_inaccessible'`
- Ensure `isPermissionDenied` triggers correctly for these codes
**Depends on:** 3.1, 3.2, 3.3
**Risk:** Low — but needs real private content to verify error detection

## Phase 4: Caller Wiring — Services

### Step 4.1 — QueueManager auth injection
**File:** `queue_manager.dart`
**Changes:**
- Add `BilibiliAccountService?` and `YouTubeAccountService?` to constructor
- Add `_getAuthHeaders(SourceType)` helper method
- Wrap `source.getAudioStream()` and `source.refreshAudioUrl()` in `ensureAudioUrl()` with `withAuthRetryDirect`
**Depends on:** 1.2, 2.1, 3.2
**Risk:** Low

### Step 4.2 — ImportService auth injection
**File:** `import_service.dart`
**Changes:**
- Add account services to constructor
- Wrap `source.parsePlaylist()` in `importFromUrl()` and `refreshPlaylist()`
- Wrap `source.getVideoPages()` in `_expandMultiPageVideos()`
**Depends on:** 1.2, 2.1, 3.3
**Risk:** Low

### Step 4.3 — DownloadService auth injection
**File:** `download_service.dart`
**Changes:**
- Add account services to constructor
- Wrap `source.getAudioStream()` in `_startDownload()`
- Wrap `source.getVideoDetail()` for metadata fetch
**Depends on:** 1.2, 2.1, 3.2
**Risk:** Low

## Phase 5: Caller Wiring — UI/Providers

### Step 5.1 — TrackDetailProvider
**File:** `track_detail_provider.dart`
**Changes:**
- Wrap `source.getVideoDetail()` with `withAuthRetry` (Ref-based)
**Depends on:** 1.2, 2.1, 3.1
**Risk:** Low

### Step 5.2 — SearchPage video expansion
**File:** `search_page.dart`
**Changes:**
- Wrap `getVideoPages()` in `_loadVideoPages()` with `withAuthRetry`
**Depends on:** 1.2, 2.1
**Risk:** Low

### Step 5.3 — Provider wiring
**Files:** Provider definition files for QueueManager, ImportService, DownloadService
**Changes:**
- Pass `bilibiliAccountService` and `youtubeAccountService` to constructors
**Depends on:** 4.1, 4.2, 4.3
**Risk:** Low — but touches provider dependency graph

## Phase 6: Testing & Validation

### Step 6.1 — Test with Bilibili private content
- Import private favorites: `fid=3981100746`
- Play private video: `BV1Qkw1zMECR`
- Refresh imported playlist
- Download private video audio
**Depends on:** all previous

### Step 6.2 — Test with YouTube private content
- Import private playlist: `PLtTz-WrL9mKDXViXJsLYYWK0-KajdyPqb`
- Play private video: `_mpaMi0m3mc`
- Refresh imported playlist
- Download private video audio
**Depends on:** all previous

### Step 6.3 — Regression: public content still works
- Verify anonymous access unchanged for public videos/playlists
- Verify not-logged-in path: permission error propagates correctly
**Depends on:** all previous

## Dependency Graph

```
1.1 Exception ──┬── 1.2 Utility ──┬── 4.1 QueueManager ──┐
                │                 ├── 4.2 ImportService ──┤
                │                 ├── 4.3 DownloadService ┤
                │                 ├── 5.1 TrackDetail ────┤
                │                 └── 5.2 SearchPage ─────┤
                │                                         │
                ├── 2.1 Bilibili authHeaders ──┐          │
                │                              ├── 2.2 BaseSource
                ├── 3.1 YT InnerTube info ─────┤
                ├── 3.2 YT InnerTube stream ───┤
                ├── 3.3 YT InnerTube playlist ─┤
                └── 3.4 YT error codes ────────┘
                                                          │
                                               5.3 Provider wiring
                                                          │
                                               6.x Testing
```

## Parallelization Opportunities

- Phase 2 (Bilibili) and Phase 3 (YouTube) are independent — can be done in parallel
- Steps 4.1/4.2/4.3 are independent of each other
- Steps 5.1/5.2 are independent of each other
