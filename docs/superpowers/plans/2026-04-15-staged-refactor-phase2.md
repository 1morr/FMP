# FMP Staged Refactor Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the phase-2 maintenance pass by tightening provider invalidation rules, filling missing stable `ValueKey` coverage, consolidating repeated single-track menu behavior, and only introducing lightweight page aggregation where it clearly reduces UI fan-out.

**Architecture:** Phase 2 stays outside the playback core and does not split `AudioController` or `QueueManager`. The work is limited to provider/UI maintenance seams: clarify when FutureProvider invalidation is still necessary, add explicit keys to dynamic rows, centralize repeated single-track actions into one handler, and treat page view-model aggregation as an optional last step only where it measurably simplifies top-level page reads.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, flutter_test

---

## File Structure

### Existing files to modify
- `lib/providers/playlist_provider.dart`
  - Clarify and tighten invalidation rules without assuming `allPlaylistsProvider` is watch-driven.
  - Keep detail/cover invalidation explicit where required.
- `lib/providers/download/download_providers.dart`
  - Remains the reference example of FutureProvider paths that still require explicit invalidation because they are file-scan driven.
- `lib/ui/pages/library/import_preview_page.dart`
  - Align playlist creation/import refresh behavior with the corrected invalidation rules.
- `lib/ui/pages/search/search_page.dart`
  - Add stable keys to dynamic row widgets.
  - Migrate only the repeated **single-track** menu actions to a shared handler.
- `lib/ui/pages/home/home_page.dart`
  - Migrate ranking/history single-track menu actions to the shared handler.
- `lib/ui/pages/explore/explore_page.dart`
  - Migrate ranking single-track menu actions to the shared handler.
- `lib/ui/pages/library/playlist_detail_page.dart`
  - Add stable keys to dynamic rows.
  - Migrate only the repeated **single-track** menu actions to the shared handler; keep multi-P/group actions local.
- `lib/ui/pages/library/downloaded_category_page.dart`
  - Migrate repeated single-track menu actions to the shared handler.
- `lib/ui/pages/library/library_page.dart`
  - Touch only if a single-track menu path clearly overlaps with the new handler; otherwise leave playlist-level actions alone.
- `lib/services/audio/player_state.dart`
  - Only touched if a new UI-state clearing behavior is needed by a tested Task 2/3 slice.

### New production files to create
- `lib/ui/handlers/track_action_handler.dart`
  - Shared action entrypoint for **single Track** menu operations used by search/home/explore/library/downloaded pages.
  - Handles only the repeated actions already duplicated in multiple pages: play temporary, add next, add to queue, add to playlist, match lyrics, add to remote playlist.
- `lib/providers/ui/home_page_view_model_provider.dart`
  - Optional lightweight aggregated provider for the top-level Home page only if Task 4 proves there is real fan-out reduction value.
- `lib/providers/ui/search_page_view_model_provider.dart`
  - Optional lightweight aggregated provider for the top-level Search page only if Task 4 proves there is real fan-out reduction value.

### New test files to create
- `test/providers/playlist_provider_phase2_test.dart`
  - Verifies the corrected invalidation rules by behavior, not by counting provider invalidations.
- `test/ui/pages/search/search_page_phase2_test.dart`
  - Verifies stable keys on dynamic search rows.
- `test/ui/handlers/track_action_handler_test.dart`
  - Covers the shared single-track action handler behavior.
- `test/ui/pages/home/home_page_phase2_test.dart`
  - Optional, only if Task 4 is executed.

---

### Task 1: Clarify and lock the playlist invalidation rules by behavior

**Files:**
- Create: `test/providers/playlist_provider_phase2_test.dart`
- Modify: `lib/providers/playlist_provider.dart:82-176`
- Modify: `lib/ui/pages/library/import_preview_page.dart:265-294`
- Test: `test/providers/playlist_provider_phase2_test.dart`

- [ ] **Step 1: Write the failing invalidation-behavior regression**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/providers/playlist_provider.dart';

void main() {
  test('creating a playlist updates playlist list and playlist detail consumers correctly', () async {
    final harness = await createPlaylistPhase2Harness();

    final listBefore = await harness.readAllPlaylists();
    expect(listBefore, isEmpty);

    final playlist = await harness.container
        .read(playlistListProvider.notifier)
        .createPlaylist(name: 'Phase 2 Playlist');

    expect(playlist, isNotNull);

    final listAfter = await harness.readAllPlaylists(forceRefresh: true);
    expect(listAfter.map((p) => p.name), contains('Phase 2 Playlist'));

    final detail = harness.container.read(playlistDetailProvider(playlist!.id));
    expect(detail.playlist?.id, playlist.id);
  });
}
```

- [ ] **Step 2: Run the playlist behavior test and confirm it fails**

Run:
```bash
flutter test test/providers/playlist_provider_phase2_test.dart
```

Expected: FAIL because the current create/import flow still mixes watch-driven and manual invalidation behavior in a way the harness exposes as inconsistent or overly coupled.

- [ ] **Step 3: Add the smallest realistic test harness**

```dart
class PlaylistPhase2Harness {
  PlaylistPhase2Harness(this.container);

  final ProviderContainer container;

  Future<List<Playlist>> readAllPlaylists({bool forceRefresh = false}) async {
    if (forceRefresh) {
      container.invalidate(allPlaylistsProvider);
    }
    final value = await container.read(allPlaylistsProvider.future);
    return value;
  }
}

Future<PlaylistPhase2Harness> createPlaylistPhase2Harness() async {
  final container = ProviderContainer();
  return PlaylistPhase2Harness(container);
}
```

- [ ] **Step 4: Update the invalidation rules without pretending `allPlaylistsProvider` is watch-driven**

```dart
// lib/providers/playlist_provider.dart
/// `playlistListProvider` is watch-driven through Isar.
/// `allPlaylistsProvider` is a plain FutureProvider and still requires explicit invalidation
/// when a caller depends on its value instead of the notifier-backed list state.
void invalidatePlaylistProviders(int playlistId, {bool includeAllPlaylists = false}) {
  if (includeAllPlaylists) {
    _ref.invalidate(allPlaylistsProvider);
  }
  _ref.invalidate(playlistDetailProvider(playlistId));
  _ref.invalidate(playlistCoverProvider(playlistId));
}
```

```dart
// lib/ui/pages/library/import_preview_page.dart
await service.addTracksToPlaylist(playlist.id, tracks);

ref.invalidate(allPlaylistsProvider);
ref.invalidate(playlistDetailProvider(playlist.id));
ref.invalidate(playlistCoverProvider(playlist.id));
```

- [ ] **Step 5: Remove only the truly redundant invalidation calls from notifier methods that are already covered by watch-driven UI**

```dart
// lib/providers/playlist_provider.dart
Future<Playlist?> createPlaylist({
  required String name,
  String? description,
  String? coverUrl,
}) async {
  try {
    final playlist = await _service.createPlaylist(
      name: name,
      description: description,
      coverUrl: coverUrl,
    );
    return playlist;
  } catch (e) {
    state = state.copyWith(error: e.toString());
    return null;
  }
}
```

```dart
// keep explicit invalidation in addTrackToPlaylistProvider because it serves FutureProvider consumers
final addTrackToPlaylistProvider =
    FutureProvider.family<bool, ({int playlistId, Track track})>((ref, params) async {
  final service = ref.watch(playlistServiceProvider);
  await service.addTrackToPlaylist(params.playlistId, params.track);
  ref.invalidate(allPlaylistsProvider);
  ref.invalidate(playlistDetailProvider(params.playlistId));
  ref.invalidate(playlistCoverProvider(params.playlistId));
  return true;
});
```

- [ ] **Step 6: Re-run the invalidation-behavior regression**

Run:
```bash
flutter test test/providers/playlist_provider_phase2_test.dart
```

Expected: PASS, proving the provider rules are coherent by observable behavior rather than by counting internal invalidation calls.

- [ ] **Step 7: Commit the provider-rules slice**

```bash
git add test/providers/playlist_provider_phase2_test.dart lib/providers/playlist_provider.dart lib/ui/pages/library/import_preview_page.dart
git commit -m "$(cat <<'EOF'
refactor(provider): clarify playlist invalidation rules

Document and tighten the split between watch-driven playlist state and explicit FutureProvider refresh paths without changing playback-core structure.
EOF
)"
```

---

### Task 2: Add stable `ValueKey` coverage to dynamic track rows

**Files:**
- Create: `test/ui/pages/search/search_page_phase2_test.dart`
- Modify: `lib/ui/pages/search/search_page.dart:520-560`
- Modify: `lib/ui/pages/search/search_page.dart:980-1008`
- Modify: `lib/ui/pages/search/search_page.dart:1485-1508`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:330-385`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:1388-1413`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Write the failing stable-key regression**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search result and local rows expose stable ValueKey identities', (tester) async {
    await tester.pumpWidget(buildSearchPageHarnessWithResults(
      onlineTracks: [
        buildTrack(sourceId: 'video-1', pageNum: 1, title: 'Track 1'),
      ],
      localTracks: [
        buildTrack(sourceId: 'local-1', pageNum: 1, title: 'Local Track'),
      ],
    ));

    expect(find.byKey(const ValueKey('search_video-1_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('local_local-1_1')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the stable-key test and confirm it fails**

Run:
```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: FAIL because the current widget constructors/call sites do not yet expose stable explicit keys.

- [ ] **Step 3: Add `super.key` support to the dynamic row widgets before changing call sites**

```dart
// lib/ui/pages/search/search_page.dart
class _SearchResultTile extends ConsumerWidget {
  const _SearchResultTile({
    super.key,
    required this.track,
    required this.isLocal,
    required this.isExpanded,
    required this.isLoading,
    required this.pages,
    required this.onTap,
    required this.onToggleExpand,
    required this.onMenuAction,
    required this.onPageMenuAction,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });
```

```dart
// lib/ui/pages/search/search_page.dart
class _LocalTrackTile extends ConsumerWidget {
  const _LocalTrackTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.onMenuAction,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });
```

```dart
// lib/ui/pages/library/playlist_detail_page.dart
class _TrackListTile extends ConsumerWidget {
  const _TrackListTile({
    super.key,
    required this.track,
    required this.playlistId,
    required this.playlistName,
    required this.onTap,
    this.onLongPress,
    required this.isPartOfMultiPage,
    required this.isImported,
    this.indent = false,
    this.isMix = false,
    this.isSelectionMode = false,
    this.isSelected = false,
  });
```

- [ ] **Step 4: Add stable keys at the dynamic row call sites**

```dart
// lib/ui/pages/search/search_page.dart
return _SearchResultTile(
  key: ValueKey('search_${track.sourceId}_${track.pageNum ?? 1}'),
  track: track,
  ...
);
```

```dart
// lib/ui/pages/search/search_page.dart
return _LocalTrackTile(
  key: ValueKey('local_${track.sourceId}_${track.pageNum ?? 1}'),
  track: track,
  ...
);
```

```dart
// lib/ui/pages/library/playlist_detail_page.dart
return _TrackListTile(
  key: ValueKey('playlist_${track.sourceId}_${track.pageNum ?? 1}_${playlistId}'),
  track: track,
  playlistId: playlistId,
  ...
);
```

- [ ] **Step 5: Re-run the stable-key regression**

Run:
```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS, with dynamic rows now discoverable through stable keys.

- [ ] **Step 6: Commit the stable-key slice**

```bash
git add test/ui/pages/search/search_page_phase2_test.dart lib/ui/pages/search/search_page.dart lib/ui/pages/library/playlist_detail_page.dart
git commit -m "$(cat <<'EOF'
fix(ui): add stable keys to dynamic track rows

Expose explicit ValueKey identities for dynamic search and playlist rows so selection and playback UI stay stable during list updates.
EOF
)"
```

---

### Task 3: Consolidate repeated **single-track** menu actions only

**Files:**
- Create: `lib/ui/handlers/track_action_handler.dart`
- Create: `test/ui/handlers/track_action_handler_test.dart`
- Modify: `lib/ui/pages/explore/explore_page.dart:340-377`
- Modify: `lib/ui/pages/home/home_page.dart:919-957`
- Modify: `lib/ui/pages/search/search_page.dart:871-953`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:1554-1609`
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:694-760`
- Test: `test/ui/handlers/track_action_handler_test.dart`

- [ ] **Step 1: Write the failing shared single-track action test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playNext delegates to audio controller and reports success', () async {
    final audio = FakeTrackActionAudioController()..addNextResult = true;
    final sink = FakeTrackActionFeedbackSink();
    final handler = TrackActionHandler(
      audioController: audio,
      feedbackSink: sink,
    );
    final track = buildTrack(sourceId: 'track-1', title: 'Track 1');

    await handler.handle(
      TrackAction.playNext,
      track: track,
      isLoggedIn: true,
      onAddToPlaylist: () async {},
      onMatchLyrics: () async {},
      onAddToRemote: () async {},
    );

    expect(audio.addNextCalls.single.sourceId, 'track-1');
    expect(sink.successMessages.single, contains('added'));
  });
}
```

- [ ] **Step 2: Run the single-track handler test and confirm it fails**

Run:
```bash
flutter test test/ui/handlers/track_action_handler_test.dart
```

Expected: FAIL because `TrackActionHandler` does not exist yet.

- [ ] **Step 3: Add the minimal handler scoped to repeated single-track actions**

```dart
// lib/ui/handlers/track_action_handler.dart
import '../../data/models/track.dart';
import '../../services/audio/audio_provider.dart';

enum TrackAction {
  play,
  playNext,
  addToQueue,
  addToPlaylist,
  matchLyrics,
  addToRemote,
}

abstract class TrackActionFeedbackSink {
  void showAddedToNext();
  void showAddedToQueue();
  void showPleaseLogin();
}

class TrackActionHandler {
  TrackActionHandler({
    required AudioController audioController,
    required TrackActionFeedbackSink feedbackSink,
  })  : _audioController = audioController,
        _feedbackSink = feedbackSink;

  final AudioController _audioController;
  final TrackActionFeedbackSink _feedbackSink;

  Future<void> handle(
    TrackAction action, {
    required Track track,
    required bool isLoggedIn,
    required Future<void> Function() onAddToPlaylist,
    required Future<void> Function() onMatchLyrics,
    required Future<void> Function() onAddToRemote,
  }) async {
    switch (action) {
      case TrackAction.play:
        await _audioController.playTemporary(track);
        return;
      case TrackAction.playNext:
        final added = await _audioController.addNext(track);
        if (added) _feedbackSink.showAddedToNext();
        return;
      case TrackAction.addToQueue:
        final added = await _audioController.addToQueue(track);
        if (added) _feedbackSink.showAddedToQueue();
        return;
      case TrackAction.addToPlaylist:
        await onAddToPlaylist();
        return;
      case TrackAction.matchLyrics:
        await onMatchLyrics();
        return;
      case TrackAction.addToRemote:
        if (!isLoggedIn) {
          _feedbackSink.showPleaseLogin();
          return;
        }
        await onAddToRemote();
        return;
    }
  }
}
```

- [ ] **Step 4: Replace only the repeated single-track action branches with the handler**

```dart
// lib/ui/pages/explore/explore_page.dart
TrackAction _mapTrackAction(String action) {
  switch (action) {
    case 'play':
      return TrackAction.play;
    case 'play_next':
      return TrackAction.playNext;
    case 'add_to_queue':
      return TrackAction.addToQueue;
    case 'add_to_playlist':
      return TrackAction.addToPlaylist;
    case 'matchLyrics':
      return TrackAction.matchLyrics;
    case 'add_to_remote':
      return TrackAction.addToRemote;
    default:
      throw ArgumentError('Unsupported track action: $action');
  }
}
```

```dart
// lib/ui/pages/search/search_page.dart
// Keep `_handlePageMenuAction(...)` and multi-P aggregate actions local.
// Use the shared handler only inside `_handleMenuAction(Track track, String action)`.
```

```dart
// lib/ui/pages/library/playlist_detail_page.dart
// Keep group / multi-P / download-all actions local.
// Use the shared handler only inside `_TrackListTile._handleMenuAction(...)` for single-track actions.
```

- [ ] **Step 5: Re-run the handler regression**

Run:
```bash
flutter test test/ui/handlers/track_action_handler_test.dart
```

Expected: PASS, with the repeated single-track behavior covered once.

- [ ] **Step 6: Commit the single-track handler slice**

```bash
git add test/ui/handlers/track_action_handler_test.dart lib/ui/handlers/track_action_handler.dart lib/ui/pages/explore/explore_page.dart lib/ui/pages/home/home_page.dart lib/ui/pages/search/search_page.dart lib/ui/pages/library/playlist_detail_page.dart lib/ui/pages/library/downloaded_category_page.dart
git commit -m "$(cat <<'EOF'
refactor(ui): consolidate repeated single-track actions

Route duplicated single-track menu behavior through a shared handler while keeping multi-page and group actions local.
EOF
)"
```

---

### Task 4: Optionally add lightweight page view-model providers only if they clearly reduce top-level fan-out

**Files:**
- Create: `lib/providers/ui/search_page_view_model_provider.dart`
- Create: `lib/providers/ui/home_page_view_model_provider.dart`
- Create: `test/ui/pages/home/home_page_phase2_test.dart`
- Modify: `lib/ui/pages/search/search_page.dart:75-137`
- Modify: `lib/ui/pages/home/home_page.dart:90-140`
- Test: `test/ui/pages/home/home_page_phase2_test.dart`

**Execution rule:** Only do this task if, after Tasks 1-3, the top-level page reads still feel materially noisy. If the earlier tasks already remove the main maintenance pain, skip this task for Phase 2 and treat it as follow-up.

- [ ] **Step 1: Write the failing view-model regression only if the task is still justified**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home page top-level state can be read from one view model provider', () {
    final container = buildHomePageProviderHarness();
    final viewModel = container.read(homePageViewModelProvider);

    expect(viewModel.hasBilibiliData, isTrue);
    expect(viewModel.hasYoutubeData, isTrue);
  });
}
```

- [ ] **Step 2: Run the optional view-model regression and confirm it fails**

Run:
```bash
flutter test test/ui/pages/home/home_page_phase2_test.dart
```

Expected: FAIL because the optional page view-model providers do not exist yet.

- [ ] **Step 3: Add the smallest aggregated providers**

```dart
// lib/providers/ui/home_page_view_model_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../popular_provider.dart';
import '../../services/cache/ranking_cache_service.dart';

class HomePageViewModel {
  const HomePageViewModel({
    required this.hasBilibiliData,
    required this.hasYoutubeData,
    required this.isInitialLoading,
  });

  final bool hasBilibiliData;
  final bool hasYoutubeData;
  final bool isInitialLoading;
}

final homePageViewModelProvider = Provider<HomePageViewModel>((ref) {
  final bilibiliAsync = ref.watch(homeBilibiliMusicRankingProvider);
  final youtubeAsync = ref.watch(homeYouTubeMusicRankingProvider);
  final cacheService = ref.watch(rankingCacheServiceProvider);

  return HomePageViewModel(
    hasBilibiliData: bilibiliAsync.valueOrNull?.isNotEmpty ?? false,
    hasYoutubeData: youtubeAsync.valueOrNull?.isNotEmpty ?? false,
    isInitialLoading: cacheService.isInitialLoading,
  );
});
```

```dart
// lib/providers/ui/search_page_view_model_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../search_provider.dart';
import '../selection_provider.dart';

class SearchPageViewModel {
  const SearchPageViewModel({
    required this.searchState,
    required this.selectionState,
  });

  final SearchState searchState;
  final SearchSelectionState selectionState;
}

final searchPageViewModelProvider = Provider<SearchPageViewModel>((ref) {
  return SearchPageViewModel(
    searchState: ref.watch(searchProvider),
    selectionState: ref.watch(searchSelectionProvider),
  );
});
```

- [ ] **Step 4: Switch only the page-top reads to the aggregated view models**

```dart
// lib/ui/pages/search/search_page.dart
final viewModel = ref.watch(searchPageViewModelProvider);
final searchState = viewModel.searchState;
final selectionState = viewModel.selectionState;
```

```dart
// lib/ui/pages/home/home_page.dart
final viewModel = ref.watch(homePageViewModelProvider);
final hasBilibiliData = viewModel.hasBilibiliData;
final hasYoutubeData = viewModel.hasYoutubeData;
final isLoading = viewModel.isInitialLoading;
```

- [ ] **Step 5: Re-run the optional view-model regression**

Run:
```bash
flutter test test/ui/pages/home/home_page_phase2_test.dart
```

Expected: PASS if this optional task is executed.

- [ ] **Step 6: Commit the optional page-view-model slice**

```bash
git add test/ui/pages/home/home_page_phase2_test.dart lib/providers/ui/home_page_view_model_provider.dart lib/providers/ui/search_page_view_model_provider.dart lib/ui/pages/home/home_page.dart lib/ui/pages/search/search_page.dart
git commit -m "$(cat <<'EOF'
refactor(ui): add lightweight page view models where justified

Reduce top-level provider fan-out only where the page reads remain noisy after the earlier phase-2 maintenance cleanup.
EOF
)"
```

---

### Task 5: Run the Phase 2 verification suite and capture the maintenance rules

**Files:**
- Modify: `CLAUDE.md`
- Test: `test/providers/playlist_provider_phase2_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`
- Test: `test/ui/handlers/track_action_handler_test.dart`
- Test: `test/ui/pages/home/home_page_phase2_test.dart` (only if Task 4 was executed)

- [ ] **Step 1: Add the Phase 2 maintenance note to project docs**

```md
### Phase-2 Maintenance Note (2026-04-15)
Phase-2 work should stay outside core playback structure and focus on consistency at the provider and page layer.

- Normalize invalidation rules by observable behavior, not by assuming every list provider is watch-driven.
- Add stable `ValueKey` identities to dynamic list rows before changing surrounding behavior.
- Consolidate repeated single-track menu behavior through shared handlers, while keeping multi-page and group-specific actions local.
- Add page view-model providers only where they measurably reduce top-level UI fan-out.
```

- [ ] **Step 2: Run the focused Phase 2 verification suite**

Run:
```bash
flutter test test/providers/playlist_provider_phase2_test.dart && flutter test test/ui/pages/search/search_page_phase2_test.dart && flutter test test/ui/handlers/track_action_handler_test.dart
```

Expected: PASS for all required Phase 2 regressions.

- [ ] **Step 3: If Task 4 was executed, run its verification too**

Run:
```bash
flutter test test/ui/pages/home/home_page_phase2_test.dart
```

Expected: PASS only when the optional Task 4 was actually implemented.

- [ ] **Step 4: Run adjacent Phase 1 suites to confirm no regression at the stabilization layer**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart && flutter test test/services/download/download_service_phase1_test.dart && flutter test test/providers/database_migration_test.dart && flutter test test/services/cache/ranking_cache_service_test.dart
```

Expected: PASS, proving the Phase 2 maintenance work did not disturb the Phase 1 stabilization suite.

- [ ] **Step 5: Run static analysis after the provider/UI cleanup**

Run:
```bash
flutter analyze
```

Expected: PASS, or only pre-existing unrelated warnings.

- [ ] **Step 6: Commit the Phase 2 verification slice**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: record phase-2 maintenance constraints

Document the provider and page-layer guardrails for the post-stabilization maintenance pass and verify the new regression suite.
EOF
)"
```

---

## Self-Review

### Spec coverage check
- **FutureProvider invalidation strategy**: Covered by Task 1, but corrected to validate behavior and clarify rules without incorrectly assuming `allPlaylistsProvider` is watch-driven.
- **ValueKey completion**: Covered by Task 2, including the required `super.key` constructor support before call-site changes.
- **Menu action consolidation**: Covered by Task 3, explicitly scoped to repeated single-track actions and not to VideoPage / multi-P aggregate flows.
- **Page-level provider fan-out reduction**: Covered by Task 4 as an optional/conditional task rather than mandatory work when the payoff is unclear.
- **Phase 2 verification/documentation**: Covered by Task 5.

### Placeholder scan
- No `TODO`, `TBD`, or “similar to Task N” shortcuts remain.
- Every task includes exact file paths, concrete commands, and code snippets for the intended slice.
- Optional Task 4 is explicitly marked conditional rather than left ambiguous.

### Type consistency check
- `TrackActionHandler`, `TrackAction`, `TrackActionFeedbackSink`, `HomePageViewModel`, and `SearchPageViewModel` are introduced before later tasks use them.
- The plan no longer references undefined `_mapTrackAction` behavior without defining it.
- The plan keeps the work at the provider/UI maintenance boundary and avoids introducing playback-core extraction types reserved for later phases.
