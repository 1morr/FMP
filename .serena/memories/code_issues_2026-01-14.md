# FMP 代码问题与优化建议（2026-01-14 分析）

## 一、已发现的问题

### 🔴 高优先级问题

#### 1. 播放时不验证本地文件存在性
**位置**: `audio_provider.dart:843-860`

**问题代码**:
```dart
final url = trackWithUrl.firstDownloadPath ??
            trackWithUrl.cachedPath ??
            trackWithUrl.audioUrl;

if (trackWithUrl.firstDownloadPath != null || trackWithUrl.cachedPath != null) {
  await _audioService.playFile(url);  // 文件可能不存在！
}
```

**风险**: `firstDownloadPath` 只返回 `downloadPaths[0]`，不检查文件是否存在。如果用户手动删除了文件，播放会失败。

**解决方案**:
```dart
// 方案 A: 使用 DownloadStatusCache
final cache = ref.read(downloadStatusCacheProvider.notifier);
final existingPath = cache.getFirstExistingPathSync(track);

// 方案 B: 直接检查文件
String? localPath;
for (final path in track.downloadPaths) {
  if (await File(path).exists()) {
    localPath = path;
    break;
  }
}
```

---

#### 2. `_getDownloadBaseDir` 实现重复
**位置**: 4 个文件中有几乎相同的代码

| 文件 | 方法 | 行号 |
|------|------|------|
| `download_service.dart` | `_getDefaultDownloadDir()` | 596-616 |
| `import_service.dart` | `_getDownloadBaseDir()` | 489-509 |
| `playlist_service.dart` | `_getDownloadBaseDir()` | 247-267 |
| `playlist_folder_migrator.dart` | `_getDefaultDownloadDir()` | 197-210 |

**问题**: 代码重复，且 `PlaylistFolderMigrator` 使用 `Platform.environment` 而其他三个使用 `path_provider`，虽然结果相同但实现不一致。

**解决方案**:
```dart
// 在 DownloadPathUtils 中添加静态方法
class DownloadPathUtils {
  static Future<String> getDefaultBaseDir(SettingsRepository settingsRepo) async {
    final settings = await settingsRepo.get();
    if (settings.customDownloadDir?.isNotEmpty == true) {
      return settings.customDownloadDir!;
    }
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return p.join(extDir.parent.parent.parent.parent.path, 'Music', 'FMP');
      }
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, 'FMP');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, 'FMP');
  }
}
```

---

### 🟡 中优先级问题

#### 3. `cachedPath` 字段从未被设置
**位置**: `track.dart:50`

**问题**: 代码中读取 `track.cachedPath` 但从未写入，该字段始终为 `null`。

**分析**: 可能是为未来的流媒体缓存功能预留的字段。

**建议**: 
- 如果不实现缓存功能，移除该字段以减少困惑
- 如果计划实现，添加 `// TODO: 实现流媒体缓存` 注释

---

#### 4. `localCoverPath` 使用同步 I/O
**位置**: `track_extensions.dart:8-14`

**问题代码**:
```dart
String? get localCoverPath {
  if (firstDownloadPath == null) return null;
  final dir = Directory(firstDownloadPath!).parent;
  final coverPath = '${dir.path}/cover.jpg';
  return File(coverPath).existsSync() ? coverPath : null;  // 阻塞！
}
```

**风险**: 在 build 方法中调用时会阻塞 UI 线程。

**解决方案**:
```dart
// 方案 A: 改为异步方法
Future<String?> getLocalCoverPath() async {
  if (firstDownloadPath == null) return null;
  final coverPath = '${Directory(firstDownloadPath!).parent.path}/cover.jpg';
  return await File(coverPath).exists() ? coverPath : null;
}

// 方案 B: 使用缓存（类似 DownloadStatusCache）
```

---

### 🟢 低优先级问题

#### 5. 歌单页面 vs 已下载页面数据源不一致
**问题**: 两个页面使用不同的数据来源判断下载状态

| 页面 | 数据来源 | 检测方式 |
|------|---------|---------|
| `playlist_detail_page` | 数据库 Track | `DownloadStatusCache.isDownloadedForPlaylist()` |
| `downloaded_category_page` | 文件扫描 | 文件存在即已下载 |

**潜在问题**: 数据库中的 `downloadPaths` 可能与实际文件不同步。

**建议**: 可以接受，但应在删除文件时同步更新数据库。

---

#### 6. "正在播放"判断方式不一致
**位置**:
- `downloaded_category_page.dart:602`: 使用 `firstDownloadPath` 比较
- `playlist_detail_page.dart:535-540`: 使用 `sourceId + pageNum` 比较

**建议**: 统一使用 `sourceId + pageNum` 或 `track.id` 比较。

---

## 二、代码清理完成确认

以下功能已在重构中移除，确认代码库中不再存在：

| 功能 | 状态 |
|------|------|
| `DownloadService.syncDownloadedFiles()` | ✅ 已移除 |
| `TrackRepository.findBestMatchForRefresh()` | ✅ 已移除 |
| `TrackRepository.getBySourceIdPrefix()` | ✅ 已移除 |
| `downloaded_page.dart` 中的 sync 调用 | ✅ 已移除 |
| `downloadedPath` 单一路径字段 | ✅ 已替换为 `downloadPaths` |
| `downloadedPlaylistIds` 字段 | ✅ 已替换为 `playlistIds` |

---

## 三、推荐的修复优先级

1. **立即修复**: 播放时验证本地文件存在性（用户体验直接影响）
2. **近期修复**: 统一 `_getDownloadBaseDir` 实现（代码维护性）
3. **可选修复**: 其他问题可在后续迭代中处理

---

## 四、核心系统逻辑总结

### 下载路径获取流程
```
用户导入/添加歌曲 → PlaylistService/ImportService
                  → DownloadPathUtils.computeDownloadPath(baseDir, playlistName, track)
                  → track.setDownloadPath(playlistId, computedPath)
                  → 保存到数据库
```

### 已下载标记显示流程
```
进入歌单页面 → build 检测 tracks.length 变化
            → addPostFrameCallback
            → downloadStatusCache.refreshCache(tracks)
            → 异步 File.exists() 检测
            → 更新 state
            → ref.watch 触发 UI 重建
            → isDownloadedForPlaylist() 返回缓存值
```

### 本地文件播放流程
```
播放歌曲 → AudioController._playTrack()
        → track.firstDownloadPath ?? track.cachedPath ?? track.audioUrl
        → 是本地路径 ? audioService.playFile() : audioService.playUrl()
```

### 已下载页面显示流程
```
进入已下载页面 → downloadedCategoriesProvider
              → 扫描下载目录子文件夹
              → DownloadScanner.countAudioFiles()
              → 返回 DownloadedCategory 列表

进入分类详情 → downloadedCategoryTracksProvider(folderPath)
            → DownloadScanner.scanFolderForTracks()
            → 读取 metadata.json 恢复 Track 信息
```
