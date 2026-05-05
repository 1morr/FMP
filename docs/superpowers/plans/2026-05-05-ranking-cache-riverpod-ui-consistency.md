# Ranking Cache Riverpod UI Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move ranking cache data into immutable Riverpod state, update ranking UI to consume that state consistently, and clean up the remaining low-risk Phase 7 UI consistency issues that are directly visible in the current code.

**Architecture:** Keep the existing ranking cache lifecycle behavior, timers, and connectivity refresh triggers, but make `rankingCacheServiceProvider` a `StateNotifierProvider<RankingCacheService, RankingCacheState>`. UI widgets watch immutable `RankingCacheState` or derived providers and call refresh methods through `rankingCacheServiceProvider.notifier`. Reuse the existing `LoadingPlaceholder` and `ErrorDisplay` wrappers instead of adding a speculative generic UI abstraction.

**Tech Stack:** Flutter, Dart, Riverpod `StateNotifierProvider`, existing `BilibiliSource`/`YouTubeSource`, existing `ConnectivityNotifier`, existing `ErrorDisplay`/`LoadingPlaceholder`, Flutter widget tests, and static-rule tests only where behavior tests are impractical.

---

## File Structure

- Modify: `lib/services/cache/ranking_cache_service.dart:1-220`
  - Add immutable `RankingCacheState`.
  - Convert `RankingCacheService` to `StateNotifier<RankingCacheState>`.
  - Remove mutable public list/loading getters and the `StreamController<void>` snapshot notification path.
  - Keep lifecycle methods: `initialize()`, `refreshBilibili()`, `refreshYouTube()`, `updateRefreshInterval()`, `setupNetworkMonitoring()`, and idempotent `dispose()`.
- Modify: `lib/providers/popular_provider.dart:133-289`
  - Convert the four ranking cache providers from `StreamProvider<List<Track>>` to pure derived `Provider<List<Track>>` values from `RankingCacheState`.
- Modify: `lib/ui/pages/home/home_page.dart:85-248`
  - Watch `RankingCacheState` directly for initial loading and per-source errors.
  - Render ranking cards from plain `List<Track>` providers instead of `AsyncValue<List<Track>>`.
- Modify: `lib/ui/pages/explore/explore_page.dart:47-231`
  - Watch ranking lists as plain providers.
  - Read `rankingCacheServiceProvider.notifier` for refresh actions.
  - Use `LoadingPlaceholder` and `ErrorDisplay.empty`/`ErrorDisplay` for loading, empty, and error states.
- Modify: `lib/providers/refresh_settings_provider.dart:55-75`
  - Call `rankingCacheServiceProvider.notifier.updateRefreshInterval()`.
- Modify: `lib/ui/pages/settings/developer_options_page.dart:217-221`
  - Read `RankingCacheState` for cache counts.
- Modify: `lib/ui/pages/library/import_preview_page.dart:455-900`
  - Replace remaining `ListTile.leading: Row(...)` instances with explicit-width private leading widgets.
- Modify: `lib/ui/pages/settings/lyrics_source_settings_page.dart:330-398`
  - Replace `_LyricsSourceTile` `ListTile.leading: Row(...)` with an explicit-width private leading widget.
- Move/modify: `test/ui/ui_consistency_phase1_test.dart` -> `test/ui/static_rules/ui_consistency_static_rule_test.dart`
  - Keep unavoidable source-shape checks, but clearly name them as static architecture rules.
- Create: `test/ui/static_rules/list_tile_leading_static_rule_test.dart`
  - Clearly named static rule proving no `ListTile.leading` directly receives a `Row` in runtime UI files.
- Modify: `test/services/cache/ranking_cache_service_test.dart:16-167`
  - Update lifecycle tests for `StateNotifierProvider` reads.
  - Add state emission and retained-cache-on-failure coverage.
- Tests to run:
  - `flutter test test/services/cache/ranking_cache_service_test.dart`
  - `flutter test test/ui/static_rules/ui_consistency_static_rule_test.dart test/ui/static_rules/list_tile_leading_static_rule_test.dart`
  - `flutter test test/ui/pages/library/library_page_reorder_test.dart test/ui/pages/search/search_page_phase2_test.dart`
  - `flutter analyze`
  - `flutter test`

## Scope Guardrails

- Do not redesign Home or Explore UI layout.
- Do not introduce a new generic async/list wrapper when `LoadingPlaceholder` and `ErrorDisplay` already cover this phase's UI state needs.
- Do not change ranking fetch endpoints, refresh intervals, source ownership, sorting rules, or connectivity polling behavior.
- Do not migrate unrelated source-text tests in this phase; only rename the existing Phase 1 UI consistency test and add one clearly named static rule for the specific `ListTile.leading` cleanup.
- Do not touch queue identity semantics; queue rows include index in their key because duplicate queue entries can represent the same track.

## Roadmap Coverage

- Reusable loading/error/empty wrappers: Task 2 migrates Explore ranking states to existing shared wrappers.
- Remaining `ListTile.leading` Row cleanup: Task 3 removes the remaining runtime `ListTile.leading: Row(...)` cases found in `import_preview_page.dart` and `lyrics_source_settings_page.dart`.
- Stable keys for mutable secondary lists: Task 4 preserves existing stable-key static checks under a clearly named static-rule path and verifies no regression in reorder/search tests.
- Ranking cache immutable Riverpod state: Tasks 1 and 2 migrate ranking cache from mutable service snapshots plus `stateChanges` to immutable `RankingCacheState`.
- Brittle source-text tests: Task 4 renames unavoidable source-shape tests as static rules and keeps them broad rather than formatting-sensitive.

---

### Task 1: Ranking Cache Immutable State Provider

**Files:**
- Modify: `lib/services/cache/ranking_cache_service.dart:1-220`
- Modify: `test/services/cache/ranking_cache_service_test.dart:16-167`
- Modify: `lib/providers/popular_provider.dart:133-289`
- Modify: `lib/providers/refresh_settings_provider.dart:55-75`
- Modify: `lib/ui/pages/settings/developer_options_page.dart:217-221`

- [ ] **Step 1: Add failing state tests**

In `test/services/cache/ranking_cache_service_test.dart`, keep the existing imports and add these two tests at the start of `group('RankingCacheService lifecycle hardening', () {`:

```dart
test('provider exposes immutable ranking state after refresh', () async {
  final bilibiliTrack = _track('bv-1', SourceType.bilibili);
  final youtubeTrack = _track('yt-1', SourceType.youtube, viewCount: 20);
  final bilibiliSource = _FakeBilibiliSource()..tracks = [bilibiliTrack];
  final youtubeSource = _FakeYouTubeSource()..tracks = [youtubeTrack];
  final notifier = _TestConnectivityNotifier();
  final container = ProviderContainer(
    overrides: [
      bilibiliSourceProvider.overrideWith((ref) => bilibiliSource),
      youtubeSourceProvider.overrideWith((ref) => youtubeSource),
      connectivityProvider.overrideWith((ref) => notifier),
    ],
  );

  expect(container.read(rankingCacheServiceProvider).isInitialLoading, isTrue);

  await pumpEventQueue(times: 5);
  final state = container.read(rankingCacheServiceProvider);

  expect(state.isInitialLoading, isFalse);
  expect(state.bilibiliTracks, [bilibiliTrack]);
  expect(state.youtubeTracks, [youtubeTrack]);
  expect(state.bilibiliLoaded, isTrue);
  expect(state.youtubeLoaded, isTrue);

  expect(
    () => state.bilibiliTracks.add(_track('mutate', SourceType.bilibili)),
    throwsUnsupportedError,
  );

  container.dispose();
  await notifier.closeStream();
});

``` 

Then add this second test immediately after it:

```dart
test('refresh failure keeps old tracks and records source error', () async {
  final oldTrack = _track('old-bv', SourceType.bilibili);
  final bilibiliSource = _FakeBilibiliSource()..tracks = [oldTrack];
  final youtubeSource = _FakeYouTubeSource();
  final service = RankingCacheService(
    bilibiliSource: bilibiliSource,
    youtubeSource: youtubeSource,
  );

  await service.refreshBilibili();
  expect(service.state.bilibiliTracks, [oldTrack]);
  expect(service.state.bilibiliError, isNull);

  bilibiliSource.nextError = Exception('network down');
  await service.refreshBilibili();

  expect(service.state.bilibiliTracks, [oldTrack]);
  expect(service.state.bilibiliError, contains('network down'));

  service.dispose();
});
```

At the bottom of the test file, add this helper so the new tests can create ranking tracks:

```dart
Track _track(String id, SourceType sourceType, {int? viewCount}) {
  return Track()
    ..sourceId = id
    ..sourceType = sourceType
    ..title = id
    ..artist = 'Tester'
    ..viewCount = viewCount;
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `flutter test test/services/cache/ranking_cache_service_test.dart --plain-name "provider exposes immutable ranking state"`

Expected: FAIL because `rankingCacheServiceProvider` still exposes `RankingCacheService`, not `RankingCacheState`, and the fake source classes do not yet support `tracks`/`nextError`.

- [ ] **Step 3: Implement immutable `RankingCacheState` and convert the service provider**

In `lib/services/cache/ranking_cache_service.dart`, replace the mutable list/loading fields, public snapshot getters, `StreamController`, and provider declaration with this shape. Keep the existing imports except remove `package:flutter/foundation.dart` only if the file no longer uses `debugPrint` outside this code.

```dart
class RankingCacheState {
  final List<Track> bilibiliTracks;
  final List<Track> youtubeTracks;
  final bool isInitialLoading;
  final bool bilibiliLoaded;
  final bool youtubeLoaded;
  final String? bilibiliError;
  final String? youtubeError;

  const RankingCacheState({
    this.bilibiliTracks = const [],
    this.youtubeTracks = const [],
    this.isInitialLoading = true,
    this.bilibiliLoaded = false,
    this.youtubeLoaded = false,
    this.bilibiliError,
    this.youtubeError,
  });

  RankingCacheState copyWith({
    List<Track>? bilibiliTracks,
    List<Track>? youtubeTracks,
    bool? isInitialLoading,
    bool? bilibiliLoaded,
    bool? youtubeLoaded,
    String? bilibiliError,
    String? youtubeError,
    bool clearBilibiliError = false,
    bool clearYoutubeError = false,
  }) {
    return RankingCacheState(
      bilibiliTracks: List.unmodifiable(bilibiliTracks ?? this.bilibiliTracks),
      youtubeTracks: List.unmodifiable(youtubeTracks ?? this.youtubeTracks),
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      bilibiliLoaded: bilibiliLoaded ?? this.bilibiliLoaded,
      youtubeLoaded: youtubeLoaded ?? this.youtubeLoaded,
      bilibiliError:
          clearBilibiliError ? null : bilibiliError ?? this.bilibiliError,
      youtubeError: clearYoutubeError ? null : youtubeError ?? this.youtubeError,
    );
  }
}

class RankingCacheService extends StateNotifier<RankingCacheState> {
  static const _initialLoadTimeout = Duration(seconds: 5);

  final BilibiliSource _bilibiliSource;
  final YouTubeSource _youtubeSource;

  Timer? _refreshTimer;
  StreamSubscription<void>? _networkRecoveredSubscription;
  Duration _refreshInterval = const Duration(hours: 1);
  bool _isDisposed = false;

  RankingCacheService({
    required BilibiliSource bilibiliSource,
    required YouTubeSource youtubeSource,
  })  : _bilibiliSource = bilibiliSource,
        _youtubeSource = youtubeSource,
        super(const RankingCacheState());

  Future<void> initialize({Duration? refreshInterval}) async {
    if (_isDisposed) return;
    if (refreshInterval != null && _refreshTimer == null) {
      _refreshInterval = refreshInterval;
    }

    await _refreshAll().timeout(
      _initialLoadTimeout,
      onTimeout: () {
        debugPrint('[RankingCache] 初始加載超時（${_initialLoadTimeout.inSeconds}秒）');
        if (_isDisposed) return;
        if (state.isInitialLoading) {
          state = state.copyWith(isInitialLoading: false);
        }
      },
    );

    if (_isDisposed) return;
    _startRefreshTimer();
  }

  void updateRefreshInterval(Duration interval) {
    if (_isDisposed) return;
    _refreshInterval = interval;
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    if (_isDisposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (_isDisposed) return;
      _refreshAll();
    });
  }

  void setupNetworkMonitoring(ConnectivityNotifier connectivityNotifier) {
    if (_isDisposed) return;

    _networkRecoveredSubscription?.cancel();
    _networkRecoveredSubscription =
        connectivityNotifier.onNetworkRecovered.listen((_) {
      if (_isDisposed) return;
      debugPrint('[RankingCache] 網絡恢復，重新獲取排行榜緩存');
      _refreshAll();
    });

    debugPrint('[RankingCache] 網絡恢復監聽已設置');
  }

  Future<void> _refreshAll() async {
    if (_isDisposed) return;

    await Future.wait([
      refreshBilibili().catchError((e) {
        debugPrint('[RankingCache] Bilibili 刷新異常（未預期）: $e');
      }),
      refreshYouTube().catchError((e) {
        debugPrint('[RankingCache] YouTube 刷新異常（未預期）: $e');
      }),
    ]);

    if (_isDisposed) return;

    if (state.isInitialLoading) {
      state = state.copyWith(isInitialLoading: false);
      debugPrint(
        '[RankingCache] 初始加載完成（Bilibili: ${state.bilibiliLoaded}, YouTube: ${state.youtubeLoaded}）',
      );
    }
  }

  Future<void> refreshBilibili() async {
    if (_isDisposed) return;
    try {
      final tracks = await _bilibiliSource.getRankingVideos(rid: 1003);
      if (_isDisposed) return;
      state = state.copyWith(
        bilibiliTracks: tracks,
        bilibiliLoaded: true,
        clearBilibiliError: true,
      );
      debugPrint('[RankingCache] Bilibili 音樂排行榜緩存已刷新: ${tracks.length} 首');
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(bilibiliError: e.toString());
      debugPrint('[RankingCache] Bilibili 刷新失敗: $e');
    }
  }

  Future<void> refreshYouTube() async {
    if (_isDisposed) return;
    try {
      final tracks = await _youtubeSource.getTrendingVideos(category: 'music');
      if (_isDisposed) return;
      tracks.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
      state = state.copyWith(
        youtubeTracks: tracks,
        youtubeLoaded: true,
        clearYoutubeError: true,
      );
      debugPrint('[RankingCache] YouTube 緩存已刷新: ${tracks.length} 首');
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(youtubeError: e.toString());
      debugPrint('[RankingCache] YouTube 刷新失敗: $e');
    }
  }

  void clearNetworkMonitoring() {
    _networkRecoveredSubscription?.cancel();
    _networkRecoveredSubscription = null;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    clearNetworkMonitoring();
    super.dispose();
  }
}

final rankingCacheServiceProvider =
    StateNotifierProvider<RankingCacheService, RankingCacheState>((ref) {
  final service = RankingCacheService(
    bilibiliSource: ref.watch(bilibiliSourceProvider),
    youtubeSource: ref.watch(youtubeSourceProvider),
  );

  Future.microtask(() => service.initialize());

  final connectivityNotifier = ref.read(connectivityProvider.notifier);
  service.setupNetworkMonitoring(connectivityNotifier);

  return service;
});
```

Do not keep `Stream<void> get stateChanges`, `_stateController`, `_bilibiliTracks`, `_youtubeTracks`, `_isInitialLoading`, `_bilibiliLoaded`, or `_youtubeLoaded` as mutable public snapshot state.

- [ ] **Step 4: Update ranking tests for notifier reads and controllable fakes**

In `test/services/cache/ranking_cache_service_test.dart`, update provider tests so direct service reads use `.notifier` and state reads use the provider value:

```dart
final firstService = firstContainer.read(rankingCacheServiceProvider.notifier);
...
final secondService = secondContainer.read(rankingCacheServiceProvider.notifier);
```

Replace `_FakeBilibiliSource` and `_FakeYouTubeSource` with this implementation:

```dart
class _FakeBilibiliSource extends BilibiliSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];

  @override
  Future<List<Track>> getRankingVideos({int rid = 0}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return List<Track>.of(tracks);
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  int fetchCount = 0;
  Completer<void>? nextFetchCompleter;
  Object? nextError;
  List<Track> tracks = const [];

  @override
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    fetchCount++;
    final completer = nextFetchCompleter;
    if (completer != null) {
      nextFetchCompleter = null;
      await completer.future;
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return List<Track>.of(tracks);
  }
}
```

- [ ] **Step 5: Convert derived ranking providers to immutable-state providers**

In `lib/providers/popular_provider.dart`, replace `homeBilibiliMusicRankingProvider`, `homeYouTubeMusicRankingProvider`, `cachedBilibiliRankingProvider`, and `cachedYouTubeRankingProvider` with plain providers:

```dart
final homeBilibiliMusicRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select((state) => state.bilibiliTracks),
  );
  return tracks.take(AppConstants.rankingPreviewCount).toList(growable: false);
});

final homeYouTubeMusicRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select((state) => state.youtubeTracks),
  );
  return tracks.take(AppConstants.rankingPreviewCount).toList(growable: false);
});

final cachedBilibiliRankingProvider = Provider<List<Track>>((ref) {
  return ref.watch(
    rankingCacheServiceProvider.select((state) => state.bilibiliTracks),
  );
});

final cachedYouTubeRankingProvider = Provider<List<Track>>((ref) {
  return ref.watch(
    rankingCacheServiceProvider.select((state) => state.youtubeTracks),
  );
});
```

- [ ] **Step 6: Update non-page call sites to use notifier/state**

In `lib/providers/refresh_settings_provider.dart`, update both ranking interval writes:

```dart
_ref.read(rankingCacheServiceProvider.notifier).updateRefreshInterval(
      Duration(minutes: rankingMinutes),
    );
```

and:

```dart
_ref.read(rankingCacheServiceProvider.notifier).updateRefreshInterval(
      Duration(minutes: minutes),
    );
```

In `lib/ui/pages/settings/developer_options_page.dart`, replace the mutable service read with a state read:

```dart
final rankingCache = ref.read(rankingCacheServiceProvider);
final bilibiliCacheCount = rankingCache.bilibiliTracks.length;
final youtubeCacheCount = rankingCache.youtubeTracks.length;
```

- [ ] **Step 7: Run focused ranking cache tests**

Run: `flutter test test/services/cache/ranking_cache_service_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add lib/services/cache/ranking_cache_service.dart lib/providers/popular_provider.dart lib/providers/refresh_settings_provider.dart lib/ui/pages/settings/developer_options_page.dart test/services/cache/ranking_cache_service_test.dart
git commit -m "refactor(cache): expose ranking cache as Riverpod state"
```

---

### Task 2: Ranking UI State Consumption

**Files:**
- Modify: `lib/ui/pages/home/home_page.dart:85-248`
- Modify: `lib/ui/pages/explore/explore_page.dart:47-231`
- Modify: `test/services/cache/ranking_cache_service_test.dart:16-167`

- [ ] **Step 1: Add provider contract tests for derived ranking lists**

In `test/services/cache/ranking_cache_service_test.dart`, add this test after the two Task 1 state tests:

```dart
test('derived ranking providers expose preview and full immutable lists', () async {
  final bilibiliTracks = List.generate(
    12,
    (index) => _track('bv-$index', SourceType.bilibili),
  );
  final youtubeTracks = List.generate(
    12,
    (index) => _track('yt-$index', SourceType.youtube, viewCount: index),
  );
  final notifier = _TestConnectivityNotifier();
  final container = ProviderContainer(
    overrides: [
      bilibiliSourceProvider.overrideWith(
        (ref) => _FakeBilibiliSource()..tracks = bilibiliTracks,
      ),
      youtubeSourceProvider.overrideWith(
        (ref) => _FakeYouTubeSource()..tracks = youtubeTracks,
      ),
      connectivityProvider.overrideWith((ref) => notifier),
    ],
  );

  await pumpEventQueue(times: 5);

  expect(container.read(homeBilibiliMusicRankingProvider), bilibiliTracks.take(10));
  expect(container.read(cachedBilibiliRankingProvider), bilibiliTracks);
  expect(container.read(homeYouTubeMusicRankingProvider), hasLength(10));
  expect(container.read(cachedYouTubeRankingProvider), hasLength(12));

  container.dispose();
  await notifier.closeStream();
});
```

Add this import to the test file:

```dart
import 'package:fmp/providers/popular_provider.dart';
```

- [ ] **Step 2: Run the derived provider test and verify it passes after Task 1**

Run: `flutter test test/services/cache/ranking_cache_service_test.dart --plain-name "derived ranking providers"`

Expected: PASS once Task 1 provider conversion is complete.

- [ ] **Step 3: Update Home ranking section to consume immutable state**

In `lib/ui/pages/home/home_page.dart`, remove `import '../../../services/cache/ranking_cache_service.dart';` only if it becomes unused after the edits.

In `_MusicRankingsSection.build`, replace the `AsyncValue` and mutable service reads with:

```dart
final bilibiliTracks = ref.watch(homeBilibiliMusicRankingProvider);
final youtubeTracks = ref.watch(homeYouTubeMusicRankingProvider);
final rankingState = ref.watch(rankingCacheServiceProvider);

final hasBilibiliData = bilibiliTracks.isNotEmpty;
final hasYoutubeData = youtubeTracks.isNotEmpty;
final isLoading = rankingState.isInitialLoading;
```

Update the `_buildRankingContent` call to pass plain lists:

```dart
_buildRankingContent(
  context,
  colorScheme,
  bilibiliTracks: bilibiliTracks,
  youtubeTracks: youtubeTracks,
  isLoading: isLoading,
  hasBilibiliData: hasBilibiliData,
  hasYoutubeData: hasYoutubeData,
),
```

Change `_buildRankingContent` parameters from `AsyncValue<List<Track>>` to lists:

```dart
required List<Track> bilibiliTracks,
required List<Track> youtubeTracks,
```

Change `_buildRankingCard` parameters from `AsyncValue<List<Track>> asyncValue` to:

```dart
required List<Track> tracks,
```

Replace the `asyncValue.when(...)` body with:

```dart
if (tracks.isEmpty) return const SizedBox.shrink();
final displayTracks = tracks.take(AppConstants.homeTrackPreviewCount).toList();
return Column(
  children: [
    for (int i = 0; i < displayTracks.length; i++)
      _RankingTrackTile(
        key: ValueKey(
          '${displayTracks[i].sourceId}_${displayTracks[i].pageNum}',
        ),
        track: displayTracks[i],
        rank: i + 1,
      ),
  ],
);
```

Update the two `_buildRankingCard` calls so they pass `tracks: bilibiliTracks` and `tracks: youtubeTracks`.

- [ ] **Step 4: Update Explore ranking tabs to consume state and shared wrappers**

In `lib/ui/pages/explore/explore_page.dart`, keep `import '../../widgets/error_display.dart';` and use the already existing `LoadingPlaceholder` from that file.

In `build`, replace the `valueOrNull` reads with:

```dart
final bilibiliTracks = ref.watch(cachedBilibiliRankingProvider);
final youtubeTracks = ref.watch(cachedYouTubeRankingProvider);
```

In `_buildBilibiliTab`, replace the `AsyncValue.when` block with:

```dart
final tracks = ref.watch(cachedBilibiliRankingProvider);
final rankingState = ref.watch(rankingCacheServiceProvider);
return _buildRankingContent(
  tracks: tracks,
  isLoading: rankingState.isInitialLoading && tracks.isEmpty,
  error: rankingState.bilibiliError,
  onRefresh: () => ref.read(rankingCacheServiceProvider.notifier).refreshBilibili(),
);
```

In `_buildYouTubeTab`, use:

```dart
final tracks = ref.watch(cachedYouTubeRankingProvider);
final rankingState = ref.watch(rankingCacheServiceProvider);
return _buildRankingContent(
  tracks: tracks,
  isLoading: rankingState.isInitialLoading && tracks.isEmpty,
  error: rankingState.youtubeError,
  onRefresh: () => ref.read(rankingCacheServiceProvider.notifier).refreshYouTube(),
);
```

In `_buildRankingContent`, replace the three state branches with:

```dart
if (isLoading && tracks.isEmpty) {
  return const LoadingPlaceholder();
}

if (error != null && tracks.isEmpty) {
  return ErrorDisplay(
    type: ErrorType.general,
    message: t.general.loadFailed,
    onRetry: () => onRefresh(),
  );
}

if (tracks.isEmpty) {
  return ErrorDisplay.empty(
    message: t.databaseViewer.noData,
    icon: Icons.library_music_outlined,
    onRetry: () => onRefresh(),
  );
}
```

Do not change `_ExploreTrackTile` action behavior.

- [ ] **Step 5: Run focused ranking UI/provider tests**

Run: `flutter test test/services/cache/ranking_cache_service_test.dart test/ui/pages/library/library_page_reorder_test.dart test/ui/pages/search/search_page_phase2_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add lib/ui/pages/home/home_page.dart lib/ui/pages/explore/explore_page.dart test/services/cache/ranking_cache_service_test.dart
git commit -m "refactor(ui): read ranking cache state directly"
```

---

### Task 3: Remaining `ListTile.leading` Row Cleanup

**Files:**
- Modify: `lib/ui/pages/library/import_preview_page.dart:455-900`
- Modify: `lib/ui/pages/settings/lyrics_source_settings_page.dart:330-398`
- Create: `test/ui/static_rules/list_tile_leading_static_rule_test.dart`

- [ ] **Step 1: Add a clearly named failing static rule for `ListTile.leading` rows**

Create `test/ui/static_rules/list_tile_leading_static_rule_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListTile leading static rules', () {
    test('runtime UI ListTile leading values do not directly use Row', () {
      final offenders = <String>[];

      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        final matches = RegExp(r'ListTile\s*\([\s\S]*?leading:\s*Row\s*\(')
            .allMatches(source);
        if (matches.isNotEmpty) {
          offenders.add(entity.path);
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the static rule and verify it fails**

Run: `flutter test test/ui/static_rules/list_tile_leading_static_rule_test.dart`

Expected: FAIL listing `lib/ui/pages/library/import_preview_page.dart` and `lib/ui/pages/settings/lyrics_source_settings_page.dart`.

- [ ] **Step 3: Add private import-preview leading widgets**

In `lib/ui/pages/library/import_preview_page.dart`, add these private widgets before `_UnmatchedTrackTile`:

```dart
class _ImportTrackLeading extends StatelessWidget {
  final bool isSelected;
  final Track? track;

  const _ImportTrackLeading({
    required this.isSelected,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedTrack = track;

    return SizedBox(
      width: 72,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: isSelected
                ? Icon(Icons.check_circle, color: colorScheme.primary, size: 20)
                : Icon(
                    Icons.radio_button_unchecked,
                    color: colorScheme.outline,
                    size: 20,
                  ),
          ),
          const SizedBox(width: 8),
          if (selectedTrack != null)
            TrackThumbnail(
              track: selectedTrack,
              size: AppSizes.thumbnailSmall,
              borderRadius: 4,
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(
                Icons.music_note,
                color: colorScheme.outline,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportMatchLeading extends StatelessWidget {
  final Track track;
  final bool isIncluded;
  final ValueChanged<bool> onChanged;

  const _ImportMatchLeading({
    required this.track,
    required this.isIncluded,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isIncluded,
              onChanged: (value) => onChanged(value ?? false),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          TrackThumbnail(
            track: track,
            size: AppSizes.thumbnailSmall,
            borderRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _AlternativeTrackLeading extends StatelessWidget {
  final Track track;
  final bool isSelected;

  const _AlternativeTrackLeading({
    required this.track,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 60,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: isSelected
                ? Icon(Icons.check_circle, color: colorScheme.primary, size: 18)
                : Icon(
                    Icons.radio_button_unchecked,
                    color: colorScheme.outline,
                    size: 18,
                  ),
          ),
          const SizedBox(width: 8),
          TrackThumbnail(
            track: track,
            size: 32,
            borderRadius: 4,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Replace import-preview `leading: Row(...)` blocks**

In `_UnmatchedTrackTile`, replace the entire `leading: Row(...)` block with:

```dart
leading: _ImportTrackLeading(
  isSelected: hasSelection,
  track: selectedTrack,
),
```

In `_ImportMatchTile`, replace the entire `leading: Row(...)` block with:

```dart
leading: _ImportMatchLeading(
  track: track,
  isIncluded: matchedTrack.isIncluded,
  onChanged: onToggleInclude,
),
```

In `_AlternativeTrackTile`, replace the entire `leading: Row(...)` block with:

```dart
leading: _AlternativeTrackLeading(
  track: track,
  isSelected: isSelected,
),
```

- [ ] **Step 5: Add and use a lyrics-source leading widget**

In `lib/ui/pages/settings/lyrics_source_settings_page.dart`, add this private widget before `_LyricsSourceTile`:

```dart
class _LyricsSourceLeading extends StatelessWidget {
  final int index;
  final IconData icon;
  final bool isEnabled;

  const _LyricsSourceLeading({
    required this.index,
    required this.icon,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const disabledAlpha = 0.38;

    return SizedBox(
      width: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            icon,
            size: 20,
            color: isEnabled
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: disabledAlpha),
          ),
        ],
      ),
    );
  }
}
```

Then replace `_LyricsSourceTile`'s `leading: Row(...)` block with:

```dart
leading: _LyricsSourceLeading(
  index: index,
  icon: icon,
  isEnabled: isEnabled,
),
```

- [ ] **Step 6: Run static and relevant UI tests**

Run: `flutter test test/ui/static_rules/list_tile_leading_static_rule_test.dart test/ui/ui_consistency_phase1_test.dart`

Expected: the list-tile static rule passes after the production cleanup, and the existing UI consistency test still passes before it is moved in Task 4.

- [ ] **Step 7: Commit Task 3**

```bash
git add lib/ui/pages/library/import_preview_page.dart lib/ui/pages/settings/lyrics_source_settings_page.dart test/ui/static_rules/list_tile_leading_static_rule_test.dart
git commit -m "refactor(ui): constrain list tile leading rows"
```

---

### Task 4: Clearly Named Static Rules and Final Phase 7 Verification

**Files:**
- Move/modify: `test/ui/ui_consistency_phase1_test.dart` -> `test/ui/static_rules/ui_consistency_static_rule_test.dart`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Move the Phase 1 UI consistency source-shape test into static rules**

Move `test/ui/ui_consistency_phase1_test.dart` to `test/ui/static_rules/ui_consistency_static_rule_test.dart`.

Update its group name from:

```dart
group('Phase 1 UI consistency', () {
```

to:

```dart
group('UI consistency static rules', () {
```

Keep the current assertions unchanged except update any future path references only if needed. This phase is not trying to convert every historical source-text test; it is making unavoidable static tests explicit and clearly named.

- [ ] **Step 2: Run the moved static-rule tests**

Run: `flutter test test/ui/static_rules/ui_consistency_static_rule_test.dart test/ui/static_rules/list_tile_leading_static_rule_test.dart`

Expected: PASS.

- [ ] **Step 3: Update project guidance for ranking cache state**

In `CLAUDE.md`, under the Riverpod provider list, update the `rankingCacheService` memory/snapshot guidance by adding this bullet to the **Rules:** list:

```markdown
- Ranking cache UI must watch immutable `RankingCacheState` from `rankingCacheServiceProvider`; refresh/timer methods are called through `rankingCacheServiceProvider.notifier`, not by reading mutable service snapshot lists.
```

- [ ] **Step 4: Run focused Phase 7 verification**

Run these commands from the worktree root:

```bash
flutter test test/services/cache/ranking_cache_service_test.dart
flutter test test/ui/static_rules/ui_consistency_static_rule_test.dart test/ui/static_rules/list_tile_leading_static_rule_test.dart
flutter test test/ui/pages/library/library_page_reorder_test.dart test/ui/pages/search/search_page_phase2_test.dart
flutter analyze
```

Expected: all commands exit 0.

- [ ] **Step 5: Run full Flutter test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add CLAUDE.md test/ui/static_rules/ui_consistency_static_rule_test.dart test/ui/static_rules/list_tile_leading_static_rule_test.dart
git add -u test/ui/ui_consistency_phase1_test.dart
git commit -m "test(ui): name remaining consistency checks as static rules"
```

---

## Rollback Considerations

- If ranking cache state migration causes lifecycle regressions, revert Task 1 and Task 2 commits together. Task 2 depends on Task 1's provider type.
- If ListTile leading layout changes cause UI regressions, revert Task 3 only; it is independent from ranking cache state.
- If static-rule test relocation causes CI path issues, move the test file back and keep the clearer group name; no production code depends on this task.

## Self-Review Checklist

- Roadmap coverage: Phase 7's ranking cache immutable state, shared loading/error/empty usage, remaining `ListTile.leading` cleanup, stable-key/static-rule clarity, and test-shape cleanup are each mapped to a task.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: `rankingCacheServiceProvider` is consistently planned as `StateNotifierProvider<RankingCacheService, RankingCacheState>`; UI state reads use `ref.watch(rankingCacheServiceProvider)` and method calls use `.notifier`.
