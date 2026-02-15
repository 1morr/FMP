# Lyrics Matching Feature - Implementation Status

## Status: Phase 1 Complete (2026-02)

### Implemented
1. **LyricsMatch Isar Model** (`lib/data/models/lyrics_match.dart`)
   - `trackUniqueKey` (unique index, replace: true) - links to Track.uniqueKey
   - `lyricsSource` ("lrclib") - future multi-source support
   - `externalId` - lrclib track ID for online fetch
   - `offsetMs` - user-adjustable offset
   - Does NOT store lyrics content (fetched online via externalId)

2. **LyricsRepository** (`lib/data/repositories/lyrics_repository.dart`)
   - `getByTrackKey()`, `save()`, `delete()`, `updateOffset()`

3. **Providers** (`lib/providers/lyrics_provider.dart`)
   - `lrclibSourceProvider` / `titleParserProvider` - singletons
   - `currentLyricsMatchProvider` - FutureProvider.autoDispose, watches currentTrack
   - `currentLyricsContentProvider` - FutureProvider.autoDispose, fetches from lrclib by ID
   - `lyricsSearchProvider` - StateNotifierProvider for search UI
   - `lyricsMatchForTrackProvider` - family provider for per-track match status

4. **LyricsSearchSheet** (`lib/ui/pages/lyrics/lyrics_search_sheet.dart`)
   - DraggableScrollableSheet with search box
   - Auto-searches using TitleParser parsed result
   - Shows synced/plain/instrumental badges, duration match color coding
   - Save/remove match with toast feedback

5. **Menu Integration** - "匹配歌词" added to:
   - explore_page.dart
   - home_page.dart
   - search_page.dart
   - playlist_detail_page.dart
   - play_history_page.dart

6. **i18n** - en, zh-CN, zh-TW lyrics namespace

### Existing (from demo phase)
- `TitleParser` (`lib/services/lyrics/title_parser.dart`) - regex-based title parsing
- `LrclibSource` (`lib/services/lyrics/lrclib_source.dart`) - lrclib.net API client

### Not Yet Implemented (Phase 2)
- Player page lyrics scrolling display
- AI title parser
- Multiple lyrics sources (Netease, QQ Music)
- Lyrics caching (currently fetches online each time)
