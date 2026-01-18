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
