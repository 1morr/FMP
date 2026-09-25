# Code-reuse thinking guide

FMP keeps one owner per concern, and several of those owners are guarded by
static rules. Writing a second copy is usually what the rule catches. Search
first:

```bash
rg -n "<value or name>" lib test docs
```

## Owners of recurring concerns

| Concern | Owner |
|---------|-------|
| Headers, user agents, image hosts per source | `SourceHttpPolicy` (`lib/data/sources/source_http_policy.dart`) |
| Is this URL trusted, which host is it | `SourceUrlPolicy` |
| Which sources exist / support search / rankings | `registeredSourceTypesProvider`, `searchSourceTypesProvider`, `rankingSourceTypesProvider` |
| Source error meaning | `SourceErrorKind` getters (`isRetryable`, `shouldSkipTrack`, …) |
| Exception → user sentence | `userMessageFor` / `failureMessage` |
| Track identity string | `TrackKey.format` / `formatGroup` |
| Timeouts, limits, retry ladders | `AppConstants` and friends in `lib/core/constants/app_constants.dart`; class statics next to the owner |
| Radii, durations, sizes | `AppRadius`, `AnimationDurations`, `AppSizes`, `AppLayout` |
| Window skeleton vs container columns | `WindowClass.of` / `columnsFor` (`breakpoints.dart`) |
| Backend decisions both players share | `playback_end_reason_rules.dart`, `live_edge_seek_policy.dart`, `next_media_plan.dart` |
| Playlist provider refresh after a mutation | `libraryInvalidationCoordinatorProvider` |
| Duration text | `DurationFormatter` |
| Widgets: images, sliders, dialogs, menus, toasts, errors | the table in `../ui/widgets.md` |
| Test doubles and waits | `test/support/`, `test/support/fakes/` (`../testing/test-conventions.md`) |

## When there are two near-copies

- Three or more copies of the same shape → extract to the owner above, or make
  that owner.
- Two copies that must stay identical across backends or layers → a shared pure
  function, plus a test both sides run (`backend_contract_test.dart` pattern).
- Do not add an abstraction for a single caller or an imagined future caller;
  FMP deletes those (`aa0bdd28`, `19f721c7`).

## Changing a constant

`rg` the value and the name. Constants here carry their reason in dartdoc (often
with a measurement); update that reason, and any test that pins the value.
