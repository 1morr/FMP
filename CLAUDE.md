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
1. **Muxed** (video+audio) - Required on Windows (libmpv can't open audio-only streams)
2. **HLS** (m3u8 segmented) - Fallback

Note: Audio-only streams (webm/opus, mp4/aac) fail with "Failed to open" error on Windows regardless of how headers are passed. This is a libmpv/media_kit limitation.

### State Management: Riverpod

- `audioControllerProvider` - Main audio state (PlayerState)
- `playlistProvider` / `playlistDetailProvider` - Playlist management
- `searchProvider` - Search state
- `themeProvider` - Theme configuration

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
- **Important**: All async methods use unified `_enterLoadingState()` / `_exitLoadingState()` helpers

### Mute Toggle
Volume mute must use `controller.toggleMute()`, NOT `setVolume(0)` / `setVolume(1.0)`. The mute logic remembers the previous volume in `_volumeBeforeMute`.

### Remember Playback Position
For long videos (>10 min) with progress >5%, the playback position is automatically saved. When replaying, it resumes from the saved position.

- Stored in `Track.rememberedPositionMs` via Isar
- Uses `rememberPlaybackPosition()`, `getRememberedPosition()`, `clearRememberedPosition()` in QueueManager
- Automatically restored in `_playTrack()`

### Shuffle Mode
Managed in `QueueManager` with `_shuffleOrder` list. When queue is cleared and songs added, shuffle order regenerates automatically.

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
- YouTube uses search API with `UploadDateFilter.lastMonth` (InnerTube API unstable), sorted by viewCount locally

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
│       └── ranking_cache_service.dart  # 首頁排行榜緩存（主動後台刷新）
│   ├── download/
│   │   ├── download_service.dart       # 下載任務調度
│   │   ├── download_path_manager.dart  # 下載路徑選擇和管理
│   │   └── download_path_utils.dart    # 路徑計算工具
│   └── storage_permission_service.dart # Android 存儲權限請求（MANAGE_EXTERNAL_STORAGE）
├── data/
│   ├── models/               # Isar collections (*.dart + *.g.dart)
│   ├── repositories/         # Data access layer
│   └── sources/              # Audio source parsers (Bilibili, YouTube)
├── ui/
│   ├── pages/                # Full pages
│   │   ├── home/             # 首頁（快捷操作、最近熱門預覽）
│   │   ├── explore/          # 探索頁（完整排行榜）
│   │   ├── search/           # 搜索頁
│   │   ├── player/           # 全屏播放器
│   │   ├── queue/            # 播放隊列
│   │   ├── library/          # 音樂庫、歌單詳情、已下載
│   │   └── settings/         # 設置、下載管理
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
