# FMP 已完成的重构与关键经验

## 已完成的重构 (2026-01-14)

### 1. 预计算路径模式
- Track 使用 `playlistIds` + `downloadPaths` 并行列表支持多歌单下载
- 路径在**加入歌单时**预计算，非下载时
- 移除了 `syncDownloadedFiles()`、`findBestMatchForRefresh()` 等复杂同步逻辑

### 2. 统一路径获取
- 所有基础目录获取统一使用 `DownloadPathUtils.getDefaultBaseDir()`
- 已删除 4 个重复的 `_getDownloadBaseDir()` 实现

### 3. 播放时验证文件存在性
- `ensureAudioUrl()` 返回 `(Track, String?)` 元组
- 直接返回找到的本地文件路径，避免二次检查

### 4. 清理无用字段
- 移除 `cachedPath` 字段（从未被设置）
- `localCoverPath` 不再使用 `existsSync()`（由 ImageLoadingService 处理回退）

---

## 关键经验教训

### 1. StateNotifier 不能在 build 期间修改 state
```dart
// 错误 - 会导致 StateNotifierListenerError
Widget build() {
  cache.checkAndUpdate(track);  // 修改 state
}

// 正确 - 延迟到下一个 microtask
void _scheduleRefresh(String path) {
  Future.microtask(() async {
    state = {...state, path: exists};
  });
}
```

### 2. ref.watch vs ref.read 的正确使用
```dart
// 正确：watch 监听状态变化，read 调用方法
ref.watch(downloadStatusCacheProvider);  // 触发重建
final cache = ref.read(downloadStatusCacheProvider.notifier);
final isDownloaded = cache.isDownloadedForPlaylist(track, playlistId);

// 错误：watch notifier 不触发重建
ref.watch(provider.notifier).method();  // UI 不会更新
```

### 3. Dart 3 Records 简化多返回值
```dart
// 旧方式 - 需要额外定义类或回调
final track = await ensureAudioUrl(t);
final localPath = await track.getFirstExistingPath();

// 新方式 - 直接使用 Record
final (trackWithUrl, localPath) = await ensureAudioUrl(t);
```

### 4. 歌单封面路径格式
- 实际下载路径：`/{playlistName}/{...}`（只有歌单名）
- 错误的匹配方式：`/{playlistName}_{playlistId}/{...}`

### 5. getter 必须同步
```dart
// 错误 - getter 不能是 async
String? get firstExistingPath async => ...;  // 编译错误

// 正确 - 使用方法
Future<String?> getFirstExistingPath() async => ...;
```

### 6. addTrackToPlaylist 必须使用 getOrCreate (2026-01-18)

**问题**：使用 `save()` 直接保存传入的 track 对象会导致 playlistIds/downloadPaths 数据不同步。

```dart
// 错误 - 缓存的旧 track 数据会覆盖数据库最新数据
Future<void> addTrackToPlaylist(int playlistId, Track track) async {
  track.setDownloadPath(playlistId, path);
  await _trackRepository.save(track);  // 可能用旧数据覆盖
}

// 正确 - 先从数据库获取最新数据
Future<void> addTrackToPlaylist(int playlistId, Track track) async {
  final existingTrack = await _trackRepository.getOrCreate(track);  // 获取最新数据
  existingTrack.setDownloadPath(playlistId, path);
  await _trackRepository.save(existingTrack);
}
```

**场景**：
1. Track 在歌单 A、B 中 → playlistIds=[A,B]
2. 删除歌单 B → 数据库更新为 playlistIds=[A]
3. 用缓存的旧 track 添加到歌单 C → 旧数据 playlistIds=[A,B,C] 覆盖数据库

### 7. refreshPlaylist 必须清理被移除的 tracks (2026-01-18)

**問題**：刷新導入的歌單時，如果遠程移除了某些歌曲，只更新了 `Playlist.trackIds`，但沒有清理對應 Track 的 `playlistIds` 和 `downloadPaths`。

### 8. ListTile 的 leading 中放 Row 會導致滾動卡頓 (2026-01-19)

**問題**：在 `ListTile.leading` 中放置 `Row`（包含排名數字和縮略圖）會導致列表滾動時卡頓。

```dart
// 錯誤 - 會導致額外的佈局計算
ListTile(
  leading: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 28, child: Text('$rank')),
      const SizedBox(width: 12),
      TrackThumbnail(track: track, size: 48),
    ],
  ),
  ...
)

// 正確 - 使用扁平的自定義佈局
InkWell(
  onTap: () => ...,
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(
      children: [
        SizedBox(width: 24, child: Text('$rank')),
        const SizedBox(width: 12),
        TrackThumbnail(track: track, size: 48, borderRadius: 4),
        const SizedBox(width: 12),
        Expanded(child: Column(...)),  // 標題和副標題
        PopupMenuButton(...),  // 菜單按鈕
      ],
    ),
  ),
)
```

**原因**：`ListTile` 對 `leading` 有特殊的佈局約束處理。當 `leading` 中包含複雜組件（如 `Row`）時，會觸發額外的佈局計算，導致性能問題。

**解決方案**：放棄 `ListTile`，使用 `InkWell` + `Padding` + `Row` 構建扁平的自定義佈局。

### 9. 快速連續切歌的競態條件防護 (2026-01-19)

**問題**：快速點擊多首歌曲時，會加載所有點擊過的歌曲而不是只加載最後一個，導致根據加載速度輪流播放。同時可能出現 `Player already exists` 錯誤。

**解決方案**：

1. **請求 ID 機制** - 每個播放請求都有唯一 ID，舊請求會被新請求取代
2. **帶 ID 的鎖包裝類** - 確保只有正確的請求才能完成鎖
3. **UI 立即更新** - 在任何 `await` 之前更新 UI
4. **等待播放器 idle** - 設置新的 audio source 前確保播放器完全清理
5. **finally 塊處理 isLoading** - 請求被 abort 時重置加載狀態

**實現**：

```dart
// 帶有請求 ID 的鎖包裝類
class _LockWithId {
  final int requestId;
  final Completer<void> completer;

  _LockWithId(this.requestId) : completer = Completer<void>();

  void completeIf(int expectedRequestId) {
    if (requestId == expectedRequestId && !completer.isCompleted) {
      completer.complete();
    }
  }
}

// AudioController
class AudioController {
  _LockWithId? _playLock;
  int _playRequestId = 0;

  Future<void> playTemporary(Track track) async {
    // 【重要】立即更新 UI
    _updatePlayingTrack(track);
    _updateQueueState();

    final requestId = ++_playRequestId;

    // 立即完成舊鎖，讓舊請求可以快速退出
    if (_playLock != null && !_playLock!.completer.isCompleted) {
      _playLock!.completeIf(_playLock!.requestId);
      await _playLock!.completer.future.timeout(...);
    }

    // 檢查是否被取代
    if (requestId != _playRequestId) {
      return;  // abort
    }

    _playLock = _LockWithId(requestId);
    bool completedSuccessfully = false;

    try {
      // ... 播放邏輯，多處檢查 requestId ...
      completedSuccessfully = true;
    } finally {
      _playLock?.completeIf(requestId);
      // 如果沒有成功完成且被取代，重置 isLoading
      if (!completedSuccessfully && requestId != _playRequestId) {
        state = state.copyWith(isLoading: false);
      }
    }
  }
}
```

**AudioService 修復** - 等待播放器 idle 狀態：

```dart
// AudioService.playUrl/playFile
await _player.stop();

// 等待播放器進入 idle 狀態，確保底層播放器完全清理
// 這對 just_audio_media_kit 特別重要，否則會出現 "Player already exists" 錯誤
if (_player.processingState != ProcessingState.idle) {
  try {
    await _player.playerStateStream
        .where((state) => state.processingState == ProcessingState.idle)
        .first
        .timeout(const Duration(milliseconds: 500));
  } catch (e) {
    // 超時也繼續
  }
}

// 現在可以安全地設置新的 audio source
await _player.setAudioSource(audioSource);
```

**關鍵點**：
- 多個檢查點：在 `await` 操作後都要檢查 `requestId != _playRequestId`
- 鎖的安全完成：使用 `completeIf` 而非直接 `complete()`
- 正確的狀態管理：`completedSuccessfully` 標誌 + finally 塊處理

### 10. 所有異步方法必須在 finally 塊中重置 isLoading (2026-01-19)

**問題**：臨時播放時點擊「下一首」導致 UI 一直顯示 loading 狀態。

**原因**：`_restoreSavedState()` 方法在正常完成時沒有重置 `isLoading`，只在異常時重置。

```dart
// ❌ 錯誤 - 只在異常時重置
Future<void> _restoreSavedState() async {
  try {
    // ... 恢復邏輯 ...
  } catch (e) {
    _isTemporaryPlay = false;
    _clearSavedState();
  }
  // 正常完成時沒有重置 isLoading！
}

// ✅ 正確 - 使用 finally 塊確保一定重置
Future<void> _restoreSavedState() async {
  try {
    // ... 恢復邏輯 ...
  } catch (e) {
    _isTemporaryPlay = false;
    _clearSavedState();
  } finally {
    state = state.copyWith(isLoading: false);
  }
}
```

**經驗**：任何設置了 `isLoading = true` 的方法，都必須在 `finally` 塊中重置它。即使在正常流程中已經重置，`finally` 塊可以作為雙重保險，處理所有可能的退出路徑（early return、異常等）。

### 11. 播放器狀態監聽器不能用 `||` 保留 loading 狀態 (2026-01-19)

**問題**：在 `_onPlayerStateChanged` 中使用 `state.isLoading || playerState.processingState == loading` 會導致 `isLoading` 只能變成 `true`，永遠不能通過播放器狀態變成 `false`。這導致 Android 上歌曲成功播放後仍顯示 loading。

**原因**：`||` 運算符意味著只要 `state.isLoading` 是 `true`，結果就會是 `true`。即使我們顯式調用 `copyWith(isLoading: false)`，如果播放器狀態事件在之後觸發，`isLoading` 會再次被設為 `true`。

```dart
// ❌ 錯誤 - isLoading 只能變成 true，不能通過播放器狀態變成 false
isLoading: state.isLoading || playerState.processingState == just_audio.ProcessingState.loading,

// ✅ 正確 - isLoading 純粹反映播放器狀態
isLoading: playerState.processingState == just_audio.ProcessingState.loading,
```

**经验**：播放器狀態監聽器應該純粹反映播放器狀態，不要嘗試「保留」先前的狀態值。

### 12. 切歌時必須立即更新所有 UI 狀態 (2026-01-19)

**問題**：點擊下一首後，在歌曲實際開始播放之前：
1. 按鈕顯示「播放」而非「加載中」，點擊會播放舊歌曲
2. 進度條不會重置，仍顯示舊歌曲的進度

**根本原因**：
1. `isLoading` 和 `position` 設置被播放器狀態事件覆蓋
2. `_audioService.stop()` 觸發 `_onPlayerStateChanged`，把 `isLoading` 設回 `false`
3. `_onPositionChanged` 持續接收舊歌曲的位置，覆蓋 `position: Duration.zero`

**解決方案**：引入 `_manualLoading` 標誌

```dart
class AudioController {
  // 手動加載標誌 - 用於 URL 獲取期間保持 loading 狀態
  bool _manualLoading = false;

  void _onPlayerStateChanged(just_audio.PlayerState playerState) {
    state = state.copyWith(
      isPlaying: playerState.playing,
      isBuffering: playerState.processingState == just_audio.ProcessingState.buffering,
      // 手動標誌優先，防止播放器事件覆蓋
      isLoading: _manualLoading || playerState.processingState == just_audio.ProcessingState.loading,
      processingState: playerState.processingState,
    );
  }

  void _onPositionChanged(Duration position) {
    // 手動加載期間忽略位置更新（防止舊歌曲位置覆蓋已重置的進度條）
    if (_manualLoading) return;
    state = state.copyWith(position: position);
    // ...
  }

  Future<void> _playTrack(Track track) async {
    // 1. 保存當前狀態（playTemporary 需要）
    final savedPosition = _audioService.position;
    final savedIsPlaying = _audioService.isPlaying;

    // 2. 立即更新 UI
    _updatePlayingTrack(track);
    _updateQueueState();

    // 3. 設置手動加載標誌，防止播放器事件覆蓋
    _manualLoading = true;
    state = state.copyWith(isLoading: true, position: Duration.zero, error: null);

    // 4. 停止當前播放（此時播放器事件不會覆蓋 isLoading 和 position）
    await _audioService.stop();

    // ... 獲取 URL 和播放 ...

    // 5. 完成時重置標誌
    _manualLoading = false;
    state = state.copyWith(isLoading: false);
  }
}
```

**關鍵點**：
- `_manualLoading = true` 必須在 `stop()` 之前設置
- `_onPlayerStateChanged` 檢查 `_manualLoading` 來決定 `isLoading`
- `_onPositionChanged` 在 `_manualLoading` 時直接返回，不更新位置
- 每個 `isLoading: false` 之前都要設置 `_manualLoading = false`

### 13. next()/previous()/_onTrackCompleted() 必須檢測完整的「脫離隊列」狀態 (2026-01-19)

**問題**：
1. 隊列為空時進行臨時播放，添加歌曲後點擊「下一首」播放第二首而非第一首
2. 臨時歌曲自然結束時，剛添加的歌曲自動播放第二首

**原因**：`next()` 和 `_onTrackCompleted()` 只檢查 `_isTemporaryPlay`，但「脫離隊列」還有其他情況：
- 隊列被清空但歌曲繼續播放
- `_playingTrack.id != queueTrack.id`

當這些情況發生時，`_isTemporaryPlay` 可能是 false，所以會錯誤地調用 `moveToNext()`，從索引 0 移動到索引 1。

**修復**：使用與 `_updateQueueState()` 相同的完整檢測邏輯：

```dart
// 檢測是否脫離隊列（next/previous/_onTrackCompleted 都要用這個邏輯）
final queue = _queueManager.tracks;
final queueTrack = _queueManager.currentTrack;
final isPlayingOutOfQueue = _isTemporaryPlay ||
    (_playingTrack != null && queueTrack != null && _playingTrack!.id != queueTrack.id) ||
    (_playingTrack != null && queueTrack == null && queue.isNotEmpty);

if (isPlayingOutOfQueue) {
  if (_isTemporaryPlay && _temporaryState != null) {
    // 有保存的狀態：恢復
    await _restoreSavedState();
  } else {
    // 無保存狀態：播放隊列第一首
    _isTemporaryPlay = false;
    _temporaryState = null;
    if (queue.isNotEmpty) {
      _queueManager.setCurrentIndex(0);
      await _playTrack(_queueManager.currentTrack!);
    }
  }
  return;
}

// 只有正常隊列播放才調用 moveToNext()/moveToPrevious()
```

**時序問題**：位置檢測定時器可能比播放器完成事件先觸發 `_onTrackCompleted`，第一次調用清除 `_isTemporaryPlay` 後，第二次調用會錯誤地調用 `moveToNext()`。使用完整的 `isPlayingOutOfQueue` 檢測可以避免這個問題，因為即使 `_isTemporaryPlay` 被清除，`_playingTrack.id != queueTrack.id` 仍然成立。

### 14. 使用 PlaybackContext 统一状态管理 (2026-01-19)

**问题**：`AudioController` 中有多个分散的状态字段管理播放模式和加载状态：
- `_isTemporaryPlay` - 是否临时播放
- `_temporaryState` - 保存的队列状态
- `_manualLoading` - 手动加载标志
- `_playLock` / `_playRequestId` - 播放锁和请求 ID

这些字段之间有复杂的交互关系，容易遗漏同步更新。

**解决方案**：引入 `PlayMode` 枚举和 `_PlaybackContext` 类统一管理：

```dart
enum PlayMode {
  queue,      // 正常队列播放
  temporary,  // 临时播放（播放完成后恢复）
  detached,   // 脱离队列（如队列清空后继续播放）
}

class _PlaybackContext {
  final PlayMode mode;
  final int activeRequestId;     // 当前活动的请求 ID（0 表示无活动请求）
  final int? savedQueueIndex;    // 临时播放保存的队列索引
  final Duration? savedPosition; // 临时播放保存的播放位置
  final bool? savedWasPlaying;   // 临时播放保存的播放状态
  
  bool get isTemporary => mode == PlayMode.temporary;
  bool get isInLoadingState => activeRequestId > 0;  // 替代 _manualLoading
  bool get hasSavedState => savedQueueIndex != null;
  
  _PlaybackContext copyWith({...});
}
```

**好处**：
1. **单一真相来源** - 所有播放模式状态在一个对象中
2. **不可变更新** - 使用 `copyWith` 更新，更安全
3. **便捷 getter** - `isTemporary`, `isInLoadingState`, `hasSavedState` 等
4. **减少重复检测** - `_isPlayingOutOfQueue` getter 使用 `_context.mode`

**统一播放入口**：

```dart
Future<void> _executePlayRequest({
  required Track track,
  required PlayMode mode,
  bool persist = true,
  bool recordHistory = true,
  bool prefetchNext = true,
}) async {
  // 所有播放操作都通过这个入口
  // _playTrack() 和 playTemporary() 都调用它
}
```

**关键点**：
- 用 `_context.mode` 替代 `_isTemporaryPlay`
- 用 `_context.isInLoadingState` 替代 `_manualLoading`
- 用 `_context.hasSavedState` 检查是否有保存的临时状态
- 清理临时状态用 `_context = _context.copyWith(mode: PlayMode.queue, savedQueueIndex: null, ...)`

### 15. 所有有独立 URL 获取逻辑的方法都必须使用 _playRequestId (2026-01-19)

**问题**：临时播放正在获取 URL 时，用户点击"下一首"，恢复操作开始。但临时播放的 URL 获取完成后，仍然播放了临时歌曲，覆盖了恢复操作。

**原因**：`_restoreSavedState()` 有自己的 URL 获取逻辑，但没有使用 `_playRequestId` 机制来取消旧请求。

```dart
// ❌ 错误 - _restoreSavedState() 没有递增 _playRequestId
Future<void> _restoreSavedState() async {
  // ... 准备工作 ...
  final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(currentTrack);
  // 此时临时播放的 URL 获取可能也完成了，它不知道已经被取代
  await _audioService.setUrl(url);
  await _audioService.play();
}

// ✅ 正确 - 开始时递增 _playRequestId，并在 await 后检查取代
Future<void> _restoreSavedState() async {
  // 【重要】递增 _playRequestId 来取消任何正在进行的播放请求
  final requestId = ++_playRequestId;
  _context = _context.copyWith(activeRequestId: requestId);
  
  // ... 准备工作 ...
  
  final (trackWithUrl, localPath) = await _queueManager.ensureAudioUrl(currentTrack);
  
  // 检查是否被取代
  if (_isSuperseded(requestId)) {
    logDebug('_restoreSavedState superseded after URL fetch, aborting');
    return;
  }
  
  await _audioService.setUrl(url);
  
  // 再次检查
  if (_isSuperseded(requestId)) {
    await _audioService.stop();
    return;
  }
  
  await _audioService.play();
}
```

**经验**：任何有独立 URL 获取逻辑的方法（不通过 `_executePlayRequest()`）都必须：
1. 开始时递增 `_playRequestId`
2. 每个 `await` 点后检查 `_isSuperseded(requestId)`
3. 如果被取代，立即中止并清理

**受影响的方法**：
- `_restoreSavedState()` - 恢复临时播放状态
- `_prepareCurrentTrack()` - 初始化时准备当前歌曲（不自动播放，风险较低）

**问题**：刷新导入的歌单时，如果远程移除了某些歌曲，只更新了 `Playlist.trackIds`，但没有清理对应 Track 的 `playlistIds` 和 `downloadPaths`。

```dart
// 错误 - 只计算了移除数量，没有清理 tracks
final removedCount = originalTrackIds.difference(newTrackIdSet).length;
playlist.trackIds = newTrackIds;  // Track 数据不一致！

// 正确 - 清理被移除的 tracks
final removedTrackIds = originalTrackIds.difference(newTrackIdSet);
if (removedTrackIds.isNotEmpty) {
  final removedTracks = await _trackRepository.getByIds(removedTrackIds.toList());
  for (final track in removedTracks) {
    track.removeDownloadPath(playlist.id);
    // 如果 playlistIds 为空，删除 track
  }
}
playlist.trackIds = newTrackIds;
```

$1

**问题**：逐个查询和保存导致删除大歌单极慢（N 首歌 = 2N 次数据库操作）。

```dart
// 优化前 - O(2N) 数据库操作
for (final trackId in trackIds) {
  final track = await _trackRepository.getById(trackId);  // N 次查询
  await _trackRepository.save(track);  // N 次写入
}

// 优化后 - O(3) 数据库操作
final tracks = await _trackRepository.getByIds(trackIds);  // 1 次批量查询
await _isar.writeTxn(() async {
  await _isar.playlists.delete(playlistId);  // 1 次删除
  await _isar.tracks.deleteAll(toDelete);    // 1 次批量删除
  await _isar.tracks.putAll(toUpdate);       // 1 次批量更新
});
```

---

$1

| 组件 | 位置 | 用途 |
|------|------|------|
| TrackThumbnail | `lib/ui/widgets/track_thumbnail.dart` | 统一封面显示 |
| DurationFormatter | `lib/core/utils/duration_formatter.dart` | 时长格式化 |
| TrackExtensions | `lib/core/extensions/track_extensions.dart` | Track 扩展方法 |
| ToastService | `lib/core/services/toast_service.dart` | 消息提示 |
| ImageLoadingService | `lib/core/services/image_loading_service.dart` | 图片加载（本地优先）|
| DownloadPathUtils | `lib/services/download/download_path_utils.dart` | 路径计算 |
| DownloadStatusCache | `lib/providers/download/download_status_cache.dart` | 下载状态缓存 |

---

## 封面图片优先级

1. 本地封面 (`track.localCoverPath` → `{dir}/cover.jpg`)
2. 网络封面 (`track.thumbnailUrl`)
3. 占位符 (Icons.music_note)

由 `ImageLoadingService.loadImage()` 自动处理回退。
