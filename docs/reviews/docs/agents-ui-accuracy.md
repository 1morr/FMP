# AGENTS UI Accuracy Review

Reviewed: 2026-05-21

Scope: `AGENTS.md` UI Development Guidelines, including unified image components, `FileExistsCache`, play state checks, menu/track actions, refresh behavior, AppBar action spacing, `ListTile.leading`, and UI constants, compared against `lib/ui/`, shared UI widgets, UI handlers, and shared image/cache helpers.

Method: Used `rg` first for the scoped headings and symbols, then read the relevant files with line numbers.

## Summary

The scoped UI documentation is mostly directionally accurate. The strongest matches are the image-loading rule, shared track-action menu/coordinator flow, AppBar trailing spacing in the main high-use AppBars, and avoiding `Row` directly inside `ListTile.leading`.

Two claims are not fully accurate as written: the play-state check is not universal, and "all UI magic numbers" is broader than the current code supports. The docs also miss important current UI behavior around `ContextMenuRegion` and the optimized `FileExistsCache.select(...)` pattern used by shared thumbnail widgets.

## Confirmed Accurate Claims

- [accurate] Unified image components are the current UI path for track covers, avatars, and other remote/local images.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Unified image components, `AGENTS.md:407-412`.
  Code evidence: `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_thumbnail.dart:18` defines `TrackThumbnail`; `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_thumbnail.dart:98-105` loads track thumbnails through `ImageLoadingService.loadImage(...)` with width/height; `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_thumbnail.dart:141` defines `TrackCover`; `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\services\image_loading_service.dart:52-63` defines `loadImage(...)`; `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\services\image_loading_service.dart:148-176` defines `loadAvatar(...)` and passes `width`/`height`. `rg -n "Image\.(network|file)" lib/ui lib/core lib/services lib/providers` returned no direct `Image.network()` or `Image.file()` call sites in the checked paths.

- [accurate] Common track actions are centralized through menu helpers and dispatched through `TrackActionCoordinator`.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Track action menus, `AGENTS.md:431`.
  Code evidence: `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\handlers\track_action_menu.dart:47-124` builds common menu entries; `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\handlers\track_action_coordinator.dart:17-68` dispatches single and multi-track actions; representative pages use the flow at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:347-359`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\home\home_page.dart:916-927`, and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\playlist_detail_page.dart:1573-1674`.

- [accurate] AppBars whose last action is an `IconButton` generally keep the documented trailing spacer.
  Related AGENTS paragraph: AppBar Actions Trailing Spacing, `AGENTS.md:435-436`.
  Code evidence: `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\library_page.dart:98-111`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\downloaded_page.dart:79-90`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\queue\queue_page.dart:299-316`, and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\selection_mode_app_bar.dart:84-109` all include `const SizedBox(width: 8)` in the actions list. AppBars ending in `PopupMenuButton` omit the spacer in places such as `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\history\play_history_page.dart:180-208` and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\settings\log_viewer_page.dart:109-141`.

- [accurate] The `ListTile.leading` performance rule appears followed in the checked UI code.
  Related AGENTS paragraph: ListTile Performance, `AGENTS.md:438-439`.
  Code evidence: multiline `rg` checks for `ListTile(... leading: Row(`, `leading: Builder(... Row(`, and `leading: SizedBox(... Row(` returned no matches in `lib/ui`. The only direct `leading: Row(` match is an AppBar leading area, not a `ListTile`, at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\library_page.dart:56-58`.

- [accurate] Refresh flows use provider invalidation or cache-service refreshes where reviewed.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Refresh, `AGENTS.md:433`.
  Code evidence: Explore uses a `RefreshIndicator` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:173-175`, backed by `rankingCacheServiceProvider.notifier.refreshBilibili()` and `refreshYouTube()` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:120-140`; downloaded-library navigation invalidates `downloadedCategoriesProvider` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\library_page.dart:56-65`; downloaded category refresh invalidates and re-reads its provider at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\downloaded_category_page.dart:137-147`.

## Outdated Or Contradicted Claims

- [contradicted] "All UI magic numbers centralized" is not true as a literal statement.
  Related AGENTS paragraph: UI Constants, `AGENTS.md:441-443`.
  Code evidence: the constants do exist at `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\constants\ui_constants.dart:6-32`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\constants\ui_constants.dart:37-56`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\constants\ui_constants.dart:60-79`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\constants\ui_constants.dart:83-90`, and `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\constants\ui_constants.dart:94-101`; however UI code still uses local literals such as `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\switch_expansion_tile.dart:26` (`BorderRadius.circular(8)`), `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\queue\queue_page.dart:127` (`Duration(milliseconds: 50)`), and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\player\player_page.dart:874` (`Radius.circular(20)`). Suggested doc action: soften this to "Shared/repeated UI constants live in..." or define which literals must use `ui_constants.dart`.

## Missing Important Behaviors

- [missing] The menu-action guidance does not mention `ContextMenuRegion`, now a common desktop/right-click menu wrapper paired with `PopupMenuEntry` lists.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Menu actions, `AGENTS.md:429`.
  Code evidence: `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\context_menu_region.dart:7-16` defines the wrapper, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\context_menu_region.dart:22-38` opens a menu on secondary tap, and pages use it for track/menu surfaces at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:229-337`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\home\home_page.dart:806-908`, and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\search\search_page.dart:1013-1017`.
  Suggested doc action: Add `ContextMenuRegion` as the expected right-click/context-menu companion to `PopupMenuButton` for menu-capable tiles/cards.

- [missing] The `FileExistsCache` paragraph shows the older broad-watch pattern but not the optimized `.select(...)` pattern used by shared cover widgets.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / FileExistsCache pattern, `AGENTS.md:414-419`.
  Code evidence: the provider is a `StateNotifierProvider<FileExistsCache, Set<String>>` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\providers\download\file_exists_cache.dart:238-244`; `TrackThumbnail` watches only the relevant path result with `.select(...)` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_thumbnail.dart:51-70`; `TrackCover` does the same at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_thumbnail.dart:175-192`; direct extension-based lookup still exists for cover/avatar paths at `C:\Users\Roxy\Documents\VSCode\FMP\lib\core\extensions\track_extensions.dart:58-82`.
  Suggested doc action: Keep the direct pattern for non-repeated detail UI, but document `.select(...)` or the shared `TrackThumbnail`/`TrackCover` wrappers as the preferred list/grid path.

## Architecture Rules Not Currently Followed

- [outdated] The documented "unified" play-state check is not universal.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Play state check, `AGENTS.md:421-427`.
  Code evidence: many track tiles match the documented `sourceId + pageNum` pattern, for example `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:224-227`, `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\home\home_page.dart:801-804`, and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\playlist_detail_page.dart:1444-1448`; however play history deliberately compares `sourceId + cid` at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\history\play_history_page.dart:581-588`, and multi-page search group highlighting first checks `sourceId` for the whole video before checking `pageNum` for the specific row at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\search\search_page.dart:998-1007`.
  Suggested doc action: Document the exceptions (`cid` for history/Bilibili page identity and source-level group highlighting) or decide that the code should be brought back to the stated unified rule.

## Unclear Items Needing Human Decision

- [unclear] The AppBar spacer rule is clear for trailing `IconButton`, but current code is mixed on whether a spacer after a trailing `PopupMenuButton` is desirable.
  Related AGENTS paragraph: AppBar Actions Trailing Spacing, `AGENTS.md:435-436`.
  Code evidence: `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\selection_mode_app_bar.dart:101-109` adds `const SizedBox(width: 8)` after a `PopupMenuButton`, while `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\history\play_history_page.dart:194-208` and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\settings\log_viewer_page.dart:129-141` end with `PopupMenuButton` and no spacer.
  Decision needed: If the spacer after `PopupMenuButton` is intentionally optional, say so. If it should be avoided, `SelectionModeAppBar` diverges from the documented pattern.

- [unclear] The refresh paragraph may read as "always use pull-to-refresh", but current refresh UI also uses buttons and direct notifier refreshes.
  Related AGENTS paragraph: UI Development Guidelines / Code Consistency / Refresh, `AGENTS.md:433`.
  Code evidence: only `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\explore\explore_page.dart:173-175` uses `RefreshIndicator` in the checked UI, while library/download refresh paths use invalidation/button flows such as `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\library_page.dart:56-65` and `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\pages\library\downloaded_category_page.dart:137-147`; detail refresh uses a notifier call at `C:\Users\Roxy\Documents\VSCode\FMP\lib\ui\widgets\track_detail_panel.dart:422`.
  Decision needed: Clarify whether `RefreshIndicator` is required for scrollable list pages only, or whether button/notifier refreshes are accepted patterns where pull-to-refresh is not ergonomic.
