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

### Phase 3 Complete (2026-02) - Multi-Source Lyrics + Cache

13. **LyricsResult** (`lib/services/lyrics/lyrics_result.dart`)
    - 统一歌词结果类型，从 `lrclib_source.dart` 抽出为独立文件
    - 新增 `source` 字段（"lrclib" / "netease"）
    - 新增 `translatedLyrics`（翻译歌词）、`romajiLyrics`（罗马音歌词）字段
    - `fromJson` 兼容旧缓存（缺失字段默认 null）

14. **NeteaseSource 歌词搜索** (`lib/services/lyrics/netease_source.dart`)
    - `searchLyrics()` - 搜索歌曲 → 批量获取歌词 → 转换为 `LyricsResult` 列表
    - `getLyricsResult(int songId)` - 通过 songId 获取歌词，返回 `LyricsResult`
    - 内部 `_toLyricsResult()` 将 NeteaseSong + NeteaseLyrics 转换为统一类型

15. **LyricsCacheService 多源支持** (`lib/services/lyrics/lyrics_cache_service.dart`)
    - `put()` 序列化新增 `source`、`translatedLyrics`、`romajiLyrics` 字段
    - `get()` 反序列化兼容旧缓存

16. **多源搜索 Provider** (`lib/providers/lyrics_provider.dart`)
    - `neteaseSourceProvider` - NeteaseSource 单例
    - `LyricsSourceFilter` 枚举：`all`, `netease`, `lrclib`
    - `LyricsSearchState` 新增 `filter` 字段
    - `LyricsSearchNotifier` 支持 `setFilter()` + 按 filter 搜索
    - `filter == all` 时并行搜索两个源，网易云结果在前
    - `saveMatch()` 根据 `result.source` 设置 `lyricsSource`
    - `currentLyricsContentProvider` 根据 `lyricsSource` 从对应 API 获取歌词

17. **自动匹配优先级** (`lib/services/lyrics/lyrics_auto_match_service.dart`)
    - 构造函数新增 `NeteaseSource` 参数
    - `tryAutoMatch()` 先尝试网易云 → 有同步歌词且时长匹配则使用 → 否则 fallback 到 lrclib
    - `_tryNeteaseMatch()` 内部方法处理网易云匹配逻辑

18. **搜索弹窗筛选 UI** (`lib/ui/pages/lyrics/lyrics_search_sheet.dart`)
    - `SegmentedButton<LyricsSourceFilter>` 三选项：全部 / 网易云 / lrclib
    - 切换筛选后自动重新搜索
    - 结果项显示来源标签（网易云 / lrclib）
    - 网易云结果额外显示"翻译"/"罗马音"标签

19. **i18n** - 新增：sourceAll, sourceLrclib, sourceNetease, translated, romaji

### Phase 4 Complete (2026-02) - QQ Music Lyrics Source

20. **QQMusicSource** (`lib/services/lyrics/qqmusic_source.dart`)
    - `QQMusicSong` - songmid, songname, singers, albumName, interval(秒)
    - `QQMusicLyrics` - songmid, lyric(LRC), trans(翻译LRC)
    - `QQMusicException` - statusCode, message
    - `QQMusicSource` - 主类，with Logging
    - `searchSongs()` - 搜索歌曲
    - `getLyrics()` - 获取歌词（nobase64 优先，base64 fallback）
    - `searchLyrics()` - 搜索并返回 `List<LyricsResult>` (source: `'qqmusic'`)
    - `getLyricsResult(String songmid)` - 通过 songmid 获取歌词
    - HTML 实体解码（`&#58;` `&#32;` 等）

21. **externalId 统一为 String** (`lib/data/models/lyrics_match.dart`, `lib/services/lyrics/lyrics_result.dart`)
    - `LyricsMatch.externalId` 从 `int` 改为 `String`
    - `LyricsResult.id` 从 `int` 改为 `String`
    - lrclib/netease 使用数字字符串（如 `"12345"`），QQ 音乐使用 songmid（如 `"0039MnYb0qxYhV"`）
    - 删除了 `externalStringId` 字段，模型更简洁
    - `LrclibSource.getById()` 和 `NeteaseSource.getLyricsResult()` 参数改为 String
    - `LyricsResult.fromJson()` 兼容旧缓存（id 可能是 int 或 String）
    - **注意：Isar schema 变更，旧的 LyricsMatch 数据不兼容**

22. **多源搜索扩展** (`lib/providers/lyrics_provider.dart`)
    - `qqmusicSourceProvider` - QQMusicSource 单例
    - `LyricsSourceFilter` 枚举新增 `qqmusic`
    - `LyricsSearchNotifier` 支持 QQ 音乐搜索
    - `filter == all` 时并行搜索三个源：网易云 → QQ音乐 → lrclib
    - `currentLyricsContentProvider` 根据 `lyricsSource` 分发到对应源

24. **自动匹配优先级** (`lib/services/lyrics/lyrics_auto_match_service.dart`)
    - 构造函数新增 `QQMusicSource` 参数
    - `tryAutoMatch()` 流程：原平台ID直取 → 网易云搜索 → QQ音乐搜索 → lrclib
    - `_tryDirectFetch(String songId, String source)` - 通过原平台ID直接获取歌词（网易云/QQ音乐），跳过搜索步骤
    - `_tryQQMusicMatch()` 内部方法处理 QQ 音乐匹配逻辑
    - 直接获取依赖 `Track.originalSongId` 和 `Track.originalSource`（导入歌单时保存）

25. **搜索弹窗 UI** (`lib/ui/pages/lyrics/lyrics_search_sheet.dart`)
    - `SegmentedButton` 四选项：全部 / 网易云 / QQ音乐 / lrclib
    - QQ 音乐来源标签使用 `colorScheme.tertiary` 颜色

26. **i18n** - 新增：sourceQQMusic (en: "QQ Music", zh-CN: "QQ音乐", zh-TW: "QQ音樂")

### Phase 5 Complete (2026-02) - Original Platform ID Direct Fetch

27. **ImportedTrack 原平台ID** (`lib/data/sources/playlist_import/playlist_import_source.dart`)
    - `sourceId` - 原平台歌曲 ID（网易云: song ID, QQ音乐: songmid, Spotify: track ID）
    - `source` - 来源平台（`PlaylistSource` 枚举）

28. **导入源提取ID**
    - `NeteasePlaylistSource._fetchTrackDetails()` - 从 `song['id']` 提取
    - `QQMusicPlaylistSource._fetchPlaylistPage()` - 从 `song['mid']` 提取
    - `SpotifyPlaylistSource._parsePlaylistData()` - 从 `item['uid']` 或 `item['id']` 提取

29. **Track 模型新增字段** (`lib/data/models/track.dart`)
    - `originalSongId` (String?) - 原平台歌曲 ID
    - `originalSource` (String?) - 来源标识（"netease" / "qqmusic" / "spotify"）
    - Isar nullable 字段，兼容旧数据

30. **selectedTracks getter 复制ID**
    - `PlaylistImportState.selectedTracks` (`lib/providers/playlist_import_provider.dart`)
    - `PlaylistImportResult.selectedTracks` (`lib/services/import/playlist_import_service.dart`)
    - 从 `ImportedTrack.sourceId/source` 复制到 `Track.originalSongId/originalSource`
    - `PlaylistSource` → String 映射：netease→"netease", qqMusic→"qqmusic", spotify→"spotify"

31. **歌词直接获取** (`lib/services/lyrics/lyrics_auto_match_service.dart`)
    - `_tryDirectFetch(String songId, String source)` - 新增方法
    - 网易云: `_netease.getLyricsResult(songId)`
    - QQ音乐: `_qqmusic.getLyricsResult(songId)`
    - Spotify: 不支持（返回 null，fallback 到搜索）
    - 只返回有同步歌词的结果
    - 在 `tryAutoMatch()` 中位于已有匹配检查之后、搜索之前

### Not Yet Implemented (Phase 6+)
- AI title parser
- Lyrics offset per-source persistence
