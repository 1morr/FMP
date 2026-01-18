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

**經驗**：任何設置了 `isLoading = true` 的方法，都必須在 `finally` 塊中重置它。即使在正常流程中已經重置，`finally` 塊可以作為雙重保險，處理所有可能的退出路徑（early return、異常等）。。當 `leading` 中包含複雜組件（如 `Row`）時，會觸發額外的佈局計算，導致性能問題。

**解決方案**：放棄 `ListTile`，使用 `InkWell` + `Padding` + `Row` 構建扁平的自定義佈局。

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
