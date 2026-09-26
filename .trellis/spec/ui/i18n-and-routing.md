# Strings (slang) and routes (go_router)

## Strings

- User-visible strings are slang keys (a known literal: the `'Info+'` /
  `'Warning+'` filter labels in `log_viewer_page.dart`). Files are
  `lib/i18n/{zh-CN,zh-TW,en}/<namespace>.i18n.json`; `zh-CN` is the base locale
  (`slang.yaml`). A new key goes into **all three** files of the namespace.
- Namespaces and keys are camelCase; nested objects are fine
  (`t.settings.launchAtStartup.portableHint`).
- Parameters use `$name`: `"Load failed: $error"` →
  `t.library.loadFailedWithError(error: userMessageFor(e))`. No plural forms are
  in use. Never pass raw exception text into a template (the `error:` parameter is
  gated across `lib/` by `test/ui/static_rules/error_presentation_static_rule_test.dart`).
- Access is the global `t` (`package:fmp/i18n/strings.g.dart`) in UI, providers
  and services. A subtree that must rebuild when the locale arrives after the
  first frame uses `context.t` (`ResponsiveScaffold`, #112).
- Locale switch: `LocaleSettings.instance.setLocaleSync(locale)` **before**
  `state = locale` (`LocaleNotifier`).
- Regenerate with `dart run slang` (standalone; `slang_build_runner` is
  deliberately not used). `dart run slang analyze` writes
  `_missing_translations.json` / `_unused_translations.json` into `lib/i18n/` —
  delete them afterwards.

## Routes

- Constants in `lib/ui/router.dart`: `RoutePaths` (plus builders like
  `playlistDetailPath(id)`) and `RouteNames`. Every `GoRoute` sets both `path:`
  and `name:`.
- Tabs live inside the `ShellRoute` with `NoTransitionPage`; sub-pages use
  `builder:`; full-screen players sit outside the shell with
  `parentNavigatorKey: rootNavigatorKey`.
- Navigate with `context.go(RoutePaths.x)` for tabs, `context.push(RoutePaths.x)`
  or `context.pushNamed(RouteNames.x)` for sub-pages. Never a string literal.
- The index ↔ path mapping for navigation destinations lives only in
  `destinations` (`lib/ui/layouts/responsive_scaffold.dart`).
- Adding a route: constants in `RoutePaths` + `RouteNames`, a `GoRoute` under the
  right parent, the page import in `router.dart`.
