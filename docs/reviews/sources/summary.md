# Source Consistency Review Summary

## Review Corpus

規範性語料以 repo-local instructions 為主：`AGENTS.md:9` 到 `AGENTS.md:20` 定義 scoped instruction 讀取順序；source/audio/service 規範主要在 `lib/data/sources/AGENTS.md:3`、`lib/services/audio/AGENTS.md:42`、`lib/services/AGENTS.md:18`。`docs/README.md:9` 到 `docs/README.md:12` 指向的 `docs/development.md`、`docs/build-guide.md`、`docs/build-and-release.md`、`docs/debugging-with-vm-service.md` 是當前核心文檔；`docs/agents/` 目前不存在。`.serena/memories/refactoring_lessons.md:34` 到 `.serena/memories/refactoring_lessons.md:36` 是補充記憶，僅在不高於 `AGENTS.md` 時採用。

描述性語料不直接當事實；本次所有 source 行為結論都用 `lib/data/sources/*`、`lib/services/audio/*`、`lib/services/download/*`、`lib/services/lyrics/*` 與測試行號驗證。分報告位於：

- `docs/reviews/sources/bilibili-review.md`
- `docs/reviews/sources/youtube-review.md`
- `docs/reviews/sources/netease-review.md`
- `docs/reviews/sources/shared-contract-review.md`
- `docs/reviews/sources/playback-download-integration-review.md`
- `docs/reviews/sources/lyrics-source-review.md`
- `docs/reviews/sources/source-docs-alignment-review.md`

## Behavior Matrix

| Area | Bilibili | YouTube | Netease | Assessment |
|---|---|---|---|---|
| Primary `getAudioStream` identity | `bvid` path re-reads default `cid` (`lib/data/sources/bilibili_source.dart:223`, `lib/data/sources/bilibili_source.dart:231`); cid-aware API exists (`lib/data/sources/bilibili_source.dart:646`) | single video ID | single song ID | Bilibili needs source-specific `Track.cid` preservation in shared resolver. |
| Stream type fallback | DASH audio-only then durl muxed according to priority (`lib/data/sources/bilibili_source.dart:299`) | audio-only/muxed/HLS priority (`lib/data/sources/youtube_source.dart:333`) | audioOnly only (`lib/data/sources/base_source.dart:49`) | Differences are reasonable; fallback contract must preserve non-fallbackable errors. |
| Lower-quality fallback | shared high -> medium -> low (`lib/data/sources/audio_stream_quality_fallback.dart:33`) | same helper | same helper | Contract is consistent; sourceId-only helper breaks Bilibili multi-P. |
| Alternative stream | no override; base returns null (`lib/data/sources/base_source.dart:211`, `lib/data/sources/base_source.dart:217`) | excludes failed URL (`lib/data/sources/youtube_source.dart:659`, `lib/data/sources/youtube_source.dart:698`, `lib/data/sources/youtube_source.dart:1715`) | no override | YouTube-specific alternative is reasonable; Bilibili should use DASH backup/durl alternatives. |
| Error kind | Bilibili numeric codes map to `SourceErrorKind` (`lib/data/sources/bilibili_exception.dart:23`) | YouTube string code maps to `SourceErrorKind` (`lib/data/sources/youtube_exception.dart:20`) | Netease numeric codes map to `SourceErrorKind` (`lib/data/sources/netease_exception.dart:27`) | `kind` is mostly unified; YouTube non-Source exceptions and Bilibili `-3` are inconsistent. |
| Auth-for-play resolution | setting read before playback/download stream resolution (`lib/services/audio/internal/audio_stream_delegate.dart:71`, `lib/services/download/download_service.dart:702`) | same | same | Resolution is consistent. |
| Media headers | no auth merge for media (`lib/data/sources/source_http_policy.dart:37`) | no auth merge for media (`lib/data/sources/source_http_policy.dart:42`) | media headers can merge auth (`lib/data/sources/source_http_policy.dart:54`) | Netease difference is reasonable, but playback ignores the user setting. |
| URL expiry metadata | Bilibili stream returns expiry (`lib/data/sources/bilibili_source.dart:360`, `lib/data/sources/bilibili_source.dart:397`) | TTL constant exists (`lib/core/constants/app_constants.dart:28`) but stream constructors omit expiry (`lib/data/sources/youtube_source.dart:406`) | stream returns 16 min expiry (`lib/data/sources/netease_source.dart:154`, `lib/data/sources/netease_source.dart:160`) | YouTube should carry source TTL in `AudioStreamResult`. |
| Lyrics direct/original ID | video sources depend on title matching; `artist` is uploader/channel | same | direct lyrics by sourceId (`lib/services/lyrics/lyrics_auto_match_service.dart:103`) | Direct ID behavior is reasonable; regex fallback should not treat uploader/channel as song artist. |
| Download/image headers | helper path is source-aware (`lib/services/download/download_service.dart:764`, `lib/services/download/download_service.dart:1176`) | same | same | Core download path is correct; Netease external playlist import has hard-coded headers. |

## Reasonable Source-Specific Differences

- Bilibili needs `bvid + cid` for multi-P audio identity; YouTube/Netease single `sourceId` identity is appropriate. Evidence: `lib/data/models/track.dart:240`, `lib/data/sources/bilibili_source.dart:646`.
- YouTube has richer alternative stream selection because failed audio-only URLs can fall back to muxed/HLS while excluding the exact failed URL. Evidence: `lib/data/sources/youtube_source.dart:571`, `lib/data/sources/youtube_source.dart:659`, `lib/data/sources/youtube_source.dart:745`.
- Netease media requests may need `MUSIC_U`; Bilibili/YouTube auth is intentionally used for stream resolution rather than forwarded to CDN/media. Evidence: `lib/data/sources/source_http_policy.dart:54`, `lib/services/account/netease_account_service.dart:244`.
- Netease VIP/copyright/region classification must inspect per-song `fee/code/flag/message`, not only HTTP status. Evidence: `lib/data/sources/netease_source.dart:735`, `lib/data/sources/netease_source.dart:743`, `lib/data/sources/netease_source.dart:750`.
- Bilibili live APIs legitimately use live Referer and live Dio separate from regular video/search APIs. Evidence: `lib/data/sources/source_http_policy.dart:111`, `lib/data/sources/bilibili_source.dart:84`, `lib/data/sources/bilibili_source.dart:1084`.

## Unreasonable Inconsistencies

1. **Bilibili multi-P stream resolution drops `Track.cid`.** Playback and download call `fetchAudioStreamWithQualityFallback(sourceId: track.sourceId)` (`lib/services/audio/internal/audio_stream_delegate.dart:74`, `lib/services/download/download_service.dart:706`), while `BilibiliSource.getAudioStream()` re-reads the default `cid` (`lib/data/sources/bilibili_source.dart:223`) despite having `getAudioStreamWithCid()` (`lib/data/sources/bilibili_source.dart:646`). This can play/download the wrong page.
2. **Bilibili regular API requests inherit search headers.** `SourceHttpPolicy.apiHeaders()` defines regular Bilibili Origin/Referer (`lib/data/sources/source_http_policy.dart:72`, `lib/data/sources/source_http_policy.dart:74`), but `BilibiliSource` initializes `_dio` with `bilibiliSearchApiHeaders()` (`lib/data/sources/bilibili_source.dart:77`, `lib/data/sources/bilibili_source.dart:80`), then uses it for `_viewApi`/`_playUrlApi` (`lib/data/sources/bilibili_source.dart:215`, `lib/data/sources/bilibili_source.dart:316`).
3. **Bilibili account live import does not use live header policy.** `BilibiliAccountService` builds a regular Bilibili API Dio (`lib/services/account/bilibili_account_service.dart:74`, `lib/services/account/bilibili_account_service.dart:77`) but uses it for live APIs (`lib/services/account/bilibili_account_service.dart:488`, `lib/services/account/bilibili_account_service.dart:511`) instead of `SourceHttpPolicy.bilibiliLiveHeaders()` (`lib/data/sources/source_http_policy.dart:111`).
4. **Bilibili has no same-quality alternative stream fallback.** Base alternative returns null (`lib/data/sources/base_source.dart:211`, `lib/data/sources/base_source.dart:217`), while Bilibili only takes first DASH URL/backup and first durl (`lib/data/sources/bilibili_source.dart:346`, `lib/data/sources/bilibili_source.dart:348`, `lib/data/sources/bilibili_source.dart:387`).
5. **YouTube manifest failures can collapse into `no_stream`.** Non-`SourceApiException` errors in audio-only/muxed/HLS are swallowed unless rate-limit-like (`lib/data/sources/youtube_source.dart:414`, `lib/data/sources/youtube_source.dart:456`, `lib/data/sources/youtube_source.dart:505`, `lib/data/sources/youtube_source.dart:2122`), eventually becoming `no_stream` (`lib/data/sources/youtube_source.dart:364`).
6. **YouTube playability does not preserve geo restriction.** `YouTubeApiException` supports `geo_restricted` (`lib/data/sources/youtube_exception.dart:34`), but playability handling uses status strings without reason-based geo mapping (`lib/data/sources/youtube_source.dart:64`, `lib/data/sources/youtube_source.dart:68`, `lib/data/sources/youtube_source.dart:70`).
7. **Playback handoff lower-quality fallback can retry the failed URL.** Delegate passes `failedUrl` to `getAlternativeAudioStream()` (`lib/services/audio/internal/audio_stream_delegate.dart:133`) but then calls plain `source.getAudioStream()` without exclusion (`lib/services/audio/internal/audio_stream_delegate.dart:141`), which is risky for YouTube despite its source-level exclusion logic (`lib/data/sources/youtube_source.dart:1715`).
8. **Netease playback media auth bypasses `useNeteaseAuthForPlay`.** Stream/download resolution read the setting (`lib/services/audio/internal/audio_stream_delegate.dart:71`, `lib/services/download/download_service.dart:702`), but playback headers always fetch Netease auth (`lib/services/audio/audio_stream_manager.dart:181`, `lib/services/audio/audio_stream_manager.dart:182`).
9. **Netease external playlist import hard-codes headers.** It creates raw Dio (`lib/data/sources/playlist_import/netease_playlist_source.dart:12`) and repeats Netease UA/Referer (`lib/data/sources/playlist_import/netease_playlist_source.dart:126`, `lib/data/sources/playlist_import/netease_playlist_source.dart:176`) instead of `SourceHttpPolicy.apiHeaders()` (`lib/data/sources/source_http_policy.dart:66`).
10. **YouTube stream TTL is not carried in `AudioStreamResult`.** YouTube track refresh uses a one-hour TTL (`lib/core/constants/app_constants.dart:28`, `lib/data/sources/youtube_source.dart:779`), but primary stream results omit `expiry` (`lib/data/sources/youtube_source.dart:406`, `lib/data/sources/youtube_source.dart:448`, `lib/data/sources/youtube_source.dart:492`).
11. **Lyrics regex fallback treats video uploader/channel as song artist.** Regex fallback uses `track.artist` when parser has no artist (`lib/services/lyrics/lyrics_auto_match_service.dart:231`); Bilibili fills `artist` from owner (`lib/data/sources/bilibili_source.dart:183`) and YouTube from author/channel (`lib/data/sources/youtube_source.dart:177`), unlike Netease song artists (`lib/data/sources/netease_source.dart:611`, `lib/data/sources/netease_source.dart:629`).
12. **Manual lyrics single-source filters can bypass disabled sources.** Provider single-source branches call the selected source directly (`lib/providers/lyrics_provider.dart:337`, `lib/providers/lyrics_provider.dart:339`, `lib/providers/lyrics_provider.dart:345`, `lib/providers/lyrics_provider.dart:351`) while disabled enforcement is mainly UI/All-filter side (`lib/ui/pages/lyrics/lyrics_search_sheet.dart:133`, `lib/providers/lyrics_provider.dart:358`).
13. **Bilibili invalid-input code `-3` is classified as retryable network.** `-3` maps to network (`lib/data/sources/bilibili_exception.dart:24`, `lib/data/sources/bilibili_exception.dart:25`) but is thrown for invalid source type/favorites URL (`lib/data/sources/bilibili_source.dart:419`, `lib/data/sources/bilibili_source.dart:506`), and network is retryable (`lib/data/sources/source_exception.dart:16`).
14. **Netease semantic code string diverges for login.** Bilibili uses `login_required` (`lib/data/sources/bilibili_exception.dart:50`) and YouTube maps that string (`lib/data/sources/youtube_exception.dart:30`), while Netease 301 returns `requires_login` (`lib/data/sources/netease_exception.dart:51`, `lib/data/sources/netease_exception.dart:52`), though `kind` remains correct (`lib/data/sources/netease_exception.dart:37`).

## Shared Contract / Helper Targets

- **Track-aware stream resolver:** Replace duplicated `source.getAudioStream(track.sourceId, ...)` call sites in playback/download/fallback with a helper that accepts `Track`, `AudioStreamConfig`, `authHeaders`, and optional `failedUrl`. It should dispatch Bilibili `Track.cid` to `getAudioStreamWithCid()` (`lib/data/sources/bilibili_source.dart:646`) while keeping YouTube/Netease sourceId behavior. Current duplicated call sites: `lib/services/audio/internal/audio_stream_delegate.dart:74`, `lib/services/audio/internal/audio_stream_delegate.dart:141`, `lib/services/download/download_service.dart:706`.
- **Auth decision + media header helper:** Centralize `settings.useAuthForPlay(sourceType)` with media header construction so playback and download cannot diverge. Current divergence: `lib/services/audio/audio_stream_manager.dart:182` versus `lib/services/download/download_service.dart:702`.
- **YouTube exception classifier wrapper:** Add a small source-owned classifier for `youtube_explode_dart`/HTTP/timeout/socket errors before stream-type fallback. Current catch sites: `lib/data/sources/youtube_source.dart:414`, `lib/data/sources/youtube_source.dart:456`, `lib/data/sources/youtube_source.dart:505`.
- **SourceHttpPolicy coverage for import sources:** Reuse `SourceHttpPolicy.apiHeaders(SourceType.netease)` in `NeteasePlaylistSource` instead of hard-coded headers (`lib/data/sources/playlist_import/netease_playlist_source.dart:126`, `lib/data/sources/playlist_import/netease_playlist_source.dart:176`).
- **Alternative stream contract:** Either make `failedUrl` exclusion available to lower-quality primary fallback or forbid plain `getAudioStream()` after a failed URL when the source supports same URL reuse. Current risky call: `lib/services/audio/internal/audio_stream_delegate.dart:141`.

## User-Visible Risk

- **Wrong audio or download for Bilibili multi-P:** sourceId-only resolver can fetch default P instead of selected page (`lib/services/audio/internal/audio_stream_delegate.dart:74`, `lib/data/sources/bilibili_source.dart:223`).
- **Misleading error prompts / wrong retry behavior:** YouTube network/timeout/permission/geo errors can become generic unavailable (`lib/data/sources/youtube_source.dart:364`), and Bilibili invalid input can be retryable network (`lib/data/sources/bilibili_exception.dart:25`).
- **Auth privacy / expectation mismatch:** Netease media playback may send `MUSIC_U` even when auth-for-play is disabled (`lib/services/audio/audio_stream_manager.dart:182`).
- **Fallback loop or repeated failure:** handoff can reselect a failed YouTube URL through lower-quality primary fallback (`lib/services/audio/internal/audio_stream_delegate.dart:141`).
- **Lyrics mismatches:** Bilibili UP 主 / YouTube channel can be used as artist in regex fallback (`lib/services/lyrics/lyrics_auto_match_service.dart:231`).
- **Disabled lyrics source still queried:** stale manual filter can bypass `disabledLyricsSources` (`lib/providers/lyrics_provider.dart:337`).

## Documentation Updates Needed

- Fix Bilibili live docs: `lib/data/sources/AGENTS.md:11` says HLS, but current implementation reads `durl[0]` (`lib/data/sources/bilibili_source.dart:1135`, `lib/services/radio/radio_source.dart:280`, `lib/services/radio/radio_source.dart:286`).
- Fix shared stream contract wording: `lib/data/sources/AGENTS.md:116` says `getAudioUrl()` returns `AudioStreamResult`, but `getAudioStream()` returns it (`lib/data/sources/base_source.dart:182`) and `getAudioUrl()` returns `String` (`lib/data/sources/base_source.dart:190`).
- Add Bilibili multi-P integration rule: playback/download/fallback must preserve `Track.cid` when resolving streams. Current docs mention multi-P support (`lib/data/sources/AGENTS.md:8`) but not integration-layer cid preservation.
- Clarify Netease media auth setting: `lib/data/sources/AGENTS.md:168` to `lib/data/sources/AGENTS.md:170` explains Netease media auth merge, but should state whether `useNeteaseAuthForPlay` governs media headers too.
- Add YouTube expiry metadata expectation: docs mention `AudioStreamResult` metadata (`lib/data/sources/AGENTS.md:116`) but not that source-owned TTL should be returned for YouTube.
- Correct stale YouTube comment: authenticated InnerTube implementation uses WEB client (`lib/data/sources/youtube_source.dart:1642`), while nearby comments/docs should not imply androidVr auth path.

## Suggested Fix Order And Tests

1. **Fix Bilibili cid-aware stream resolution.**
   Code targets: `lib/services/audio/internal/audio_stream_delegate.dart:74`, `lib/services/audio/internal/audio_stream_delegate.dart:141`, `lib/services/download/download_service.dart:706`, `lib/data/sources/bilibili_source.dart:646`.
   Tests: add playback primary, download primary, and handoff fallback tests asserting selected `Track.cid` reaches Bilibili stream getter; extend `test/services/audio/audio_stream_manager_test.dart` and `test/services/download/download_service_phase1_test.dart`.

2. **Fix Netease playback media auth decision.**
   Code targets: `lib/services/audio/audio_stream_manager.dart:181`, `lib/data/sources/source_http_policy.dart:54`, `lib/services/download/download_service.dart:702`.
   Tests: update `test/services/audio/audio_stream_manager_test.dart` so `useNeteaseAuthForPlay=false` yields no media Cookie and true yields `MUSIC_U`; keep `test/services/download/download_media_headers_test.dart` aligned.

3. **Fix YouTube error preservation and failed URL exclusion.**
   Code targets: `lib/data/sources/youtube_source.dart:414`, `lib/data/sources/youtube_source.dart:456`, `lib/data/sources/youtube_source.dart:505`, `lib/services/audio/internal/audio_stream_delegate.dart:141`.
   Tests: add `test/data/sources/youtube_source_test.dart` cases for network/timeout/403 manifest errors not becoming `no_stream`; add audio stream manager test that fallback never returns `failedUrl`.

4. **Add Bilibili same-quality alternative stream.**
   Code targets: `lib/data/sources/base_source.dart:211`, `lib/data/sources/bilibili_source.dart:346`, `lib/data/sources/bilibili_source.dart:348`, `lib/data/sources/bilibili_source.dart:387`.
   Tests: Bilibili source test with DASH base URL failed, backup URL selected; durl fallback selected; rate-limit/login errors rethrown.

5. **Separate Bilibili regular/search/live header policy.**
   Code targets: `lib/data/sources/bilibili_source.dart:77`, `lib/data/sources/bilibili_source.dart:80`, `lib/services/account/bilibili_account_service.dart:488`, `lib/services/account/bilibili_account_service.dart:511`.
   Tests: Bilibili source tests asserting view/play URL use regular Referer/Origin while search keeps search Referer; account live import test asserting live Referer plus Cookie.

6. **Carry source TTL consistently.**
   Code targets: YouTube `AudioStreamResult` constructors at `lib/data/sources/youtube_source.dart:406`, `lib/data/sources/youtube_source.dart:448`, `lib/data/sources/youtube_source.dart:492`, InnerTube constructors around `lib/data/sources/youtube_source.dart:1736`.
   Tests: `test/services/audio/audio_stream_manager_test.dart` already has expiry behavior around `selectPlayback`; add YouTube source tests for explicit one-hour expiry metadata.

7. **Tighten lyrics source semantics.**
   Code targets: `lib/services/lyrics/lyrics_auto_match_service.dart:231`, `lib/providers/lyrics_provider.dart:337`, `lib/providers/lyrics_provider.dart:351`.
   Tests: Bilibili/YouTube regex fallback does not use uploader/channel as artist when parser lacks artist; Netease still uses song artist; disabled single-source manual filter does not call disabled source.

8. **Clean up shared exception/docs consistency.**
   Code/docs targets: `lib/data/sources/bilibili_exception.dart:25`, `lib/data/sources/netease_exception.dart:52`, `lib/data/sources/AGENTS.md:11`, `lib/data/sources/AGENTS.md:116`.
   Tests: update `test/data/sources/source_exception_test.dart` for non-retryable invalid-input semantics and chosen Netease login `code` contract; run `git diff --check` for docs.

Minimum verification after code fixes should include `flutter test test/data/sources test/services/audio test/services/download test/services/lyrics test/providers` plus `flutter analyze` when production code changes.
