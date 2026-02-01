# YouTube Mix 播放列表功能設計

## 概述

YouTube Mix/Radio 播放列表（ID 以 "RD" 開頭）是動態生成的無限播放列表，無法使用官方 API 或 youtube_explode_dart 獲取。本設計使用 InnerTube `/next` API 實現導入和播放。

## 核心設計決策

### 1. Mix 是「動態引用」而非「靜態快照」
- 導入時只保存 URL/playlist ID，不保存 tracks
- 每次進入歌單頁時從 InnerTube API 實時獲取
- 播放時自動加載更多（無限滾動）

### 2. 重用現有 QueueManager
- Mix tracks 加載後放入現有 QueueManager
- 附加輕量的 `_MixPlaylistState` 追蹤 Mix 狀態
- 只需攔截特定操作（addToQueue、shuffle 等）

### 3. InnerTube 分頁機制
YouTube Mix 沒有傳統 continuation token，使用「當前視頻重新生成」模式：
- 初次請求：用 seedVideoId + playlistId
- 加載更多：用最後一首的 videoId + playlistId
- 每次返回 25 首，約 13 首重疊，12 首新增
- 需要客戶端去重

## 數據模型

### Playlist 新增欄位
```dart
bool isMix = false;           // 是否為 Mix 播放列表
String? mixPlaylistId;        // RDxxxxxx
String? mixSeedVideoId;       // 種子視頻 ID
```

### PlayerState 新增欄位
```dart
bool isMixMode = false;       // 當前是否處於 Mix 播放模式
String? mixTitle;             // Mix 歌單名稱（隊列頁顯示）
```

### PlayMode 新增值
```dart
enum PlayMode {
  queue,
  temporary,
  detached,
  mix,  // 新增
}
```

### _MixPlaylistState（AudioController 內部）
```dart
class _MixPlaylistState {
  final String playlistId;
  final String seedVideoId;
  final String title;
  final Set<String> seenVideoIds;  // 去重用
  bool isLoadingMore;
}
```

## 關鍵行為

### 導入 Mix 歌單
1. 檢測 URL 是否為 Mix（list= 參數以 RD 開頭）
2. 調用 InnerTube 獲取標題和封面
3. 創建 Playlist，設置 isMix=true，trackIds 為空
4. 不保存任何 Track

### 進入 Mix 歌單詳情頁
1. 檢測 playlist.isMix
2. 調用 InnerTube API 獲取當前 25 首 tracks
3. 顯示 track 列表（非從 DB 加載）
4. 不顯示下載選項

### 播放 Mix 歌單
1. 調用 `playMixPlaylist(playlist)`
2. 清空現有隊列，設置 PlayMode.mix
3. 加載初始 tracks 到 QueueManager
4. 初始化 `_mixState`
5. 開始播放第一首

### 播放過程中
- 禁止 shuffle（忽略或 Toast 提示）
- 禁止 addToQueue/addNext（Toast：「Mix 模式下無法添加歌曲，請先清空隊列」）
- 臨時播放不受影響
- 播放到最後一首時自動調用 `_loadMoreMixTracks()`

### 退出 Mix 模式
- 調用 `clearQueue()` 時清除 `_mixState`
- 播放其他歌單時自動退出

## UI 變更

### 隊列頁
- 標題：Mix 模式顯示 "Mix - {歌單名稱}"
- 隱藏 shuffle 按鈕

### 歌單詳情頁
- Mix 歌單：從 InnerTube 加載而非 DB
- 「播放全部」調用 `playMixPlaylist()` 而非 `addAllToQueue()`
- 不顯示下載按鈕
- 「加到其他歌單」可用（此時保存為普通 Track）

### 歌單列表
- Mix 歌單顯示特殊圖標（如 radio 圖標）

## InnerTube API 詳情

### Endpoint
```
POST https://www.youtube.com/youtubei/v1/next?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8
```

### Request Body
```json
{
  "videoId": "currentVideoId",
  "playlistId": "RDxxxxxx",
  "context": {
    "client": {
      "clientName": "WEB",
      "clientVersion": "2.20260128.05.00",
      "hl": "zh-TW",
      "gl": "TW"
    }
  }
}
```

### Response Path
```
contents.twoColumnWatchNextResults.playlist.playlist
  .title        → 歌單標題
  .contents[]   → 25 首 tracks
    .playlistPanelVideoRenderer
      .videoId
      .title.simpleText 或 .title.runs[0].text
      .shortBylineText.runs[0].text  → artist
      .lengthText.simpleText         → "4:38" 格式
      .thumbnail.thumbnails[-1].url
```

## 文件變更清單

| 文件 | 變更 |
|------|------|
| `lib/data/models/playlist.dart` | +3 欄位 |
| `lib/data/models/playlist.g.dart` | 重新生成 |
| `lib/data/sources/youtube_source.dart` | +getMixPlaylistInfo, +fetchMixTracks |
| `lib/services/audio/audio_provider.dart` | +PlayMode.mix, +_MixPlaylistState, +playMixPlaylist, 修改多個方法 |
| `lib/services/import/import_service.dart` | Mix 導入分支 |
| `lib/ui/pages/queue/queue_page.dart` | Mix 標題 + 隱藏 shuffle |
| `lib/ui/pages/library/playlist_detail_page.dart` | Mix 歌單加載邏輯 |

## 實現順序

1. Phase 1: 數據模型變更（Playlist + build_runner）✅ COMPLETED
2. Phase 2: YouTubeSource 增強（API 方法）✅ COMPLETED
3. Phase 3: AudioController Mix 模式（核心邏輯）✅ COMPLETED
4. Phase 4: Import Service（Mix 導入）✅ COMPLETED
5. Phase 5: UI 變更（隊列頁 + 歌單詳情頁）✅ COMPLETED

## 實現進度詳情

### Phase 1: Playlist Model ✅
- Added `isMix`, `mixPlaylistId`, `mixSeedVideoId` fields
- Regenerated Isar code

### Phase 2: YouTubeSource API ✅
- Added `MixPlaylistInfo` and `MixFetchResult` data classes
- Added static helpers: `isMixPlaylistId()`, `isMixPlaylistUrl()`, `extractMixInfo()`
- Added instance methods: `getMixPlaylistInfo()`, `fetchMixTracks()`

### Phase 3: AudioController ✅
- Added `PlayMode.mix` to enum
- Added `isMix` getter to `_PlaybackContext`
- Added `_MixPlaylistState` class (playlistId, seedVideoId, title, seenVideoIds, isLoadingMore)
- Added `isMixMode` and `mixTitle` to `PlayerState`
- Added `_mixState` field to `AudioController`
- Added methods: `playMixPlaylist()`, `_exitMixMode()`, `_loadMoreMixTracks()`
- Modified queue methods: `addToQueue()`, `addAllToQueue()`, `addNext()`, `shuffleQueue()`, `toggleShuffle()` - blocked with Toast
- Modified `clearQueue()` to exit Mix mode
- Modified `next()` and `_onTrackCompleted()` for auto-load at last track

### Phase 4: Import Service ✅
- Added import for `YouTubeSource`
- Modified `importFromUrl()` to detect Mix URLs using `YouTubeSource.isMixPlaylistUrl()`
- Added `_importMixPlaylist()` method: saves only metadata, no tracks
- Modified `refreshPlaylist()` to skip Mix playlists

### Phase 5: UI Changes ✅
- **`lib/providers/playlist_provider.dart`**:
  - Added `_loadMixTracks()` method to `PlaylistDetailNotifier`
  - `loadPlaylist()` detects Mix playlists and fetches tracks from InnerTube instead of DB
- **`lib/ui/pages/library/playlist_detail_page.dart`**:
  - "播放全部" → "播放 Mix" with `playMixPlaylist()` for Mix playlists
  - Hidden "随机添加" button for Mix playlists
  - Hidden download button for Mix playlists
  - Added "Mix" badge (using `tertiaryContainer` color + radio icon)
  - Added `_playMix()` method
- **`lib/ui/pages/queue/queue_page.dart`**:
  - Title shows "Mix - {playlist name} (count)" in Mix mode
  - Hidden shuffle button in Mix mode

### Phase 4: Import Service ✅
- Added import for `YouTubeSource`
- Modified `importFromUrl()` to detect Mix URLs using `YouTubeSource.isMixPlaylistUrl()`
- Added `_importMixPlaylist()` method:
  - Uses `getMixPlaylistInfo()` to get metadata
  - Creates Playlist with `isMix=true`, `mixPlaylistId`, `mixSeedVideoId`
  - Does NOT save any tracks (tracks loaded dynamically)
  - Sets `refreshIntervalHours = null` (Mix doesn't need scheduled refresh)
- Modified `refreshPlaylist()` to skip Mix playlists (returns empty result)
