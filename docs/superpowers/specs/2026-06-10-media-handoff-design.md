# Media Handoff Design

Date: 2026-06-10
Status: Approved design, pending implementation

## Summary

Deepen FMP's Media Handoff behavior into a dedicated module used by playback and
download byte requests. The refactor keeps `SourceAuthContext` as the owner of
Auth For Play and other source auth gates, while moving URL/header preparation
for actual media requests into a pure, isolate-safe Media Handoff module.

This intentionally strengthens download behavior: download redirect hops should
use the same Media Request Credentials policy as playback. Netease credentials
remain attached only for allowlisted HTTPS Netease media hosts, and redirects to
non-allowlisted hosts must strip credentials on the next hop.

## Goals

- Create one deep Media Handoff module for playback and download media byte
  requests.
- Keep Auth For Play, playlist import auth, and playlist refresh auth in
  `SourceAuthContext`.
- Keep source API/stream resolution auth distinct from Media Request
  Credentials.
- Preserve the current Netease media credential allowlist.
- Preserve the rule that Bilibili and YouTube account credentials never reach
  media/CDN requests.
- Make download redirect-hop header behavior directly testable without a full
  `DownloadService` or isolate fixture.
- Move range header construction out of the download loop and into Media
  Handoff.
- Preserve download isolate ownership of network I/O, progress, pause/cancel,
  and final persistence behavior.

## Non-Goals

- Do not change Auth For Play defaults.
- Do not expand Netease credential attachment beyond the existing allowlist.
- Do not send Bilibili or YouTube account credentials to media/CDN hosts.
- Do not move source API header defaults out of `SourceHttpPolicy`.
- Do not move account service access into the download isolate.
- Do not change source stream resolution, quality fallback, or audio recovery
  retry policy.
- Do not remove `SourceAuthContext.playbackNetworkRequest()` from public use in
  this refactor.

## Existing Friction

Playback already uses the higher-level
`SourceAuthContext.playbackNetworkRequest()` interface, but download Media
Handoff is still split across:

- `DownloadService`, which receives raw Stream Resolution Auth from
  `StreamResolutionService`.
- `_isolateDownload()`, which owns redirect looping and range headers.
- `download_media_headers.dart`, which is a shallow pass-through to
  `SourceHttpPolicy.mediaHeaders()`.
- `SourceHttpPolicy`, which correctly owns pure source header defaults and the
  Netease media credential allowlist.

The current download helper fails the deletion test: deleting
`download_media_headers.dart` mostly moves the call back to
`SourceHttpPolicy.mediaHeaders()`. A deeper module should hide the credential
allowlist, redirect-hop header recalculation, range header construction, and
download/playback request shape behind one interface.

## Chosen Approach

Add a new pure Media Handoff module, tentatively
`lib/services/media/media_handoff.dart`.

`SourceAuthContext` remains the app-level source auth policy module. It still
loads Stream Resolution Auth through `authForPlay()` and remains the public seam
used by `AudioStreamManager` for playback handoff. Internally,
`DefaultSourceAuthContext.playbackNetworkRequest()` delegates final media
URL/header preparation to Media Handoff.

Download uses the same Media Handoff module inside the isolate. The isolate
cannot use Riverpod, account services, or `SourceAuthContext`, so the Media
Handoff implementation must be pure and constructible without app-level state.

## Module Shape

### External Interface

The Media Handoff interface is byte-request oriented:

```dart
class MediaHandoffRequest {
  const MediaHandoffRequest({
    required this.sourceType,
    required this.url,
    this.streamResolutionAuth,
    this.rangeStart,
  });

  final SourceType sourceType;
  final Uri url;
  final Map<String, String>? streamResolutionAuth;
  final int? rangeStart;
}

class MediaHandoffResult {
  const MediaHandoffResult({
    required this.url,
    required this.headers,
    required this.credentialsIncluded,
  });

  final Uri url;
  final Map<String, String> headers;
  final bool credentialsIncluded;
}

abstract interface class MediaHandoff {
  Future<MediaHandoffResult> preparePlayback(MediaHandoffRequest request);
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request);
}
```

`preparePlayback()` may perform Netease redirect preflight. It is async because
the current playback behavior probes redirects before handing the URL to the
backend.

`prepareDownloadHop()` is sync and pure. The download isolate already follows
redirects itself, so this method prepares headers for the current hop only. It
must not do network I/O.

### Production Implementation

Use a default implementation, tentatively `DefaultMediaHandoff`, that depends
only on pure functions and optional test adapters:

- `SourceHttpPolicy.mediaHeaders()` for source-aware media headers and the
  final credential allowlist.
- `SourceHttpPolicy.canAttachNeteaseMediaCredentials()` to decide
  `credentialsIncluded`.
- An optional playback redirect resolver for tests.
- `HttpClient` only inside playback preflight, not inside download hop
  preparation.

### SourceAuthContext Integration

`DefaultSourceAuthContext` keeps its current public interface:

```dart
Future<PlaybackNetworkRequest> playbackNetworkRequest(Track track, String url);
```

Internally it:

1. Calls `authForPlay(track.sourceType)`.
2. Builds a `MediaHandoffRequest` from `track.sourceType`, `url`, and the auth
   headers.
3. Calls `mediaHandoff.preparePlayback(...)`.
4. Converts the result back to `PlaybackNetworkRequest`.

This limits call-site churn while moving the actual media byte-request policy
behind the deeper module.

## Data Flow

### Playback

1. `AudioStreamManager` calls
   `SourceAuthContext.playbackNetworkRequest(track, url)`.
2. `SourceAuthContext` loads Stream Resolution Auth through
   `authForPlay(track.sourceType)`.
3. `SourceAuthContext` delegates to `MediaHandoff.preparePlayback()`.
4. Media Handoff preflights Netease redirects when credentials could attach.
5. If the final Netease URL remains on an allowlisted HTTPS Netease media host,
   credentials are included in headers.
6. If redirect preflight fails or the final URL leaves the allowlist, the result
   keeps a safe URL and returns headers without credentials.
7. The backend receives the final URL and safe media headers.

### Download

1. `DownloadService` resolves the stream through
   `StreamResolutionService.resolvePrimary(..., purpose:
   StreamResolutionPurpose.download)`.
2. The returned `RemoteStreamResolution.authHeaders` remains Stream Resolution
   Auth. It is passed into the isolate as data, not as app-level services.
3. The isolate redirect loop parses the current request URL.
4. For each hop, the isolate calls `MediaHandoff.prepareDownloadHop()` with the
   current URL, source type, Stream Resolution Auth, and optional resume offset.
5. Media Handoff returns hop-specific headers, including `Range` when
   `rangeStart` is provided.
6. Redirect handling remains in the isolate. The next hop calls Media Handoff
   again with the redirected URL, so credentials are naturally stripped if the
   redirected URL is not allowlisted.

## Behavior Rules

| Area | Rule |
| --- | --- |
| Bilibili media | Include source media defaults such as Referer/User-Agent; never include account cookies. |
| YouTube media | Include YouTube media defaults; never include account Authorization or cookies. |
| Netease media | Include Netease cookies only for allowlisted HTTPS Netease media hosts. |
| Download redirects | Recompute headers for every hop through Media Handoff. |
| Download range | Media Handoff adds `Range: bytes=<rangeStart>-` when a range start is present. |
| Playback preflight failure | Log a sanitized warning, keep URL fallback behavior, strip credentials. |
| Images | Continue using `SourceAuthContext.imageHeaders()` / `SourceHttpPolicy.imageHeaders()`; image credentials remain out of scope for Media Handoff. |

## Error Handling

- Media Handoff must not catch source resolution errors or classify
  `SourceApiException`.
- Playback Netease preflight failures keep the current behavior: log a fixed
  sanitized warning and return media headers without credentials.
- Download malformed URLs, unsupported schemes, missing redirect locations, too
  many redirects, HTTP errors, and stalled responses remain download isolate
  errors.
- Download hop preparation must not throw for credential stripping; it should
  return safe headers for the current URL.
- Credential parse/load failures remain in account services and
  `SourceAuthContext`, before Media Handoff receives the request.

## Test Plan

Add `test/services/media/media_handoff_test.dart`:

- `prepareDownloadHop` strips Bilibili auth cookies.
- `prepareDownloadHop` strips YouTube Authorization/cookies.
- `prepareDownloadHop` includes Netease cookies for allowlisted HTTPS media
  hosts.
- `prepareDownloadHop` strips Netease cookies for non-allowlisted redirects.
- `prepareDownloadHop` adds `Range: bytes=N-` when `rangeStart` is provided.
- `preparePlayback` keeps credentials for safe Netease redirect resolution.
- `preparePlayback` strips credentials for unsafe Netease redirect resolution.
- `preparePlayback` strips credentials when redirect preflight throws.

Update existing tests:

- `test/services/account/source_auth_context_test.dart`
  - verify `playbackNetworkRequest()` delegates to Media Handoff behavior.
- `test/services/download/download_media_headers_test.dart`
  - move pass-through helper expectations to the Media Handoff seam, or keep
    compatibility assertions only if the helper remains.
- `test/services/download/download_service_phase1_test.dart`
  - preserve stream resolution auth and metadata/image header behavior.

Minimum verification:

```bash
flutter test test/services/media test/services/account/source_auth_context_test.dart test/services/download/download_media_headers_test.dart
flutter test test/services/download/download_service_phase1_test.dart
flutter analyze
```

## Documentation Updates

After implementation, update:

- `lib/services/AGENTS.md`
  - document Media Handoff ownership for download redirects, range headers, and
    Media Request Credentials.
- `lib/data/sources/AGENTS.md`
  - clarify that `SourceHttpPolicy` remains the final pure allowlist helper,
    while Media Handoff is the byte-request seam.
- `lib/services/audio/AGENTS.md`
  - clarify that playback handoff still enters through `SourceAuthContext` but
    URL/header byte-request policy is delegated to Media Handoff.
- `CONTEXT.md`
  - update the Media Handoff definition if the term needs sharper wording after
    implementation.

## Implementation Notes

- Use TDD: write the Media Handoff tests before production code.
- Keep the first implementation small and behavior-focused.
- Prefer deleting `download_media_headers.dart` if no production caller remains.
  If tests or compatibility require it temporarily, make it a thin forwarder to
  Media Handoff and mark it as compatibility-only.
- Do not change download isolate lifecycle, progress buffering, pause/cancel
  state, or path persistence while doing this refactor.
- Do not commit without an explicit user request.
