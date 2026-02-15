# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important: Before Modifying Code

### 1. Read Serena Memories First
Before making any code changes, use Serena to read relevant memories:
```
mcp__plugin_serena_serena__list_memories()
mcp__plugin_serena_serena__read_memory(memory_file_name: "audio_system")
mcp__plugin_serena_serena__read_memory(memory_file_name: "architecture")
```

Key memories:
- `audio_system` - Detailed audio architecture, design decisions, common mistakes to avoid
- `architecture` - Overall project architecture
- `project_overview` - Project status and features
- `code_style` - Code style conventions
- `ui_coding_patterns` - **UI 页面开发必读** - 统一编码模式、组件使用规范

### 2. Use Serena for Code Modifications
Always use Serena MCP tools for code changes:
- `mcp__plugin_serena_serena__find_symbol` - Find symbols by name
- `mcp__plugin_serena_serena__get_symbols_overview` - Get file structure
- `mcp__plugin_serena_serena__replace_symbol_body` - Replace entire symbol
- `mcp__plugin_serena_serena__replace_content` - Regex-based replacement
- `mcp__plugin_serena_serena__insert_after_symbol` / `insert_before_symbol` - Add new code

Benefits: Precise symbolic editing, better for refactoring, avoids accidental changes.

### 3. Update Documentation After Significant Changes ⚠️ IMPORTANT

**在完成重大代码修改后，必须同时更新：**
1. **本文件 (CLAUDE.md)** - 项目核心文档
2. **Serena 记忆文件** - 详细架构/实现文档

#### 需要更新 CLAUDE.md 的情况

| 修改类型 | 需要更新的章节 |
|----------|---------------|
| 音频架构变更 | "Three-Layer Audio System"、"File Structure" |
| 核心设计决策变更 | "Key Design Decisions" |
| 新增核心命令/工具 | "Common Commands" |
| 状态管理变更 | "State Management: Riverpod" |
| 数据层变更 | "Data Layer" |

#### 需要更新 Serena 记忆的情况

| 修改类型 | 需要更新的记忆 |
|----------|---------------|
| 音频系统架构变更 | `audio_system` |
| 新增/删除模块、服务 | `architecture` |
| 依赖包变更 | `project_overview` |
| 下载系统变更 | `download_system` |
| UI 页面结构变更 | `ui_pages_details` |
| 新的设计决策/经验教训 | `refactoring_lessons` |

#### 更新方法

**CLAUDE.md 更新：**
```
mcp__plugin_serena_serena__replace_content(relative_path: "CLAUDE.md", needle: "...", repl: "...", mode: "literal")
```

**Serena 记忆更新：**
```
# 小范围编辑（推荐）
mcp__plugin_serena_serena__edit_memory(memory_file_name: "...", needle: "旧内容", repl: "新内容", mode: "literal")

# 大范围重写
mcp__plugin_serena_serena__write_memory(memory_file_name: "...", content: "...")

# 删除过时记忆
mcp__plugin_serena_serena__delete_memory(memory_file_name: "...")
```

#### 检查清单

完成重大修改后，问自己：
- [ ] 是否添加/删除了依赖包？→ 更新 CLAUDE.md + `project_overview`
- [ ] 是否添加/删除了服务类？→ 更新 CLAUDE.md "File Structure" + `architecture`
- [ ] 是否修改了核心架构？→ 更新 CLAUDE.md 相关章节 + 相关记忆
- [ ] 是否有新的设计决策？→ 更新 CLAUDE.md "Key Design Decisions" + `refactoring_lessons`

## Project Overview

FMP (Flutter Music Player) is a cross-platform music player supporting Bilibili and YouTube audio sources. Target platforms: Android and Windows.

## Common Commands

```bash
# Run the app
flutter run

# Build
flutter build apk        # Android APK
flutter build windows    # Windows executable

# Code generation (required after modifying Isar models)
flutter pub run build_runner build --delete-conflicting-outputs

# Static analysis
flutter analyze

# Run tests
flutter test
flutter test test/path/to/specific_test.dart
```

## Architecture

### Three-Layer Audio System

```
UI (player_page, mini_player)
         │
         ▼
┌─────────────────────────────────────┐
│         AudioController             │  ← UI uses ONLY this
│   (audio_provider.dart)             │
│   - State management (PlayerState)  │
│   - Business logic                  │
│   - Temporary play, mute memory     │
└─────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│MediaKitAudioSvc │  │  QueueManager   │
│(media_kit direct│  │ (queue logic)   │
│ Low-level play  │  │ Shuffle, loop   │
│ control         │  │ Persistence     │
└─────────────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│   media_kit      │  ← Native httpHeaders, no proxy
└─────────────────┘
```

**Key Rule:** UI must call `AudioController` methods, never `AudioService` directly.

### Audio Backend (media_kit)

Uses `media_kit` directly (not through `just_audio`). This replaces the previous `just_audio` + `just_audio_media_kit` setup.

**Why the migration:**
- `just_audio_media_kit` created a local HTTP proxy when headers were provided
- The proxy had compatibility issues with various stream types
- Direct `media_kit` usage provides cleaner architecture and native header support

**Current architecture:**
- `media_kit` supports `httpHeaders` natively via `Media(url, httpHeaders: headers)`
- No proxy needed, cleaner code path
- **Note:** audio-only streams still fail on Windows (libmpv limitation, not proxy-related)
- YouTube playback uses muxed streams (video+audio) for reliability

Required initialization in `main.dart`:
```dart
import 'package:media_kit/media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // ...
}
```

**Custom types** (`audio_types.dart`):
- `FmpAudioProcessingState` - Replaces `just_audio.ProcessingState`
- `MediaKitPlayerState` - Synthesized from media_kit events

**Volume conversion**: media_kit uses 0-100 range, app uses 0-1 range. Conversion handled in `MediaKitAudioService`.

**YouTube Stream Format Priority**:
1. **Audio-only via androidVr client** - Preferred (lowest bandwidth, no video data)
2. **Muxed** (video+audio) - Fallback if androidVr fails
3. **HLS** (m3u8 segmented) - Last resort

**Important Discovery (2026-02)**: Only the `YoutubeApiClient.androidVr` client produces audio-only stream URLs that are HTTP accessible. Other clients (`android`, `ios`, `safari`) return HTTP 403 for audio-only streams. The androidVr client URLs contain `c=ANDROID_VR` parameter.

**Bandwidth comparison**:
- Audio-only (mp4/aac): ~128-256 kbps
- Muxed (360p video+audio): ~500-1000 kbps

### State Management: Riverpod

- `audioControllerProvider` - Main audio state (PlayerState)
- `playlistProvider` / `playlistDetailProvider` - Playlist management
- `searchProvider` - Search state
- `themeProvider` - Theme configuration
- `lyricsSearchProvider` - Multi-source lyrics search (lrclib + netease, with filter)
- `neteaseSourceProvider` - NeteaseSource singleton

#### Data Loading Pattern Selection (按数据来源选择)

| 数据来源 | 模式 | 示例 |
|----------|------|------|
| DB 集合（多处可修改） | Isar `watchAll()` + `StateNotifier` | 歌单列表、电台、播放历史 |
| DB 联合查询 | `StateNotifier` + 乐观更新 | 歌单详情 |
| 文件系统扫描 | `FutureProvider` + `invalidate` | 已下载页面 |
| API + 缓存 | `CacheService` + `StreamProvider` | 首页/探索页排行榜 |
| 设置项 | `StateNotifier` + 直接更新 state | 设置页面 |

**关键规则：**
- 使用 `isLoading` 的页面必须加守卫：`isLoading && data.isEmpty`
- FutureProvider 操作后必须 `invalidate`，否则 UI 不更新
- 乐观更新失败时必须回滚（`await loadXxx()`）
- 列表/网格项加 `ValueKey(item.id)`

详见 `ui_coding_patterns` 记忆第 3 节。

### Data Layer

- **Models:** Isar collections in `lib/data/models/` (Track, Playlist, PlayQueue, Settings)
- **Repositories:** CRUD operations in `lib/data/repositories/`
- **Sources:** Audio source parsers in `lib/data/sources/` (BilibiliSource, YouTubeSource implemented)

## Key Design Decisions

### Temporary Play Feature
When clicking a song in search/playlist pages, it plays temporarily without modifying the queue. After completion, the original queue position is restored (minus 10 seconds).

- Uses `playTemporary()` method, NOT `playTrack()`
- Saved state is stored in `_context` with `savedQueueIndex`, `savedPosition`, `savedWasPlaying` (does NOT save queue content)
- Uses `_executePlayRequest()` with `mode: PlayMode.temporary`
- On restore: Uses current queue directly, user's queue modifications during temporary play are preserved
- Index is clamped to valid range if queue was modified
- **Position restore controlled by `rememberPlaybackPosition` setting** - if disabled, returns to queue track but starts from beginning
- **Important**: All async methods use unified `_enterLoadingState()` / `_exitLoadingState()` helpers

### Mute Toggle
Volume mute must use `controller.toggleMute()`, NOT `setVolume(0)` / `setVolume(1.0)`. The mute logic remembers the previous volume in `_volumeBeforeMute`.

### Remember Playback Position
Unified playback position persistence controlled by `Settings.rememberPlaybackPosition` (default `true`).

**Position saving** (always active regardless of setting):
- `QueueManager` saves `currentIndex` and `lastPositionMs` to `PlayQueue` model every 10 seconds (`AppConstants.positionSaveInterval`)
- `seekTo()`, `seekForward()`, `seekBackward()` call `savePositionNow()` immediately

**Position restoring** (controlled by `rememberPlaybackPosition` setting):
- **App restart**: `QueueManager.initialize()` restores `_currentPosition` from `PlayQueue.lastPositionMs`; if disabled, starts from `Duration.zero`
- **Temporary play restore**: `_restoreSavedState()` checks `_queueManager.shouldRememberPosition`; if disabled, returns to queue track but starts from beginning instead of saved position
- **UI**: Settings page toggle "记住播放位置" with subtitle "应用重启后从上次位置继续播放" (`lib/ui/pages/settings/settings_page.dart`)

### Shuffle Mode
Managed in `QueueManager` with `_shuffleOrder` list. When queue is cleared and songs added, shuffle order regenerates automatically.

### Mix Playlist Mode (YouTube Mix/Radio)
YouTube Mix/Radio playlists (ID starts with "RD") are dynamic infinite playlists. They are imported as "references" (no tracks saved), and tracks are fetched from InnerTube API at runtime.

**Key behaviors:**
- Shuffle disabled (button greyed out with tooltip)
- addToQueue/addNext blocked (returns false, shows toast)
- Auto-loads more tracks when approaching queue end
- State persisted across app restart via `PlayQueue` model fields (`isMixMode`, `mixPlaylistId`, `mixSeedVideoId`, `mixTitle`)

**UI changes:**
- Queue page title: "Mix · {playlist name}" (60% max width, truncated)
- Playlist detail page: PopupMenuButton hidden for Mix tracks (no download/add options)
- Player page: shuffle button disabled

**Implementation files:**
- `lib/data/sources/youtube_source.dart` - `getMixPlaylistInfo()`, `fetchMixTracks()`
- `lib/services/audio/audio_provider.dart` - `playMixPlaylist()`, `_MixPlaylistState`, `PlayMode.mix`
- `lib/services/audio/queue_manager.dart` - `setMixMode()`, `clearMixMode()`, Mix state persistence

See `mix_playlist_design` memory for full implementation details.

### PlaybackContext and Play Lock (Race Condition Prevention)
`AudioController` uses a unified `_PlaybackContext` class to manage playback state and prevent race conditions during rapid track switching.

**New Architecture (2026-01 Refactoring):**
```dart
/// 播放模式枚举
enum PlayMode {
  queue,      // 正常隊列播放
  temporary,  // 臨時播放（播放完成後恢復）
  detached,   // 脫離隊列（隊列被清空後的狀態）
}

/// 統一的內部播放上下文
class _PlaybackContext {
  final PlayMode mode;
  final int activeRequestId;  // > 0 表示正在加載
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;
  
  bool get isTemporary => mode == PlayMode.temporary;
  bool get isInLoadingState => activeRequestId > 0;
  bool get hasSavedState => savedQueueIndex != null;
}
```

**Key methods:**
- `_executePlayRequest()` - unified play entry point for all playback
- `_enterLoadingState()` / `_exitLoadingState()` - manage loading UI
- `_isPlayingOutOfQueue` getter - detect when playing outside queue
- `_returnToQueue()` - unified logic to return to queue

**Important: Methods with independent URL fetching must use `_playRequestId`:**

Any method that fetches URLs outside of `_executePlayRequest()` (e.g., `_restoreSavedState()`) must:
1. Increment `_playRequestId` at the start to cancel in-flight requests
2. Check `_isSuperseded(requestId)` after each `await`
3. Abort immediately if superseded

This prevents race conditions like: temporary play loading → user clicks next → restore starts → temporary play finishes and overwrites restore.

**Player state listeners use `_context.isInLoadingState`:**
```dart
void _onPlayerStateChanged(just_audio.PlayerState playerState) {
  state = state.copyWith(
    isLoading: _context.isInLoadingState || 
               playerState.processingState == ProcessingState.loading,
  );
}

void _onPositionChanged(Duration position) {
  if (_context.isInLoadingState) return;
  state = state.copyWith(position: position);
}
```

**AudioService also waits for player idle state:**
```dart
await _player.stop();

// Wait for idle state before setting new audio source
// This prevents "Player already exists" errors with just_audio_media_kit
if (_player.processingState != ProcessingState.idle) {
  await _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.idle)
      .first
      .timeout(const Duration(milliseconds: 500));
}

await _player.setAudioSource(audioSource);
```

### Progress Bar Dragging
Slider `onChanged` must NOT call `seekToProgress()` directly. Only call seek in `onChangeEnd` to avoid flooding the message queue during continuous dragging. See `player_page.dart` and `mini_player.dart` for correct implementation.

### Download System Simplification (2026-02)
- **Path deduplication by `savePath`** (not trackId) - same track can download to multiple playlists
- **File verification before saving path** - verify file exists after download completes
- **Smart path clearing** - only clear non-existing paths when playing, not proactively
- **Sync replaces paths** - local files are authority, sync REPLACES all DB paths
- **Provider debouncing** - completion events use 300ms debouncing for bulk operations
- **Playlist-specific download marks** - UI shows download status per playlist
- **Isolate download (Windows)** - network I/O runs in separate Isolate to avoid PostMessage queue overflow
- **In-memory progress state** - progress updates stored in memory only, not written to DB (avoids Isar watch triggers)

### Playlist Rename - No Auto File Migration
When renaming a playlist that has downloaded songs, files are **NOT** automatically moved. Instead:
- `PlaylistService.updatePlaylist()` returns `PlaylistUpdateResult` with old/new folder paths
- UI shows a dialog prompting user to manually move the folder
- This avoids potential data loss from failed file operations
- Note: Precomputed paths are no longer used - download paths are saved when downloads complete

### Android Storage Permission (MANAGE_EXTERNAL_STORAGE)
Android 10+ 引入分区存储，传统的 `WRITE_EXTERNAL_STORAGE` 不再有效。使用 `MANAGE_EXTERNAL_STORAGE` 权限访问外部存储。

- `StoragePermissionService` 处理权限请求逻辑
- `DownloadPathManager.selectDirectory()` 在 Android 上先请求权限再选择目录
- 权限请求显示解释对话框，引导用户到系统设置页面授权
- Google Play 上架需要提交权限使用说明

### Home Page Ranking Cache (Proactive Background Refresh)
Home page ranking data (Bilibili/YouTube) is cached and refreshed in the background every hour.

- `RankingCacheService` initialized in `main.dart` at app startup
- Data fetched immediately on startup, then refreshed every hour via `Timer.periodic`
- UI always displays cached data instantly (no loading after first launch)
- Uses `StreamProvider` to notify UI when cache updates
- YouTube uses "New This Week" playlist from YouTube Music channel (InnerTube Browse API), falls back to search if unavailable

### Audio Quality Settings (2026-02)
User-configurable audio quality settings for different sources.

**Settings Model** (`lib/data/models/settings.dart`):
- `AudioQualityLevel` enum: high, medium, low (global, applies to all sources)
- `AudioFormat` enum: opus, aac (YouTube only - Bilibili only has AAC)
- `StreamType` enum: audioOnly, muxed, hls

**Provider** (`lib/providers/audio_settings_provider.dart`):
- `audioSettingsProvider` - StateNotifierProvider for audio quality settings
- `lyricsSearchProvider` - StateNotifierProvider for lyrics search
- `currentLyricsMatchProvider` / `currentLyricsContentProvider` - Current track lyrics
- Settings persisted via Isar Settings model

**UI** (`lib/ui/pages/settings/audio_settings_page.dart`):
- "全局音质等级" - Quality level selection (high/medium/low), applies to all sources
- "YouTube 格式优先级" - Format priority (Opus/AAC), only affects YouTube
- "YouTube 流优先级" - Stream type priority (audioOnly/muxed/hls)
- "Bilibili 流优先级" - Stream type priority (audioOnly/muxed)

**Source Integration**:
- `AudioStreamConfig` passed to source `getAudioUrl()` methods
- `AudioStreamResult` returned with bitrate, container, codec, streamType info
- `QueueManager` reads settings and builds config for sources

**PlayerState Display**:
- `currentBitrate`, `currentContainer`, `currentCodec`, `currentStreamType` fields
- Displayed in player info dialog and track detail panel

**Key Limitations**:
- Bilibili only supports AAC format, format priority has no effect
- Bilibili live streams are always muxed (video+audio), no audio-only option

### AppBar Actions Trailing Spacing
All page-level `AppBar` actions lists must end with `const SizedBox(width: 8)` to maintain consistent spacing between the last action button and the screen edge. This applies when the last action is an `IconButton`. Pages where the last action is a `PopupMenuButton` do not need the extra spacing since `PopupMenuButton` has built-in padding.

```dart
// ✅ Correct
appBar: AppBar(
  actions: [
    IconButton(...),
    IconButton(...),
    const SizedBox(width: 8), // trailing spacing
  ],
),

// ❌ Wrong - no trailing spacing
appBar: AppBar(
  actions: [
    IconButton(...),
    IconButton(...),
  ],
),

// ❌ Wrong - using Padding wrapper instead
appBar: AppBar(
  actions: [
    Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(...),
    ),
  ],
),
```

### ListTile Performance in Lists
**Avoid putting `Row` inside `ListTile.leading`** - this causes layout jitter during scrolling.

Use flat custom layout instead:
```dart
// ✓ Correct - flat layout
InkWell(
  onTap: () => ...,
  child: Padding(
    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(children: [/* rank, thumbnail, info, menu */]),
  ),
)

// ✗ Wrong - causes layout issues
ListTile(
  leading: Row(children: [/* rank, thumbnail */]),  // Performance problem!
  ...
)
```

### UI Constants System (2026-02)
All UI magic numbers are centralized in `lib/core/constants/ui_constants.dart`.

| 常量類 | 用途 | 示例 |
|--------|------|------|
| `AppRadius` | 圓角值 + 預構建 BorderRadius | `AppRadius.borderRadiusLg` → 12dp |
| `AnimationDurations` | 動畫時長 | `AnimationDurations.normal` → 300ms |
| `AppSizes` | UI 尺寸 (按鈕、列表項高度、縮略圖、卡片比例等) | `AppSizes.thumbnailMedium` → 48.0 |
| `ToastDurations` | Toast 顯示時長 | `ToastDurations.short` → 1500ms |
| `DebounceDurations` | 防抖時長 | `DebounceDurations.standard` → 300ms |

**注意**: `AppRadius.borderRadiusXl` 等是 `static final`（非 `const`），不能用在 `const` 上下文中。

### Image Thumbnail Optimization (2026-02)
Network images are automatically optimized to reduce memory and bandwidth usage.

**ThumbnailUrlUtils** (`lib/core/utils/thumbnail_url_utils.dart`):
- Converts high-res image URLs to appropriately-sized thumbnails
- Bilibili: adds `@{size}w.jpg` suffix (200/400/640/1280)
- YouTube: selects quality tier (default/mq/hq/sd/maxres) + webp format
- Reduces download size from ~700 KB to ~20 KB for thumbnails

**ImageLoadingService integration**:
- Automatically calls `ThumbnailUrlUtils.getOptimizedUrl()` based on display size
- Also sets `memCacheWidth`/`memCacheHeight` as fallback for unsupported URLs
- Decoded bitmap memory reduced from ~8 MB (1920×1080) to ~160 KB (200×200)

See `image_handling` memory for full implementation details.

## UI Page Development Guidelines

### 4. Ensure Code Consistency Across Pages ⚠️ CRITICAL

在创建新页面或修改现有页面前，**必须**阅读 `ui_coding_patterns` 记忆：

```
mcp__plugin_serena_serena__read_memory(memory_file_name: "ui_coding_patterns")
```

#### 核心原则

1. **使用统一组件**：
   - 歌曲封面 → `TrackThumbnail` / `TrackCover`
   - 头像 → `ImageLoadingService.loadAvatar()`
   - 其他图片 → `ImageLoadingService.loadImage()`
   - **禁止**直接使用 `Image.network()` 或 `Image.file()`

2. **FileExistsCache 模式**：
   ```dart
   ref.watch(fileExistsCacheProvider);  // 监听变化
   final cache = ref.read(fileExistsCacheProvider.notifier);  // 读取
   final localPath = track.getLocalCoverPath(cache);  // 使用
   ```

3. **播放状态判断**（统一逻辑）：
   ```dart
   final currentTrack = ref.watch(currentTrackProvider);
   final isPlaying = currentTrack != null &&
       currentTrack.sourceId == track.sourceId &&
       currentTrack.pageNum == track.pageNum;
   ```

4. **菜单操作**：参考 `ExplorePage` 或 `HomePage` 中的 `_handleMenuAction` 实现

5. **刷新模式**：使用 `RefreshIndicator` + `ref.invalidate()` 或 cache service

#### 相似页面对照

| 新建/修改页面 | 应参考的页面 | 统一点 |
|--------------|-------------|--------|
| 任何带歌曲列表的页面 | `ExplorePage` | TrackTile 样式、菜单 |
| 带分组的歌曲列表 | `PlaylistDetailPage` | 多P分组逻辑 |
| 网格卡片页面 | `LibraryPage` / `DownloadedPage` | 卡片样式、长按菜单 |

#### 检查清单

创建或修改页面时，确认：
- [ ] 图片加载使用统一组件
- [ ] FileExistsCache 正确使用（watch + read）
- [ ] 播放状态判断逻辑统一
- [ ] 菜单操作与其他页面一致
- [ ] 错误/空状态处理符合规范
- [ ] AppBar actions 尾部间距：IconButton 结尾加 `SizedBox(width: 8)`

## File Structure Highlights

```
lib/
├── services/
│   ├── audio/
│   │   ├── audio_provider.dart          # AudioController + PlayerState + Providers
│   │   ├── media_kit_audio_service.dart # Low-level media_kit wrapper
│   │   ├── audio_types.dart             # FmpAudioProcessingState, MediaKitPlayerState
│   │   ├── audio_handler.dart           # FmpAudioHandler (Android notification via audio_service)
│   │   └── queue_manager.dart           # Queue, shuffle, loop, persistence
│   ├── cache/
│   │   └── ranking_cache_service.dart  # 首頁排行榜緩存（主動後台刷新）
│   ├── lyrics/
│   │   ├── lrclib_source.dart          # lrclib.net API 客戶端
│   │   ├── netease_source.dart         # 網易雲音樂歌詞源（搜索+歌詞獲取）
│   │   ├── lyrics_result.dart          # 統一歌詞結果類型（LyricsResult）
│   │   ├── lyrics_auto_match_service.dart # 自動匹配（網易雲優先 → lrclib fallback）
│   │   ├── lyrics_cache_service.dart   # 歌詞緩存（LRU，支持多源）
│   │   ├── lrc_parser.dart             # LRC 格式解析
│   │   └── title_parser.dart           # 標題解析（提取歌名/歌手）
│   ├── download/
│   │   ├── download_service.dart       # 下載任務調度
│   │   ├── download_path_manager.dart  # 下載路徑選擇和管理
│   │   └── download_path_utils.dart    # 路徑計算工具
│   ├── import/
│   │   ├── import_service.dart         # URL 導入服務
│   │   └── playlist_import_service.dart # 外部歌單導入服務（匹配搜索）
│   ├── radio/
│   │   ├── radio_controller.dart       # 直播/電台控制
│   │   ├── radio_refresh_service.dart  # 直播流刷新
│   │   └── radio_source.dart           # 直播源解析
│   ├── update/
│   │   └── update_service.dart         # 應用內更新（GitHub Releases）
│   └── storage_permission_service.dart # Android 存儲權限請求（MANAGE_EXTERNAL_STORAGE）
├── data/
│   ├── models/               # Isar collections (*.dart + *.g.dart)
│   │   └── lyrics_match.dart          # 歌词匹配记录（Track↔lrclib/netease）
│   ├── repositories/         # Data access layer
│   │   └── lyrics_repository.dart     # 歌词匹配 CRUD
│   └── sources/              # Audio source parsers
│       ├── bilibili_source.dart        # Bilibili 音源
│       ├── youtube_source.dart         # YouTube 音源
│       └── playlist_import/            # 外部歌單導入源
│           ├── netease_playlist_source.dart   # 網易雲音樂
│           ├── qq_music_playlist_source.dart  # QQ音樂
│           └── spotify_playlist_source.dart   # Spotify
├── core/
│   ├── constants/
│   │   ├── app_constants.dart         # 應用級常量（超時、重試、緩存策略等）
│   │   └── ui_constants.dart          # UI 常量（間距、圓角、動畫時長、尺寸等）
│   ├── utils/                         # 工具類
│   └── services/                      # 核心服務（Toast、圖片加載等）
├── ui/
│   ├── pages/                # Full pages
│   │   ├── home/             # 首頁（快捷操作、最近熱門預覽）
│   │   ├── explore/          # 探索頁（完整排行榜）
│   │   ├── search/           # 搜索頁
│   │   ├── player/           # 全屏播放器
│   │   ├── queue/            # 播放隊列
│   │   ├── history/          # 播放歷史
│   │   ├── library/          # 音樂庫、歌單詳情、已下載、導入預覽
│   │   ├── live_room/        # 直播間
│   │   │   ├── lyrics/            # 歌詞匹配搜索（多源篩選：全部/網易雲/lrclib）
│   ├── radio/            # 電台頁面
│   │   ├── download/         # 下載相關
│   │   └── settings/         # 設置、下載管理、音頻設置
│   ├── widgets/              # Shared widgets
│   └── layouts/              # Responsive layouts
└── providers/                # Riverpod providers
```

## Bilibili API Notes

- Audio requires `Referer: https://www.bilibili.com` header
- Audio URLs expire and need periodic refresh via `ensureAudioUrl()`
- Track availability checked via `isUnavailable` / `isGeoRestricted`

## Responsive Breakpoints

- Mobile: < 600dp (bottom navigation)
- Tablet: 600-1200dp (side navigation)
- Desktop: > 1200dp (three-column layout)
