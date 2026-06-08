# Source Capability Deepening Design

## Goal

Remove runtime concrete source access by routing Bilibili, YouTube, and
Netease source behavior through narrow source capabilities while preserving
current product behavior.

## Context

FMP already uses narrow source capabilities for several source operations:

- `TrackInfoSource`
- `AudioStreamSource`
- `SearchSource`
- `PlaylistParsingSource`
- `AvailabilitySource`

`SourceManager` is the source registry and can resolve these capabilities by
`SourceType`. The friction is that it also exposes concrete source getters:

- `bilibiliSource`
- `youtubeSource`
- `neteaseSource`

Runtime modules use those concrete getters and providers to call operations
that are not represented as capabilities yet. Current leaked operations include
track detail, Bilibili multi-page video pages, YouTube Mix metadata and tracks,
home ranking, and Bilibili live search/stream helpers.

Recent refactors already moved in this direction:

- `centralize stream resolution`
- `centralize bilibili live client`

This refactor should extend that pattern rather than introducing a broad facade.

## Scope

This is a behavior-preserving architecture refactor. It includes:

- Adding narrow source capabilities for currently leaked source operations.
- Making existing source adapters implement those capabilities.
- Updating runtime callers to use capability lookups rather than concrete
  source classes or concrete source providers.
- Removing `SourceManager` concrete source getters.
- Removing public runtime concrete source providers:
  `bilibiliSourceProvider`, `youtubeSourceProvider`, and
  `neteaseAudioSourceProvider`.
- Adding guard coverage so runtime code cannot reintroduce concrete source
  access.
- Updating scoped AGENTS guidance affected by the source seam.

It does not include:

- Product behavior changes.
- Audio stream resolution changes beyond call-site wiring.
- Header or auth policy changes.
- A new broad `SourceOperations` or `ExtendedSource` facade.
- A redesign of ranking, live, import, download, or track detail UX.
- Removing direct concrete source usage from tests.

## Architecture

Use per-domain source capability interfaces. Runtime callers should learn only
the interface they need.

Add capabilities to `lib/data/sources/source_capabilities.dart`:

- `TrackDetailSource`: fetches `VideoDetail`.
- `PagedVideoSource`: fetches `VideoPage` lists for multi-page sources.
- `DynamicPlaylistSource`: owns YouTube Mix metadata and dynamic track fetches.
- `RankingSource`: fetches source-specific home/popular ranking tracks.
- `LiveSource`: owns live-room search and stream helpers.

Existing capabilities stay unchanged:

- `TrackInfoSource`
- `AudioStreamSource`
- `SearchSource`
- `PlaylistParsingSource`
- `AvailabilitySource`

`SourceManager` remains the runtime registry. It should expose capability lookup
methods only, such as:

- `trackDetailSource(SourceType type)`
- `pagedVideoSource(SourceType type)`
- `dynamicPlaylistSource(SourceType type)`
- `rankingSource(SourceType type)`
- `liveSource(SourceType type)`

Adapter construction remains concrete inside `SourceManager`. `SourceManager()`
may still instantiate `BilibiliSource`, `YouTubeSource`, and `NeteaseSource`.
The restriction is on runtime consumers, not source adapter construction or
tests.

The source adapters keep source-owned behavior:

- `BilibiliSource` implements Bilibili detail, pages, ranking, and live
  capabilities where it already exposes that behavior.
- `YouTubeSource` implements YouTube detail, Mix, and ranking capabilities.
- `NeteaseSource` implements Netease detail and ranking capabilities.

## Data Flow

### Track Detail

`TrackDetailNotifier` depends on `SourceManager` instead of concrete source
classes. For each track it asks:

```text
SourceManager.trackDetailSource(track.sourceType)
```

Then it calls `getVideoDetail(track.sourceId, authHeaders: authHeaders)`.

Local metadata fallback stays in `TrackDetailNotifier`; the source capability
only owns network detail lookup.

### Download Metadata

`DownloadService` uses `TrackDetailSource` when saving metadata after audio
download finalization.

It keeps the current behavior:

- Bilibili and YouTube can fetch detail for metadata.
- Netease does not use the local metadata fallback path currently used for
  downloaded Bilibili/YouTube files.
- Detail fetch failure is logged and does not fail the completed audio
  download.

### Playlist Import And Refresh

`ImportService` keeps using `PlaylistParsingSource` to parse playlist URLs.

For Bilibili multi-page expansion, it asks:

```text
SourceManager.pagedVideoSource(source.sourceType)
```

If the capability is absent, tracks are left unexpanded.

For dynamic playlist import, it asks:

```text
SourceManager.dynamicPlaylistSourceForUrl(normalizedUrl)
```

Then it uses the dynamic playlist capability for Mix metadata and track fetches
only when the capability's `sourceType` matches the parser source type. This
prevents non-YouTube playlist URLs with `list=RD...` query parameters from being
routed into YouTube Mix import.

### Search Multi-Page Expansion

`SearchService.loadVideoPagesForTrack()` asks `PagedVideoSource` for the
track's source type.

Unsupported sources return an empty list. Missing Bilibili support is treated
as a source configuration error through the existing `SearchException` path.

### Home Ranking

Ranking cache and popular providers ask `RankingSource` for the requested
source type.

Ranking behavior stays source-specific:

- Bilibili music ranking.
- YouTube trending music ranking.
- Netease hot ranking tracks.

The ranking cache still owns refresh orchestration and state. The capability
only owns platform ranking fetches.

### Bilibili Live

Search and radio live paths ask `LiveSource` for `SourceType.bilibili`.

The existing Bilibili live client remains the implementation owner for live
endpoint mechanics. The capability is the runtime seam used by callers.

## Error Handling

Capability lookup failures should be explicit and close to the caller:

- Callers with existing domain exceptions keep using them, such as
  `SearchException` and `ImportException`.
- Provider or impossible configuration failures may use `StateError`.
- Unsupported optional capabilities return benign results where existing
  behavior already does, such as an empty page list for non-Bilibili sources.

Source-specific exceptions stay source-owned:

- `BilibiliApiException`
- `YouTubeApiException`
- `NeteaseApiException`

The new capability interfaces must not flatten those into generic exceptions.

Auth headers remain caller-owned for this refactor. The capability methods
accept `authHeaders` where the current concrete methods already accept them.
This preserves the existing separation between stream resolution auth, media
headers, account state, and refresh auth.

## Compatibility

Allowed concrete source references:

- Inside source adapter files.
- Inside `SourceManager` construction and disposal.
- Inside tests and test fakes.

Disallowed runtime concrete source access:

- `SourceManager.bilibiliSource`
- `SourceManager.youtubeSource`
- `SourceManager.neteaseSource`
- `bilibiliSourceProvider`
- `youtubeSourceProvider`
- `neteaseAudioSourceProvider`
- Runtime imports whose only purpose is concrete source access.

Existing product behavior must remain unchanged:

- Bilibili multi-page playlist expansion.
- Bilibili page loading from search results.
- YouTube Mix import and dynamic track fetching.
- Home ranking refresh for Bilibili, YouTube, and Netease.
- Bilibili live search and stream helpers.
- Netease track detail.
- Source-specific exception semantics.

## Testing

Use TDD for implementation. Each behavior migration should start with a failing
test that proves the runtime module depends on a capability instead of a
concrete source.

Required tests:

- Source manager resolves each new capability for supported source types and
  returns `null` for unsupported source types.
- `TrackDetailNotifier` loads detail through `TrackDetailSource` and does not
  require concrete Bilibili, YouTube, or Netease sources.
- `DownloadService` metadata fetch uses `TrackDetailSource` and preserves
  detail-failure tolerance.
- `ImportService` Bilibili expansion uses `PagedVideoSource`.
- `ImportService` YouTube Mix import uses `DynamicPlaylistSource`.
- `ImportService` keeps non-YouTube URLs with `list=RD...` query parameters on
  the parser path instead of treating them as YouTube Mix imports.
- `SearchService.loadVideoPagesForTrack()` uses `PagedVideoSource` and returns
  an empty list for unsupported sources.
- Ranking cache or ranking providers use `RankingSource`.
- Live search/stream callers use `LiveSource`.
- A structural guard fails if runtime `lib/` code reintroduces concrete source
  getters or concrete source providers outside the allowed construction files.

Targeted verification during implementation should use the smallest relevant
test first. Final verification should include:

```bash
flutter test test/data/sources test/services/import test/services/download test/services/cache
flutter test test/providers/track_detail_refresh_stale_test.dart test/providers/search_pagination_stale_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
flutter test test/ui/pages/search test/ui/pages/home test/ui/pages/ranking_ui_state_consumption_test.dart
flutter analyze
```

Run the full `flutter test test/providers` suite only after known unrelated
baseline failures in that suite are fixed.

If the implementation touches audio Mix playback fetchers, also run:

```bash
flutter test test/services/audio
```

## Documentation

Update `lib/data/sources/AGENTS.md` to state that source-specific operations
should be exposed through narrow capabilities and that runtime code must not
consume concrete source getters/providers.

Update other scoped AGENTS files only if the implementation changes their
current guidance:

- `lib/services/AGENTS.md` if download/import/radio wording changes.
- `lib/providers/AGENTS.md` if provider wiring guidance changes.

No human-facing docs update is expected because behavior should not change.

## Constraints

- Preserve unrelated user changes in the working tree.
- Do not change public product behavior.
- Do not introduce hidden global enabled-source filters.
- Do not bypass `AudioController` from UI playback controls.
- Do not alter persisted schema semantics.
- Do not commit unless explicitly requested by the user.
