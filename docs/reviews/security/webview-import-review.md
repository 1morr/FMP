# WebView And Playlist Import Security Review

Scope: WebView cookie extraction, playlist URL import, short URL resolution,
Spotify / QQ Music / Netease import, URL validation, redirect handling, HTML
parsing, and untrusted input handling.

Review basis: code evidence only. Descriptive docs were used as questions to
verify, not as proof of implementation behavior.

## Valid findings

### Medium: Short URL import can request attacker-controlled local or LAN URLs before host validation

**Affected code**

- User-controlled URL reaches import validation and dispatch:
  - `lib/ui/pages/library/widgets/import_playlist_dialog.dart:253`
  - `lib/ui/pages/library/widgets/import_playlist_dialog.dart:268`
  - `lib/ui/pages/library/widgets/import_playlist_dialog.dart:562`
  - `lib/ui/pages/library/widgets/import_playlist_dialog.dart:565`
  - `lib/services/import/playlist_import_service.dart:136`
  - `lib/services/import/playlist_import_service.dart:202`
  - `lib/services/import/import_service.dart:198`
  - `lib/services/import/import_service.dart:201`
  - `lib/services/import/import_service.dart:223`
- Substring-based source/short-link detection:
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:21`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:22`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:23`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:18`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:19`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:98`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:20`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:21`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:22`
  - `lib/data/sources/netease_source.dart:55`
  - `lib/data/sources/netease_source.dart:58`
- Request sinks using the unvalidated original URL:
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:71`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:74`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:88`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:96`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:100`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:71`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:74`
  - `lib/data/sources/netease_source.dart:716`
  - `lib/data/sources/netease_source.dart:718`
  - `lib/data/sources/netease_source.dart:729`

**Evidence**

The UI accepts a pasted URL, validates it by asking import/source detectors, and
passes the same trimmed URL to import execution. The detectors use
`String.contains()` rather than parsing `Uri.host`. For example, Spotify accepts
any string containing `open.spotify.com/playlist` or `spotify.link`, and its
short-link resolver performs `_dio.get(url, followRedirects: true)`. QQ Music
and Netease have the same pattern for `c.y.qq.com` / `url.cn` and `163cn.tv`.
The internal Netease playlist path is also reachable because
`SourceManager.getSourceForUrl()` returns sources based on `isPlaylistUrl()`.

This means inputs such as these can cause a local request before the import
eventually fails or parses a platform ID:

```text
http://127.0.0.1:8080/?x=spotify.link
http://127.0.0.1:8080/?x=c.y.qq.com&id=123
http://127.0.0.1:8080/?x=163cn.tv&id=12345
```

For legitimate short-link hosts, the QQ and Spotify resolvers also follow up to
five redirects without validating each redirect destination, so an attacker-held
short link can redirect the desktop/mobile client to `127.0.0.1`, RFC1918 LAN
addresses, or link-local metadata-style addresses.

I did not find credential leakage in this path. The Netease short URL request
uses the source API Dio with static Netease `Origin` / `Referer` / `User-Agent`
headers from `SourceHttpPolicy.apiHeaders()` at
`lib/data/sources/source_http_policy.dart:83`, not account cookies. QQ and
Spotify use plain `Dio()` instances. The issue is therefore SSRF-like local/LAN
request capability from a user-imported URL, not platform cookie exfiltration.

**Attack or failure scenario**

An attacker shares a playlist import URL that visually appears to mention a
supported platform or uses a real short-link service. When a user pastes it into
the import dialog, FMP makes a request from the user's device to an attacker
chosen local or LAN URL. This can probe whether local services exist, trigger
state-changing GET/HEAD endpoints on local admin panels, or send platform-like
Referer/Origin headers to a non-platform service. Because FMP is a client app
and no account cookies were found on this path, the impact is below a server-side
credential SSRF, but it is still a real untrusted-input network boundary issue.

**Recommended fix**

Replace substring checks with a shared URL validator:

- Parse with `Uri.tryParse`, require `http` or `https`, and compare normalized
  `uri.host` against exact allowlists before any network request.
- For short links, allow only the intended short-link hosts as the initial
  request target: `163cn.tv`, `c.y.qq.com` / `url.cn`, and `spotify.link`.
- Disable automatic redirect following for user-controlled URLs. Resolve each
  `Location` manually, enforce scheme/host allowlists for the destination, and
  reject private, loopback, link-local, multicast, and unspecified IP ranges.
- Keep playlist ID extraction host-aware: parse IDs only from expected platform
  hosts and expected path/query fields.
- Add regression tests for `https://evil.test/?x=spotify.link`,
  `http://127.0.0.1/?x=163cn.tv`, and short-link redirects to `127.0.0.1`.

## Checked and safe items

- WebView cookie extraction did not show a reportable cross-domain cookie leak.
  Bilibili, YouTube, and Netease login pages extract cookies through
  `CookieManager.getCookies()` for fixed platform URLs, not from the currently
  loaded arbitrary URL:
  - `lib/ui/pages/settings/bilibili_login_page.dart:138`
  - `lib/ui/pages/settings/youtube_login_page.dart:127`
  - `lib/ui/pages/settings/netease_login_page.dart:135`
- WebView cleanup is present after login and on dispose for platform cookie
  stores/cache/web storage:
  - `lib/ui/pages/settings/bilibili_login_page.dart:104`
  - `lib/ui/pages/settings/youtube_login_page.dart:34`
  - `lib/ui/pages/settings/netease_login_page.dart:106`
- Account services persist only selected required cookies after validation
  gates, not entire WebView cookie jars:
  - `lib/services/account/bilibili_account_service.dart:87`
  - `lib/services/account/youtube_account_service.dart:52`
  - `lib/services/account/netease_account_service.dart:54`
  - `lib/services/account/netease_account_service.dart:74`
- YouTube playlist import uses fixed YouTube/InnerTube endpoints after extracting
  `list` with `Uri.queryParameters`; I did not find a user-controlled HTTP
  request to the pasted YouTube URL itself:
  - `lib/data/sources/youtube_source.dart:1125`
  - `lib/data/sources/youtube_source.dart:1126`
  - `lib/data/sources/youtube_source.dart:1345`
  - `lib/data/sources/youtube_source.dart:1363`
- Spotify HTML parsing fetches a fixed embed URL after extracting an
  alphanumeric playlist ID and parses `__NEXT_DATA__` as JSON. No script
  execution sink was found in the parser:
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:26`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:30`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:45`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:90`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:100`
- QQ Music API import posts to a fixed QQ endpoint after converting playlist ID
  to an integer. `QQMusicSign` is local signing logic over generated request
  JSON, not execution of remote code:
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:55`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:122`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:125`
- Netease playlist API import posts to fixed Netease endpoints after playlist ID
  extraction and uses numeric IDs in the request body:
  - `lib/services/library/remote_playlist_id_parser.dart:29`
  - `lib/services/library/remote_playlist_id_parser.dart:30`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:123`
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:169`
- Media/download auth-header policy matched the documented security boundary:
  Bilibili/YouTube auth is not merged into generic media headers, while Netease
  auth merging is explicit and source-scoped:
  - `lib/data/sources/source_http_policy.dart:33`
  - `lib/data/sources/source_http_policy.dart:54`
  - `lib/data/sources/source_http_policy.dart:55`

## Instruction docs accuracy notes

- `lib/services/AGENTS.md` and `lib/data/sources/AGENTS.md` accurately describe
  that external playlist import supports Netease short links, QQ Music formats,
  and Spotify embed `__NEXT_DATA__` parsing. The code confirms this in:
  - `lib/data/sources/playlist_import/netease_playlist_source.dart:71`
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:122`
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:90`
- The suggested path `lib/services/playlist_import/**` does not exist in this
  checkout. The actual service-layer import files are under `lib/services/import/`,
  with platform-specific parser implementations under
  `lib/data/sources/playlist_import/`.
- The docs state short URLs are resolved through HEAD/GET redirects. That is
  accurate for Netease, and GET redirect following is present for QQ/Spotify.
  The docs do not mention the current lack of host and redirect-destination
  validation before these requests.
- The docs' WebView cookie extraction claims are broadly accurate: Bilibili,
  YouTube, and Netease all have WebView cookie extraction implementations, with
  QR alternatives for Bilibili/Netease.

## Verification performed

- Read required instruction and threat-model files:
  - `AGENTS.md`
  - `lib/services/AGENTS.md`
  - `lib/data/sources/AGENTS.md`
  - `docs/reviews/security/instruction-document-corpus.md`
  - `docs/reviews/security/threat-model.md`
- Traced user input from the import dialog through providers/services into
  platform-specific import sources.
- Reviewed WebView cookie extraction and account-service persistence paths for
  cookie scope and obvious logging/exfiltration sinks.
- Reviewed redirect handling, URL detection, Spotify HTML parsing, QQ signing,
  and Netease/YouTube playlist ID extraction.

No product code was modified.
