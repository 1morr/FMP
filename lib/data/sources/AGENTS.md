# lib/data/sources AGENTS.md

Guidance for Bilibili, YouTube, Netease, external playlist import sources, and
shared source error/stream/auth policy.

## Bilibili

- Direct source supports video audio extraction through DASH audio-only and durl
  muxed streams.
- Multi-page video (multi-P) is supported.
- Playback, download, and handoff stream resolution must preserve `Track.cid`
  and call the cid-aware Bilibili resolver for multi-P tracks, including
  source-specific alternative streams. Falling back to sourceId-only resolution
  can play or download the wrong page.
- Live room audio streams currently use Bilibili live `durl` URLs returned by
  `/room/v1/Room/playUrl`; do not document or assume HLS unless the
  implementation changes.
- Bilibili live radio remains Bilibili-only unless explicit multi-source radio
  support is added.
- Live room API clients, stream playback headers, and radio cover preloading
  must use `SourceHttpPolicy.bilibiliLiveHeaders()` /
  `SourceHttpPolicy.createBilibiliLiveDio()` so live Referer and media user
  agent stay consistent.
- `BilibiliLiveClient` owns Bilibili live room helpers, live endpoint URLs, real
  room ID resolution, live room search enrichment, live stream lookup, and medal
  wall room lookup. `BilibiliSource`, `RadioSource`, and
  `BilibiliAccountService` delegate live mechanics to the client.
- Favorites folder import is supported.
- Regular media/API requests require `Referer: https://www.bilibili.com`.
- Bilibili ranking requests that return `-352` are risk-control failures; refresh
  browser fingerprint cookies through `/x/frontend/finger/spi` and retry once
  instead of changing away from `/x/web-interface/ranking/v2`.
- Audio URLs expire; `ensureAudioUrl()` must periodically refresh them.
- `AudioStreamResult.expiry` must report the same Bilibili URL TTL used by track
  refresh logic so shared playback caching does not fall back to a generic
  default.
- Bilibili same-quality alternative fallback should exclude the failed media URL
  and may select DASH backup URLs or another durl entry before giving up.
- Rate-limit/risk-control codes include `-352`, `-412`, `-509`, and `-799`.

## YouTube

- Direct source uses `youtube_explode_dart` plus InnerTube API.
- YouTube Mix/Radio dynamic infinite playlists use `RD` playlist IDs and
  InnerTube `/next`.
- YouTube trending rankings use the YouTube Music "New This Week" playlist via
  InnerTube `/browse`; retry transient network/timeout/5xx failures once after
  `AppConstants.networkRetryDelay`, but do not immediately retry HTTP 429.
- Playlist import uses InnerTube `/browse`.
- Authenticated video detail paths must fall back to InnerTube when
  `youtube_explode_dart` reports a private/unplayable video.
- Stream priority: audio-only (`androidVr`) > muxed > HLS.
- Only `YoutubeApiClient.androidVr` produces accessible audio-only URLs; other
  clients can return 403.
- Supports Opus / AAC format selection.
- Authenticated InnerTube fallback must respect `AudioStreamConfig.streamPriority`
  and `formatPriority`.
- Do not hard-code audio-only before muxed or bitrate before configured codec
  order.
- Alternative stream fallback must pass and exclude the failed media URL while
  continuing through the same InnerTube response so a failed audio-only URL can
  fall back to muxed/HLS.
- Alternative fallback must rethrow non-fallbackable `SourceErrorKind` values
  such as login-required, rate-limit, permission, network, timeout, and geo
  errors instead of returning `null`.
- Rate limiting is HTTP 429.
- YouTube stream results must carry the one-hour YouTube URL TTL in
  `AudioStreamResult.expiry`, including InnerTube fallback streams.

## Netease Cloud Music

- Search uses `/api/cloudsearch/pc` with plain form encoding.
- Song detail uses `/api/v3/song/detail`, max 400 IDs per request.
- Audio stream uses `/eapi/song/enhance/player/url/v1`, eapi encryption, and
  generally requires login.
- Audio stream failures inspect per-song `data[0].code/message/fee/flag`.
  VIP/paid failures become `vipRequired`; copyright/region failures become
  `geoRestricted` (including `404` + copyright flag); generic missing URLs
  become `unavailable`.
- Playlist import uses `/api/v6/playlist/detail` plus batch song detail.
- Hot songs ranking uses the official Netease hot playlist id `3778678` via
  `/api/v6/playlist/detail` plus song detail metadata only; ranking fetches
  must not resolve or refresh audio URLs.
- Short URLs (`163cn.tv`) are resolved through HEAD/GET redirects.
- VIP detection: `fee == 1 || fee == 4` -> `Track.isVip = true`.
- Availability: `st == -200` -> unavailable.
- Audio URL expiry is 16 minutes.
- Requires `Referer: https://music.163.com/`.
- Encryption is in `lib/core/utils/netease_crypto.dart` (`eapi` + `weapi`).
- Account login supports QR code and WebView cookie extraction; `MUSIC_U` is the
  long-lived token.
- Default `useNeteaseAuthForPlay = true`.

## External Playlist Import

Search-match playlist import supports:
- Netease standard links and short links (`163cn.tv`)
- QQ Music multiple URL formats with `QQMusicSign`
- Spotify embed page parsing (`__NEXT_DATA__`), no auth needed

Imported tracks save the original platform ID for direct lyrics fetch:
- `ImportedTrack.sourceId` -> `Track.originalSongId`
- `ImportedTrack.source` -> `Track.originalSource`

## Unified Source Exceptions

`BilibiliApiException`, `YouTubeApiException`, and `NeteaseApiException` extend
`SourceApiException` from `source_exception.dart`.

- `AudioController` catches `on SourceApiException` for unified error handling.
- `_handleSourceError()` uses `SourceErrorKind` through helpers such as
  `_shouldSkipSourceError(e)` and checks like
  `e.kind == SourceErrorKind.rateLimited`.
- Base getters such as `isUnavailable`, `isRateLimited`, `isGeoRestricted`, and
  `isVipRequired` are convenience views over `kind`.
- Playback toasts for source failures must preserve semantic reason
  (`cannotPlayReason` / `cannotPlaySkippedReason`) instead of collapsing
  skippable failures to a generic "cannot play" message.
- `BilibiliApiException` uses `numericCode` (int) with semantic `code` getter.
- `YouTubeApiException` uses `code` (String) directly.
- `NeteaseApiException` uses `numericCode` (int).
- `SourceApiException.classifyDioError()` provides shared Dio classification.

## Audio Quality And Stream Config

User-configurable per source:
- `AudioQualityLevel`: high, medium, low
- `AudioFormat`: opus, aac (YouTube only; Bilibili/Netease only have AAC)
- `StreamType`: audioOnly, muxed, hls

Defaults:
- YouTube format priority: Opus > AAC
- YouTube stream priority: audioOnly > muxed > hls
- Bilibili stream priority: audioOnly > muxed (live streams always muxed)
- Netease stream priority: audioOnly

Source adapters implement narrow capabilities from `source_capabilities.dart`
instead of a broad shared base interface. Use `AudioStreamSource` for stream
resolution, `TrackInfoSource` for direct track metadata, `SearchSource` for
search, `PlaylistParsingSource` for playlist import, and `AvailabilitySource`
for source availability checks. `SourceManager` is the registry for those
capabilities; new callers should request the narrow capability they need.
Runtime callers must request narrow source capabilities from `SourceManager`;
do not expose or consume concrete source getters/providers such as
`bilibiliSourceProvider`, `youtubeSourceProvider`, or
`neteaseAudioSourceProvider`. Concrete adapter construction belongs inside
`SourceManager`; tests may instantiate adapters directly.

`AudioStreamRequest` is passed to source `getAudioStream()` /
`getAlternativeAudioStream()` and carries source identity (`sourceId`, optional
`cid` / `pageNum`), `AudioStreamConfig`, auth headers, and the failed media URL
for alternative fallback. Source adapters own source-specific identity rules:
Bilibili multi-P stream resolution must use `request.cid` when present, and
shared fallback helpers must not branch on `BilibiliSource`.

`AudioStreamResult` returns bitrate/codec/container/stream-type metadata and
the URL expiry. Playback handoff fallback must pass the same auth-for-play
headers as primary stream resolution.

Quality fallback uses the shared ladder:
- high -> medium -> low
- medium -> low
- low has no lower fallback

Fallback applies to playback URL resolution and download stream resolution. It
is allowed only for `unavailable` and `vipRequired`. Network, timeout,
rate-limit, login-required, permission-denied, geo-restricted, and unknown
errors keep normal retry/skip/error behavior.

During playback handoff fallback after a selected URL fails,
`StreamResolutionService.resolveFallback()` first tries lower-quality
alternatives before source-specific same-quality alternatives. YouTube
alternative selection must still respect format priority and requested fallback
quality.

Source adapters must preserve non-fallbackable `SourceErrorKind` values while
trying stream types; do not collapse rate-limit/login/permission/network/
timeout/geo errors into generic "no stream" errors after fallback attempts.

## Auth For Playback And Headers

Defaults:

| Setting | Default | Rationale |
|---------|---------|-----------|
| `useBilibiliAuthForPlay` | `false` | Most content accessible without login |
| `useYoutubeAuthForPlay` | `false` | Most content accessible without login |
| `useNeteaseAuthForPlay` | `true` | Most songs require login for audio URLs |

`SourceAuthContext` owns source auth gates for app-level callers. Do not add
new direct account-service header helpers in providers, services, or UI.

`SourceAuthContext.authForPlay()` reads
`settings.useAuthForPlay(track.sourceType)` and is used for stream resolution,
playback handoff, download stream resolution, download metadata detail, track
detail, and auth-aware app service paths that fetch source track metadata.
Existing `SourceManager.parseUrl()` / `refreshAudioUrl()` capability helpers
remain unauthenticated unless a future auth-aware overload is added; do not add
direct account-service auth there. Source adapters receive raw account headers
only for source API/stream URL resolution, not for media/CDN byte requests.

Search does not request account auth. Playlist import uses the import
UI/account entry choice through `SourceAuthContext.playlistImportAuth()`;
playlist refresh uses `Playlist.useAuthForRefresh` through
`SourceAuthContext.playlistRefreshAuth()`.

`SourceHttpPolicy` centralizes API/media header defaults. Direct source adapters
and account services should create Dio clients through
`SourceHttpPolicy.createApiDio()` and use `SourceHttpPolicy.apiHeaders()` for
stable per-request API headers.

Source-owned dynamic details stay local:
- Bilibili keeps generated buvid cookies and search-host defaults.
- YouTube keeps SAPISIDHASH/InnerTube auth headers source-owned.
- Netease keeps eapi/weapi encryption plus Cookie-only per-request auth merging
  source-owned.

Media playback/download request headers are intentionally narrower than
stream-resolution auth headers. `SourceHttpPolicy.mediaHeaders()` remains the
final pure source-aware media/header allowlist. It currently merges auth headers
only for HTTPS Netease media URLs whose host is explicitly allowlisted
(`music.163.com` / `*.music.163.com` / `music.126.net` /
`*.music.126.net`). Bilibili and YouTube account credentials are source
API/stream URL resolution credentials, not media/CDN headers. Do not forward
them to media/CDN requests unless a future design explicitly changes that
security boundary. Image/header helpers must not attach credential cookies,
including Netease `Cookie`, by default.

External playlist import must parse URLs with `Uri`, compare normalized hosts
against exact allowlists, and validate each redirect target before following it.
Reject loopback, localhost, private, carrier-grade NAT, and link-local literal
IP hosts. Do not detect platforms with substring checks against the raw input
URL.
