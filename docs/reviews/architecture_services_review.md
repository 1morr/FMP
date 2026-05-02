# Architecture and Cross-Cutting Services Review

Scope: service boundaries, source-specific duplication, error/result handling, provider invalidation, and small shared helpers that would reduce drift. This review is intentionally focused on simplification opportunities; no production code was changed.

## Summary

The codebase already has several good separation points: `AudioController` delegates URL selection to `AudioStreamManager` / `PlaybackRequestExecutor`, source exceptions share `SourceApiException`, and playlist providers have a small invalidation helper. The remaining complexity is mostly cross-cutting logic that exists in multiple layers at once: playlist membership synchronization, HTTP/header policy, error classification, and UI refresh side effects.

## Findings

### P0

No P0 architecture issues found.

### P1: Remote/import playlist persistence duplicates playlist membership logic

**Evidence**

- `ImportService.importFromUrl()` manually creates or updates playlists, looks up tracks by source identity, adds `Track.playlistInfo`, writes individual tracks, mutates `playlist.trackIds`, updates cover, and saves the playlist in one flow: `lib/services/import/import_service.dart:198-331`.
- `ImportService.refreshPlaylist()` repeats the same identity lookup/linking loop, then computes removed tracks and performs orphan cleanup: `lib/services/import/import_service.dart:461-602`.
- `PlaylistService` already has transaction-oriented methods for the same domain operation (`addTrackToPlaylist`, `addTracksToPlaylist`) including dedupe and metadata merge: `lib/services/library/playlist_service.dart:287-423`.
- `TrackRepository` also has `getOrCreate` / `getOrCreateAll` with similar source identity and metadata completeness logic: `lib/data/repositories/track_repository.dart:268-421`.

**Why it matters**

The import refresh path is a second implementation of "sync this playlist's desired track set into Isar". That increases the chance of drift in identity rules (`sourceId + sourceType + cid`), metadata merge rules, orphan deletion, cover updates, and transaction boundaries. It also keeps `ImportService` responsible for both remote parsing and local persistence semantics.

**Recommendation**

Move the local persistence part into one shared service/repository method, for example:

- `PlaylistService.syncTracksFromRemote(playlistId, desiredTracks, {platformCoverUrl}) -> PlaylistSyncResult`
- or a smaller `PlaylistTrackMembershipService` that owns link/add/remove/orphan cleanup.

Then `ImportService` should only:

1. detect source and parse playlist,
2. expand Bilibili multi-page videos,
3. call the shared sync method,
4. emit progress.

This is the highest-value simplification because it removes the largest duplicated write path and makes future playlist changes safer.

### P1: Network and source error classification has multiple competing paths

**Evidence**

- Generic app error wrapping classifies `DioException` in `ErrorHandler.wrap()`: `lib/core/errors/app_exception.dart:76-189`, plus `ErrorHandler.isNetworkError()`: `lib/core/errors/app_exception.dart:212-220`.
- Source-specific classification exists separately in `SourceApiException.classifyDioError()`: `lib/data/sources/source_exception.dart:53-85`.
- Each direct source maps the classified result back to its own exception shape: Bilibili `lib/data/sources/bilibili_source.dart:777-805`, YouTube `lib/data/sources/youtube_source.dart:1867-1874`, Netease `lib/data/sources/netease_source.dart:747-772`.
- `AudioController` still has string-based network detection for non-source errors: `lib/services/audio/audio_provider.dart:1989-2001`.

**Why it matters**

The semantic categories are mostly the same (`timeout`, `network_error`, `rate_limited`, `forbidden`, unavailable), but they are encoded in several ways: `AppException` classes, source exception booleans, source numeric codes, source string codes, and string matching. This makes behavior hard to reason about when deciding whether to retry, skip, or show a blocking error.

**Recommendation**

Introduce a single small error classifier enum, e.g. `AppErrorKind { network, timeout, rateLimited, unavailable, permissionDenied, loginRequired, geoRestricted, vipRequired, unknown }`.

- Let `SourceApiException` expose `kind` while retaining source-specific code fields for diagnostics.
- Let `ErrorHandler` and source `_handleDioError()` share the same Dio-to-kind mapping.
- Replace `AudioController._isNetworkError()` with kind-based checks, falling back to `ErrorHandler.isNetworkError()` only for non-Dio/non-source errors.

This keeps source-specific details without duplicating cross-cutting retry/skip decisions.

### P1: Header, auth, and HTTP client policy is spread across playback, download, sources, and account services

**Evidence**

- Playback media headers are built in `AudioStreamManager.getPlaybackHeaders()`: `lib/services/audio/audio_stream_manager.dart:180-200`.
- Download media headers duplicate the same source switch with slightly different Netease auth merge logic: `lib/services/download/download_media_headers.dart:4-35`.
- Auth headers are built in `buildAuthHeaders()`: `lib/core/utils/auth_headers_utils.dart:8-31`.
- `HttpClientFactory` exists to centralize Dio defaults: `lib/core/utils/http_client_factory.dart:5-35`, but many services still instantiate raw `Dio(BaseOptions(...))` or `Dio()` with repeated user agents and referers, e.g. `lib/services/download/download_service.dart:144-152`, `lib/services/account/bilibili_favorites_service.dart:45-58`, `lib/services/account/youtube_playlist_service.dart:50-65`, and playlist import sources such as `lib/data/sources/playlist_import/netease_playlist_source.dart:119-131`.

**Why it matters**

FMP relies on source-specific `Referer`, `Origin`, `User-Agent`, and cookie behavior. When playback, download, import, account operations, and lyrics each define these independently, small changes can fix one path while silently regressing another.

**Recommendation**

Create a source HTTP/header policy layer, for example `SourceHttpPolicy`:

- `apiHeaders(sourceType)`
- `mediaHeaders(sourceType, {authHeaders})`
- `authHeaders(sourceType)` or an `AuthHeaderProvider`
- named user-agent constants by platform/use case (browser, Netease desktop, QQ mobile, YouTube Android client when needed)

Then make `AudioStreamManager`, `DownloadService`, account playlist services, and playlist import sources consume this policy. This is a small helper, not a new framework, and it would reduce header drift substantially.

### P1: Provider invalidation and refresh side effects are scattered across service/provider boundaries

**Evidence**

- `PlaylistListNotifier.invalidatePlaylistProviders()` centralizes some playlist invalidation: `lib/providers/playlist_provider.dart:176-191`.
- Detail mutations still invalidate cover/list providers inline: add/remove/batch remove/reorder paths at `lib/providers/playlist_provider.dart:411-501`.
- Refresh success invalidates detail, cover, and all-playlists separately: `lib/providers/refresh_provider.dart:184-187`.
- Download completion has its own debounced invalidation and silent playlist refresh path: `lib/providers/download/download_event_handler.dart:52-67`.
- Remote playlist refresh is fired-and-forgotten and swallows errors: `lib/providers/remote_playlist_sync_provider.dart:16-23`.

**Why it matters**

The same domain event (playlist changed, cover may have changed, downloaded state changed) is expressed differently depending on who caused it. That makes it easy to forget one invalidation path and hard to know which layer owns UI refresh.

**Recommendation**

Create a small UI-side coordinator for domain mutations, not a production service dependency inside repositories. For example:

- `PlaylistProviderInvalidator.playlistChanged(playlistId, {coverChanged, tracksChanged, includeAll})`
- `DownloadInvalidator.downloadCompleted(savePath, playlistId)`

Then providers and event handlers call the same coordinator. Also make remote sync return/log refresh failures instead of `catchError((_) => null)` so failed background reconciliation is visible.

### P2: Import/progress/cancellation plumbing is duplicated

**Evidence**

- Direct URL import defines `ImportProgress`, `ImportStatus`, cancel flags, and a progress controller: `lib/services/import/import_service.dart:20-61`, `lib/services/import/import_service.dart:109-123`, `lib/services/import/import_service.dart:738-758`.
- Search-match playlist import defines a second `ImportProgress`, `ImportPhase`, cancel flags, and progress controller: `lib/services/import/playlist_import_service.dart:32-54`, `lib/services/import/playlist_import_service.dart:115-124`, `lib/services/import/playlist_import_service.dart:1135-1137`.
- Refresh manager creates per-refresh `ImportService` instances and bridges progress into refresh state: `lib/providers/refresh_provider.dart:121-167`.

**Recommendation**

Use a tiny shared `ProgressJob<TStatus>` / `CancellationToken` helper for long-running operations. It should only own `StreamController`, current progress, cancellation, and safe close. Keep statuses domain-specific if desired, but remove duplicated controller/cancel boilerplate.

### P2: URL parsing and short-link resolution is duplicated across sources and remote playlist helpers

**Evidence**

- Remote playlist IDs are parsed in `RemotePlaylistIdParser`: `lib/services/library/remote_playlist_id_parser.dart:4-35`.
- YouTube has a separate private playlist parser: `lib/data/sources/youtube_source.dart:150-157`.
- Netease direct source resolves short URLs and then calls the shared parser: `lib/data/sources/netease_source.dart:648-682`.
- Netease playlist import has another short-link resolver and parser path: `lib/data/sources/playlist_import/netease_playlist_source.dart:25-32`, `lib/data/sources/playlist_import/netease_playlist_source.dart:68-99`.
- QQ Music and Spotify playlist import each implement the same redirect-following pattern: `lib/data/sources/playlist_import/qq_music_playlist_source.dart:96-113`, `lib/data/sources/playlist_import/spotify_playlist_source.dart:70-87`.

**Recommendation**

Centralize URL parsing and redirect resolution into source-specific URL utilities:

- `SourceUrlParser.parseTrackId/parsePlaylistId/isPlaylistUrl`
- `ShortUrlResolver.resolve(url, allowedHosts/maxRedirects)`

Then `BaseSource`, playlist import sources, and remote sync/actions can share the same canonical parsing behavior.

### P2: SourceManager owns concrete construction and consumers downcast sources

**Evidence**

- `SourceManager` constructs all sources directly: `lib/data/sources/source_provider.dart:10-18`.
- Source-specific providers retrieve and downcast from the manager: `lib/data/sources/source_provider.dart:157-173`.
- Some services branch on concrete source types for extra capabilities, such as Bilibili multi-page expansion in import: `lib/services/import/import_service.dart:206-224`, and Mix handling for YouTube: `lib/services/import/import_service.dart:187-196`.

**Recommendation**

Keep `SourceManager`, but register source instances through providers and expose optional capability interfaces instead of concrete type checks where possible:

- `MultiPageVideoSource.expandPages(...)`
- `DynamicPlaylistSource.getMixPlaylistInfo/fetchMixTracks(...)`
- `RemotePlaylistCapableSource` if remote add/remove grows.

This makes new source additions less likely to require edits in generic import/playback services.

## What to simplify first

1. **Extract playlist track synchronization from `ImportService` into `PlaylistService` or a dedicated membership service.** This removes the largest duplicated write path and clarifies service boundaries.
2. **Unify error kinds and replace string-based network detection.** This makes retry/skip/login/rate-limit behavior easier to reason about.
3. **Centralize source HTTP/header policy.** Playback and download are sensitive to referer/auth drift, so this reduces subtle regressions.
4. **Create one provider invalidation coordinator for playlist/download mutations.** This is a small UI-layer cleanup that will make future feature work safer.
5. **Then clean up URL parsing and progress-job boilerplate.** These are lower risk and can be done incrementally.
