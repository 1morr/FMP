# Network / Headers Security Review

Scope: `SourceHttpPolicy`, Dio clients, API headers, playback media headers,
download media/image headers, account auth interceptors, redirect/short URL
handling, radio/live headers, and update downloads. Descriptive instruction
docs were used as review questions only; conclusions below are grounded in code.

## Valid findings

### FMP-NH-01 - Medium - Netease `MUSIC_U` is attached by source type, not by request URL

FMP builds Netease media headers from the track source type and then reuses
those headers for playback, audio download, cover download, and avatar download.
When Netease auth-for-play is enabled, the resulting headers include the raw
`Cookie` value. The sinks accept URLs supplied by source/API metadata or local
track metadata and do not verify that the final request target is an allowed
Netease media host before sending `MUSIC_U`.

**Evidence**

- Netease auth-for-play defaults to enabled:
  `lib/data/models/settings.dart:275`, and `useAuthForPlay()` returns that
  value for Netease at `lib/data/models/settings.dart:587`.
- Netease auth headers include the raw cookie and source-origin headers:
  `lib/core/utils/auth_headers_utils.dart:24`,
  `lib/core/utils/auth_headers_utils.dart:27`,
  `lib/data/sources/source_http_policy.dart:118`,
  `lib/data/sources/source_http_policy.dart:120`.
- `SourceHttpPolicy.mediaHeaders()` copies `Cookie` into all Netease media
  headers when auth headers are present:
  `lib/data/sources/source_http_policy.dart:33`,
  `lib/data/sources/source_http_policy.dart:47`,
  `lib/data/sources/source_http_policy.dart:54`.
- Playback headers are computed only from `track.sourceType`, not from the
  playback URL host: `lib/services/audio/audio_stream_manager.dart:184`,
  `lib/services/audio/audio_stream_manager.dart:191`. `selectPlayback()` then
  returns those headers for `trackWithUrl.audioUrl`:
  `lib/services/audio/audio_stream_manager.dart:121`,
  `lib/services/audio/audio_stream_manager.dart:123`,
  `lib/services/audio/audio_stream_manager.dart:132`.
- Netease audio URLs come directly from the platform response without host or
  scheme validation: `lib/data/sources/netease_source.dart:139`,
  `lib/data/sources/netease_source.dart:140`,
  `lib/data/sources/netease_source.dart:156`.
- Downloaded audio uses the same source-type media headers for the resolved
  `audioUrl`: `lib/services/download/download_service.dart:702`,
  `lib/services/download/download_service.dart:713`,
  `lib/services/download/download_service.dart:764`,
  `lib/services/download/download_service.dart:772`,
  `lib/services/download/download_service.dart:774`. The isolate sends every
  supplied header to `Uri.parse(params.url)`:
  `lib/services/download/download_service.dart:1488`,
  `lib/services/download/download_service.dart:1491`.
- Image downloads reuse the media-header helper:
  `lib/services/download/download_media_headers.dart:14`,
  `lib/services/download/download_media_headers.dart:18`. `_saveMetadata()`
  builds image headers once and sends them to `track.thumbnailUrl` and
  `videoDetail.ownerFace`: `lib/services/download/download_service.dart:1176`,
  `lib/services/download/download_service.dart:1241`,
  `lib/services/download/download_service.dart:1244`,
  `lib/services/download/download_service.dart:1257`,
  `lib/services/download/download_service.dart:1260`.
- Netease track and detail image URLs come from remote metadata:
  `lib/data/sources/netease_source.dart:397`,
  `lib/data/sources/netease_source.dart:444`,
  `lib/data/sources/netease_source.dart:448`,
  `lib/data/sources/netease_source.dart:450`,
  `lib/data/sources/netease_source.dart:598`,
  `lib/data/sources/netease_source.dart:609`,
  `lib/data/sources/netease_source.dart:698`. The existing thumbnail utility
  documents normal Netease image hosts as `music.126.net`, including `http://`
  examples: `lib/core/utils/thumbnail_url_utils.dart:244`,
  `lib/core/utils/thumbnail_url_utils.dart:252`.
- Tests confirm the current intended behavior preserves Netease cookies in both
  media and image headers: `test/services/download/download_media_headers_test.dart:33`,
  `test/services/download/download_media_headers_test.dart:45`,
  `test/services/download/download_media_headers_test.dart:72`,
  `test/services/download/download_media_headers_test.dart:85`,
  `test/services/audio/audio_stream_manager_test.dart:785`,
  `test/services/audio/audio_stream_manager_test.dart:802`.

**Attack or failure scenario**

A malicious or compromised Netease API response, a poisoned local track row, or a
crafted restore/import path that leaves a Netease track with an attacker URL in
`thumbnailUrl`, `ownerFace`, or an audio stream URL can cause FMP to request that
URL with `Cookie: MUSIC_U=...`. For cover/avatar downloads this does not require
the attacker URL to be a media CDN URL: `_saveMetadata()` sends the source-type
image headers to whatever URL is in the metadata. For audio playback/download,
the same URL-blind policy means a non-allowlisted URL returned as the stream URL
receives the cookie on the initial request. If the URL is `http://`, the cookie
is also exposed on cleartext transport.

**Recommended fix**

Bind credential-bearing media headers to the request URL, not only to
`SourceType`.

- Split Netease image headers from Netease media headers. Image downloads should
  normally use only `User-Agent` plus the source referer/origin, without
  `Cookie`.
- Before adding `Cookie` to Netease media requests, parse the target URI and
  require `https` plus an explicit allowlist of hosts that actually require
  authenticated media access.
- Apply the same allowlist in playback and download paths, including cover and
  avatar downloads, and strip credential headers on redirects or when the final
  URL leaves the allowlist.
- Add tests that cover attacker-controlled `https://example.invalid/cover.jpg`,
  `http://p1.music.126.net/...`, and a non-allowlisted audio URL for Netease
  tracks.

## Checked and safe items

- Bilibili and YouTube media/download headers do not carry account auth. The
  policy drops Bilibili cookies and YouTube authorization/cookies from media
  headers at `lib/data/sources/source_http_policy.dart:37` and
  `lib/data/sources/source_http_policy.dart:42`; tests cover this at
  `test/data/sources/source_http_policy_test.dart:7`,
  `test/data/sources/source_http_policy_test.dart:19`,
  `test/services/download/download_media_headers_test.dart:10`, and
  `test/services/download/download_media_headers_test.dart:21`.
- YouTube SAPISID/SAPISIDHASH auth is used for `www.youtube.com/youtubei/v1`
  API calls. The base is fixed at `lib/data/sources/youtube_source.dart:23` and
  `lib/services/account/youtube_account_service.dart:27`; auth headers are
  added to InnerTube requests at `lib/data/sources/youtube_source.dart:49` and
  `lib/data/sources/youtube_source.dart:117`, and account/playlist mutations use
  the same fixed base at `lib/services/account/youtube_account_service.dart:168`
  and `lib/services/account/youtube_playlist_service.dart:90`.
- Bilibili generated browser cookies and optional account cookies are used on
  fixed Bilibili API endpoints. `BilibiliSource` creates its API Dio through
  `SourceHttpPolicy.createApiDio()` and a generated browser cookie at
  `lib/data/sources/bilibili_source.dart:79`; account refresh endpoints are
  fixed Bilibili/passport URLs at
  `lib/services/account/bilibili_account_service.dart:299`,
  `lib/services/account/bilibili_account_service.dart:335`, and
  `lib/services/account/bilibili_account_service.dart:346`.
- Bilibili live/radio headers are narrower than account API headers. Live Dio
  uses `SourceHttpPolicy.createBilibiliLiveDio()` at
  `lib/services/radio/radio_source.dart:93`; stream playback receives only
  `SourceHttpPolicy.bilibiliLiveHeaders()` at
  `lib/services/radio/radio_source.dart:286` and
  `lib/services/radio/radio_source.dart:290`. The policy has no `Cookie` in
  live headers at `lib/data/sources/source_http_policy.dart:111`.
- Netease playlist short URL resolution currently does not send account cookies.
  The import source creates a non-auth Netease API Dio at
  `lib/data/sources/playlist_import/netease_playlist_source.dart:14`, resolves
  `163cn.tv` with HEAD/GET at
  `lib/data/sources/playlist_import/netease_playlist_source.dart:71`, and only
  sends normal Netease API headers to playlist/detail API calls at
  `lib/data/sources/playlist_import/netease_playlist_source.dart:123` and
  `lib/data/sources/playlist_import/netease_playlist_source.dart:175`.
- Spotify and QQ playlist short URL resolution uses fresh unauthenticated Dio
  clients, so no platform account cookie is available to leak:
  `lib/data/sources/playlist_import/spotify_playlist_source.dart:14`,
  `lib/data/sources/playlist_import/spotify_playlist_source.dart:74`,
  `lib/data/sources/playlist_import/qq_music_playlist_source.dart:12`, and
  `lib/data/sources/playlist_import/qq_music_playlist_source.dart:100`.
- Update checks and update downloads do not attach source cookies or auth
  headers. The update Dio has timeout-only defaults at
  `lib/services/update/update_service.dart:111`; the GitHub release request
  sends only `Accept` at `lib/services/update/update_service.dart:225`, and
  asset downloads call `_dio.download()` without credential headers at
  `lib/services/update/update_service.dart:364`,
  `lib/services/update/update_service.dart:404`, and
  `lib/services/update/update_service.dart:434`.
- `DownloadService` does not rely on default source cookies in its shared Dio.
  Its default headers only set a media user agent at
  `lib/services/download/download_service.dart:159`,
  `lib/services/download/download_service.dart:162`.

## Evidence

Review coverage included targeted searches for `Dio()`, `createApiDio`,
`Options(headers:)`, `getAuthHeaders`, `Cookie`, `Authorization`, `Referer`,
`Origin`, `followRedirects`, `maxRedirects`, `head`, and download/playback URL
sinks under `lib/data/sources`, `lib/services/account`,
`lib/services/download`, `lib/services/radio`, and `lib/services/update`.

The main vulnerable flow is:

1. `Settings.useNeteaseAuthForPlay` defaults to true:
   `lib/data/models/settings.dart:275`.
2. `DownloadService` resolves Netease auth headers when the setting is true:
   `lib/services/download/download_service.dart:702`.
3. `buildDownloadImageHeaders()` and `buildDownloadMediaHeaders()` both call
   `SourceHttpPolicy.mediaHeaders()`:
   `lib/services/download/download_media_headers.dart:4` and
   `lib/services/download/download_media_headers.dart:14`.
4. `SourceHttpPolicy.mediaHeaders()` copies `Cookie` for every Netease media
   header build:
   `lib/data/sources/source_http_policy.dart:54`.
5. The resulting headers are sent to URLs that are not checked against the
   cookie's domain:
   `lib/services/download/download_service.dart:1242`,
   `lib/services/download/download_service.dart:1258`,
   `lib/services/download/download_service.dart:1488`.

## Attack or failure scenario

The concrete credential at risk is Netease `MUSIC_U`, a long-lived cookie stored
by the account service and returned by `getAuthCookieString()` at
`lib/services/account/netease_account_service.dart:238`. The app intentionally
uses it for Netease playback when auth-for-play is enabled, but the current
header boundary is `SourceType.netease`, not a URL allowlist. Any path that
places an attacker-controlled URL into Netease audio or image metadata can
receive that cookie during playback or download.

## Recommended fix

Implement a URL-aware credential policy for Netease:

- `SourceHttpPolicy` should expose a helper that accepts `(sourceType, uri,
  requestKind, authHeaders)` and only returns credential headers when the parsed
  URI matches an approved HTTPS host for that request kind.
- `buildDownloadImageHeaders()` should not reuse credential-bearing media
  headers.
- The playback path should compute headers for the selected URL, not only for
  the `Track`.
- The download isolate should receive already-filtered headers and should not
  follow credential-bearing redirects to hosts outside the same allowlist.

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md` is accurate that `SourceHttpPolicy.mediaHeaders()`
  currently merges auth headers only for Netease media requests, and code/tests
  confirm that boundary.
- `lib/services/AGENTS.md` is accurate that downloads use
  `buildDownloadMediaHeaders()` and `buildDownloadImageHeaders()` instead of Dio
  defaults.
- The instructions do not distinguish Netease media URLs from Netease image URLs
  or require a host/scheme allowlist before sending `MUSIC_U`. That omission
  matches the current bug: the image helper aliases the media helper and tests
  assert that Netease image headers preserve `Cookie`.
