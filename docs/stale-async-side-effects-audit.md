# Stale Async Side Effects Audit

Date: 2026-05-02

## Background

A race was found in `currentLyricsContentProvider`: an older lyrics-content request could complete after the provider had been invalidated and still write its result into `LyricsCacheService` under the current track key. This caused logs like two cache writes for the same track during AI advanced lyrics matching. The first write came from an obsolete UI lyrics-content load, not from the AI selector path.

This audit records similar stale async side-effect patterns to fix or monitor.

## Status

The concrete risks below have been fixed and covered by regression tests, except the final "Mostly acceptable / monitor" item, which remains intentionally unfixed because it writes only to the old track key and can serve as background pre-warming.

## Highest priority fixes

### Search pagination stale result merges

Files:
- `lib/providers/search_provider.dart`

Affected methods:
- `SearchNotifier.loadMore`
- `SearchNotifier.loadMoreAll`
- `SearchNotifier.loadMoreLiveRooms`

Fixed risk:
- Initial `search()` and `searchLiveRooms()` use `_searchRequestId` guards.
- Pagination methods do not capture and validate query/filter/order/request generation after `await`.
- If the user changes query, source filter, sort order, or live-room filter while a load-more request is in flight, stale page results can be appended into the new search state.

Fix:
- Capture request generation and relevant state before each pagination await.
- After await, verify `mounted`, generation, query, filters, order, page, and mode are unchanged before merging results.
- Increment `_searchRequestId` when clearing or changing filters without immediately delegating to `search()` if needed.

Tests:
- Start a search, trigger load-more, change query/filter/order, complete old request, and assert old results are not merged.
- Repeat for live-room pagination.

### Track detail refresh stale overwrite

Files:
- `lib/providers/track_detail_provider.dart`

Affected method:
- `TrackDetailNotifier.refresh`

Fixed risk:
- `loadDetail(track)` checks that the current source id/type still match before writing state.
- `refresh()` does not. If refreshing track A and the current track changes to B before A returns, A can overwrite the detail state.
- `refresh()` also uses `state.detail!.bvid` as the source id for all source types, which is suspicious for non-Bilibili sources.

Fix:
- Capture `_currentSourceId` and `_currentSourceType` before await.
- Fetch using the captured source id.
- Write success/error only if the captured id/type still match the current id/type.

Tests:
- Refresh A, load B before A completes, complete A, assert B state is not overwritten.

### Radio current-station info stale overwrite

Files:
- `lib/services/radio/radio_controller.dart`

Affected method:
- `RadioController.refreshStationInfo`

Fixed risk:
- It passes `state.currentStation!` into an async request and writes `viewerCount` after await without checking whether the current station changed.
- A delayed result for station A can write its viewer count while station B is current.

Fix:
- Capture station and station id before await.
- After await, write viewer count only if the current station id still matches.

Tests:
- Start station-info refresh for A, switch current station to B, complete A request, assert B viewer count is not overwritten.

## Medium priority fixes

### Playback network recovery / retry stale playback

Files:
- `lib/services/audio/audio_provider.dart`

Affected flows:
- `_scheduleRetry`
- `_retryPlayback`
- `_onNetworkRecovered`
- `retryManually`

Fixed risk:
- Retry/recovery captures a track, then may wait before executing playback recovery.
- User-initiated playback during that wait can clear retry state, but the captured local track may still be used unless guarded by a retry generation.

Fix:
- Add retry/recovery generation token.
- Increment generation when retry state is reset, rescheduled, network recovery starts, or manual retry starts.
- Verify generation and track identity before executing recovered playback or seek.

Tests:
- Schedule retry for A, start network recovery, play B during stabilization delay, assert A does not restart.
- Manual retry uses the same generation/track guards for post-await reset and seek work.

### FileExistsCache async checks after disposal

Files:
- `lib/providers/download/file_exists_cache.dart`

Affected methods:
- `preloadPaths`
- `_checkAndCache`
- `_scheduleRefreshPaths`

Fixed risk:
- Microtask/file-exists checks can update notifier state after the owning provider container is disposed.
- This is less likely to corrupt business data, but can cause state-after-dispose errors in tests or lifecycle edge cases.

Fix:
- Check `mounted` after awaits before `_updateState`, `_markAsMissing*`, and pending set cleanup where appropriate.
- Clear pending and missing caches during disposal.

Tests:
- Start async file check, dispose provider container before completion, assert no state-after-dispose error.

### Import playlist cancellation / overlapping operation state

Files:
- `lib/providers/import_playlist_provider.dart`

Affected methods:
- `_ensureService`
- `importFromUrl`
- `cancelImport`
- `reset`

Fixed risk:
- `_cancelRequested` handles simple cancellation, but no operation id guards against old import futures completing after cancel/reset/new import.
- Progress stream writes state without operation identity.

Fix:
- Add `_operationId` incremented on import/cancel/reset/dispose.
- Only write progress/result/error for the active operation id.
- Dispose superseded per-operation services after cleanup.

Tests:
- Start import A, cancel, start/import B, complete A late, assert A does not overwrite B state.

### Refresh manager delayed cleanup removes newer state

Files:
- `lib/providers/refresh_provider.dart`

Affected flow:
- Delayed completed/failed state removal in `RefreshManagerNotifier.refreshPlaylist`

Fixed risk:
- Completed/failed cleanup runs after 3-5 seconds and removes by playlist id only.
- If a new refresh for the same playlist starts before old cleanup fires, old cleanup can remove the new state.

Fix:
- Track per-playlist refresh generation.
- Progress/result/error side effects write only for the current generation.
- Delayed cleanup removes only the generation/status it scheduled for.

Tests:
- Complete refresh #1, start refresh #2 before cleanup, advance time, assert #2 state remains.

### Radio background refresh overlap

Files:
- `lib/services/radio/radio_refresh_service.dart`

Affected methods:
- `setRepository`
- `_startRefreshTimer`
- `refreshAll`

Fixed risk:
- Multiple `refreshAll()` calls can overlap.
- Older refresh results can overwrite newer live-status cache or station metadata.
- `repository.save(station)` is not awaited, hiding failures and allowing write races.

Fix:
- Coalesce overlapping `refreshAll()` calls by returning the active future.
- Add refresh generation for disposal/replacement safety.
- Await station saves so write order and failures are visible to the refresh future.

Tests:
- Start refresh #1, call refresh #2 while #1 is in flight, assert both calls share the same active future and only one live-info request/save occurs.

## Mostly acceptable / monitor

### Auto lyrics matching for no-longer-current tracks

Files:
- `lib/services/audio/audio_provider.dart`
- `lib/services/lyrics/lyrics_auto_match_service.dart`

Flow:
- `_executePlayRequest` starts `unawaited(_tryAutoMatchLyrics(track))`.
- If user switches tracks, the old track's auto-match can still finish and save `LyricsMatch` and cache under the old track key.

Assessment:
- This does not write old lyrics into the new current track key, unlike the fixed `currentLyricsContentProvider` bug.
- It can be acceptable as background pre-warming for a track the user just played.
- The UI loading flag is a single boolean and can still be wrong if multiple auto-match tasks overlap.

Optional fix:
- If product behavior should be current-track-only, add a cancellation predicate to `tryAutoMatch` and check before DB/cache writes.
- Track auto-match loading by track key or request count instead of a single boolean.

## Rule of thumb for future work

Any async path that captures current item/query/provider state and performs a side effect after `await` should either:

1. be keyed by the captured object and only write to that object's key; or
2. re-check a request id/generation/current identity before writing state/cache/database; or
3. be cancelable/disposed and skip side effects after disposal.
