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

### 3. Update Memories After Significant Changes
After making architectural changes, update relevant memories:
```
mcp__plugin_serena_serena__write_memory(memory_file_name: "...", content: "...")
mcp__plugin_serena_serena__edit_memory(memory_file_name: "...", needle: "...", repl: "...", mode: "literal")
```

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
│  AudioService   │  │  QueueManager   │
│ (just_audio)    │  │ (queue logic)   │
│ Low-level play  │  │ Shuffle, loop   │
│ control         │  │ Persistence     │
└─────────────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│just_audio_media_kit│  ← Windows/Linux backend
└─────────────────┘
```

**Key Rule:** UI must call `AudioController` methods, never `AudioService` directly.

### Windows Audio Backend

Uses `just_audio_media_kit` instead of `just_audio_windows`. The latter has platform threading issues causing "Failed to post message to main thread" errors during seek operations on long videos.

Required initialization in `main.dart`:
```dart
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  // ...
}
```

### State Management: Riverpod

- `audioControllerProvider` - Main audio state (PlayerState)
- `playlistProvider` / `playlistDetailProvider` - Playlist management
- `searchProvider` - Search state
- `themeProvider` - Theme configuration

### Data Layer

- **Models:** Isar collections in `lib/data/models/` (Track, Playlist, PlayQueue, Settings)
- **Repositories:** CRUD operations in `lib/data/repositories/`
- **Sources:** Audio source parsers in `lib/data/sources/` (BilibiliSource implemented)

## Key Design Decisions

### Temporary Play Feature
When clicking a song in search/playlist pages, it plays temporarily without modifying the queue. After completion, the original queue position is restored (minus 10 seconds).

- Uses `playTemporary()` method, NOT `playTrack()`
- Saved state: `_savedQueue`, `_savedIndex`, `_savedPosition`, `_savedIsPlaying`

### Mute Toggle
Volume mute must use `controller.toggleMute()`, NOT `setVolume(0)` / `setVolume(1.0)`. The mute logic remembers the previous volume in `_volumeBeforeMute`.

### Shuffle Mode
Managed in `QueueManager` with `_shuffleOrder` list. When queue is cleared and songs added, shuffle order regenerates automatically.

### Play Lock (Race Condition Prevention)
`AudioController` uses `_playLock` and `_playRequestId` to prevent race conditions during rapid track switching.

### Progress Bar Dragging
Slider `onChanged` must NOT call `seekToProgress()` directly. Only call seek in `onChangeEnd` to avoid flooding the message queue during continuous dragging. See `player_page.dart` and `mini_player.dart` for correct implementation.

## File Structure Highlights

```
lib/
├── services/audio/
│   ├── audio_provider.dart   # AudioController + PlayerState + Providers
│   ├── audio_service.dart    # Low-level just_audio wrapper
│   └── queue_manager.dart    # Queue, shuffle, loop, persistence
├── data/
│   ├── models/               # Isar collections (*.dart + *.g.dart)
│   ├── repositories/         # Data access layer
│   └── sources/              # Audio source parsers (Bilibili)
├── ui/
│   ├── pages/                # Full pages (home, search, player, etc.)
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
