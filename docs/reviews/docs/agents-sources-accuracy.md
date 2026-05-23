# AGENTS.md Source Accuracy Review

Reviewed: 2026-05-21

Scope: `AGENTS.md` claims under Bilibili, YouTube, Netease, Unified Source Exception Handling, Audio Quality Settings, and Auth for Playback, compared against `lib/data/sources/`, audio stream resolution code, and download stream/header/auth integration.

Method: Used `rg` first for AGENTS headings, source adapters, stream config/fallback, auth, headers, and download integration, then read relevant files with line numbers.

## Summary

The scoped source documentation is mostly current. The main Bilibili, YouTube, Netease, shared quality fallback, and auth-for-stream-resolution claims match the implementation. The strongest issues are not broad architectural mismatches: the docs overstate Bilibili live/header consistency, describe an older getter-based `_handleSourceError()` implementation, and state a source-adapter fallback rule that YouTube alternative fallback does not currently preserve.

Several items need human decision because the docs do not define the intended boundary clearly: whether Bilibili/YouTube auth headers should ever be forwarded to media playback/download requests, whether `BilibiliSource.getTrackInfo()` should propagate auth to its best-effort audio URL fetch, and whether AGENTS should distinguish Bilibili API, search, media, and live referers.

## Confirmed Accurate Claims

### [accurate] Bilibili direct source supports DASH audio-only, durl muxed, multi-page videos, URL expiry, and documented rate-limit codes

Related AGENTS paragraph: Bilibili (Direct Source), `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:189-197`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:203-229` resolves `bvid -> cid` before stream lookup.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:251-304` tries configured stream types and maps Bilibili `audioOnly` to DASH and `muxed` to durl.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:307-358` returns DASH audio-only `AudioStreamResult` with AAC metadata and Bilibili expiry.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:362-395` returns durl muxed `AudioStreamResult` with the same Bilibili expiry.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:614-632` implements multi-page `getVideoPages()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:830-843` maps `-412`, `-509`, and `-799` to rate-limit handling; `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_exception.dart:26-31` also classifies `-429`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/core/constants/app_constants.dart:25-29` defines Bilibili URL expiry as 2 hours, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:357`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:394`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:429-430` use that same TTL.

### [accurate] YouTube stream resolution uses youtube_explode plus authenticated InnerTube fallback and respects configured stream/format order

Related AGENTS paragraph: YouTube (Direct Source), `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:199-206`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:328-357` tries `youtube_explode_dart` first by `config.streamPriority`, then falls back to authenticated InnerTube when auth headers exist.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:383-407` uses only `YoutubeApiClient.androidVr` for audio-only streams.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:416-449` tries muxed streams with iOS/Safari/Android clients; `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:458-505` tries HLS.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:519-528` applies `config.formatPriority` before bitrate/quality selection for audio-only streams.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:1634-1645` iterates authenticated InnerTube streams by `config.streamPriority`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:1684-1723` filters failed URLs and applies `config.formatPriority` for InnerTube audio-only selection; `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:1726-1756` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:1759-1771` continue to muxed/HLS when audio-only is unavailable.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:951-973` uses InnerTube `/next` for Mix/Radio playlists, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:1271-1312` uses InnerTube `/browse` before falling back to `youtube_explode_dart` for normal playlists.

### [accurate] Netease source behavior matches the documented endpoints, encryption, stream failure classification, and defaults

Related AGENTS paragraph: Netease Cloud Music (Direct Source), `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:208-221`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:180-197` searches via `/api/cloudsearch/pc` with form-encoded data.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:458-490` fetches single-song details via `/api/v3/song/detail`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:493-526` batches playlist song details in chunks of 400.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:101-160` fetches audio from `/eapi/song/enhance/player/url/v1`, uses `NeteaseCrypto.eapi()`, returns `StreamType.audioOnly`, and sets 16-minute expiry.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:735-790` classifies missing stream URLs from per-song `code`, `message`, `fee`, and `flag`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:810-830` classifies VIP/paid stream errors, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:832-850` classifies copyright/region errors, including flag-based cases.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:247-320` imports playlists through `/api/v6/playlist/detail`; `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:636-669` resolves `163cn.tv` short URLs with HEAD/GET fallback.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:617-633` maps `fee == 1 || fee == 4` from privilege or song data to `Track.isVip` and `st == -200` to unavailable.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_http_policy.dart:83-88` sets the Netease API Referer/Origin, `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_http_policy.dart:118-124` builds authenticated Netease headers, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/core/utils/netease_crypto.dart:10-12` documents eapi/weapi support.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:230-237` defaults `useNeteaseAuthForPlay` to `true`.

### [accurate] Shared audio quality config and quality fallback are used by playback and download stream resolution

Related AGENTS paragraph: Audio Quality Settings, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:240-257`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:21-51` defines `AudioQualityLevel`, `AudioFormat`, and `StreamType`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:139-153` stores default high quality, Opus > AAC, YouTube `audioOnly,muxed,hls`, Bilibili `audioOnly,muxed`, and Netease `audioOnly`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/base_source.dart:43-56` builds `AudioStreamConfig` from per-source settings.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/audio_stream_quality_fallback.dart:5-25` implements the high -> medium -> low ladder.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_exception.dart:24-27` restricts lower-quality fallback to `unavailable` and `vipRequired`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:68-79` applies shared quality fallback during playback URL resolution.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_service.dart:699-711` applies the same config and fallback during download stream resolution.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:128-157` first tries lower-quality alternatives, then same-quality source-specific alternatives for playback handoff fallback.

### [accurate] Auth-for-playback settings are read by stream resolution, fallback, and download resolution

Related AGENTS paragraph: Auth for Playback, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:259-270`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:230-237` defines the documented auth defaults, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:518-538` maps source type to `useAuthForPlay()` and `setUseAuthForPlay()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/core/utils/auth_headers_utils.dart:11-28` builds source-specific auth headers for Bilibili, YouTube, and Netease.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:68-79` reads `settings.useAuthForPlay(track.sourceType)` for primary playback stream resolution.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:122-157` reads the same setting for playback fallback and passes `authHeaders` to `BaseSource.getAlternativeAudioStream()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_service.dart:699-711` reads the same setting for download stream resolution.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_service.dart:764-767` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_service.dart:1168-1179` pass the resulting auth headers into download media/image header construction.

### [accurate] Source exception hierarchy and semantic playback messages are implemented

Related AGENTS paragraph: Unified Source Exception Handling, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:228-238`.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_exception.dart:5`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_exception.dart:5`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_exception.dart:5` all extend `SourceApiException`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_exception.dart:5-27` defines `SourceErrorKind`, retry, skip, and lower-quality fallback semantics.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_exception.dart:79-146` implements shared Dio classification.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:694-703`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:791-800`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1964-1981` catch `on SourceApiException`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2077-2103` builds `cannotPlayReason` / `cannotPlaySkippedReason` messages from semantic source reasons instead of a generic failure string.

## Outdated Or Contradicted Claims

### [outdated] Unified Source Exception Handling says `_handleSourceError()` uses base-class convenience getters

Related AGENTS paragraph: Unified Source Exception Handling, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:231-232`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2023-2072` implements `_handleSourceError()` with `_shouldSkipSourceError(e)` and `e.kind == SourceErrorKind.rateLimited`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2088-2103` switches on `error.kind`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2113-2117` maps retry/skip decisions through `SourceErrorKind`.

Assessment: The behavior is still unified, but the AGENTS implementation detail is stale. The current controller does not call `isUnavailable`, `isRateLimited`, or `isGeoRestricted` in this path.

### [outdated] Netease exception wording says `NeteaseApiException` adds `isVipRequired`

Related AGENTS paragraph: Unified Source Exception Handling, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:235-237`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_exception.dart:5-44` defines `numericCode`, `code`, and `kind`; it maps `numericCode == -10` to `SourceErrorKind.vipRequired`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_exception.dart:72-73` defines the `isVipRequired` getter on the shared base class.

Assessment: Netease exceptions do expose `isVipRequired` behavior through the base getter, but `NeteaseApiException` does not add its own getter. This is wording drift, not a runtime mismatch.

### [contradicted] Bilibili live room API/header policy is only followed by `RadioSource`, not by all Bilibili live clients

Related AGENTS paragraph: Bilibili (Direct Source), `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:192-193`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_source.dart:93-95` correctly creates the radio live Dio via `SourceHttpPolicy.createBilibiliLiveDio()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_source.dart:288-291` returns radio stream playback headers from `SourceHttpPolicy.bilibiliLiveHeaders()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:75-81` creates its shared `_dio` with `SourceHttpPolicy.createApiDio()` and `SourceHttpPolicy.bilibiliSearchApiHeaders()`, not `createBilibiliLiveDio()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:1078-1099` uses that shared `_dio` for live room info and anchor info.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:1116-1137` uses the same shared `_dio` for live stream URL lookup.

Assessment: AGENTS states a rule that live room API clients must use live-specific policy. The radio client follows it, but `BilibiliSource` live room helpers do not.

## Missing Important Behaviors

### [missing] Audio Quality Settings do not document source-specific quality mappings

Related AGENTS paragraph: Audio Quality Settings, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:240-257`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:334-340` sorts Bilibili DASH audio by bandwidth and selects high/middle/low positionally.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:549-560` uses the same positional high/middle/low selection for YouTube streams.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:109-113` sends a Netease `level` parameter, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/netease_source.dart:680-688` maps high/medium/low to `lossless` / `exhigh` / `standard`.

Assessment: The existing docs correctly describe the shared enum and fallback ladder, but omit how each source interprets high/medium/low. This matters when debugging stream availability or bitrate surprises.

### [missing] BilibiliSource uses search-host default headers for all of its API requests

Related AGENTS paragraph: Auth for Playback backend note and Bilibili header note, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:195` and `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:270`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_http_policy.dart:95-108` defines `bilibiliSearchApiHeaders()` with `Referer: https://search.bilibili.com/` and `Origin: https://search.bilibili.com`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:75-81` applies those search headers to the source-level `_dio`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:212-216` uses that `_dio` for the view API during audio stream resolution.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:313-322` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:367-376` use the same `_dio` for playurl stream API calls.

Assessment: AGENTS says Bilibili requires the `www.bilibili.com` referer and separately says Bilibili keeps `bilibiliSearchApiHeaders()` for search-host defaults. Current code uses search-host defaults more broadly. The docs should either document that broader default or split expected API/search/media/live header policy more precisely.

## Architecture Rules Not Currently Followed

### [contradicted] YouTube alternative stream fallback does not preserve non-fallbackable source errors

Related AGENTS paragraph: Audio Quality Settings, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:256-257`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:336-347` preserves non-fallbackable errors in primary stream selection by rethrowing them.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:2103-2107` classifies non-fallbackable source errors and rate-limit errors for primary stream fallback.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:573-608` catches alternative stream failures broadly, logs, and returns `null`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:657-659`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:697-699`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/youtube_source.dart:743-746` swallow alternative audio-only, muxed, and HLS exceptions without checking `SourceErrorKind`.

Assessment: The primary YouTube path follows the AGENTS rule. The alternative playback handoff path can collapse rate-limit/login/permission/network/timeout/geo errors to "no alternative" by returning `null`, which diverges from the documented adapter rule.

### [contradicted] Bilibili live source helpers do not follow the documented live-header rule

Related AGENTS paragraph: Bilibili (Direct Source), `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:193`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_http_policy.dart:111-147` provides `bilibiliLiveHeaders()` and `createBilibiliLiveDio()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:1078-1099` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:1116-1137` do not use either live-specific helper.

Assessment: This is the same underlying issue as the Bilibili finding above, but it is also an explicit architecture rule not currently followed by one source class.

## Unclear Items Needing Human Decision

### [unclear] Auth for Playback does not define whether auth headers should be media-request headers for Bilibili/YouTube

Related AGENTS paragraph: Auth for Playback, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:259-270`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:68-79` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/internal/audio_stream_delegate.dart:122-157` pass auth headers to source stream resolution and fallback.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_stream_manager.dart:181-188` only loads Netease auth headers for final playback media headers.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/source_http_policy.dart:33-64` only merges auth headers into media headers when `sourceType == SourceType.netease`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_service.dart:764-767` passes auth headers into `buildDownloadMediaHeaders()`, but `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/download/download_media_headers.dart:4-21` delegates to the Netease-only merge behavior above.

Decision needed: If auth-for-play means "use credentials only to fetch signed/authorized stream URLs", the docs are mostly fine but should say media requests only merge Netease auth. If it means Bilibili/YouTube media downloads/playback should also receive cookies/SAPISID-derived headers, code currently diverges.

### [unclear] `BilibiliSource.getTrackInfo()` accepts auth headers but does not pass them to its best-effort audio URL fetch

Related AGENTS paragraph: Auth for Playback, `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:259-270`.

Actual code:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:163-171` accepts `authHeaders` and uses them for the metadata view request.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:185-189` then calls `getAudioUrl(bvid)` without `authHeaders`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:665-670` supports auth-aware URL fetching through `getAudioUrlWithCid(..., authHeaders: authHeaders)`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/sources/bilibili_source.dart:203-229` supports auth-aware `getAudioStream()`.

Decision needed: If `getTrackInfo()` should only best-effort populate anonymous audio URLs, document that exception. If it should honor source auth consistently whenever it fetches streams, this is a code divergence.

