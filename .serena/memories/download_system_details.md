# FMP 下载系统详细文档

## 更新记录
- 2026-01-14: 重构为预计算路径模式，移除 syncDownloadedFiles，新增 DownloadStatusCache

## 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                       UI 层                                  │
│  playlist_detail_page, downloaded_page, search_page         │
│                            │                                 │
│                            ▼                                 │
│    downloadServiceProvider + downloadStatusCacheProvider     │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    DownloadService                           │
│              (lib/services/download/download_service.dart)   │
│                                                              │
│  职责：                                                       │
│  - 任务调度（并发控制）                                        │
│  - 文件下载（带进度）                                          │
│  - 元数据保存                                                 │
│  - 封面/头像下载                                              │
│  - 下载前使用预计算的 downloadPaths                           │
└─────────────────────────────────────────────────────────────┘
                             │
┌─────────────────────────────────────────────────────────────┐
│                  DownloadStatusCache                         │
│        (lib/providers/download/download_status_cache.dart)   │
│                                                              │
│  职责：                                                       │
│  - 缓存文件存在性检测结果                                     │
│  - 避免 UI build 时阻塞                                       │
│  - 异步刷新机制（Future.microtask）                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据模型（2026-01-14 更新）

### Track 字段变更

**旧字段（已移除）：**
- `downloadedPath` → 单一路径
- `downloadedPlaylistIds` → 歌单 ID 列表

**新字段：**
```dart
class Track {
  // 预计算的下载路径（按歌单分组）
  List<int> playlistIds = [];      // 关联的歌单 ID 列表
  List<String> downloadPaths = []; // 对应的预计算下载路径列表
  
  // 获取指定歌单的下载路径
  String? getDownloadPath(int playlistId) {
    final index = playlistIds.indexOf(playlistId);
    return index >= 0 && index < downloadPaths.length ? downloadPaths[index] : null;
  }
  
  // 设置指定歌单的下载路径
  void setDownloadPath(int playlistId, String path) {
    final index = playlistIds.indexOf(playlistId);
    if (index >= 0) {
      downloadPaths[index] = path;
    } else {
      playlistIds.add(playlistId);
      downloadPaths.add(path);
    }
  }
  
  // 便捷属性：第一个下载路径（不验证存在性！）
  String? get firstDownloadPath => downloadPaths.isNotEmpty ? downloadPaths.first : null;
}
```

---

## 预计算路径工作流程

### 1. 路径计算时机

路径在**歌曲加入歌单时**预计算，而非下载时：

```dart
// DownloadPathUtils.computeDownloadPath()
static String computeDownloadPath({
  required String baseDir,
  required String playlistName,
  required Track track,
}) {
  // 文件夹名：sourceId_parentTitle（如 BV1xxx_视频标题）
  final folderName = sanitizeFileName(
    '${track.sourceId}_${track.parentTitle ?? track.title}'
  );
  
  // 文件名
  String fileName;
  if (track.pageNum != null && track.pageNum! > 1) {
    fileName = 'P${track.pageNum}.m4a';
  } else {
    fileName = 'P1.m4a';
  }
  
  return p.join(baseDir, playlistName, folderName, fileName);
}
```

### 2. 路径计算触发位置

| 操作 | 服务 | 方法 |
|------|------|------|
| 导入歌单 | ImportService | `importFromUrl()` |
| 刷新歌单 | ImportService | `refreshPlaylist()` |
| 添加歌曲到歌单 | PlaylistService | `addTracksToPlaylist()` |

### 3. 下载时的使用

```dart
// DownloadService.addTrackDownload()
Future<DownloadTask?> addTrackDownload(Track track, {required Playlist fromPlaylist}) async {
  // 1. 获取预计算的路径
  final downloadPath = track.getDownloadPath(fromPlaylist.id);
  if (downloadPath == null) return null;
  
  // 2. 检查文件是否已存在
  if (await File(downloadPath).exists()) {
    return null;  // 跳过已下载
  }
  
  // 3. 创建下载任务，使用预计算的路径
  final task = DownloadTask()
    ..downloadPath = downloadPath;
}
```

---

## 下载状态检测（DownloadStatusCache）

### 设计目的
避免在 UI build 期间执行同步 I/O 操作（File.existsSync），防止卡顿和 StateNotifier 异常。

### 核心方法

```dart
class DownloadStatusCache extends StateNotifier<Map<String, bool>> {
  
  /// 检查歌曲在指定歌单中是否已下载（只读缓存）
  bool isDownloadedForPlaylist(Track track, int playlistId) {
    final path = track.getDownloadPath(playlistId);
    if (path == null) return false;
    
    if (state.containsKey(path)) {
      return state[path]!;  // 返回缓存值
    }
    
    // 未缓存：返回 false，异步刷新
    _scheduleRefresh(path);
    return false;
  }
  
  /// 异步刷新（延迟到下一个 microtask）
  void _scheduleRefresh(String path) {
    Future.microtask(() async {
      if (!state.containsKey(path)) {
        final exists = await File(path).exists();
        state = {...state, path: exists};  // 触发 UI 重建
      }
    });
  }
  
  /// 批量预加载（进入页面时调用）
  Future<void> refreshCache(List<Track> tracks) async {
    final newState = <String, bool>{};
    for (final track in tracks) {
      for (final path in track.downloadPaths) {
        newState[path] = await File(path).exists();
      }
    }
    state = {...state, ...newState};
  }
}
```

### UI 使用模式

```dart
// 正确用法
ref.watch(downloadStatusCacheProvider);  // 监听状态变化，触发重建
final cache = ref.read(downloadStatusCacheProvider.notifier);
final isDownloaded = cache.isDownloadedForPlaylist(track, playlistId);

// 错误用法（会导致 StateNotifierListenerError）
// ref.watch(downloadStatusCacheProvider.notifier).isDownloadedForPlaylist(...)
```

---

## 已移除的功能

### ~~syncDownloadedFiles()~~
**原功能**：扫描下载目录的 metadata.json，与数据库 Track 匹配并恢复 downloadedPath。

**移除原因**：预计算路径模式下，路径在加入歌单时已确定，无需事后同步。

### ~~findBestMatchForRefresh()~~
**原功能**：刷新歌单时使用多级回退匹配查找已存在的 Track。

**移除原因**：预计算路径模式下，Track 的 downloadPaths 字段直接保存，无需复杂匹配。

---

## 基础目录获取（统一实现）

四个位置使用相同逻辑：

```dart
Future<String> _getDownloadBaseDir() async {
  final settings = await _settingsRepository.get();
  
  // 1. 优先使用自定义目录
  if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
    return settings.customDownloadDir!;
  }
  
  // 2. Android: /storage/emulated/0/Music/FMP
  if (Platform.isAndroid) {
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      return p.join(extDir.parent.parent.parent.parent.path, 'Music', 'FMP');
    }
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'FMP');
  }
  
  // 3. Windows: C:\Users\xxx\Documents\FMP
  final docsDir = await getApplicationDocumentsDirectory();
  return p.join(docsDir.path, 'FMP');
}
```

**位置**：
- `DownloadService._getDefaultDownloadDir()`
- `ImportService._getDownloadBaseDir()`
- `PlaylistService._getDownloadBaseDir()`
- `PlaylistFolderMigrator._getDefaultDownloadDir()`（⚠️ 使用 Platform.environment，实现略有不同）

---

## 已下载页面数据源

已下载页面基于**文件系统扫描**，不依赖数据库：

```dart
// 扫描文件夹中的音频文件
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>((ref, folderPath) async {
  return DownloadScanner.scanFolderForTracks(folderPath);
});

// DownloadScanner 从 metadata.json 恢复 Track 信息
```

**优点**：即使数据库损坏，已下载的文件仍可访问和播放。

---

## Provider 结构

```dart
// 核心服务
final downloadServiceProvider = Provider<DownloadService>
final downloadStatusCacheProvider = StateNotifierProvider<DownloadStatusCache, Map<String, bool>>

// 任务列表
final downloadTasksProvider = StreamProvider<List<DownloadTask>>
final activeDownloadsProvider = Provider<List<DownloadTask>>
final completedDownloadsProvider = Provider<List<DownloadTask>>

// 已下载内容
final downloadedCategoriesProvider = FutureProvider<List<DownloadedCategory>>
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>
```

---

## 常见错误与解决

### StateNotifierListenerError
**症状**：`Tried to modify a provider while the widget tree was building`

**原因**：在 build 方法中调用了修改 state 的方法

**解决**：使用 `Future.microtask()` 延迟状态更新

### 下载标记不显示
**症状**：进入歌单页面时下载标记不显示，播放后才显示

**原因**：
1. `initState` 时 tracks 为空
2. 使用 `ref.watch(provider.notifier)` 不触发重建

**解决**：
1. 在 build 中检测 tracks 变化并调用 `refreshCache`
2. 使用 `ref.watch(provider)` 监听状态 + `ref.read(provider.notifier)` 调用方法
