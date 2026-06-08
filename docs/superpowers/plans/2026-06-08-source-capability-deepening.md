# Source Capability Deepening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove runtime concrete access to Bilibili, YouTube, and Netease data source adapters by routing callers through narrow source capabilities.

**Architecture:** Add per-domain capability interfaces to the source registry, make existing source adapters implement them, and migrate runtime call sites capability-by-capability. Keep concrete adapter construction inside `SourceManager`; tests may still instantiate concrete source adapters directly.

**Tech Stack:** Flutter/Dart, Riverpod, Isar, existing FMP source adapters, `flutter test`, `flutter analyze`.

---

## Commit Policy

The repository `AGENTS.md` says not to commit unless the user explicitly asks.
All "checkpoint" steps in this plan mean: inspect `git diff` and leave changes
unstaged/uncommitted. Do not run `git commit`.

## File Structure

Create:

- `lib/data/sources/dynamic_playlist_types.dart` - source-neutral Mix playlist DTOs currently defined in `youtube_source.dart`.

Modify:

- `lib/data/sources/source_capabilities.dart` - new narrow interfaces and ranking request DTO.
- `lib/data/sources/source_provider.dart` - new capability lookups; remove concrete getters/providers after migrations.
- `lib/data/sources/source_url_policy.dart` - move source-neutral playlist URL parsers out of concrete adapters.
- `lib/data/sources/bilibili_source.dart` - implement detail, pages, ranking, live capabilities.
- `lib/data/sources/youtube_source.dart` - implement detail, dynamic playlist, ranking capabilities; move Mix DTOs.
- `lib/data/sources/netease_source.dart` - implement detail and ranking capabilities.
- `lib/services/audio/mix_playlist_types.dart` - export `MixFetchResult` from the new DTO file.
- `lib/services/audio/audio_provider.dart` - remove `YouTubeSource` dependency; inject dynamic playlist fetcher from capability.
- `lib/providers/library/track_detail_provider.dart` - load details through `TrackDetailSource`.
- `lib/services/download/download_service.dart` - fetch metadata details through `TrackDetailSource`.
- `lib/services/import/import_service.dart` - use `DynamicPlaylistSource` and `PagedVideoSource`.
- `lib/services/search/search_service.dart` - load video pages through `PagedVideoSource`.
- `lib/providers/library/playlist_provider.dart` - load Mix tracks through `DynamicPlaylistSource`.
- `lib/services/cache/ranking_cache_service.dart` - depend on `RankingSource` interfaces.
- `lib/providers/search/popular_provider.dart` - depend on `RankingSource` interfaces.
- `lib/providers/search/search_provider.dart` - depend on `LiveSource` interface.
- `lib/services/library/remote_playlist_id_parser.dart` - remove static concrete `BilibiliSource` parser dependency.
- `lib/ui/pages/debug/youtube_stream_test_page.dart` - use `TrackDetailSource` and `AudioStreamSource`.
- `lib/data/sources/AGENTS.md` - document no runtime concrete source access.

Test files to modify or add:

- `test/data/sources/source_capabilities_test.dart`
- `test/data/sources/source_ownership_phase3_test.dart`
- `test/providers/track_detail_refresh_stale_test.dart`
- `test/services/download/download_service_phase1_test.dart`
- `test/services/import/import_service_phase4_test.dart`
- `test/services/import/import_service_refresh_partial_test.dart`
- `test/providers/search_pagination_stale_test.dart`
- `test/services/cache/ranking_cache_service_test.dart`
- `test/ui/pages/home/home_ranking_sources_test.dart`
- `test/ui/pages/ranking_ui_state_consumption_test.dart`
- `test/ui/pages/search/search_page_phase2_test.dart`

---

### Task 1: Add Capability Contracts And Source-Neutral DTOs

**Files:**
- Create: `lib/data/sources/dynamic_playlist_types.dart`
- Modify: `lib/data/sources/source_capabilities.dart`
- Modify: `lib/data/sources/source_provider.dart`
- Test: `test/data/sources/source_capabilities_test.dart`

- [ ] **Step 1: Write the failing capability lookup test**

Append this test to `test/data/sources/source_capabilities_test.dart`:

```dart
test('source manager exposes detail, pages, dynamic playlist, ranking, and live capabilities', () {
  final manager = SourceManager();
  addTearDown(manager.dispose);

  expect(manager.trackDetailSource(SourceType.bilibili), isA<TrackDetailSource>());
  expect(manager.trackDetailSource(SourceType.youtube), isA<TrackDetailSource>());
  expect(manager.trackDetailSource(SourceType.netease), isA<TrackDetailSource>());

  expect(manager.pagedVideoSource(SourceType.bilibili), isA<PagedVideoSource>());
  expect(manager.pagedVideoSource(SourceType.youtube), isNull);
  expect(manager.pagedVideoSource(SourceType.netease), isNull);

  expect(manager.dynamicPlaylistSource(SourceType.youtube), isA<DynamicPlaylistSource>());
  expect(manager.dynamicPlaylistSource(SourceType.bilibili), isNull);
  expect(manager.dynamicPlaylistSource(SourceType.netease), isNull);

  expect(manager.rankingSource(SourceType.bilibili), isA<RankingSource>());
  expect(manager.rankingSource(SourceType.youtube), isA<RankingSource>());
  expect(manager.rankingSource(SourceType.netease), isA<RankingSource>());

  expect(manager.liveSource(SourceType.bilibili), isA<LiveSource>());
  expect(manager.liveSource(SourceType.youtube), isNull);
  expect(manager.liveSource(SourceType.netease), isNull);
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
flutter test test/data/sources/source_capabilities_test.dart
```

Expected: compile failure because `TrackDetailSource`, `PagedVideoSource`,
`DynamicPlaylistSource`, `RankingSource`, `LiveSource`, and lookup methods do
not exist.

- [ ] **Step 3: Create source-neutral Mix DTOs**

Create `lib/data/sources/dynamic_playlist_types.dart`:

```dart
import '../models/track.dart';

/// Dynamic playlist metadata used for imported Mix-style playlists.
class MixPlaylistInfo {
  final String title;
  final String playlistId;
  final String seedVideoId;
  final String? coverUrl;

  const MixPlaylistInfo({
    required this.title,
    required this.playlistId,
    required this.seedVideoId,
    this.coverUrl,
  });
}

/// Dynamic playlist track fetch result.
class MixFetchResult {
  final String title;
  final List<Track> tracks;

  const MixFetchResult({
    required this.title,
    required this.tracks,
  });
}
```

- [ ] **Step 4: Add capability interfaces**

Update `lib/data/sources/source_capabilities.dart` imports:

```dart
import '../models/live_room.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';
import 'dynamic_playlist_types.dart';
```

Add these declarations after `AudioStreamSourceConvenience`:

```dart
abstract interface class TrackDetailSource implements SourceCapability {
  Future<VideoDetail> getVideoDetail(
    String sourceId, {
    Map<String, String>? authHeaders,
  });
}

abstract interface class PagedVideoSource implements SourceCapability {
  Future<List<VideoPage>> getVideoPages(
    String sourceId, {
    Map<String, String>? authHeaders,
  });
}

abstract interface class DynamicPlaylistSource implements SourceCapability {
  bool isDynamicPlaylistUrl(String url);

  Future<MixPlaylistInfo> getMixPlaylistInfo(String url);

  Future<MixFetchResult> fetchMixTracks({
    required String playlistId,
    required String currentVideoId,
  });
}

class SourceRankingRequest {
  const SourceRankingRequest({
    this.regionId,
    this.category,
    this.limit,
  });

  final int? regionId;
  final String? category;
  final int? limit;
}

abstract interface class RankingSource implements SourceCapability {
  Future<List<Track>> getRankingTracks(SourceRankingRequest request);
}

abstract interface class LiveSource implements SourceCapability {
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  });

  Future<String?> getLiveStreamUrl(int roomId);
}
```

- [ ] **Step 5: Add SourceManager lookup methods**

Add to `SourceManager` in `lib/data/sources/source_provider.dart`:

```dart
TrackDetailSource? trackDetailSource(SourceType type) =>
    _capability<TrackDetailSource>(type);

PagedVideoSource? pagedVideoSource(SourceType type) =>
    _capability<PagedVideoSource>(type);

DynamicPlaylistSource? dynamicPlaylistSource(SourceType type) =>
    _capability<DynamicPlaylistSource>(type);

DynamicPlaylistSource? dynamicPlaylistSourceForUrl(String url) {
  for (final source in _sources.whereType<DynamicPlaylistSource>()) {
    if (source.isDynamicPlaylistUrl(url)) return source;
  }
  return null;
}

RankingSource? rankingSource(SourceType type) =>
    _capability<RankingSource>(type);

LiveSource? liveSource(SourceType type) => _capability<LiveSource>(type);
```

- [ ] **Step 6: Run the test and verify current failure narrows**

Run:

```bash
flutter test test/data/sources/source_capabilities_test.dart
```

Expected: the test still fails because adapters do not implement the new
interfaces yet.

- [ ] **Step 7: Checkpoint**

Run:

```bash
git diff -- lib/data/sources/dynamic_playlist_types.dart lib/data/sources/source_capabilities.dart lib/data/sources/source_provider.dart test/data/sources/source_capabilities_test.dart
```

Expected: only capability contracts, lookup methods, and the failing test are
changed.

---

### Task 2: Make Existing Adapters Implement The New Capabilities

**Files:**
- Modify: `lib/data/sources/bilibili_source.dart`
- Modify: `lib/data/sources/youtube_source.dart`
- Modify: `lib/data/sources/netease_source.dart`
- Modify: `lib/services/audio/mix_playlist_types.dart`
- Test: `test/data/sources/source_capabilities_test.dart`

- [ ] **Step 1: Move YouTube Mix DTO imports**

In `lib/data/sources/youtube_source.dart`, add:

```dart
import 'dynamic_playlist_types.dart';
```

Remove the `MixPlaylistInfo` and `MixFetchResult` class declarations from the
bottom of `youtube_source.dart`. The method signatures keep the same type names
because they now come from `dynamic_playlist_types.dart`.

- [ ] **Step 2: Update audio Mix type export**

Replace `lib/services/audio/mix_playlist_types.dart` with:

```dart
import '../../data/sources/dynamic_playlist_types.dart' show MixFetchResult;
export '../../data/sources/dynamic_playlist_types.dart' show MixFetchResult;

typedef MixTracksFetcher = Future<MixFetchResult> Function({
  required String playlistId,
  required String currentVideoId,
});
```

- [ ] **Step 3: Add Bilibili capability implementations**

Change the `BilibiliSource` implements list to include:

```dart
        AvailabilitySource,
        TrackDetailSource,
        PagedVideoSource,
        RankingSource,
        LiveSource {
```

Add this method near `getRankingVideos`:

```dart
  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) {
    return getRankingVideos(rid: request.regionId ?? 0);
  }
```

Existing `getVideoDetail`, `getVideoPages`, `searchLiveRooms`, and
`getLiveStreamUrl` satisfy the other new capability interfaces.

- [ ] **Step 4: Add YouTube capability implementations**

Change the `YouTubeSource` implements list to include:

```dart
        AvailabilitySource,
        TrackDetailSource,
        DynamicPlaylistSource,
        RankingSource {
```

Add:

```dart
  @override
  bool isDynamicPlaylistUrl(String url) => YouTubeSource.isMixPlaylistUrl(url);

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) {
    return getTrendingVideos(category: request.category ?? 'music');
  }
```

Existing `getVideoDetail`, `getMixPlaylistInfo`, and `fetchMixTracks` satisfy
the remaining new capability interface methods.

- [ ] **Step 5: Add Netease capability implementations**

Change the `NeteaseSource` implements list to include:

```dart
        AvailabilitySource,
        TrackDetailSource,
        RankingSource {
```

Add:

```dart
  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) {
    return getHotRankingTracks(limit: request.limit ?? 50);
  }
```

Existing `getVideoDetail` satisfies `TrackDetailSource`.

- [ ] **Step 6: Run the capability test and verify green**

Run:

```bash
flutter test test/data/sources/source_capabilities_test.dart
```

Expected: all tests in the file pass.

- [ ] **Step 7: Checkpoint**

Run:

```bash
git diff -- lib/data/sources/bilibili_source.dart lib/data/sources/youtube_source.dart lib/data/sources/netease_source.dart lib/services/audio/mix_playlist_types.dart
```

Expected: only interface lists, small adapter methods, and DTO relocation are
changed.

---

### Task 3: Migrate Track Detail Provider To TrackDetailSource

**Files:**
- Modify: `lib/providers/library/track_detail_provider.dart`
- Modify: `test/providers/track_detail_refresh_stale_test.dart`

- [ ] **Step 1: Write the failing provider test update**

In `test/providers/track_detail_refresh_stale_test.dart`, replace fake source
subclasses with one fake capability:

```dart
class _CompletingTrackDetailSource implements TrackDetailSource {
  _CompletingTrackDetailSource(this.sourceType);

  @override
  final SourceType sourceType;

  final requests = <String>[];
  final completers = <String, Completer<VideoDetail>>{};

  @override
  Future<VideoDetail> getVideoDetail(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) {
    requests.add(sourceId);
    final completer = Completer<VideoDetail>();
    completers[sourceId] = completer;
    return completer.future;
  }

  void complete(String sourceId, VideoDetail detail) {
    completers[sourceId]!.complete(detail);
  }
}
```

Update notifier construction in the tests to:

```dart
final sourceManager = SourceManager(sources: [
  bilibili,
  youtube,
  netease,
]);
addTearDown(sourceManager.dispose);

final notifier = TrackDetailNotifier(sourceManager, ref);
```

- [ ] **Step 2: Run the provider test and verify it fails**

Run:

```bash
flutter test test/providers/track_detail_refresh_stale_test.dart
```

Expected: compile failure because `TrackDetailNotifier` still expects concrete
sources.

- [ ] **Step 3: Update TrackDetailNotifier dependencies**

In `lib/providers/library/track_detail_provider.dart`:

Remove concrete source imports:

```dart
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/netease_source.dart';
import '../../data/sources/youtube_source.dart';
```

Add:

```dart
import '../../data/sources/source_capabilities.dart';
```

Change fields and constructor:

```dart
class TrackDetailNotifier extends StateNotifier<TrackDetailState> {
  final SourceManager _sourceManager;
  final Ref _ref;
  Track? _currentTrack;

  TrackDetailNotifier(this._sourceManager, this._ref)
      : super(const TrackDetailState());
```

Add helper:

```dart
  Future<VideoDetail> _loadNetworkDetail(Track track) async {
    final source = _sourceManager.trackDetailSource(track.sourceType);
    if (source == null) {
      throw StateError(
        'Track detail source not registered: ${track.sourceType.name}',
      );
    }

    final authHeaders = await getAuthHeadersForPlatform(track.sourceType, _ref);
    return source.getVideoDetail(track.sourceId, authHeaders: authHeaders);
  }
```

Replace both source-type branches in `loadDetail()` and `refresh()` with:

```dart
detail = await _loadNetworkDetail(track);
```

For `refresh()`, keep `VideoDetail detail;` and assign:

```dart
final detail = await _loadNetworkDetail(track);
```

Update provider construction:

```dart
  final sourceManager = ref.watch(sourceManagerProvider);
  final notifier = TrackDetailNotifier(sourceManager, ref);
```

- [ ] **Step 4: Run the provider test and verify green**

Run:

```bash
flutter test test/providers/track_detail_refresh_stale_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Checkpoint**

Run:

```bash
git diff -- lib/providers/library/track_detail_provider.dart test/providers/track_detail_refresh_stale_test.dart
```

Expected: `TrackDetailNotifier` no longer imports or stores concrete data
sources.

---

### Task 4: Migrate Download Metadata, Import, Search, And Playlist Mix

**Files:**
- Modify: `lib/services/download/download_service.dart`
- Modify: `lib/services/import/import_service.dart`
- Modify: `lib/services/search/search_service.dart`
- Modify: `lib/providers/library/playlist_provider.dart`
- Test: `test/services/download/download_service_phase1_test.dart`
- Test: `test/services/import/import_service_phase4_test.dart`
- Test: `test/services/import/import_service_refresh_partial_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Write failing import capability tests**

In `test/services/import/import_service_phase4_test.dart`, update fake source
managers so YouTube Mix is exposed through `DynamicPlaylistSource`, not
`youtubeSource`. Add this expectation to the Mix import test:

```dart
expect(sourceManager.dynamicPlaylistLookupCount, 1);
```

Also add a regression where a non-YouTube playlist URL containing a
`list=RD...` query parameter stays on the parser path and does not call Mix
metadata. This protects against `YouTubeSource.isMixPlaylistUrl()` matching
query shape without validating the URL host.

In the fake manager, add:

```dart
DynamicPlaylistSource? dynamicPlaylistSourceOverride;
int dynamicPlaylistLookupCount = 0;

@override
DynamicPlaylistSource? dynamicPlaylistSourceForUrl(String url) {
  dynamicPlaylistLookupCount++;
  final source = dynamicPlaylistSourceOverride ?? detectedSource;
  return source is DynamicPlaylistSource && source.isDynamicPlaylistUrl(url)
      ? source
      : null;
}
```

- [ ] **Step 2: Run import tests and verify failure**

Run:

```bash
flutter test test/services/import/import_service_phase4_test.dart test/services/import/import_service_refresh_partial_test.dart
```

Expected: compile or assertion failure because `ImportService` still calls
`YouTubeSource.isMixPlaylistUrl`, `_sourceManager.youtubeSource`, and
`_sourceManager.bilibiliSource`.

- [ ] **Step 3: Migrate `DownloadService` detail lookup**

In `lib/services/download/download_service.dart`, replace the Bilibili/YouTube
concrete detail block with:

```dart
      VideoDetail? videoDetail;
      try {
        final settings = await _settingsRepository.get();
        final detailSource = _sourceManager.trackDetailSource(track.sourceType);
        if (detailSource != null && track.sourceType != SourceType.netease) {
          final detailAuthHeaders = settings.useAuthForPlay(track.sourceType)
              ? await _getAuthHeaders(track.sourceType)
              : null;
          videoDetail = await detailSource.getVideoDetail(
            track.sourceId,
            authHeaders: detailAuthHeaders,
          );
        }
      } catch (e) {
        logDebug('Failed to get video detail: $e');
      }
```

- [ ] **Step 4: Migrate `ImportService` Mix detection and multi-page expansion**

In `lib/services/import/import_service.dart`, remove the concrete
`BilibiliSource` and `YouTubeSource` runtime imports if they are only used by
this wiring.

Before playlist parsing in `importFromUrl()`, replace static YouTube Mix
detection with:

```dart
      final dynamicPlaylistSource =
          _sourceManager.dynamicPlaylistSourceForUrl(normalizedUrl);
      if (dynamicPlaylistSource != null &&
          dynamicPlaylistSource.sourceType == source.sourceType) {
        return _importMixPlaylist(
          source: dynamicPlaylistSource,
          url: normalizedUrl,
          customName: customName,
          refreshIntervalHours: refreshIntervalHours,
          notifyOnUpdate: notifyOnUpdate,
        );
      }
```

Change `_importMixPlaylist` signature:

```dart
  Future<ImportResult> _importMixPlaylist({
    required DynamicPlaylistSource source,
    required String url,
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
  }) async {
```

Inside `_importMixPlaylist`, replace:

```dart
    final youtubeSource = _sourceManager.youtubeSource;
```

with the `source` parameter and call:

```dart
      final mixInfo = await source.getMixPlaylistInfo(url);
```

Change `_expandMultiPageVideos` signature:

```dart
  Future<_TrackExpansionResult> _expandMultiPageVideos(
    PagedVideoSource source,
    List<Track> tracks,
    void Function(int current, int total, String item) onProgress,
  ) async {
```

In `importFromUrl()`, replace the concrete Bilibili lookup with:

```dart
      final pagedVideoSource = _sourceManager.pagedVideoSource(source.sourceType);
      if (pagedVideoSource != null) {
        final expansion = await _expandMultiPageVideos(
          pagedVideoSource,
          result.tracks,
          (current, total, item) {
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                current: current.toString(),
                total: total.toString(),
              ),
            );
          },
        );
        expandedTracks = expansion.tracks;
      } else {
        expandedTracks = result.tracks;
      }
```

In `refreshPlaylist()`, replace the concrete Bilibili lookup with:

```dart
      final pagedVideoSource = _sourceManager.pagedVideoSource(source.sourceType);
      if (pagedVideoSource != null) {
        final expansion = await _expandMultiPageVideos(
          pagedVideoSource,
          result.tracks,
          (current, total, item) {
            _throwIfCancelled();
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                current: current.toString(),
                total: total.toString(),
              ),
            );
          },
        );
        expandedTracks = expansion.tracks;
        expansionComplete = expansion.isComplete;
      } else {
        expandedTracks = result.tracks;
        expansionComplete = true;
      }
```

- [ ] **Step 5: Migrate `SearchService.loadVideoPagesForTrack()`**

In `lib/services/search/search_service.dart`, replace the concrete lookup with:

```dart
    final source = _sourceManager.pagedVideoSource(track.sourceType);
    if (source == null) {
      if (track.sourceType == SourceType.bilibili) {
        throw SearchException(
          t.error.sourceUnavailable(source: SourceType.bilibili.name),
        );
      }
      return const [];
    }

    final authHeaders = await buildAuthHeaders(
      track.sourceType,
      bilibiliAccountService: _bilibiliAccountService,
    );

    return source.getVideoPages(track.sourceId, authHeaders: authHeaders);
```

- [ ] **Step 6: Migrate playlist detail Mix loading**

In `lib/providers/library/playlist_provider.dart`, replace:

```dart
      final youtubeSource = _ref.read(youtubeSourceProvider);
      final result = await youtubeSource.fetchMixTracks(
```

with:

```dart
      final dynamicSource = _ref
          .read(sourceManagerProvider)
          .dynamicPlaylistSource(SourceType.youtube);
      if (dynamicSource == null) {
        throw StateError(t.importSource.mixLoadFailed);
      }
      final result = await dynamicSource.fetchMixTracks(
```

- [ ] **Step 7: Run targeted tests and verify green**

Run:

```bash
flutter test test/services/download/download_service_phase1_test.dart
flutter test test/services/import/import_service_phase4_test.dart test/services/import/import_service_refresh_partial_test.dart
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: all targeted tests pass after fake source managers are updated to
override capability lookup methods instead of concrete getters.

- [ ] **Step 8: Checkpoint**

Run:

```bash
rg -n "sourceManager\\.bilibiliSource|sourceManager\\.youtubeSource|sourceManager\\.neteaseSource|_sourceManager\\.bilibiliSource|_sourceManager\\.youtubeSource|_sourceManager\\.neteaseSource|youtubeSourceProvider" lib/services/download lib/services/import lib/services/search lib/providers/library
```

Expected: no matches in the migrated runtime files.

---

### Task 5: Migrate Audio Mix Playback To DynamicPlaylistSource

**Files:**
- Modify: `lib/services/audio/audio_provider.dart`
- Test: `test/services/audio/audio_controller_mix_boundary_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Write failing static guard update**

In `test/ui/pages/search/search_page_phase2_test.dart`, extend
`playlist mix bootstrap goes through the audio controller boundary`:

```dart
expect(
  audioProviderSource.contains('YouTubeSource? _youtubeSource'),
  isFalse,
  reason: 'AudioController should not keep a concrete YouTube source fallback.',
);

expect(
  audioProviderSource.contains('youtubeSourceProvider'),
  isFalse,
  reason: 'Audio provider wiring should inject a MixTracksFetcher from a capability.',
);
```

- [ ] **Step 2: Run the guard and verify failure**

Run:

```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: fails because `AudioController` still stores `YouTubeSource?` and
the provider reads `youtubeSourceProvider`.

- [ ] **Step 3: Remove concrete YouTube fallback from AudioController**

In `lib/services/audio/audio_provider.dart`:

Remove the `youtube_source.dart` import if it becomes unused.

Remove field:

```dart
  final YouTubeSource? _youtubeSource;
```

Remove constructor parameter:

```dart
    YouTubeSource? youtubeSource,
```

Remove initializer:

```dart
        _youtubeSource = youtubeSource,
```

Replace both fetcher selections:

```dart
final fetcher = _mixTracksFetcher ?? _youtubeSource?.fetchMixTracks;
```

with:

```dart
final fetcher = _mixTracksFetcher;
```

In `audioControllerProvider`, pass:

```dart
    mixTracksFetcher: ref
        .watch(sourceManagerProvider)
        .dynamicPlaylistSource(SourceType.youtube)
        ?.fetchMixTracks,
```

Do not pass `youtubeSource`.

- [ ] **Step 4: Run audio Mix tests**

Run:

```bash
flutter test test/services/audio/audio_controller_mix_boundary_test.dart
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: tests pass.

- [ ] **Step 5: Checkpoint**

Run:

```bash
rg -n "YouTubeSource\\?|youtubeSourceProvider|_youtubeSource" lib/services/audio/audio_provider.dart
```

Expected: no matches.

---

### Task 6: Migrate Ranking Providers And Cache To RankingSource

**Files:**
- Modify: `lib/services/cache/ranking_cache_service.dart`
- Modify: `lib/providers/search/popular_provider.dart`
- Test: `test/services/cache/ranking_cache_service_test.dart`
- Test: `test/ui/pages/home/home_ranking_sources_test.dart`
- Test: `test/ui/pages/ranking_ui_state_consumption_test.dart`

- [ ] **Step 1: Write failing ranking cache constructor tests**

In `test/services/cache/ranking_cache_service_test.dart`, update fake sources
to implement `RankingSource` instead of extending concrete source classes:

```dart
class _FakeRankingSource implements RankingSource {
  _FakeRankingSource(this.sourceType);

  @override
  final SourceType sourceType;

  List<Track> tracks = const [];
  Object? failure;
  int fetchCount = 0;
  SourceRankingRequest? lastRequest;

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) async {
    fetchCount++;
    lastRequest = request;
    final error = failure;
    if (error != null) throw error;
    return tracks;
  }
}
```

Update service construction:

```dart
final service = RankingCacheService(
  bilibiliRankingSource: _FakeRankingSource(SourceType.bilibili),
  youtubeRankingSource: _FakeRankingSource(SourceType.youtube),
  neteaseRankingSource: _FakeRankingSource(SourceType.netease),
);
```

- [ ] **Step 2: Run ranking tests and verify failure**

Run:

```bash
flutter test test/services/cache/ranking_cache_service_test.dart
```

Expected: compile failure because `RankingCacheService` still requires concrete
source classes.

- [ ] **Step 3: Update `RankingCacheService` constructor and refresh methods**

In `lib/services/cache/ranking_cache_service.dart`, replace concrete source
imports with:

```dart
import '../../data/sources/source_capabilities.dart';
```

Replace fields:

```dart
  final RankingSource _bilibiliRankingSource;
  final RankingSource _youtubeRankingSource;
  final RankingSource _neteaseRankingSource;
```

Replace constructor parameters:

```dart
    required RankingSource bilibiliRankingSource,
    required RankingSource youtubeRankingSource,
    required RankingSource neteaseRankingSource,
```

Update initializers accordingly.

Replace refresh calls:

```dart
final tracks = await _bilibiliRankingSource.getRankingTracks(
  const SourceRankingRequest(regionId: 1003),
);
```

```dart
final tracks = await _youtubeRankingSource.getRankingTracks(
  const SourceRankingRequest(category: 'music'),
);
```

```dart
final tracks = await _neteaseRankingSource.getRankingTracks(
  const SourceRankingRequest(limit: 50),
);
```

In `rankingCacheServiceProvider`, resolve sources:

```dart
  final manager = ref.watch(sourceManagerProvider);
  final bilibiliRankingSource = manager.rankingSource(SourceType.bilibili);
  final youtubeRankingSource = manager.rankingSource(SourceType.youtube);
  final neteaseRankingSource = manager.rankingSource(SourceType.netease);
  if (bilibiliRankingSource == null ||
      youtubeRankingSource == null ||
      neteaseRankingSource == null) {
    throw StateError('Ranking source not registered');
  }

  final service = RankingCacheService(
    bilibiliRankingSource: bilibiliRankingSource,
    youtubeRankingSource: youtubeRankingSource,
    neteaseRankingSource: neteaseRankingSource,
  );
```

- [ ] **Step 4: Update popular providers**

In `lib/providers/search/popular_provider.dart`, replace concrete source imports
with:

```dart
import '../../data/sources/source_capabilities.dart';
```

Change `RankingVideosNotifier` field and constructor:

```dart
class RankingVideosNotifier extends StateNotifier<RankingState> {
  final RankingSource _source;

  RankingVideosNotifier(this._source) : super(const RankingState());
```

Replace call:

```dart
final tracks = await _source.getRankingTracks(
  SourceRankingRequest(regionId: category.rid),
);
```

Change provider:

```dart
final rankingVideosProvider =
    StateNotifierProvider<RankingVideosNotifier, RankingState>((ref) {
  final source =
      ref.watch(sourceManagerProvider).rankingSource(SourceType.bilibili);
  if (source == null) throw StateError('Bilibili ranking source not registered');
  return RankingVideosNotifier(source);
});
```

Change `YouTubeTrendingNotifier` field and constructor:

```dart
class YouTubeTrendingNotifier extends StateNotifier<YouTubeTrendingState> {
  final RankingSource _source;

  YouTubeTrendingNotifier(this._source)
      : super(const YouTubeTrendingState());
```

Replace its load call:

```dart
final tracks = await _source.getRankingTracks(
  SourceRankingRequest(category: category.id),
);
```

Provider:

```dart
final youtubeTrendingProvider =
    StateNotifierProvider<YouTubeTrendingNotifier, YouTubeTrendingState>((ref) {
  final source =
      ref.watch(sourceManagerProvider).rankingSource(SourceType.youtube);
  if (source == null) throw StateError('YouTube ranking source not registered');
  return YouTubeTrendingNotifier(source);
});
```

- [ ] **Step 5: Run ranking tests and verify green**

Run:

```bash
flutter test test/services/cache/ranking_cache_service_test.dart
flutter test test/ui/pages/home/home_ranking_sources_test.dart
flutter test test/ui/pages/ranking_ui_state_consumption_test.dart
```

Expected: tests pass after fakes use `RankingSource`.

- [ ] **Step 6: Checkpoint**

Run:

```bash
rg -n "BilibiliSource|YouTubeSource|NeteaseSource|bilibiliSourceProvider|youtubeSourceProvider|neteaseAudioSourceProvider" lib/services/cache/ranking_cache_service.dart lib/providers/search/popular_provider.dart
```

Expected: no matches.

---

### Task 7: Migrate Live Search And Debug YouTube Probe

**Files:**
- Modify: `lib/providers/search/search_provider.dart`
- Modify: `lib/ui/pages/debug/youtube_stream_test_page.dart`
- Test: `test/providers/search_pagination_stale_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Write failing live search constructor test updates**

In `test/providers/search_pagination_stale_test.dart`, update fake live source
to implement `LiveSource` and construct `SearchNotifier(service, liveSource)`.

Use this fake:

```dart
class _CompletingLiveSource implements LiveSource {
  @override
  SourceType get sourceType => SourceType.bilibili;

  final calls = <String>[];

  @override
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) async {
    calls.add('$query:$page:${filter.name}');
    return LiveSearchResult(
      rooms: const [],
      totalCount: 0,
      page: page,
      pageSize: pageSize,
      hasMore: false,
    );
  }

  @override
  Future<String?> getLiveStreamUrl(int roomId) async {
    return 'https://live.example/$roomId.flv';
  }
}
```

- [ ] **Step 2: Run search provider tests and verify failure**

Run:

```bash
flutter test test/providers/search_pagination_stale_test.dart
```

Expected: compile failure because `SearchNotifier` still expects
`BilibiliSource`.

- [ ] **Step 3: Update `SearchNotifier` live dependency**

In `lib/providers/search/search_provider.dart`:

Remove concrete Bilibili import and concrete provider import. Import
`source_capabilities.dart`.

Change field and constructor:

```dart
  final LiveSource? _liveSource;

  SearchNotifier(
    this._service,
    this._liveSource,
  ) : super(const SearchState());
```

Add helper:

```dart
  LiveSource _requireLiveSource() {
    final source = _liveSource;
    if (source == null) {
      throw StateError('Bilibili live source not registered');
    }
    return source;
  }
```

Replace `_bilibiliSource.searchLiveRooms` calls with:

```dart
final result = await _requireLiveSource().searchLiveRooms(
  query,
  page: 1,
  filter: state.liveRoomFilter ?? LiveRoomFilter.all,
);
```

and:

```dart
final result = await _requireLiveSource().searchLiveRooms(
  query,
  page: nextPage,
  filter: filter ?? LiveRoomFilter.all,
);
```

Replace stream URL helper:

```dart
  Future<String?> getLiveStreamUrl(int roomId) async {
    return _requireLiveSource().getLiveStreamUrl(roomId);
  }
```

Update provider:

```dart
  final liveSource =
      ref.watch(sourceManagerProvider).liveSource(SourceType.bilibili);
  return SearchNotifier(
    service,
    liveSource,
  );
```

- [ ] **Step 4: Migrate debug YouTube auth probe**

In `lib/ui/pages/debug/youtube_stream_test_page.dart`, remove direct
`YouTubeSource()` construction inside `_runAuthProbe()`.

Use source capabilities:

```dart
    final manager = ref.read(sourceManagerProvider);
    final detailSource = manager.trackDetailSource(SourceType.youtube);
    final streamSource = manager.audioStreamSource(SourceType.youtube);
    if (detailSource == null || streamSource == null) {
      _log('❌ YouTube source capabilities unavailable');
      setState(() => _status = 'YouTube source unavailable');
      return;
    }
```

Replace:

```dart
await source.getVideoDetail(videoId, authHeaders: authHeaders)
```

with:

```dart
await detailSource.getVideoDetail(videoId, authHeaders: authHeaders)
```

Replace:

```dart
await source.getAudioStream(
  fmp.AudioStreamRequest(
    sourceId: videoId,
    config: fmp.AudioStreamConfig.defaultConfig,
    authHeaders: authHeaders,
  ),
)
```

with:

```dart
await streamSource.getAudioStream(
  fmp.AudioStreamRequest(
    sourceId: videoId,
    config: fmp.AudioStreamConfig.defaultConfig,
    authHeaders: authHeaders,
  ),
)
```

- [ ] **Step 5: Run search/debug related tests**

Run:

```bash
flutter test test/providers/search_pagination_stale_test.dart
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: tests pass.

- [ ] **Step 6: Checkpoint**

Run:

```bash
rg -n "BilibiliSource|YouTubeSource\\(|bilibiliSourceProvider|youtubeSourceProvider" lib/providers/search/search_provider.dart lib/ui/pages/debug/youtube_stream_test_page.dart
```

Expected: no runtime concrete source matches in these files.

---

### Task 8: Remove Static Concrete Parser Leaks

**Files:**
- Modify: `lib/data/sources/source_url_policy.dart`
- Modify: `lib/data/sources/bilibili_source.dart`
- Modify: `lib/services/library/remote_playlist_id_parser.dart`
- Test: existing tests that cover remote playlist parsing

- [ ] **Step 1: Write failing static ownership guard**

Append to `test/data/sources/source_ownership_phase3_test.dart`:

```dart
test('runtime library parsers do not import concrete source adapters', () {
  final source = File(
    'lib/services/library/remote_playlist_id_parser.dart',
  ).readAsStringSync();

  expect(source, isNot(contains("data/sources/bilibili_source.dart")));
  expect(source, isNot(contains('BilibiliSource.')));
});
```

- [ ] **Step 2: Run guard and verify failure**

Run:

```bash
flutter test test/data/sources/source_ownership_phase3_test.dart
```

Expected: failure because `remote_playlist_id_parser.dart` imports
`BilibiliSource`.

- [ ] **Step 3: Move Bilibili favorites parser to `SourceUrlPolicy`**

Add to `lib/data/sources/source_url_policy.dart`:

```dart
  static String? parseBilibiliFavoritesId(String url) {
    final fidMatch = RegExp(r'fid=(\d+)').firstMatch(url);
    if (fidMatch != null) {
      return fidMatch.group(1);
    }

    final mlMatch = RegExp(r'ml(\d+)').firstMatch(url);
    if (mlMatch != null) {
      return mlMatch.group(1);
    }

    final detailMatch = RegExp(r'/detail/ml(\d+)').firstMatch(url);
    if (detailMatch != null) {
      return detailMatch.group(1);
    }

    return null;
  }
```

- [ ] **Step 4: Delegate old static method to the policy**

Keep backwards compatibility inside `BilibiliSource`:

```dart
static String? parseFavoritesId(String url) {
  return SourceUrlPolicy.parseBilibiliFavoritesId(url);
}
```

- [ ] **Step 5: Update remote playlist parser**

In `lib/services/library/remote_playlist_id_parser.dart`, replace the concrete
source import with:

```dart
import '../../data/sources/source_url_policy.dart';
```

Replace calls:

```dart
BilibiliSource.parseFavoritesId(url)
```

with:

```dart
SourceUrlPolicy.parseBilibiliFavoritesId(url)
```

- [ ] **Step 6: Run ownership and parser tests**

Run:

```bash
flutter test test/data/sources/source_ownership_phase3_test.dart
flutter test test/services/library/remote_playlist_id_parser_test.dart
```

If `test/services/library/remote_playlist_id_parser_test.dart` does not exist,
run:

```bash
flutter test test/services/library
```

Expected: ownership guard and library tests pass.

---

### Task 9: Remove Concrete Source Providers And Add Structural Guard

**Files:**
- Modify: `lib/data/sources/source_provider.dart`
- Modify: `test/data/sources/source_ownership_phase3_test.dart`
- Modify: tests still overriding concrete source providers
- Modify: `lib/data/sources/AGENTS.md`

- [ ] **Step 1: Write broad structural guard**

Replace or extend `test/data/sources/source_ownership_phase3_test.dart` with:

```dart
test('runtime code does not use concrete data source access', () {
  const allowedFiles = {
    'lib/data/sources/source_provider.dart',
    'lib/data/sources/bilibili_source.dart',
    'lib/data/sources/youtube_source.dart',
    'lib/data/sources/netease_source.dart',
  };

  const forbiddenTokens = {
    'SourceManager.bilibiliSource',
    'SourceManager.youtubeSource',
    'SourceManager.neteaseSource',
    '.bilibiliSource',
    '.youtubeSource',
    '.neteaseSource',
    'bilibiliSourceProvider',
    'youtubeSourceProvider',
    'neteaseAudioSourceProvider',
    "data/sources/bilibili_source.dart';",
    "data/sources/youtube_source.dart';",
    "data/sources/netease_source.dart';",
  };

  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (allowedFiles.contains(path)) continue;

    final source = entity.readAsStringSync();
    for (final token in forbiddenTokens) {
      if (source.contains(token)) {
        offenders.add('$path contains $token');
      }
    }
  }

  expect(offenders, isEmpty);
});
```

- [ ] **Step 2: Run guard and verify failure**

Run:

```bash
flutter test test/data/sources/source_ownership_phase3_test.dart
```

Expected: failure listing remaining runtime concrete access.

- [ ] **Step 3: Remove concrete getters and providers**

In `lib/data/sources/source_provider.dart`, delete:

```dart
  BilibiliSource? get bilibiliSource
  YouTubeSource? get youtubeSource
  NeteaseSource? get neteaseSource
```

Delete providers:

```dart
final bilibiliSourceProvider
final youtubeSourceProvider
final neteaseAudioSourceProvider
```

Keep concrete imports in this file because `SourceManager` still constructs and
disposes adapters.

- [ ] **Step 4: Update remaining test provider overrides**

For tests that used:

```dart
bilibiliSourceProvider.overrideWith((ref) => fake)
```

replace with:

```dart
sourceManagerProvider.overrideWith((ref) {
  final manager = SourceManager(sources: [fake]);
  ref.onDispose(manager.dispose);
  return manager;
})
```

When a test needs all three ranking sources:

```dart
sourceManagerProvider.overrideWith((ref) {
  final manager = SourceManager(sources: [
    fakeBilibili,
    fakeYouTube,
    fakeNetease,
  ]);
  ref.onDispose(manager.dispose);
  return manager;
})
```

- [ ] **Step 5: Update source AGENTS guidance**

In `lib/data/sources/AGENTS.md`, add under "Audio Quality And Stream Config" or
near the capability guidance:

```markdown
Runtime callers must request narrow source capabilities from `SourceManager`;
do not expose or consume concrete source getters/providers such as
`bilibiliSourceProvider`, `youtubeSourceProvider`, or
`neteaseAudioSourceProvider`. Concrete adapter construction belongs inside
`SourceManager`; tests may instantiate adapters directly.
```

- [ ] **Step 6: Run ownership guard and affected tests**

Run:

```bash
flutter test test/data/sources/source_ownership_phase3_test.dart
flutter test test/data/sources/source_capabilities_test.dart
flutter test test/services/cache/ranking_cache_service_test.dart
flutter test test/providers/track_detail_refresh_stale_test.dart
```

Expected: all pass.

- [ ] **Step 7: Checkpoint**

Run:

```bash
rg -n "bilibiliSourceProvider|youtubeSourceProvider|neteaseAudioSourceProvider|\\.bilibiliSource|\\.youtubeSource|\\.neteaseSource" lib
```

Expected: no matches except allowed adapter-internal text if the guard permits
it. If any runtime file matches, migrate it before continuing.

---

### Task 10: Final Verification

**Files:**
- All files changed above.

- [ ] **Step 1: Run source and affected service tests**

Run:

```bash
flutter test test/data/sources test/services/import test/services/download test/services/cache
```

Expected: all tests pass.

- [ ] **Step 2: Run provider and UI search/ranking tests**

Run:

```bash
flutter test test/providers/track_detail_refresh_stale_test.dart test/providers/search_pagination_stale_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
flutter test test/ui/pages/search test/ui/pages/home test/ui/pages/ranking_ui_state_consumption_test.dart
```

Expected: all tests pass.

Do not use the full `flutter test test/providers` suite as the required gate
until the existing baseline failure in
`test/providers/library_invalidation_coordinator_test.dart:121` is fixed. If
that baseline is fixed before this refactor lands, run the full provider suite
as an additional verification.

- [ ] **Step 3: Run audio tests if Mix playback wiring changed**

Run:

```bash
flutter test test/services/audio
```

Expected: all tests pass.

- [ ] **Step 4: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no analysis errors.

- [ ] **Step 5: Review diff for scope**

Run:

```bash
git diff --stat
git diff --name-only
```

Expected: changes are limited to source capability contracts, migrated callers,
tests, and scoped AGENTS guidance. No generated files or unrelated UI/product
changes.

- [ ] **Step 6: Final checkpoint**

Run:

```bash
git status --short
```

Expected: working tree contains only the spec, this plan, and implementation
files for this refactor. Do not commit unless the user explicitly asks.
