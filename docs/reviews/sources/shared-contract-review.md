# Shared Source Contract Review

## Findings

1. **Bilibili regular API headers inherit search-host policy.** `SourceHttpPolicy.apiHeaders(SourceType.bilibili)` defines regular Bilibili API headers with `Referer: https://www.bilibili.com/` and `Origin: https://www.bilibili.com`, but `BilibiliSource` initializes its shared `_dio` with `SourceHttpPolicy.bilibiliSearchApiHeaders()` as `extraHeaders`. Regular video/play API calls such as `_viewApi` and `_playUrlApi` then reuse that Dio without overriding the search `Referer`/`Origin`. This violates the shared header contract for regular Bilibili API/media requests while preserving no source-specific need outside search.
   Evidence: `lib/data/sources/source_http_policy.dart:72`, `lib/data/sources/source_http_policy.dart:74`, `lib/data/sources/source_http_policy.dart:95`, `lib/data/sources/source_http_policy.dart:103`, `lib/data/sources/bilibili_source.dart:77`, `lib/data/sources/bilibili_source.dart:80`, `lib/data/sources/bilibili_source.dart:170`, `lib/data/sources/bilibili_source.dart:316`.

2. **Netease playback media headers bypass the auth-for-play switch.** Primary stream resolution and handoff fallback read `settings.useAuthForPlay(track.sourceType)`, but `AudioStreamManager.getPlaybackHeaders()` always requests Netease auth headers for media playback, and `SourceHttpPolicy.mediaHeaders()` merges Netease cookies when provided. That means disabling Netease auth-for-play can still send account cookies to media/CDN requests.
   Evidence: `lib/services/audio/internal/audio_stream_delegate.dart:69`, `lib/services/audio/internal/audio_stream_delegate.dart:71`, `lib/services/audio/internal/audio_stream_delegate.dart:122`, `lib/services/audio/internal/audio_stream_delegate.dart:124`, `lib/services/audio/audio_stream_manager.dart:181`, `lib/services/audio/audio_stream_manager.dart:182`, `lib/data/sources/source_http_policy.dart:54`, `lib/data/sources/source_http_policy.dart:55`.

3. **YouTube stream TTL is not part of `AudioStreamResult`, unlike Bilibili/Netease.** YouTube has a source-specific TTL and applies it in `getTrackInfo()` / `refreshAudioUrl()`, but the actual `AudioStreamResult` constructors omit `expiry`. Shared playback caching therefore falls back to a generic default instead of receiving source-owned metadata through the shared contract.
   Evidence: `lib/core/constants/app_constants.dart:28`, `lib/data/sources/youtube_source.dart:183`, `lib/data/sources/youtube_source.dart:187`, `lib/data/sources/youtube_source.dart:406`, `lib/data/sources/youtube_source.dart:411`, `lib/data/sources/youtube_source.dart:779`, `lib/data/sources/youtube_source.dart:782`, `lib/services/audio/audio_stream_manager.dart:153`, `lib/services/audio/audio_stream_manager.dart:155`.

4. **Bilibili invalid-input exceptions are classified as retryable network errors.** `BilibiliApiException.kind` maps numeric code `-3` to `SourceErrorKind.network`, but the source also throws `-3` for invalid favorites URLs and invalid source type. This collapses caller/input errors into the shared retryable network category.
   Evidence: `lib/data/sources/bilibili_exception.dart:24`, `lib/data/sources/bilibili_exception.dart:25`, `lib/data/sources/bilibili_source.dart:506`, `lib/data/sources/bilibili_source.dart:507`, `lib/data/sources/bilibili_source.dart:419`, `lib/data/sources/bilibili_source.dart:420`, `lib/data/sources/source_exception.dart:16`.

## Evidence

The shared fallback contract itself is correctly centralized: only `unavailable` and `vipRequired` can fall back to lower audio quality. Evidence: `lib/data/sources/source_exception.dart:24`, `lib/data/sources/source_exception.dart:25`, `lib/data/sources/source_exception.dart:26`, `lib/data/sources/audio_stream_quality_fallback.dart:49`, `lib/data/sources/audio_stream_quality_fallback.dart:50`.

Download media/image headers are also centralized through shared helpers. Evidence: `lib/services/download/download_media_headers.dart:4`, `lib/services/download/download_media_headers.dart:8`, `lib/services/download/download_media_headers.dart:14`, `lib/services/download/download_media_headers.dart:18`, `lib/services/download/download_service.dart:764`, `lib/services/download/download_service.dart:1176`.

## Source-specific reason if applicable

Bilibili search can reasonably keep generated `buvid` cookies and search-host headers, but that should stay scoped to search calls. Evidence: `lib/data/sources/bilibili_source.dart:70`, `lib/data/sources/bilibili_source.dart:77`, `lib/data/sources/source_http_policy.dart:95`.

Netease media-cookie forwarding is a legitimate source-specific difference; the issue is that the forwarding is not governed by the same auth-for-play decision as stream resolution. Evidence: `lib/services/account/netease_account_service.dart:244`, `lib/services/account/netease_account_service.dart:246`, `lib/data/sources/source_http_policy.dart:54`, `lib/data/models/settings.dart:236`.

## Suggested direction

- Split Bilibili search headers from regular video/play API headers, either with separate Dio clients or explicit per-request options.
- Make Netease playback media headers honor `settings.useAuthForPlay(SourceType.netease)`, or document/rename the setting as stream-resolution-only and add an explicit media-cookie policy.
- Set YouTube `AudioStreamResult.expiry` in primary, alternative, and InnerTube stream paths.
- Stop using Bilibili code `-3` for invalid caller/input errors, or map those cases to a non-retryable kind.

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md:21` says regular Bilibili media/API requests require the regular Bilibili referer; current Bilibili source construction contradicts that at `lib/data/sources/bilibili_source.dart:80`.
- `lib/data/sources/AGENTS.md:150` through `lib/data/sources/AGENTS.md:155` accurately describe auth-for-play propagation for stream resolution and downloads, but not Netease playback media headers at `lib/services/audio/audio_stream_manager.dart:182`.
- `lib/data/sources/AGENTS.md:116` through `lib/data/sources/AGENTS.md:119` should explicitly include source-owned `expiry` expectations beyond Bilibili if shared caching depends on source TTL metadata.
