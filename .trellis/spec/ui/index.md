# UI and state layer (`lib/providers/`, `lib/ui/`, `lib/i18n/`)

Applies to Riverpod providers and notifiers, pages and widgets, theme and layout,
slang strings, routing, and `lib/app.dart` / `lib/main.dart`.

Stack: `flutter_riverpod` 3 written by hand (no codegen, no freezed, no hooks),
`go_router`, slang. Architecture map: `docs/development.md` § 架構地圖.

## Guidelines

| File | Read when |
|------|-----------|
| [riverpod.md](./riverpod.md) | Adding or changing a provider, notifier or state class; wiring a service into Riverpod; a background provider |
| [widgets.md](./widgets.md) | Building a page or widget; errors/toasts/dialogs/menus; images, sliders; theme tokens; responsive layout; accessibility; platform-only UI |
| [i18n-and-routing.md](./i18n-and-routing.md) | Adding a user-visible string or a route |

## Pre-Development Checklist

- [ ] Playback controls call `AudioController` (`ref.read(audioControllerProvider.notifier)`), never `FmpAudioService` — AGENTS.md § Boundaries.
- [ ] The search page's source chips are the only source selector — AGENTS.md § Boundaries.
- [ ] Before writing a widget, check the shared-widget table in `widgets.md`; reuse wins over a new variant.
- [ ] A string that can change layout, or any user-visible change, needs on-device verification — plan for the `verify-on-device` skill.

## Quality Check

- Run the AGENTS.md § Verification row *UI widgets/pages* (targeted `test/ui` tests + `flutter analyze`); for i18n JSON also `dart run slang`.
- On-device verification with the `verify-on-device` skill is mandatory for user-visible changes; report what was observed, or name the blocker.
- Static rules that commonly fire here (all under `test/ui/static_rules/` or `test/providers/static_rules/`): image widgets, `ScopedSlider`, watch scope, error presentation, anchored providers, Equatable `props`. When one fires, follow its failure `reason:`.
- Not gated — check by hand: `ref.mounted` after awaits, `context.mounted` after awaits, `IconButton` tooltips, `AppRadius` / `AnimationDurations` instead of literals.
