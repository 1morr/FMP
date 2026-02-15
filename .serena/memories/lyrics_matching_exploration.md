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

### Phase 2 Complete (2026-02) - Lyrics Display

7. **LRC Parser** (`lib/services/lyrics/lrc_parser.dart`)
   - `LyricsLine` - timestamp + text
   - `ParsedLyrics` - sorted lines + isSynced flag
   - `LrcParser.parse()` - parses synced LRC or plain text
   - `LrcParser.findCurrentLineIndex()` - binary search for current line by position + offset

8. **LyricsDisplay Widget** (`lib/ui/widgets/lyrics_display.dart`)
   - Shared component for player page and TrackDetailPanel
   - `compact` mode for side panel, full mode for player
   - Auto-scrolls to current line (synced lyrics)
   - User scroll detection: pauses auto-scroll for 3 seconds
   - States: loading, no match, error, instrumental, synced lyrics, plain text

9. **Player Page Integration** (`lib/ui/pages/player/player_page.dart`)
   - `_showLyrics` toggle state
   - Tap cover → switch to lyrics, tap lyrics → switch back to cover
   - `AnimatedSwitcher` for smooth transition

10. **TrackDetailPanel Integration** (`lib/ui/widgets/track_detail_panel.dart`)
    - Converted from ConsumerWidget to ConsumerStatefulWidget
    - `SegmentedButton` toggle: Info / Lyrics
    - `AnimatedSwitcher` between detail content and lyrics display

11. **Provider** (`lib/providers/lyrics_provider.dart`)
    - `parsedLyricsProvider` - caches parsed lyrics to avoid re-parsing on every position change

12. **i18n** - Added: lyrics, noLyricsAvailable, instrumentalTrack

### Not Yet Implemented (Phase 3+)
- AI title parser
- Multiple lyrics sources (Netease, QQ Music)
- Lyrics caching (currently fetches online each time)
