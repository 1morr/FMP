# Database Viewer Completeness Design

## Goal

Update the developer database viewer so it exposes every Isar collection currently opened by the app and shows all available fields/getters useful for debugging. Also update `CLAUDE.md` so future database schema changes include database viewer maintenance.

## Current State

`lib/providers/database_provider.dart` opens these collections:

- `Track`
- `Playlist`
- `PlayQueue`
- `Settings`
- `SearchHistory`
- `DownloadTask`
- `PlayHistory`
- `RadioStation`
- `LyricsMatch`
- `LyricsTitleParseCache`
- `Account`

`lib/ui/pages/settings/database_viewer_page.dart` currently omits `LyricsTitleParseCache` and `Account`. Several existing collection views also omit newer fields and computed getters.

## Chosen Approach

Keep the current per-collection hand-written viewer structure and add missing coverage directly.

This is preferred because:

- It matches the current UI and code style.
- It keeps each table's display grouped and readable.
- It supports computed getters and embedded objects without relying on runtime reflection.
- The scope is limited to the requested developer page and documentation rule.

## Database Viewer Changes

1. Add `LyricsTitleParseCache` and `Account` to the collection selector.
2. Import their model files.
3. Add list views for both missing collections.
4. Audit existing list views and display current model fields plus useful getters:
   - `Track`: include persisted fields such as `bilibiliAid`, plus getters like `uniqueKey`, `groupKey`, `formattedDuration`, and existing availability/download getters.
   - `Settings`: include lyrics display/source settings, AI title parsing settings, auth settings, refresh intervals, and existing derived enum/list getters where useful.
   - `Playlist`, `PlayQueue`, `DownloadTask`, `PlayHistory`, `RadioStation`, `LyricsMatch`, and `SearchHistory`: keep current sections and add missing computed values where useful.
5. Keep the existing `_DataCard` and `_DataSection` UI pattern. Do not redesign the page or add editing/destructive controls.

## Documentation Changes

Update `CLAUDE.md` in the database migration/data model guidance to state:

- When adding, removing, or changing an Isar collection, persisted field, embedded object, or schema registration, update `lib/ui/pages/settings/database_viewer_page.dart` in the same change.
- Regenerate Isar code when model changes require it.

Also keep the data model list aligned with the current codebase.

## Validation

Run `flutter analyze` after implementation. If practical, run focused tests related to database/model behavior; otherwise state that only analysis was run.

## Out of Scope

- No database editing in the viewer.
- No schema reflection or generic auto-rendering framework.
- No database migration beyond documentation unless field defaults require it.
