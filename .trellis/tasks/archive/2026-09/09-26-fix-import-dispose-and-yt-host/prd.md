# Close the import-service leak and host-check playlist URLs

## Goal

Fix the class-A defects from the spec reality pass
(`archive/2026-09/09-26-align-specs-with-code/research/spec-audit.md`) that
have a failure condition a test can reproduce: a playlist-import service
that is never disposed, and playlist URLs routed to a source by substring.

## Background

- **Import service.** `playlistImportServiceProvider`
  (`lib/providers/library/playlist_import_provider.dart:334`) builds a
  `PlaylistImportService` and registers no `ref.onDispose`.
  `PlaylistImportService.dispose()` (`lib/services/import/playlist_import_service.dart:1203`)
  closes the broadcast `_progressController`. The provider `ref.watch`es
  `sourceManagerProvider`, so every rebuild or invalidation
  (`test/providers/notifier_rebuild_test.dart:149` does one) strands the
  old service with an open controller — unless `PlaylistImportNotifier`
  happens to be alive: its `_teardown` called `_service.dispose()` on a
  service it does not own. That hid most of the leak and has its own
  failure: invalidating the notifier alone closes the still-shared
  service, and the rebuilt notifier listens to a closed stream.
- **Routing.** `SourceManager.playlistParsingSourceForUrl`
  (`lib/data/sources/source_provider.dart:75`) asks sources in order
  `Bilibili → YouTube → Netease` and takes the first `isPlaylistUrl` hit.
  The same call routes refreshes: `ImportService` stores the user's trimmed
  input as `playlist.sourceUrl` (`import_service.dart:263`) and routes it
  again on refresh (`:434`).
  - `BilibiliSource.isPlaylistUrl` (`bilibili_source.dart:193-201`) checks
    no host: any URL containing `favlist`, `medialist`, `/fav/`,
    `fid=<digits>` or `ml<digits>` is claimed. Being asked first, it takes a
    YouTube playlist whose id contains `ml` + digit (`...html5...`), and
    the import fails.
  - `YouTubeSource.isPlaylistUrl` (`youtube_source.dart:185-197`) accepts
    any URL whose text contains `youtube.com` / `youtu.be` plus `list=` or
    `/playlist`, e.g. `https://attacker.example/?u=youtube.com&list=x`.
  - `NeteaseSource.isPlaylistUrl` (`netease_source.dart:69`) already uses
    `SourceUrlPolicy.parseTrustedHttpUrl` with host sets;
    `test/data/sources/source_url_policy_test.dart` pins "rejects substring
    host spoofing" for Netease, Spotify and QQ Music.
  - Scheme-less input (`www.youtube.com/playlist?list=…`) passes today's
    substring checks and may already be stored; `Uri.tryParse` gives it no
    host.
  - `b23.tv` short links match none of Bilibili's substrings, so they have
    never imported a favorites folder.

## Requirements

- **R1** — disposing or rebuilding `playlistImportServiceProvider` calls
  `dispose()` on the service it built (`ref.onDispose(service.dispose)`),
  and the provider is the only owner: `PlaylistImportNotifier._teardown`
  cancels its subscription and no longer disposes the service (found
  during implementation, 2026-09-26).
- **R2** — `YouTubeSource.isPlaylistUrl` parses the URL through
  `SourceUrlPolicy.parseTrustedHttpUrl` with a new YouTube host set
  (`youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`,
  `youtu.be`), then requires a `list` query parameter or a `/playlist` path.
- **R3** — `BilibiliSource.isPlaylistUrl` does the same with a new Bilibili
  host set (`bilibili.com`, `www.bilibili.com`, `m.bilibili.com`,
  `space.bilibili.com`), then applies today's favorites shapes to the
  accepted URL. `b23.tv` stays unsupported.
- **R4** — scheme-less input stays accepted (user decision, 2026-09-26):
  a URL with no `scheme://` is read as `https://` before the host check, in
  one `SourceUrlPolicy` helper both sources call. Netease is unchanged.
- **R5** — specs match the result in the same round:
  `.trellis/spec/data/sources.md:54-59` (YouTube "does not use it yet"; the
  Bilibili claim now holds), `services/service-conventions.md:41` and
  `ui/riverpod.md:61` (the `playlistImportServiceProvider` gap).
- Comments on touched lines are Traditional Chinese.

## Acceptance Criteria

- [x] R1: a test invalidates `playlistImportServiceProvider` and sees the
      old service's `progressStream` complete; it fails without the fix.
- [x] R1: a test invalidates `playlistImportProvider` alone and sees the
      shared service's `progressStream` still open and delivering to the
      rebuilt notifier; it fails with the old `_service.dispose()` line.
- [x] R2/R3: "rejects substring host spoofing" in
      `source_url_policy_test.dart` covers `YouTubeSource.isPlaylistUrl` and
      `BilibiliSource.isPlaylistUrl`; each case fails without the fix.
- [x] R3: `SourceManager.playlistParsingSourceForUrl` routes a YouTube
      playlist URL whose id contains `ml` + digit to YouTube; fails without
      the fix.
- [x] R2: still true — `www.youtube.com/playlist?list=`,
      `www.youtube.com/watch?v=…&list=`, `m.youtube.com/…&list=`,
      `music.youtube.com/playlist?list=`, `youtu.be/<id>?list=`; false — a
      YouTube video URL without `list`.
- [x] R3: still true — `space.bilibili.com/<uid>/favlist?fid=<id>`,
      `www.bilibili.com/medialist/detail/ml<id>`.
- [x] R4: the scheme-less forms of one YouTube and one Bilibili playlist
      URL return true; `attacker.example/?u=youtube.com&list=x` returns false.
- [x] R5: the three spec passages describe the new code.
- [x] `flutter test test/data/sources test/providers test/services/import`,
      `flutter analyze` and `dart format --output=none --set-exit-if-changed lib test tool`
      pass.

## Out of Scope

- `state.error = e.toString()` in `AudioController` / `RankingCacheService`
  — never rendered as text, no failure condition.
- `netease_playlist_service.dart:198` message matching — the server's error
  code is undocumented; needs a live probe first.
- `b23.tv` resolution, `SourceUrlPolicy.parseBilibiliFavoritesId`'s regexes,
  and `YouTubeSource.parseId` / `isMixPlaylistUrl`.
- No on-device check: no UI or rendered string changes.
