# lib/data/sources AGENTS.md

Guidance for Bilibili, YouTube, Netease, external playlist import sources, and
the shared source error / stream / auth policy. This file owns the auth and
header boundary; other subtrees cross-reference it rather than restating it.

## Bilibili

- Direct source supports video audio extraction through DASH audio-only and
  `durl` muxed streams. Multi-page video (multi-P) is supported.
- Playback, download, and handoff stream resolution must preserve `Track.cid`
  and call the cid-aware Bilibili resolver for multi-P tracks, including
  source-specific alternative streams. Falling back to sourceId-only resolution
  can play or download the wrong page.
- Live room audio streams use Bilibili live `durl` URLs from
  `/room/v1/Room/playUrl`; do not document or assume HLS unless the
  implementation changes. Bilibili live radio remains Bilibili-only unless
  explicit multi-source radio support is added.
- Live room API clients, stream playback headers, and radio cover preloading
  must use `SourceHttpPolicy.bilibiliLiveHeaders()` /
  `createBilibiliLiveDio()` so live Referer and media user agent stay consistent.
- `BilibiliLiveClient` owns live room helpers, live endpoint URLs, real room ID
  resolution, live room search enrichment, live stream lookup, and medal wall
  room lookup. `BilibiliSource`, `RadioSource`, and `BilibiliAccountService`
  delegate live mechanics to it.
- Regular media/API requests require `Referer: https://www.bilibili.com`.
  Favorites folder import is supported.
- Ranking requests returning `-352` are risk-control failures: refresh browser
  fingerprint cookies through `/x/frontend/finger/spi` and retry once, instead
  of moving away from `/x/web-interface/ranking/v2`.
- Rate-limit / risk-control codes: `-352`, `-412`, `-509`, `-799`.
- Audio URLs expire; `ensureAudioUrl()` must periodically refresh them.
  `AudioStreamResult.expiry` must report the same TTL used by track refresh
  logic so shared playback caching does not fall back to a generic default.
- Same-quality alternative fallback should exclude the failed media URL and may
  select DASH backup URLs or another `durl` entry before giving up.

## YouTube

- Direct source uses `youtube_explode_dart` plus the InnerTube API.
- Mix/Radio dynamic infinite playlists use `RD` playlist IDs and InnerTube
  `/next`. Playlist import uses InnerTube `/browse`.
- Trending rankings use the YouTube Music "New This Week" playlist via InnerTube
  `/browse`; retry transient network/timeout/5xx failures once after
  `AppConstants.networkRetryDelay`, but do not immediately retry HTTP 429
  (rate limiting is HTTP 429).
- Authenticated video detail paths must fall back to InnerTube when
  `youtube_explode_dart` reports a private/unplayable video.
- Stream priority: audio-only (`androidVr`) > muxed > HLS. Only
  `YoutubeApiClient.androidVr` produces accessible audio-only URLs; other
  clients can return 403. Supports Opus / AAC format selection.
- Authenticated InnerTube fallback must respect `AudioStreamConfig.streamPriority`
  and `formatPriority`. Do not hard-code audio-only before muxed, or bitrate
  before the configured codec order.
- Alternative stream fallback must pass and exclude the failed media URL while
  continuing through the same InnerTube response, so a failed audio-only URL can
  fall back to muxed/HLS. It must rethrow non-fallbackable `SourceErrorKind`
  values (login-required, rate-limit, permission, network, timeout, geo) instead
  of returning `null`.
- YouTube stream results must carry the one-hour URL TTL in
  `AudioStreamResult.expiry`, including InnerTube fallback streams.

## Netease Cloud Music

- Search uses `/api/cloudsearch/pc` with plain form encoding.
- Song detail uses `/api/v3/song/detail`, max 400 IDs per request.
- Audio stream uses `/eapi/song/enhance/player/url/v1`, eapi encryption, and
  generally requires login. Encryption lives in
  `lib/core/utils/netease_crypto.dart` (`eapi` + `weapi`).
- Audio stream failures inspect per-song `data[0].code/message/fee/flag`.
  VIP/paid failures become `vipRequired`; copyright/region failures become
  `geoRestricted` (including `404` + copyright flag); generic missing URLs
  become `unavailable`.
- Playlist import uses `/api/v6/playlist/detail` plus batch song detail. Hot
  songs ranking uses the official hot playlist id `3778678` through the same
  endpoint plus song detail metadata only — ranking fetches must not resolve or
  refresh audio URLs.
- Short URLs (`163cn.tv`) are resolved through HEAD/GET redirects.
- VIP detection: `fee == 1 || fee == 4` -> `Track.isVip = true`.
  Availability: `st == -200` -> unavailable.
- Audio URL expiry is 16 minutes. Requires `Referer: https://music.163.com/`.
- Account login supports QR code and WebView cookie extraction; `MUSIC_U` is the
  long-lived token. Default `useNeteaseAuthForPlay = true`.

## External Playlist Import

Search-match playlist import supports:

- Netease standard links and short links (`163cn.tv`)
- QQ Music multiple URL formats with `QQMusicSign`
- Spotify embed page parsing (`__NEXT_DATA__`), no auth needed

Imported tracks save the original platform ID for direct lyrics fetch:
`ImportedTrack.sourceId` -> `Track.originalSongId`, and `ImportedTrack.source`
-> `Track.originalSource`.

Import must parse URLs with `Uri`, compare normalized hosts against exact
allowlists, and validate each redirect target before following it. Reject
loopback, localhost, private, carrier-grade NAT, and link-local literal IP
hosts. Do not detect platforms with substring checks against the raw input URL.

## Unified Source Exceptions

`BilibiliApiException`, `YouTubeApiException`, and `NeteaseApiException` extend
`SourceApiException` from `source_exception.dart`.

- `AudioController` catches `on SourceApiException` for unified error handling;
  `_handleSourceError()` uses `SourceErrorKind` through helpers such as
  `_shouldSkipSourceError(e)` and checks like `e.kind == SourceErrorKind.rateLimited`.
- Base getters (`isUnavailable`, `isRateLimited`, `isGeoRestricted`,
  `isVipRequired`) are convenience views over `kind`.
- Playback toasts must preserve the semantic reason (`cannotPlayReason` /
  `cannotPlaySkippedReason`) instead of collapsing skippable failures into a
  generic "cannot play" message.
- Code types: `BilibiliApiException` and `NeteaseApiException` use `numericCode`
  (int) — Bilibili adds a semantic `code` getter; `YouTubeApiException` uses
  `code` (String) directly.
- `SourceApiException.classifyDioError()` provides shared Dio classification.

## Source Capabilities And Registry

Source adapters implement narrow capabilities from `source_capabilities.dart`
instead of a broad shared base interface: `AudioStreamSource` (stream
resolution), `TrackInfoSource` (direct track metadata), `SearchSource`,
`PlaylistParsingSource` (playlist import), and `AvailabilitySource`.

`SourceManager` (`source_provider.dart`) is the registry. Runtime callers must
request the narrow capability they need from it, and must not expose or consume
concrete source getters/providers such as `bilibiliSourceProvider`,
`youtubeSourceProvider`, or `neteaseAudioSourceProvider`. Concrete adapter
construction belongs inside `SourceManager`; tests may instantiate adapters
directly. This rule is enforced by
`test/data/sources/source_ownership_phase3_test.dart`.

Adapters owning disposable resources (HTTP clients, live-stream clients) should
`implements DisposableSource` and release them in `dispose()`.
`SourceManager.dispose()` cleans up every registered adapter implementing it via
`whereType<DisposableSource>()`, so a newly registered source is disposed
automatically without enumerating concrete types.

## Audio Quality And Stream Config

User-configurable per source:

- `AudioQualityLevel`: high, medium, low
- `AudioFormat`: opus, aac (YouTube only; Bilibili/Netease only have AAC)
- `StreamType`: audioOnly, muxed, hls

Defaults: YouTube format Opus > AAC and stream audioOnly > muxed > hls;
Bilibili audioOnly > muxed (live streams are always muxed); Netease audioOnly.

`AudioStreamRequest` is passed to `getAudioStream()` /
`getAlternativeAudioStream()` and carries source identity (`sourceId`, optional
`cid` / `pageNum`), `AudioStreamConfig`, auth headers, and the failed media URL
for alternative fallback. Adapters own source-specific identity rules: Bilibili
multi-P resolution must use `request.cid` when present, and shared fallback
helpers must not branch on `BilibiliSource`.

`AudioStreamResult` returns bitrate/codec/container/stream-type metadata and the
URL expiry. Playback handoff fallback must pass the same auth-for-play headers
as primary stream resolution.

Quality fallback uses the shared ladder high -> medium -> low (low has none). It
applies to playback URL resolution and download stream resolution, and is
allowed **only** for `unavailable` and `vipRequired`. Network, timeout,
rate-limit, login-required, permission-denied, geo-restricted, and unknown
errors keep normal retry/skip/error behavior — do not collapse them into a
generic "no stream" error after fallback attempts.

During playback handoff fallback after a selected URL fails,
`StreamResolutionService.resolveFallback()` first tries lower-quality
alternatives before source-specific same-quality alternatives. YouTube
alternative selection must still respect format priority and the requested
fallback quality.

## Auth For Playback And Headers

Defaults:

| Setting | Default | Rationale |
|---------|---------|-----------|
| `useBilibiliAuthForPlay` | `false` | Most content accessible without login |
| `useYoutubeAuthForPlay` | `false` | Most content accessible without login |
| `useNeteaseAuthForPlay` | `true` | Most songs require login for audio URLs |

`SourceAuthContext` (`lib/services/account/`) owns source auth gates and
implements narrow purpose interfaces — `SourcePlaybackAuthContext`,
`PlaybackMediaRequestContext`, `DownloadSourceAuthContext`, `PlaylistAuthContext`.
Runtime modules depend on the narrow interface for their purpose, not the full
context. Do not add new direct account-service header helpers in providers,
services, or UI.

`SourceAuthContext.authForPlay()` reads `settings.useAuthForPlay(track.sourceType)`
and is used for stream resolution, playback handoff, download stream resolution,
download metadata detail, track detail, and auth-aware app service paths that
fetch source track metadata. `SourceManager.parseUrl()` / `refreshAudioUrl()`
remain unauthenticated unless a future auth-aware overload is added — do not add
direct account-service auth there.

Search does not request account auth. Playlist import uses the import
UI/account entry choice through `SourceAuthContext.playlistImportAuth()`;
playlist refresh uses `Playlist.useAuthForRefresh` through
`playlistRefreshAuth()`.

`SourceHttpPolicy` centralizes API/media header defaults. Direct adapters and
account services create Dio clients through `SourceHttpPolicy.createApiDio()`
and use `apiHeaders()` for stable per-request API headers. Source-owned dynamic
details stay local: Bilibili keeps generated buvid cookies and search-host
defaults; YouTube keeps SAPISIDHASH/InnerTube auth headers; Netease keeps
eapi/weapi encryption plus Cookie-only per-request auth merging.

**The media byte-request boundary is narrower than stream-resolution auth.**
`MediaHandoff` (`lib/services/media/`) is the byte-request seam for playback and
download; it delegates final source header defaults and Netease allowlist checks
to the pure `SourceHttpPolicy.mediaHeaders()`. Only HTTPS Netease media URLs
whose host is explicitly allowlisted (`music.163.com` / `*.music.163.com` /
`music.126.net` / `*.music.126.net`) may receive Netease cookies. Bilibili and
YouTube account credentials are source API / stream URL resolution credentials,
not media/CDN headers — do not forward them to media/CDN requests unless a
future design explicitly changes that security boundary. Image/header helpers
must not attach credential cookies, including the Netease `Cookie`, by default.
