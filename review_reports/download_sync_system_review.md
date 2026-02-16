# 下载与同步系统审查报告

## 审查日期
2026-02-17

## 审查范围
- `DownloadPathSyncService` - 本地文件同步服务
- `DownloadService` - 下载任务管理
- `Track` 模型 - 歌单归属与下载路径管理
- `TrackRepository` - Track CRUD 和孤儿清理
- `PlaylistService` - 歌单重命名逻辑

---

## 🔴 严重问题（P0）

### 1. 同步服务的 `existingPlaylistId` 继承逻辑存在缺陷

**位置**: `download_path_sync_service.dart:127-129`

**问题描述**:
```dart
final existingPlaylistId = track.playlistInfo.isNotEmpty
    ? track.playlistInfo.first.playlistId
    : 0;
```

当 Track 属于多个歌单时（如歌单 A、B、C），`first.playlistId` 可能是任意一个。如果用户：
1. 删除歌单 A 的文件夹
2. 保留歌单 B、C 的文件夹
3. 复制歌单 B 的文件夹为 "歌单 B - 副本"
4. 点击同步

**预期行为**: "歌单 B - 副本" 应该继承歌单 B 的 `playlistId`

**实际行为**: 如果 `first` 是歌单 A，则继承了错误的 `playlistId`

**影响**:
- 中等严重度：只在多歌单下载 + 文件夹复制场景下触发
- 会导致下载标记显示错误（显示属于歌单 A 而非歌单 B）

**建议修复**:
```dart
// 方案 1: 优先使用仍有本地文件的歌单 ID
final existingPlaylistId = track.playlistInfo.isNotEmpty
    ? (track.playlistInfo
        .where((info) => pathInfos.any((p) => p.playlistName == info.playlistName))
        .firstOrNull?.playlistId ?? track.playlistInfo.first.playlistId)
    : 0;

// 方案 2: 简化逻辑 - 新文件夹统一使用 playlistId=0（未分类）
// 用户需要手动从已下载页面将其添加到正确的歌单
final existingPlaylistId = 0;
```

**推荐**: 方案 2 更简单可靠。复制的文件夹本质上是"新发现的下载"，应该标记为未分类，让用户决定归属。

---

### 2. 同步服务清理逻辑可能误删正在播放的 Track

**位置**: `download_path_sync_service.dart:154-164`

**问题描述**:
```dart
// 第三步：清理数据库中不在本地的路径
final allTracks = await _trackRepo.getAllTracksWithDownloads();
for (final track in allTracks) {
  if (!matchedTrackIds.contains(track.id)) {
    // 这个 Track 没有在本地找到匹配文件，清除其路径
    track.clearAllDownloadPaths();
    await _trackRepo.save(track);
    removed++;
  }
}
```

**场景**:
1. 用户下载了歌曲到歌单 A
2. 用户手动将文件移动到其他位置（不在下载目录内）
3. 歌曲正在播放队列中
4. 用户点击同步
5. 同步服务找不到文件 → 清除 `downloadPath` → Track 变成 `playlistId > 0` 但无下载路径
6. 下次启动时，`deleteOrphanTracks()` 不会删除它（因为 `playlistId > 0`）

**实际影响**:
- 低严重度：不会导致数据丢失，只是下载标记消失
- 符合设计意图："本地文件是权威来源"

**是否需要修复**: ❌ 不需要
- 这是预期行为：同步的目的就是让 DB 反映本地文件状态
- 如果文件不在下载目录，就应该清除下载标记
- 播放队列中的 Track 不会被删除（`deleteOrphanTracks` 有 `excludeTrackIds` 保护）

---

## 🟡 中等问题（P1）

### 3. 歌单重命名后的文件迁移提示不够明确

**位置**: `playlist_service.dart:149-159`

**问题描述**:
歌单重命名时清除所有下载路径，但只返回旧/新文件夹路径，没有明确告知用户：
1. 需要手动移动哪些文件
2. 移动后需要做什么（点击同步）
3. 如果不移动会怎样（下载标记消失，但文件仍在）

**建议改进**:
在 UI 层（`CreatePlaylistDialog._showFileMigrationWarning`）增强提示信息：
```dart
'歌单已重命名，但下载文件需要手动迁移：\n\n'
'1. 将文件夹从以下位置移动：\n'
'   $oldDownloadFolder\n'
'   到：\n'
'   $newDownloadFolder\n\n'
'2. 移动完成后，从"已下载"页面点击刷新按钮重新关联\n\n'
'如果不移动文件，下载标记会消失，但文件不会被删除。'
```

---

### 4. `Track.setDownloadPath()` 在多歌单场景下的行为不明确

**位置**: `track.dart:115-145`

**问题描述**:
```dart
void setDownloadPath(int playlistId, String path, {String? playlistName}) {
  // 只更新匹配 playlistId 的第一个条目
  for (final info in playlistInfo) {
    if (info.playlistId == playlistId) {
      newInfos.add(PlaylistDownloadInfo()
        ..playlistId = playlistId
        ..playlistName = playlistName ?? info.playlistName
        ..downloadPath = path);
      found = true;
    } else {
      newInfos.add(PlaylistDownloadInfo()...);
    }
  }
}
```

**场景**: Track 属于歌单 A（ID=3），但有两个下载路径：
- `playlistId=3, name="歌单A", path="/path1"`
- `playlistId=3, name="歌单A - 副本", path="/path2"`

调用 `setDownloadPath(3, "/path3")` 时，只会更新第一个条目。

**实际影响**:
- 低严重度：这种场景很少见（同一歌单的多个副本）
- 当前行为可能是合理的（只更新第一个匹配）

**是否需要修复**: ⚠️ 需要明确设计意图
- 如果允许同一 `playlistId` 有多个路径 → 需要按 `playlistName` 精确匹配
- 如果不允许 → 需要在 `addToPlaylist` 时去重

**建议**: 在文档中明确说明行为，或修改为按 `playlistName` 精确匹配。

---

## 🟢 轻微问题（P2）

### 5. `DownloadScanner.scanFolderForTracks()` 总是设置 `playlistId=0`

**位置**: `download_scanner.dart:219`

**问题描述**:
```dart
..playlistInfo = [PlaylistDownloadInfo()..playlistId = 0..downloadPath = audioPath]
```

扫描器创建的 Track 总是 `playlistId=0`，即使文件在某个歌单文件夹内。

**实际影响**:
- 无影响：这是临时对象，只用于匹配 DB 中的 Track
- 同步服务会用 DB 中的 `playlistId` 覆盖

**是否需要修复**: ❌ 不需要
- 这是预期行为：扫描器不负责推断歌单归属
- 同步服务负责合并逻辑

---

### 6. `deleteOrphanTracks()` 的注释与实现不一致

**位置**: `track_repository.dart:529-530`

**注释说明**:
```dart
/// 注意：不检查 downloadPath。playlistId=0 的下载路径只是 scanner 扫描发现的，
/// 下次打开已下载页面时 scanner 会重新创建。删除数据库记录不影响本地文件。
```

**实际实现**:
```dart
final belongsToPlaylist = track.playlistInfo.any(
  (info) => info.playlistId > 0,
);
```

**问题**: 注释暗示 `playlistId=0` 的 Track 会被删除，但实际上只要 `playlistInfo` 中有任何 `playlistId > 0` 的条目就不会删除。

**场景**: Track 有两个条目：
- `playlistId=3, name="歌单A", path=""`（已清除路径）
- `playlistId=0, name="未分类", path="/path"`（扫描发现）

这个 Track 不会被删除（因为有 `playlistId=3`）。

**是否需要修复**: ✅ 需要更新注释
```dart
/// 孤立 Track 的定义：
/// - 不在当前播放队列中（通过 excludeTrackIds 排除）
/// - playlistInfo 中所有条目的 playlistId 都 <= 0
///
/// 注意：即使 Track 有 playlistId=0 的下载路径，只要它属于任何歌单（playlistId > 0），
/// 就不会被删除。这确保了歌单中的歌曲不会因为路径被清除而丢失。
```

---

## 🔵 设计建议（非 Bug）

### 7. 考虑引入"下载来源"字段区分不同歌单的下载

**当前设计**:
- Track 可以属于多个歌单
- 每个歌单可以有独立的下载路径
- 但无法区分"这个文件是从哪个歌单下载的"

**潜在问题**:
用户从歌单 A 下载了歌曲，后来将歌曲添加到歌单 B。现在：
- Track 属于 A 和 B
- 只有一个下载路径（在歌单 A 的文件夹内）
- 歌单 B 的详情页会显示"已下载"（因为 `hasAnyDownload = true`）
- 但实际上文件在歌单 A 的文件夹内

**是否需要修复**: ❌ 当前设计是合理的
- `isDownloadedForPlaylist(playlistId, playlistName)` 会按名称匹配
- 只有文件在对应歌单文件夹内才显示"已下载"
- 这是预期行为

---

### 8. 同步服务的性能优化空间

**当前实现**:
```dart
// 第二步：批量更新 Track，合并所有路径
for (final entry in trackPathsMap.entries) {
  final track = await _trackRepo.getById(trackId);  // N 次查询
  // ...
  await _trackRepo.save(track);  // N 次写入
}
```

**优化建议**:
```dart
// 批量查询
final trackIds = trackPathsMap.keys.toList();
final tracks = await _trackRepo.getByIds(trackIds);

// 批量更新
await _isar.writeTxn(() async {
  for (final track in tracks) {
    // 更新逻辑
  }
  await _isar.tracks.putAll(tracks);
});
```

**预期收益**:
- 从 O(2N) 降低到 O(2)
- 对于大量文件的同步操作有明显提升

---

## ✅ 正确的设计

### 9. 下载完成后的文件验证

**位置**: `download_service.dart:708-714`

```dart
// A3: 验证文件存在后才保存下载路径到 Track
if (await File(savePath).exists()) {
  await _trackRepository.addDownloadPath(track.id, task.playlistId, task.playlistName, savePath);
} else {
  logError('Download completed but file not found at: $savePath');
  throw Exception('Downloaded file not found at expected path');
}
```

✅ **正确**: 确保只有文件真实存在时才保存路径，避免数据库与文件系统不一致。

---

### 10. 同步服务的两阶段设计

**设计**:
1. 第一阶段：扫描所有文件夹，收集匹配结果
2. 第二阶段：批量更新 Track，合并路径
3. 第三阶段：清理不存在的路径

✅ **正确**:
- 避免边扫描边修改导致的状态不一致
- 支持进度回调
- 逻辑清晰，易于维护

---

### 11. 歌单归属以 DB 为权威，下载路径以本地文件为权威

**设计原则**:
```dart
// 合并策略：
// - 歌单归属（playlistId）以 DB 为权威来源，同步不改变
// - 下载路径以本地文件为权威来源
// - 文件夹名不匹配时，继承 DB 中已有的 playlistId
```

✅ **正确**:
- 同步不会改变歌曲的歌单归属
- 只更新下载路径，反映文件系统的真实状态
- 避免了之前的严重 Bug（同步后 `playlistId` 变成 0）

---

## 总结

### 需要修复的问题

| 优先级 | 问题 | 严重程度 | 建议 |
|--------|------|----------|------|
| P0 | 同步服务的 `existingPlaylistId` 继承逻辑 | 中 | 改为统一使用 `playlistId=0`，让用户手动分类 |
| P1 | 歌单重命名的文件迁移提示 | 低 | 增强 UI 提示信息 |
| P1 | `Track.setDownloadPath()` 多歌单行为 | 低 | 明确文档说明或改为按 `playlistName` 匹配 |
| P2 | `deleteOrphanTracks()` 注释不准确 | 极低 | 更新注释 |

### 性能优化建议

1. 同步服务批量查询/写入（从 O(2N) 到 O(2)）
2. 考虑为大文件夹添加增量同步（只扫描变更的文件夹）

### 设计验证

✅ 核心设计是正确的：
- 两阶段同步逻辑清晰
- 权威来源划分合理（歌单归属看 DB，路径看文件系统）
- 文件验证机制完善
- 孤儿清理逻辑安全（保护播放队列）

### 测试建议

建议增加以下场景的集成测试：
1. 多歌单下载 + 文件夹复制 + 同步
2. 歌单重命名 + 文件移动 + 同步
3. 删除原文件夹 + 保留副本 + 同步
4. 播放队列中的歌曲 + 删除文件 + 同步 + 重启应用
