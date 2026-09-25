# Pages and widgets

## Widget kinds and structure

- `ConsumerWidget` when only providers are read; `ConsumerStatefulWidget` when
  there are controllers, `listenManual` subscriptions or local async flows.
- Split a page into independent `ConsumerWidget` sections so a provider change
  rebuilds only its section (`HomePage` sections, `track_detail_panel.dart`).
- Private `_Xxx` widgets inside the page file are normal. A page-local widget that
  grows moves to `lib/ui/pages/<feature>/widgets/`; cross-page widgets go to
  `lib/ui/widgets/<category>/`.
- `const` constructors with `super.key`.
- After every `await` in a `State` or handler: `if (!mounted) return;` /
  `if (!context.mounted) return;` (`45f9f1fe`).
- Layout decisions worth testing are pure top-level functions
  (`resolvePlayerLayout(Size, {hasLyrics})`, `buildHomeRankingLayoutPlan(...)`),
  tested without pumping the page.

## Reuse these before writing a new one

| Need | Use |
|------|-----|
| Destructive confirm | `showConfirmDestructiveDialog(...)` — `widgets/dialogs/` |
| Inline error / empty state | `ErrorDisplay(compact: true, message:, onRetry:)`, `LoadingPlaceholder` — `widgets/feedback/error_display.dart` |
| Toast | `ToastService.success/show/error/warning(context, msg)`; for an exception **only** `ToastService.failure(context, e, stackTrace:, tag:)` — `lib/core/services/toast_service.dart`. Background services push through `toastServiceProvider` |
| Success / warning colour | `ToastService.successColor` / `warningColor` (ColorScheme has none) |
| Context menu | `ContextMenuRegion`; one action list for popup + long-press sheet: `MenuAction` + `buildMenuActionPopupEntries` / `buildMenuActionListTiles` |
| Track actions | `lib/ui/handlers/track_action_*.dart` (`TrackAction`, `TrackActionHandler`) |
| Popup item with a trailing icon | `PopupMenuRow`, not `ListTile` (`ddee98c9`) |
| Bottom sheet | `CappedDraggableSheet`, `SheetDragHandle` |
| Slider | `ScopedSlider` — a raw `Slider` freezes the Windows accessibility tree (gated) |
| Any image | `TrackThumbnail` / `TrackCover(variant:)`, `PlaylistCoverImage(variant:)`, `AvatarImage`, … in `widgets/images/`; never `Image.network` or a raw size (#107, gated) |
| Duration text | `DurationFormatter` |

Gates: `test/ui/static_rules/ui_consistency_static_rule_test.dart` (images;
`ListTile.leading` must not be a raw `Row`),
`slider_overlay_static_rule_test.dart`, `error_presentation_static_rule_test.dart`.
`CustomTitleBar` is built once in `lib/app.dart`; pages never add another.

Dialog entry points exist in two styles, both accepted: top-level
`Future<T?> showXxxDialog(...)` and `static Future<T?> show(BuildContext)` on the
dialog class. Close with `Navigator.pop(context, result)`.

## AsyncValue

- Use `.when(data:, loading:, error:)`.
- The error branch must render something: `ErrorDisplay(compact: true, …)` for a
  section, a placeholder for a cover or avatar. `SizedBox.shrink()` in an error
  branch is gated (`609cc41c`). The loading branch may be empty.
- A `FutureProvider` feeding a placeholder logs its failure inside the provider,
  then rethrows with `Error.throwWithStackTrace` — the UI error branch reruns every
  build and must not log.

## Theme and tokens

- Colours from `Theme.of(context).colorScheme`, text from `textTheme`. Raw
  `Colors.*` is almost only white/black/transparent overlays on images; the few
  fixed hues (live badge red, title-bar close hover, the colour-picker hue ring)
  are deliberate one-offs, not a precedent.
- Radii from `AppRadius`, durations from `AnimationDurations`, shared sizes from
  `AppSizes` / `AppLayout` (`lib/core/constants/`).
- Spacing is written as literals (`EdgeInsets.all(16)`). The `AppSpacing` scale was
  deleted for having no callers (`aa0bdd28`); do not reintroduce one without
  migrating callers.
- Light and dark themes come from one description in `lib/ui/theme/app_theme.dart`.

## Responsive layout

The two APIs in `lib/core/constants/breakpoints.dart` answer different questions
— read `docs/development.md` § 響應式版面配置 before using either.
`WindowClass.of(MediaQuery width)` picks the window skeleton; anything inside a
pane measures itself with `LayoutBuilder` (and `columnsFor(constraints.maxWidth)`
when it needs a column count). Mixing them is the cause of `9557e03f`.

## Accessibility

Not gated — hold these by hand:
- Every `IconButton` has a `tooltip:` (its accessible name, `104bd8d3`). Do not wrap
  an `IconButton` in `Tooltip(...)` (Windows AXTree, `docs/troubleshooting.md`).
- 48dp touch targets; no overflow at text scale 2.0.
- Nested navigators get `Semantics(container: true, …)`.

## Platform-specific UI

- `Platform.isWindows` / `Platform.isAndroid` for platform features;
  `isDesktopPlatform` (`lib/core/utils/platform_utils.dart`) for "desktop".
- Tray and hotkey logic live in `lib/services/platform/windows_desktop_service.dart`,
  SMTC in `lib/services/audio/windows_smtc_handler.dart` — not in widgets.
- The desktop lyrics window runs in a separate engine (`lib/ui/windows/`): no
  `ProviderScope`, no slang. Strings are pushed from the main window; a key it
  reads must be pushed too (`test/services/static_rules/lyrics_window_strings_static_rule_test.dart`).

## Widget tests

- Wrap as `TranslationProvider(child: ProviderScope(overrides: [...], child: MaterialApp(home: …)))`
  and set `LocaleSettings.setLocale(AppLocale.en)` in `setUp`. Assert against
  `t.xxx`, not literal text.
- `ResponsiveScaffold` reads `MediaQuery`; drive it with `tester.view.physicalSize`
  + `devicePixelRatio`, not `setSurfaceSize`.
- Semantics assertions: `tester.ensureSemantics()` + `dispose()`
  (`test/ui/layouts/nav_rail_semantics_test.dart`).
- No golden tests.
