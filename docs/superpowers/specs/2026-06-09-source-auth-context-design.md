# Source Auth Context Design

Date: 2026-06-09
Status: Approved design, revised after review, not implemented

## Summary

Refactor auth and media handoff policy into a broader `SourceAuthContext`
Module. The refactor mostly changes where decisions live, but it intentionally
changes a few auth gates to match the desired policy:

- Search does not use account auth.
- Track detail follows `useAuthForPlay`.
- Import multi-page expansion follows the import auth choice.

The current Implementation spreads auth decisions across stream resolution,
playback handoff, download, search, import, and track detail callers. Each caller
must know some combination of account credential loading, settings gates,
purpose-specific auth rules, source media headers, and Netease media credential
allowlists. That makes the existing Modules shallow: deleting one helper mostly
moves the same decisions back into callers.

`SourceAuthContext` creates one deeper seam where callers ask for intent-specific
auth policy. Account services remain credential adapters. `SourceHttpPolicy`
remains the pure source header and URL allowlist policy helper.

## Goals

- Preserve current runtime behavior except for the approved auth gate changes
  listed in the summary.
- Concentrate source auth decisions in one Module with a purpose-oriented
  Interface.
- Make `useAuthForPlay` the shared gate for stream resolution, playback
  handoff, download, track detail, and auth-aware metadata/detail service paths.
- Keep playlist import auth separate from `useAuthForPlay`.
- Keep search unauthenticated.
- Keep source API auth and media request auth distinct.
- Keep media request credentials narrower than stream-resolution auth.
- Make security behavior testable at the same seam callers use.
- Reduce direct caller dependency on `buildAuthHeaders()`,
  `getAuthHeadersForPlatform()`, settings gates, and playback redirect
  preflight details.

## Non-Goals

- Do not change default auth settings.
- Do not expand Bilibili or YouTube credentials to media/CDN requests.
- Do not change the Netease media credential allowlist.
- Do not redesign account login, secure storage, source adapters, or search
  behavior.
- Do not move pure source header constants out of `SourceHttpPolicy`.
- Do not pull account-owned radio import or debug pages into
  `SourceAuthContext`.

## Existing Friction

Current callers know too much:

| Area | Current auth/header behavior |
| --- | --- |
| Stream resolution | `DefaultStreamResolutionService` reads `settings.useAuthForPlay(sourceType)` and loads auth before building `AudioStreamRequest`. |
| Playback handoff | `AudioStreamManager` repeats playback auth setting logic, builds media headers, preflights Netease redirects, and strips credentials after unsafe redirect. |
| Download | `DownloadService` constructs its own stream resolution service in some paths, passes stream auth into the isolate, separately gates download metadata detail auth, and uses wrapper functions for media/image headers. |
| Search | `SearchService.loadVideoPagesForTrack()` directly loads Bilibili auth for page lookup; normal online search stays unauthenticated. Desired behavior is no account auth for search, including page lookup. |
| Import | `ImportService` directly loads auth only when `useAuth` or `playlist.useAuthForRefresh` is set. Multi-page expansion currently does not pass auth. Desired behavior is for import expansion to follow the same import auth choice. |
| Track detail | `TrackDetailNotifier` loads auth unconditionally for network detail. Download metadata detail uses `useAuthForPlay`. Desired behavior is for all track detail to follow `useAuthForPlay`. |

These rules are valid but scattered. The missing locality is the reason this
candidate is worth deepening.

## Chosen Approach

Use the broader Approach C: a `SourceAuthContext` Module covering playback,
download, track detail, auth-aware metadata/detail service paths, import,
refresh, and media handoff auth policy. Search is explicitly unauthenticated, so
it should not gain a
`SourceAuthContext` dependency except where removing old direct auth calls
requires a small cleanup.

This has more scope than a playback-only `MediaHandoffPolicy`, but it avoids a
new shallow facade that leaves import/detail callers with direct auth knowledge.
The key constraint is that the Interface must be purpose-oriented so different
auth gates do not collapse into one generic "get headers" method.

## Module Shape

### External Seam

`SourceAuthContext` is the seam callers use for source auth policy.

Proposed Interface:

```dart
abstract interface class SourceAuthContext {
  Future<Map<String, String>?> authForPlay(SourceType sourceType);

  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  );

  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  });

  Map<String, String> imageHeaders(SourceType sourceType);

  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  });

  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  });

  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  });
}
```

`authForPlay()` is intentionally shared by stream resolution, playback handoff,
download, track detail, and auth-aware metadata/detail service paths. Import and
refresh keep separate methods because their gates are not `useAuthForPlay`.

### Internal Adapters

- `AccountAuthLoader`: wraps `BilibiliAccountService`,
  `YouTubeAccountService`, and `NeteaseAccountService`.
- `SettingsRepository`: remains the source of playback/download auth settings.
- `PlaybackHandoffPolicy`: internal Implementation detail for Netease redirect
  preflight and `includeCredentials` decisions.
- `SourceHttpPolicy`: pure source header defaults and URL allowlist predicates.
- Test adapters: fake auth loader, fake settings repository or settings gate,
  fake playback URL resolver.

One adapter for production plus fake adapters in tests makes the seam real. The
main leverage is that callers exercise policy through the same Interface tests
use.

## Behavior Rules

The first implementation must implement these rules:

| Purpose | Gate | Auth loaded | Media credential behavior |
| --- | --- | --- | --- |
| Stream resolution for playback/download/prefetch/refresh | `settings.useAuthForPlay(sourceType)` via `authForPlay()` | Source account auth when enabled | Auth passed only to source stream resolution, not directly to media requests. |
| Auth-aware app service paths that fetch source track metadata/detail | `settings.useAuthForPlay(sourceType)` via `authForPlay()` | Source account auth when enabled | Not media headers. |
| Playback media handoff | `settings.useAuthForPlay(sourceType)` via `authForPlay()` | Source account auth when enabled | `SourceHttpPolicy.mediaHeaders()` remains final media allowlist; only Netease allowlisted HTTPS URLs can receive cookies. |
| Download stream and media isolate | `settings.useAuthForPlay(sourceType)` via stream resolution | Source account auth when enabled | Each redirect hop recalculates media headers for that hop URL. |
| Image fetch/download | No credential gate | No credentials | Image headers never include credential cookies. |
| Library page playlist import | Import dialog `useAuth` switch | Source account auth only when true | Used for playlist parsing and import multi-page expansion. Not media headers. |
| Account page playlist import | Always auth | Source account auth | Used for playlist parsing and import multi-page expansion. Not media headers. |
| Playlist refresh | `playlist.useAuthForRefresh` | Source account auth only when true | Not media headers. |
| Track detail, including Now Playing and download metadata detail | `settings.useAuthForPlay(sourceType)` via `authForPlay()` | Source account auth when enabled | Not media headers. |
| Search, including Bilibili page lookup | No auth | None | Not media headers. |
| External playlist search-match import (`PlaylistImportService`) | No source account auth in current design | None | Not media headers. |
| YouTube Mix dynamic loading | No source account auth in current design | None | Not media headers. |
| Bilibili live/radio playback and account radio import | Existing radio/account ownership | Not part of `SourceAuthContext` | Live media headers remain in `SourceHttpPolicy.bilibiliLiveHeaders()`. |
| Debug pages | Explicit debug/account calls | Not part of production policy | Not covered by this refactor. |

## Data Flow

### Stream Resolution

`DefaultStreamResolutionService` receives `SourceAuthContext` instead of an
`AuthHeadersLoader`. When it builds an `AudioStreamRequest`, it calls
`authForPlay(track.sourceType)`. Quality fallback and source-specific
stream behavior remain unchanged.

Existing `SourceManager.parseUrl()` and `SourceManager.refreshAudioUrl()`
capability helpers remain unauthenticated. If a future app service needs
auth-aware source track metadata lookup, add an explicit auth-aware path that
uses `SourceAuthContext.authForPlay()` instead of loading account services
directly from `source_provider.dart`.

### Playback Handoff

`AudioStreamManager` no longer reads settings or account services. After a
remote URL is selected, it calls `playbackNetworkRequest(track, url)` and passes
the returned URL and headers to the backend.

Netease redirect preflight moves behind `SourceAuthContext` as an internal
Implementation detail. If redirect probing fails or redirects away from the
allowlist, credentials are stripped exactly as they are today.

### Download

`DownloadService` uses the shared `StreamResolutionService`, then passes the
resolved auth headers into the isolate as it does today. The isolate cannot use
Riverpod, account services, or the context object; it calls a pure/static media
header helper for each redirect hop.

Download metadata detail auth uses `authForPlay(sourceType)`.

Image metadata downloads call `imageHeaders(sourceType)`.

### Search, Import, Track Detail

Search does not request account auth. `SearchService.loadVideoPagesForTrack()`
continues to use `PagedVideoSource`, but stops passing Bilibili auth headers.

`ImportService.importFromUrl()` calls `playlistImportAuth(..., useAuth: useAuth)`.
Library page import passes the dialog switch. Account page import already passes
`useAuth: true` and should keep doing so.

`ImportService.refreshImportedPlaylist()` calls
`playlistRefreshAuth(..., useAuthForRefresh: playlist.useAuthForRefresh)`.
Import multi-page expansion uses the same auth headers selected for the import
or refresh operation.

`TrackDetailNotifier` calls
`authForPlay(track.sourceType)`.

## SourceHttpPolicy Responsibilities

Keep `SourceHttpPolicy` pure and source-oriented:

- Source referer/origin/user-agent defaults.
- `apiHeaders()`, `mediaHeaders()`, `imageHeaders()`,
  `imageHeadersForUrl()`.
- Netease media credential allowlist via
  `canAttachNeteaseMediaCredentials()`.
- Bilibili live headers and API Dio construction.

`SourceHttpPolicy` should not read settings or account services. It should not
know why a caller wants headers.

## Security Invariants

- Bilibili and YouTube account credentials are used for source API and stream
  URL resolution only.
- Bilibili and YouTube account credentials never reach media/CDN headers.
- Netease media credentials attach only when all are true:
  - source type is Netease
  - credentials were requested by the relevant purpose
  - request URL is HTTPS
  - host is `music.163.com`, a subdomain of `music.163.com`,
    `music.126.net`, or a subdomain of `music.126.net`
  - redirect preflight has not marked credentials unsafe
- Image headers never include credential cookies.
- Isolate download redirects recalculate headers per hop.

## Error Behavior

`SourceAuthContext` should not convert source errors or retry behavior. It only
centralizes auth decisions and header shaping.

- Existing credential load failures should propagate to callers that currently
  observe them.
- Playback redirect preflight failures should keep current behavior: log a
  sanitized warning and strip credentials for the handoff.
- Search should not observe account credential load failures because it should
  not load account auth.
- Source stream resolution fallback and `SourceApiException` semantics remain in
  stream/source Modules.

Credential parse/load logging rules from `lib/services/AGENTS.md` still apply:
do not log raw secure-storage JSON, cookie strings, token-bearing exceptions, or
`FormatException` source snippets.

## Implementation Plan Outline

This is not the detailed implementation plan; it is the expected shape:

1. Add `SourceAuthContext` Interface and production Implementation.
2. Move `buildAuthHeaders()` logic behind an `AccountAuthLoader` adapter while
   keeping compatibility wrappers temporarily if needed.
3. Move playback Netease redirect preflight behind the context Implementation.
4. Wire providers to construct and share `SourceAuthContext`.
5. Refactor `StreamResolutionService`, `AudioStreamManager`,
   `DownloadService`, `ImportService`, and `TrackDetailNotifier` to use
   purpose-specific methods.
6. Remove direct auth loading from search page lookup.
7. Keep isolate-safe media header construction pure/static.
8. Update tests around the new seam, then remove obsolete duplicate tests or
   wrappers if they no longer carry useful behavior.
9. Update relevant `AGENTS.md` guidance after code changes.

## Test Plan

Add:

- `test/services/account/source_auth_context_test.dart`
  - purpose gates
  - Netease allowlist behavior through the context
  - Bilibili/YouTube media credential non-leakage
  - image header credential stripping
  - redirect stripping behavior with a fake resolver
  - Search is not an auth purpose
  - Import auth and refresh auth are separate from `useAuthForPlay`

Update or preserve:

- `test/data/sources/source_http_policy_test.dart`
  - pure header defaults and URL allowlist predicates
- `test/services/audio/stream_resolution_service_test.dart`
  - stream resolution uses context auth for `useAuthForPlay`
- `test/services/audio/audio_stream_manager_test.dart`
  - playback handoff delegates URL/header preparation to context
- `test/services/download/download_media_headers_test.dart`
  - media/image download headers route through preserved policy
- `test/services/download/download_service_phase1_test.dart`
  - download stream resolution and metadata detail auth behavior
- `test/services/import/import_service_phase4_test.dart`
  - library import `useAuth`, account import `useAuth: true`, import expansion
    auth, and refresh `useAuthForRefresh` behavior
- `test/providers/track_detail_refresh_stale_test.dart`
  - detail loading follows `useAuthForPlay` without stale state regressions
- `test/ui/pages/search/search_page_phase2_test.dart`
  - Bilibili page lookup no longer requests auth

Minimum verification after implementation:

```bash
flutter test test/services/account test/services/audio test/services/download test/services/import test/providers/track_detail_refresh_stale_test.dart test/ui/pages/search/search_page_phase2_test.dart
flutter analyze
```

## Documentation Updates

After implementation, update:

- `lib/services/AGENTS.md` for account/download/media header ownership.
- `lib/services/audio/AGENTS.md` for stream resolution and playback handoff
  ownership.
- `lib/data/sources/AGENTS.md` for source auth and media header policy.
- `CONTEXT.md` if terminology changes during implementation.

## Deferred Follow-Up

Current search page lookup passes Bilibili auth, and current Now Playing detail
loads auth unconditionally. This design intentionally changes both:

- Search should not use account auth.
- Track detail should follow `useAuthForPlay`.

If future work wants authenticated search for private or account-personalized
results, treat it as a separate behavior change with its own UI setting and
tests.
