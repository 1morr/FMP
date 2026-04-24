# Review-Driven Refactor Design

## Goal

Create a review-driven refactoring roadmap for FMP that converts the findings in `docs/review/*.md` into a staged, test-first plan. The roadmap keeps high-risk structural changes separate from low-risk defect fixes, so the project can reduce known playback, platform, data, and UI risks without destabilizing the audio core.

## Source Material

This design is based on the following audit reports:

- `docs/review/summary_review.md`
- `docs/review/architecture_review.md`
- `docs/review/stability_review.md`
- `docs/review/platform_review.md`
- `docs/review/database_review.md`
- `docs/review/performance_memory_review.md`
- `docs/review/consistency_review.md`
- `docs/review/testing_review.md`

The reports agree that FMP's main architecture is sound. The refactor should preserve the platform-split audio backend, UI-to-`AudioController` boundary, `QueueManager` responsibilities, `PlaybackRequestExecutor` request locking, `SourceApiException` model, Windows download isolate, lyrics window hide lifecycle, and Isar watch/FutureProvider split.

## Scope Decision

The review findings cover several independent subsystems. They should not be implemented as one large change. The output should be:

1. A staged roadmap covering all review findings at a useful level.
2. A detailed, executable implementation plan for Phase 1 only.

Phase 1 focuses on low-risk, high-confidence fixes and their minimum regression tests. Later phases remain as roadmap items until Phase 1 is complete and the codebase can be re-evaluated.

## Roadmap

### Phase 1: Low-Risk, High-Value Fixes

Purpose: remove clear defects and boundary issues with small, testable changes.

Included work:

- Fix playback-side `AudioStreamResult.expiry` handling in `AudioStreamDelegate.ensureAudioStream()`.
- Guard `_resumeWithFreshUrlIfNeeded()` delayed seek so an older resume path cannot seek a newer track.
- Add Windows portable ZIP extraction path traversal checks in `UpdateService`.
- Replace Android storage permission version detection with reliable SDK-int based logic.
- Remove or gate expensive `TrackRepository.save()` stack trace/debug logging on the hot path.
- Change download path setting updates to use `SettingsRepository.update()` instead of get-and-save overwrite.
- Add missing `ImageLoadingService.loadImage()` sizing hints where fixed display sizes are known.
- Add stable `ValueKey`s to dynamic cover/import preview grid/list items.
- Remove or consolidate unused `searchHistoryProvider` if it is still unreferenced.
- Add the minimum tests recommended by the review reports for these changes.

Expected result: safer playback resume behavior, safer Windows update extraction, correct Android permission branching, less hot-path logging overhead, fewer settings overwrite races, and better UI consistency with limited behavior risk.

### Phase 2: Logic Unification and Duplicate Cleanup

Purpose: reduce drift between similar code paths after the highest-confidence fixes are in place.

Candidate work:

- Extract a download media headers helper that aligns download requests with playback header strategy without blindly leaking source API headers to all CDNs.
- Change external playlist import selected-track handling to copy `Track` objects before writing `originalSongId` and `originalSource`.
- Keep search history behind one state entry point.
- Extract remote playlist remove/sync actions from `playlist_detail_page.dart` into an application service.
- Add bounded negative caching to `FileExistsCache` before removing more build-time file checks.
- Add tests for lyrics direct fetch, selected track copy behavior, download provider completion/failure glue, and local-file playback handoff.

Expected result: fewer hidden side effects, fewer duplicated source/state paths, and lower chance that playback/download/import behavior diverges.

### Phase 3: Structural Refactoring

Purpose: address larger consistency and performance risks that require broader tests and careful migration.

Candidate work:

- Make Playlist/Track bidirectional updates atomic inside single Isar transactions for core add/remove/refresh paths.
- Make download completion Track/DownloadTask database writes a recoverable, consistent transaction boundary.
- Refactor play history queries into smaller purpose-specific providers and flatten grouped history UI rows.
- Split high-frequency playback position state from low-frequency queue state to reduce large-queue Riverpod overhead.
- Move Source creation ownership toward `SourceManager`/providers and remove direct ad-hoc `YouTubeSource()` construction where practical.
- Continue small `AudioController` decomposition only after behavior tests protect playback request semantics.

Expected result: stronger data consistency, better large-list performance, and clearer ownership boundaries, without rewriting the audio architecture.

### Phase 4: Long-Term Optimization

Purpose: improve edge-case scalability and platform maintenance once core defects and structural risks are reduced.

Candidate work:

- Providerize current lyrics line index to avoid rebuilding lyrics UI on every position tick.
- Move downloaded category detail scanning to an isolate or DTO-based worker path.
- Flatten download manager rows to avoid building all non-active tasks at once.
- Add uniqueness scanning/repair for Track, DownloadTask, Account, and PlayQueue before considering unique indexes.
- Consider a small `PlaybackOwnershipCoordinator` for Radio/Audio shared-player ownership if radio or media-control functionality expands.

Expected result: lower long-running CPU/I/O cost, better behavior with large local libraries, and safer future platform extensions.

## Phase 1 Design Details

### Testing Strategy

Phase 1 should be test-first where the current code has clear behavioral gaps:

- Audio expiry: add a failing test proving the playback path stores source-provided expiry rather than a fixed one-hour value.
- Resume seek guard: add a failing test where an expired URL resume is superseded before delayed seek and must not seek the newer track.
- ZIP extraction: add tests for normal entries and malicious `../`, absolute, or Windows drive paths.
- Android permission: make SDK version branching injectable/testable and cover Android 10 versus Android 11+ branches without needing a real device for unit logic.
- Settings update: add or adjust tests to ensure download path writes update only that field.
- UI consistency: use static or widget-level tests where low-cost, especially for stable keys and forbidden patterns if existing test style supports it.

For changes that depend on actual platform behavior, keep unit tests focused on pure branching or helper functions, then list manual verification steps for Android and Windows.

### Safety Constraints

- Do not rewrite `AudioController`, `QueueManager`, or platform audio services in Phase 1.
- Do not change queue semantics, temporary play behavior, mix mode behavior, or radio ownership as part of Phase 1.
- Do not introduce new abstractions unless they are needed by a tested Phase 1 fix, such as a small ZIP path helper or SDK version provider.
- Keep platform changes local and reversible.
- Preserve existing behavior for sources that do not return an expiry by retaining a one-hour fallback.
- Do not add unique database indexes or schema-wide cleanup in Phase 1.

### Validation Strategy

Each Phase 1 task should run the narrow related tests immediately, then run broader checks after the batch:

- `flutter test` for the touched test groups or full suite when practical.
- `flutter analyze` after code changes.
- Manual playback smoke: Netease/Bilibili remote playback, pause until URL refresh is needed if feasible, resume, then quick switch tracks.
- Manual Windows portable update smoke for normal ZIP extraction behavior if environment allows.
- Manual Android storage permission smoke on Android 10-or-lower and Android 11+ device/emulator if available.
- UI smoke for home/downloaded/cover picker/import preview screens affected by sizing hints and keys.

## Documentation Expectations

After Phase 1 implementation, update project docs only if behavior or architecture changes require it:

- Update `CLAUDE.md` if Android storage permission handling or update-system safety rules become core project knowledge.
- Update `.serena/memories/update_system.md` or `download_system.md` only if the project still uses those memories for detailed implementation notes.
- Do not duplicate the review reports; the plan should link back to `docs/review` as the source of findings.

## Success Criteria

The Phase 1 implementation plan is successful if it provides a sequence of small, testable tasks that:

- Fix the top immediate playback/platform/data/UI issues identified in the review summary.
- Keep structural refactors out of Phase 1.
- Include tests before or with every behavior-sensitive fix.
- Define exact commands and expected outcomes for verification.
- Leave later phases clearly documented but not over-specified before Phase 1 results are known.

## Self-Review Notes

- Placeholder scan: no TBD/TODO placeholders remain.
- Scope check: the spec is intentionally split into roadmap plus Phase 1 detail target; it does not attempt to implement all subsystems at once.
- Consistency check: Phase names and contents match the approved option and the review summary priorities.
- Ambiguity check: Phase 1 includes only low-risk high-value fixes; structural items are explicitly deferred.
