# 音頻系統重構方案

## 一、當前問題分析

### 1.1 累積的「補丁」清單

| 問題 | 補丁位置 | 複雜度 |
|------|----------|--------|
| 快速切歌競態條件 | `_playLock`, `_playRequestId`, `_LockWithId` | 高 |
| 切歌時 UI 狀態被覆蓋 | `_manualLoading` 標誌 | 中 |
| next/previous 脫離隊列檢測 | 重複的 `isPlayingOutOfQueue` 邏輯 | 中 |
| 後台播放 completed 事件丟失 | `_positionCheckTimer` 定時器 | 中 |
| 導航請求競態 | `_navRequestId` | 低 |
| 單曲循環 vs 臨時播放 | 特殊處理邏輯 | 低 |

### 1.2 當前架構的問題

1. **狀態管理分散**：`_isTemporaryPlay`, `_manualLoading`, `_isHandlingCompletion` 等標誌散落在各處
2. **重複邏輯**：`isPlayingOutOfQueue` 檢測在 `next()`, `previous()`, `_onTrackCompleted()`, `_updateQueueState()` 中重複
3. **鎖機制複雜**：`_LockWithId` 和 `completedSuccessfully` 邏輯難以理解
4. **狀態更新時機敏感**：必須在特定時機設置 `_manualLoading`，容易出錯

---

## 二、重構目標

1. **統一狀態管理**：將分散的狀態標誌整合到統一的播放狀態機
2. **消除重複邏輯**：提取公共方法和狀態判斷
3. **簡化競態處理**：用更清晰的模式替代當前的鎖機制
4. **保持功能一致**：所有現有功能和邊緣情況必須正確處理

---

## 三、新架構設計

### 3.1 播放狀態機

```dart
/// 播放模式枚舉
enum PlayMode {
  /// 正常隊列播放
  queue,
  /// 臨時播放（播放完成後恢復）
  temporary,
  /// 脫離隊列（隊列被清空或修改後的狀態）
  detached,
}

/// 播放請求狀態
enum PlayRequestState {
  idle,       // 無進行中的請求
  preparing,  // 正在準備（停止舊播放、獲取 URL）
  loading,    // 正在加載音頻
  playing,    // 播放中
  error,      // 出錯
}

/// 統一的內部播放狀態
class _PlaybackContext {
  final PlayMode mode;
  final PlayRequestState requestState;
  final int requestId;

  // 臨時播放保存的狀態
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;

  // 當前播放的歌曲（與隊列分離）
  final Track? playingTrack;
}
```

### 3.2 核心方法重構

#### 統一的播放入口

```dart
/// 統一的播放方法 - 所有播放操作的唯一入口
Future<void> _executePlayRequest({
  required Track track,
  required PlayMode mode,
  int? targetQueueIndex,  // 用於恢復隊列時
}) async {
  final requestId = ++_requestId;

  // 階段 1：立即更新 UI（同步）
  _enterPreparingState(track, requestId);

  // 階段 2：取消之前的請求
  _cancelPreviousRequest();

  // 階段 3：停止當前播放
  await _audioService.stop();

  // 階段 4：檢查是否被取代
  if (_isRequestSuperseded(requestId)) return;

  // 階段 5：獲取音頻 URL
  final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(track);
  if (_isRequestSuperseded(requestId)) return;

  // 階段 6：播放
  await _startPlayback(trackWithUrl, localPath);
  if (_isRequestSuperseded(requestId)) {
    await _audioService.stop();
    return;
  }

  // 階段 7：完成
  _enterPlayingState(trackWithUrl, mode, requestId);
}
```

#### 統一的「脫離隊列」檢測

```dart
/// 檢測當前是否脫離隊列
bool get _isPlayingOutOfQueue {
  final queueTrack = _queueManager.currentTrack;
  return _context.mode == PlayMode.temporary ||
         _context.mode == PlayMode.detached ||
         (_playingTrack != null && queueTrack != null && _playingTrack!.id != queueTrack.id) ||
         (_playingTrack != null && queueTrack == null && _queueManager.tracks.isNotEmpty);
}

/// 統一的「返回隊列」邏輯
Future<void> _returnToQueue() async {
  if (_context.mode == PlayMode.temporary && _context.savedQueueIndex != null) {
    // 有保存的狀態：恢復
    await _restoreToSavedPosition();
  } else {
    // 無保存狀態：播放隊列第一首
    await _playFirstInQueue();
  }
}
```

### 3.3 狀態轉換圖

```
                    ┌──────────────────────────────────────────────┐
                    │                                              │
                    ▼                                              │
    ┌─────────┐   playTrack()   ┌───────────┐   完成/next()   ┌────────┐
    │  idle   │ ───────────────▶│   queue   │ ────────────────▶│ queue  │
    └─────────┘                 └───────────┘                  └────────┘
         │                           │ ▲                           │
         │                           │ │                           │
         │ playTemporary()           │ │ 恢復                       │ clearQueue()
         │                           │ │                           │
         ▼                           ▼ │                           ▼
    ┌───────────┐   歌曲完成    ┌───────────┐   添加歌曲     ┌──────────┐
    │ temporary │ ─────────────▶│  返回隊列  │◀──────────────│ detached │
    └───────────┘               └───────────┘               └──────────┘
         │                                                        ▲
         │ clearQueue()                                           │
         └────────────────────────────────────────────────────────┘
```

### 3.4 邊緣情況處理

| 邊緣情況 | 當前處理 | 重構後處理 |
|---------|---------|-----------|
| 快速連續點擊歌曲 | `_playLock` + `_playRequestId` | 統一的 `_requestId` + `_isRequestSuperseded()` |
| 切歌時 UI 狀態 | `_manualLoading` | `_enterPreparingState()` 統一處理 |
| 臨時播放結束 | `_isTemporaryPlay` 檢查 | `_context.mode == PlayMode.temporary` |
| 隊列清空後繼續播放 | 多處 `isPlayingOutOfQueue` | 統一的 `_isPlayingOutOfQueue` getter |
| 單曲循環 + 臨時播放 | 特殊 if 分支 | 狀態機自然處理 |
| 後台 completed 丟失 | `_positionCheckTimer` | 保留（這是平台限制） |
| 添加歌曲到空隊列 | `next()` 中特殊處理 | `_returnToQueue()` 統一處理 |

---

## 四、詳細流程文檔

### 4.1 正常隊列播放流程

```
用戶點擊歌曲 → playTrack(track)
    │
    ├─ 1. _enterPreparingState(track)
    │      - 設置 playingTrack（UI 立即顯示新歌曲）
    │      - 設置 isLoading = true
    │      - 設置 position = 0
    │      - 阻止播放器事件覆蓋這些狀態
    │
    ├─ 2. _audioService.stop()
    │
    ├─ 3. _queueManager.ensureAudioUrl(track)
    │      - 檢查本地文件
    │      - 或獲取網絡 URL
    │
    ├─ 4. _audioService.playUrl/playFile()
    │
    └─ 5. _enterPlayingState(track)
           - 設置 mode = PlayMode.queue
           - 設置 isLoading = false
           - 允許播放器事件更新狀態
           - 記錄播放歷史
```

### 4.2 臨時播放流程

```
搜索頁點擊歌曲 → playTemporary(track)
    │
    ├─ 1. 保存當前狀態（在 stop() 之前！）
    │      - savedQueueIndex = currentIndex
    │      - savedPosition = position
    │      - savedWasPlaying = isPlaying
    │
    ├─ 2. _enterPreparingState(track)
    │      - mode = PlayMode.temporary
    │
    ├─ 3. _audioService.stop()
    │
    ├─ 4. _queueManager.ensureAudioUrl(track, persist: false)
    │      - 不保存到數據庫
    │
    ├─ 5. _audioService.playUrl/playFile()
    │
    └─ 6. _enterPlayingState(track)
           - 保持 mode = PlayMode.temporary
```

### 4.3 臨時播放結束恢復流程

```
歌曲播放完成 → _onTrackCompleted()
    │
    ├─ 檢查 loopMode == LoopMode.one?
    │      └─ 是 → 重播當前歌曲（即使是臨時播放）
    │
    ├─ 檢查 _isPlayingOutOfQueue?
    │      │
    │      └─ 是 → _returnToQueue()
    │              │
    │              ├─ mode == temporary && 有保存狀態?
    │              │      └─ 恢復到 savedQueueIndex
    │              │         - 回退 10 秒
    │              │         - 如果之前在播放則繼續播放
    │              │
    │              └─ 其他
    │                     └─ 播放隊列第一首
    │
    └─ 否 → _queueManager.moveToNext() → _playTrack(nextTrack)
```

### 4.4 next() / previous() 流程

```
用戶點擊下一首 → next()
    │
    ├─ 檢查 _isPlayingOutOfQueue?
    │      │
    │      └─ 是 → _returnToQueue()
    │              （與 4.3 相同的邏輯）
    │
    └─ 否 → 正常隊列導航
           _queueManager.moveToNext()
           _playTrack(nextTrack)
```

### 4.5 快速切歌競態處理

```
用戶快速點擊: 歌曲A → 歌曲B → 歌曲C

歌曲A 請求 (requestId=1):
    ├─ _enterPreparingState() → UI 顯示歌曲A
    ├─ stop()
    └─ 被歌曲B 取代

歌曲B 請求 (requestId=2):
    ├─ _enterPreparingState() → UI 顯示歌曲B
    ├─ stop()
    └─ 被歌曲C 取代

歌曲C 請求 (requestId=3):
    ├─ _enterPreparingState() → UI 顯示歌曲C
    ├─ stop()
    ├─ ensureAudioUrl() → 獲取 URL
    ├─ playUrl() → 開始播放
    └─ 成功完成

結果：只有歌曲C 播放
```

### 4.6 隊列修改場景

```
場景：臨時播放中，用戶修改隊列

初始狀態:
    - 隊列: [A, B, C], 索引=1 (歌曲B)
    - 臨時播放: 歌曲X
    - savedQueueIndex = 1

用戶操作: 刪除歌曲A

新狀態:
    - 隊列: [B, C], 索引=0
    - 臨時播放: 歌曲X (不變)
    - savedQueueIndex = 1 (不變，但會被 clamp)

臨時播放結束:
    - targetIndex = min(savedQueueIndex, queue.length-1) = min(1, 1) = 1
    - 恢復到歌曲C (索引1)
```

---

## 五、重構步驟

### 階段 1：引入新的狀態類（不破壞現有邏輯）

1. 創建 `_PlaybackContext` 類
2. 添加 `_context` 字段
3. 在現有方法中同步更新 `_context`

### 階段 2：統一播放入口

1. 創建 `_executePlayRequest()` 方法
2. 重構 `_playTrack()` 使用新方法
3. 重構 `playTemporary()` 使用新方法
4. 重構 `_restoreSavedState()` 使用新方法

### 階段 3：統一脫離隊列邏輯

1. 添加 `_isPlayingOutOfQueue` getter
2. 添加 `_returnToQueue()` 方法
3. 重構 `next()`, `previous()`, `_onTrackCompleted()` 使用新方法

### 階段 4：清理舊代碼

1. 移除 `_isTemporaryPlay` 標誌（用 `_context.mode` 替代）
2. 移除 `_temporaryState` 類（整合到 `_PlaybackContext`）
3. 簡化鎖機制（只保留 `_requestId` 和 `_isRequestSuperseded()`）

### 階段 5：測試和驗證

1. 測試所有正常播放場景
2. 測試臨時播放和恢復
3. 測試快速切歌
4. 測試隊列修改場景
5. 測試 Android 後台播放
6. 測試 Windows 媒體鍵

---

## 六、風險評估

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|--------|------|----------|
| 引入新 bug | 中 | 高 | 分階段重構，每階段都測試 |
| 性能下降 | 低 | 低 | 新架構更簡單，應該更快 |
| 平台差異 | 中 | 中 | 保留 `_positionCheckTimer` 等平台相關補丁 |

---

## 七、待確認問題

1. **是否需要保留 `_LockWithId` 類**？
   - 當前方案用簡單的 `_requestId` 替代
   - 如果需要更精確的鎖控制，可以保留

2. **`_manualLoading` 標誌是否需要**？
   - 新方案中 `_enterPreparingState()` 統一處理
   - 但播放器事件監聽器仍需要知道何時忽略更新

3. **是否需要保留 `_navRequestId`**？
   - 新方案中 `_requestId` 可能足夠
   - 但如果 `next()`/`previous()` 不經過 `_executePlayRequest()`，可能需要保留

---

請確認：

1. 這個重構方向是否符合你的預期？
2. 是否有遺漏的邊緣情況？
3. 是否需要調整重構步驟的優先級？
