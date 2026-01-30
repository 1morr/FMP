# FMP 下载系统文档

## 架构概览

```
UI (playlist_detail_page, downloaded_page)
           │
           ▼
┌─────────────────────────────────────┐
│       FileExistsCache               │  ← 缓存文件存在性（避免同步 IO）
│       DownloadService               │  ← 任务调度
└─────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│      DownloadPathUtils              │  ← 路径计算（统一入口）
└─────────────────────────────────────┘
```

---

## 核心设计：按需路径模式（2026-01 重构）

### 设计变更
**旧模式（已废弃）**：歌曲加入歌单时预计算下载路径
**新模式**：下载路径仅在实际下载完成时保存

### Track 模型关键字段

```dart
class Track {
  List<int> playlistIds = [];      // 关联的歌单 ID
  List<String> downloadPaths = []; // 实际下载完成后的路径
}

// TrackExtensions (lib/core/extensions/track_extensions.dart)
extension TrackExtensions on Track {
  bool get isDownloaded;           // downloadPaths.isNotEmpty（简化判断）
  String? get localAudioPath;      // 第一个实际存在的音频路径
  List<String> get validDownloadPaths;  // 过滤出实际存在的路径
  bool get hasLocalAudio;          // localAudioPath != null
}
```

### 路径设置时机
- **添加歌曲到歌单**：只添加 playlistId，不设置 downloadPath
- **下载完成时**：由 DownloadService 调用 `trackRepository.addDownloadPath()` 保存实际路径

### TrackRepository 新方法
```dart
Future<void> addDownloadPath(int trackId, int? playlistId, String path);
Future<void> clearAllDownloadPaths();
Future<int> cleanupInvalidDownloadPaths();  // 清理无效路径，返回清理数量
```

---

## 关键组件

### 1. DownloadPathUtils (`lib/services/download/download_path_utils.dart`)

- `computeDownloadPath()` - 计算下载路径
- `getDefaultBaseDir()` - 获取基础目录（**唯一入口，其他文件调用此方法**）
- `sanitizeFileName()` - 清理文件名特殊字符
- `extractSourceIdFromFolderName()` - 从文件夹名提取 sourceId

### 2. FileExistsCache (`lib/providers/download/file_exists_cache.dart`)

**Phase 6 简化** - 避免 UI build 时阻塞 I/O。

状态类型：`Set<String>`（只缓存存在的路径）

```dart
// 正确用法
ref.watch(fileExistsCacheProvider);  // 监听状态
final cache = ref.read(fileExistsCacheProvider.notifier);

// 核心方法
cache.exists(path);               // 检查路径是否存在（带缓存）
cache.getFirstExisting(paths);    // 返回第一个存在的路径

// 缓存管理
await cache.preloadPaths(paths);  // 批量预加载
cache.markAsExisting(path);       // 标记已存在（下载完成后调用）
cache.remove(path);               // 移除缓存
cache.clearAll();                 // 清空所有缓存

// 注意：Track 相关方法已移除（isDownloadedForPlaylist, hasAnyDownload 等）
// 下载状态判断改为：track.downloadPaths.any((p) => cache.exists(p))
```

### 3. DownloadService (`lib/services/download/download_service.dart`)

- 并发控制（默认 3 个）
- **批量添加模式**（2026-01-18 更新）：
  - `addTrackDownload` 支持 `skipSchedule` 参数
  - 批量添加时设为 `true` 避免每个任务都触发调度
  - 所有任务添加完成后调用 `triggerSchedule()` 统一开始下载
  - 确保"暂停全部"能暂停所有任务（而非只暂停已添加的部分）
- **全局进度节流**（2026-01-17 更新）：
  - 500ms 或 5% 进度变化时才更新
  - 使用 `_lastGlobalProgressUpdate` 和 `_lastGlobalProgressValue` 全局追踪
  - 下载完成（100%）总是立即触发更新
  - 有效减少 UI 重建频率，提升性能
- 下载前检查文件是否已存在

**进度节流实现：**
```dart
DateTime? _lastGlobalProgressUpdate;
double _lastGlobalProgressValue = 0.0;

void _maybeNotifyProgress(double progress) {
  final now = DateTime.now();
  final timeSinceLastUpdate = _lastGlobalProgressUpdate == null
      ? const Duration(seconds: 1)
      : now.difference(_lastGlobalProgressUpdate!);
  final progressDelta = (progress - _lastGlobalProgressValue).abs();
  
  // 只有满足条件才更新
  if (progress >= 1.0 || timeSinceLastUpdate >= const Duration(milliseconds: 500) || progressDelta >= 0.05) {
    _lastGlobalProgressUpdate = now;
    _lastGlobalProgressValue = progress;
    _progressController.add(progress);
  }
}
```

### 4. DownloadScanner (`lib/providers/download/download_scanner.dart`)

已下载页面数据源：扫描文件系统，不依赖数据库

### 5. DownloadPathSyncService (`lib/services/download/download_path_sync_service.dart`)

**Phase 4 新增** - 负责扫描本地文件并同步到数据库

```dart
class DownloadPathSyncService {
  /// 同步本地文件到数据库
  /// 返回 (更新数量, 孤儿文件数量)
  Future<(int updated, int orphans)> syncLocalFiles({
    void Function(int current, int total)? onProgress,
  });

  /// 清理无效的下载路径
  Future<int> cleanupInvalidPaths();

  /// 获取孤儿文件列表（本地存在但数据库无匹配）
  Future<List<OrphanFileInfo>> getOrphanFiles();
}

// Provider
final downloadPathSyncServiceProvider = Provider<DownloadPathSyncService>(...);
```

**匹配规则**：sourceId + sourceType + cid (+ pageNum for multi-part videos)

**使用场景**：
- 已下载页面的"同步本地文件"按钮
- 用户更换下载路径后重新扫描

---

## 文件结构

```
{下载路径}/
├── {歌单名}/
│   ├── playlist_cover.jpg           ← 歌单封面
│   ├── {sourceId}_{视频标题}/       ← 每个视频一个文件夹
│   │   ├── metadata.json            ← 歌曲元数据
│   │   ├── cover.jpg                ← 视频封面
│   │   └── P01.m4a (或 audio.m4a)   ← 音频文件
│   └── ...
└── 未分类/                          ← 不属于任何歌单的下载
```

---

## 歌单重命名与下载文件

### 设计决策（2026-01-18）
歌单重命名时**不再自动移动**已下载的文件夹。原因：
- 文件移动可能失败（权限、跨盘、目标存在等）
- 用户可能不希望文件被自动移动
- 减少潜在的数据丢失风险

### 当前行为
1. `PlaylistService.updatePlaylist()` 返回 `PlaylistUpdateResult`
2. 如果旧下载文件夹存在，结果包含 `oldDownloadFolder` 和 `newDownloadFolder`
3. UI 显示提示框，告知用户手动移动文件夹

### 相关代码
- `PlaylistUpdateResult` - 更新结果类（`playlist_service.dart`）
- `CreatePlaylistDialog._showFileMigrationWarning()` - 显示手动移动提示

**注意**：`PlaylistFolderMigrator` 已在 Phase 6 删除（不再需要预计算路径更新）

---

$1

### StateNotifierListenerError
**症状**：`Tried to modify a provider while the widget tree was building`
**解决**：使用 `Future.microtask()` 延迟状态更新

### 下载标记不显示
**解决**：
1. build 中检测 tracks 变化并调用 `refreshCache`
2. `ref.watch(provider)` 监听 + `ref.read(provider.notifier)` 调用方法

### 歌单封面不显示本地图片
**原因**：`_findPlaylistLocalCover` 使用了错误的文件夹格式
**解决**：使用 `DownloadPathUtils.sanitizeFileName(playlist.name)`，不加 `_ID` 后缀

---

### 6. ChangeDownloadPathDialog (`lib/ui/widgets/change_download_path_dialog.dart`)

**Phase 5 新增** - 更改下载路径的对话框组件

```dart
class ChangeDownloadPathDialog {
  /// 显示更改下载路径对话框
  /// 流程：确认 → 选择新路径 → 清空数据库路径 → 保存新路径
  static Future<void> show(BuildContext context, WidgetRef ref);
}
```

**功能**：
- 两次确认防止误操作
- 显示加载状态（选择文件夹中、更新设置中）
- 清空所有 Track 的 downloadPaths
- 刷新相关 Provider（fileExistsCacheProvider, downloadedCategoriesProvider, downloadPathProvider）
- 提示用户点击刷新按钮扫描本地文件

**使用场景**：
- 设置页面的"更改下载路径"选项

---

## 路由

- `/library/downloaded` → DownloadedPage（已下载分类列表）
- `/library/downloaded/:folderPath` → DownloadedCategoryPage（分类详情）
- `/settings/download-manager` → DownloadManagerPage（任务管理）
