# lib/data/sources AGENTS.md

Bilibili, YouTube, Netease, playlist import, and the shared source error /
stream / auth policy. **This file owns the auth and header boundary**; other
subtrees cross-reference it rather than restating it.

Endpoints, status codes and request shapes are in the adapters. What is here is
what reading them will not tell you.

## Bilibili

- Playback, download and handoff stream resolution must preserve `Track.cid` and
  call the cid-aware resolver for multi-P tracks, including source-specific
  alternative streams. Falling back to sourceId-only resolution plays or
  downloads **the wrong page**.
- Live room audio uses live `durl` URLs; do not document or assume HLS unless
  the implementation changes. Bilibili live radio stays Bilibili-only unless
  explicit multi-source radio support is added.
- Live room clients, stream playback headers and radio cover preloading must go
  through `SourceHttpPolicy.bilibiliLiveHeaders()` / `createBilibiliLiveDio()`
  so live Referer and media user agent stay consistent. `BilibiliLiveClient`
  owns every live helper; `BilibiliSource`, `RadioSource` and
  `BilibiliAccountService` delegate to it.
- Ranking requests returning `-352` are risk control, not a broken endpoint:
  refresh browser fingerprint cookies through `/x/frontend/finger/spi` and retry
  once, instead of moving away from the ranking API. The rate-limit and
  risk-control codes are `-352`, `-412`, `-509`, `-799`.
- `AudioStreamResult.expiry` must report the same TTL that track refresh uses,
  or shared playback caching falls back to a generic default.
- Same-quality alternative fallback excludes the failed media URL and may pick a
  DASH backup URL or another `durl` entry before giving up.

## YouTube

- Stream priority is audio-only (`androidVr`) > muxed > HLS. **Only
  `YoutubeApiClient.androidVr` produces accessible audio-only URLs**; other
  clients can return 403.
- Selection tries each `streamPriority` entry anonymously and, only if that
  entry failed, retries **the same entry** with auth. Running every type
  anonymously first and then falling back to auth once makes the authenticated
  audio-only path unreachable whenever anonymous muxed succeeds — which is the
  common case, because audio-only is the flakiest of the three.
  `getAudioStream` and `getAlternativeAudioStream` must keep the same shape.
- The authenticated InnerTube path uses the **WEB** client, not `androidVr`:
  ANDROID_VR combined with web cookies returns 400 (client/auth mismatch).
- One `/player` request per call, shared across stream types — they all read the
  same `streamingData`.
- Authenticated selection must respect `AudioStreamConfig.streamPriority` and
  `formatPriority`. Do not hard-code audio-only before muxed, or bitrate before
  the configured codec order.
- Alternative fallback passes and excludes the failed media URL while continuing
  through the same InnerTube response, and must rethrow non-fallbackable
  `SourceErrorKind` values (login-required, rate-limit, permission, network,
  timeout, geo) rather than returning `null`.
- Authenticated video detail falls back to InnerTube when `youtube_explode_dart`
  reports a private/unplayable video. Trending retries transient network/5xx
  once but never retries HTTP 429.

## Netease Cloud Music

- Audio stream uses eapi encryption and generally requires login. Encryption
  lives in `lib/core/utils/netease_crypto.dart`.
- Stream failures inspect per-song `code`/`message`/`fee`/`flag`. VIP/paid
  become `vipRequired`; copyright/region become `geoRestricted`; generic missing
  URLs become `unavailable`.
- Ranking fetches use the hot playlist plus song-detail metadata only — they
  must **not** resolve or refresh audio URLs.
- Play auth defaults to on for Netease (`kDefaultUseAuthForPlayBySource`),
  because most songs need login for an audio URL at all.

## External Playlist Import

Netease links and short links, QQ Music via `QQMusicSign`, and Spotify embed
pages (no auth). Imported tracks keep the original platform ID for direct lyrics
fetch: `ImportedTrack.sourceId` -> `Track.originalSongId`, `ImportedTrack.source`
-> `Track.originalSource`.

Import must parse URLs with `Uri`, compare normalized hosts against exact
allowlists, and validate each redirect target before following it. Reject
loopback, localhost, private, carrier-grade NAT and link-local literal IP hosts.
**Do not detect platforms with substring checks against the raw input URL.**

## Source Exceptions

`BilibiliApiException`, `YouTubeApiException` and `NeteaseApiException` extend
`SourceApiException`.

- `AudioController` catches `on SourceApiException`. What that error *means* —
  skip, retry, and the wording the user sees — is `PlaybackErrorPresenter`,
  which reads `SourceErrorKind` and nothing else. The controller only decides
  what to do with the answer.
- Playback toasts must preserve the semantic reason instead of collapsing
  skippable failures into a generic "cannot play".
- Code types differ: Bilibili and Netease use `numericCode` (int), YouTube uses
  `code` (String).

## Source Capabilities And Registry

Adapters implement narrow capabilities from `source_capabilities.dart` instead
of one broad base interface. `DisposableSource` is separate — a lifecycle
interface, not a capability.

`SourceManager` (`source_provider.dart`) is the registry. **Runtime callers must
request the narrow capability they need and must never consume concrete source
getters or providers**; concrete construction belongs inside `SourceManager`.
Tests may instantiate adapters directly. Enforced by
`test/data/static_rules/source_ownership_static_rule_test.dart`.

`RankingSource` must return its tracks **already ordered** the way that
platform's chart is meant to read. Adapters owning disposable resources
`implements DisposableSource`; `SourceManager.dispose()` finds them with
`whereType`, so a newly registered source is cleaned up without enumerating
concrete types.

## Audio Quality And Stream Config

User-configurable per source: `AudioQualityLevel` (high/medium/low),
`AudioFormat` (opus/aac — YouTube only, the others are AAC), `StreamType`
(audioOnly/muxed/hls). Defaults: YouTube Opus > AAC and audioOnly > muxed > hls;
Bilibili audioOnly > muxed (live is always muxed); Netease audioOnly.

`AudioStreamRequest` carries source identity, config, auth headers and the
failed media URL. **Adapters own source-specific identity rules** — Bilibili
multi-P resolution uses `request.cid` when present, and shared fallback helpers
must not branch on `BilibiliSource`.

Quality fallback uses the shared ladder high -> medium -> low. It applies to
playback and download resolution, and is allowed **only** for `unavailable` and
`vipRequired`. Network, timeout, rate-limit, login-required, permission-denied,
geo-restricted and unknown keep normal retry/skip/error behaviour — do not
collapse them into a generic "no stream" after fallback attempts.

During playback handoff fallback, `StreamResolutionService.resolveFallback()`
tries lower-quality alternatives before source-specific same-quality ones.

## Auth For Playback And Headers

Read and write play auth through `Settings.useAuthForPlay(sourceId)` /
`setUseAuthForPlay(sourceId, value)`; defaults live in
`kDefaultUseAuthForPlayBySource` (Bilibili and YouTube `false`, Netease `true`).
The three `use*AuthForPlay` columns still exist but are `@Deprecated` and read
only by the v1 to v2 migration.

`SourceAuthContext` (`lib/services/account/`) owns the gates and implements
narrow purpose interfaces — `SourcePlaybackAuthContext`,
`PlaybackMediaRequestContext`, `DownloadSourceAuthContext`, `PlaylistAuthContext`.
Runtime modules depend on the narrow interface for their purpose, not the full
context. **Do not add new direct account-service header helpers in providers,
services or UI.**

`authForPlay()` covers stream resolution, playback handoff, download stream
resolution, download metadata detail, track detail, and auth-aware metadata
paths. `SourceManager.parseUrl()` / `refreshAudioUrl()` stay unauthenticated
unless a future auth-aware overload is added. Search requests no auth; playlist
import uses the import entry choice, playlist refresh uses
`Playlist.useAuthForRefresh`.

`SourceHttpPolicy` centralizes API/media header defaults — adapters and account
services create Dio clients through `createApiDio()` and use `apiHeaders()`.
Source-owned dynamic details stay local: Bilibili's generated buvid cookies,
YouTube's SAPISIDHASH/InnerTube headers, Netease's eapi/weapi encryption and
Cookie-only per-request merging.

**Account credentials never reach a media byte request — for any source.**
`MediaHandoff` (`lib/services/media/`) is the byte-request seam for playback and
download, and it asks `SourceHttpPolicy.mediaHeaders(sourceType)` for headers.
That function takes nothing but the source type, so there is no parameter
through which a caller could pass a cookie: **the boundary is enforced by the
signature, not by a runtime check.**

Account auth belongs to stream *resolution*. Every source signs its media URL
during resolution, so quality and entitlement are already decided by the time
the bytes are fetched; the CDN only wants `Origin` / `Referer` / `User-Agent`.
`MediaHandoffRequest.streamResolutionAuth` still exists so playback and download
can share one request object, but nothing downstream reads it for headers.

> Netease used to be an exception: HTTPS media URLs on an allowlisted host got
> the account cookie, behind a redirect preflight walking up to five hops.
> Measured 2026-09-01, signed in: eapi returns `http://` URLs, so the HTTPS gate
> rejected every real URL and the whole path never ran in production. Playback
> works without it and the signed URL redirects zero times. Removed rather than
> repaired; do not reintroduce it without evidence that the CDN needs the
> cookie. Image helpers must likewise never attach credential cookies.
