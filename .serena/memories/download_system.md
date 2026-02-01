# FMP 下载系统文档

## 架构概览

```
UI (playlist_detail_page, downloaded_page)
           │
           ▼
┌─────────────────────────────────────┐
│       FileExistsCache               │  ← 缓存文件存在性（避免同步 IO）
│       DownloadService               │  ← 任务调度（按 savePath 去重）
└─────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│      DownloadPathUtils              │  ← 路径计算（统一入口）
└─────────────────────────────────────┘
```

### 2026-02 重构：简化下载系统

**核心变更：**
1. **A1**: 更改下载路径 → 清空所有 DB 路径和已完成/失败任务
2. **A2**: 任务按 `savePath` 去重（非 trackId），启动时清理已完成/失败任务
3. **A3**: 验证文件存在后才保存路径
4. **B1**: 播放时检查所有路径，使用第一个存在的，仅清除不存在的
5. **B2**: 仅在文件不存在时清除路径（非封面缺失等）
6. **C1**: 同步时跳过无 metadata 的本地文件
7. **C2**: 本地文件添加 playlistId=0
8. **C3**: 同步时 REPLACE 所有 DB 路径（本地文件是权威来源）
9. **D1-D3**: Provider 使用 debouncing 批量刷新
10. **E2**: 删除歌单 → 仅移除该歌单关联，保留其他引用和文件
11. **E3**: 从歌单移除歌曲 → 移除该歌单的路径和关联

---

## 核心设计：按需路径模式（2026-01 重构）

### 设计变更
**旧模式（已废弃）**：歌曲加入歌单时预计算下载路径
**新模式**：下载路径仅在实际下载完成时保存

### Track 模型新增方法

```dart
// 检查是否已为指定歌单下载
bool isDownloadedForPlaylist(int playlistId);

// getDownloadPath(playlistId) 已存在
```

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

## Android 存储权限（2026-01-31 新增）

### 问题背景
Android 10+ 引入分区存储（Scoped Storage），传统的 `WRITE_EXTERNAL_STORAGE` 权限不再有效。
`file_picker.getDirectoryPath()` 返回的路径字符串无法直接通过 `dart:io` 的 `File` 类访问。

### 解决方案
使用 `MANAGE_EXTERNAL_STORAGE` 权限（Android 11+）访问外部存储。

### 关键文件

**AndroidManifest.xml**:
```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
    tools:ignore="ScopedStorage"/>
```

**StoragePermissionService** (`lib/services/storage_permission_service.dart`):
```dart
class StoragePermissionService {
  /// 检查存储权限
  static Future<bool> hasStoragePermission();
  
  /// 请求存储权限（带解释对话框）
  static Future<bool> requestStoragePermission(BuildContext context);
}
```

### 权限请求流程
1. 用户点击选择下载路径
2. `DownloadPathManager.selectDirectory()` 调用 `StoragePermissionService.requestStoragePermission()`
3. 显示解释对话框："为了将音乐下载到您选择的文件夹，应用需要访问设备存储的权限..."
4. 用户点击"继续"后跳转到系统设置页面
5. 用户在设置中允许 FMP 访问所有文件
6. 返回应用后选择下载文件夹

### 注意事项
- Google Play 对 `MANAGE_EXTERNAL_STORAGE` 有特殊要求，上架需提交权限使用说明
- 权限被永久拒绝时，引导用户去设置页面手动开启
- 非 Android 平台不需要此权限流程

---

## 关键组件

### 1. DownloadPathUtils (`lib/services/download/download_path_utils.dart`)

- `computeDownloadPath()` - 计算下载路径
- `getDefaultBaseDir()` - 获取基础目录（**唯一入口，其他文件调用此方法**）
- `sanitizeFileName()` - 清理文件名特殊字符
- `extractSourceIdFromFolderName()` - 从文件夹名提取 sourceId

### 2. FileExistsCache (`lib/providers/download/file_exists_cache.dart`)

**用途** - 避免 UI build 时阻塞 I/O，缓存文件存在性检查结果。

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

**主要使用场景**:
- `TrackThumbnail` / `PlaylistCover` - 检查本地封面是否存在
- `TrackDetailPanel` / `PlayerPage` - 显示本地图片
- `PlaylistDetailPage` - 预加载封面路径
- 下载完成后标记文件存在，触发 UI 更新

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

**包含的类**:
- `DownloadedCategory` - 已下载分类（文件夹）数据模型
- `ScanCategoriesParams` - Isolate 扫描参数
- `DownloadScanner` - 扫描工具类

**关键方法**:
- `scanCategoriesInIsolate()` - 在 Isolate 中扫描已下载分类，返回 `List<DownloadedCategory>`
- `DownloadScanner.scanFolderForTracks()` - 扫描单个文件夹获取 Track 列表

**注意**: `download_state.dart` 和 `download_extensions.dart` 已删除（2026-02 简化）

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

### 6. DownloadPathManager (`lib/services/download/download_path_manager.dart`)

管理下载路径的选择、验证和持久化。

```dart
class DownloadPathManager {
  /// 检查是否已配置下载路径
  Future<bool> hasConfiguredPath();
  
  /// 选择下载目录（Android 会先请求存储权限）
  Future<String?> selectDirectory(BuildContext context);
  
  /// 保存/获取/清除下载路径
  Future<void> saveDownloadPath(String path);
  Future<String?> getCurrentDownloadPath();
  Future<void> clearDownloadPath();
}
```

**Android 权限集成**：`selectDirectory()` 在 Android 上会先调用 `StoragePermissionService.requestStoragePermission()`，只有权限获得后才进行目录选择。

---

### 7. ChangeDownloadPathDialog (`lib/ui/widgets/change_download_path_dialog.dart`)

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

---

## Android 平台限制（2026-01-31）

### 分区存储 (Scoped Storage) 限制

从 Android 11 开始，应用无法直接使用 File API 访问公共存储目录（如 `/storage/emulated/0/Music`）。`file_picker` 的 `getDirectoryPath()` 返回的传统路径在 Android 11+ 上会抛出 `PathAccessException: Operation not permitted`。

### 解决方案

**DownloadPathUtils.getDefaultBaseDir()** 已修改：
- Android 平台自动使用 `getExternalStorageDirectory()` 返回的私有外部存储目录
- 路径格式：`/storage/emulated/0/Android/data/{package_name}/files/FMP`
- 无需额外权限，应用可自由读写
- 缺点：卸载应用时会被删除（但用户可备份）

**DownloadPathManager.selectDirectory()** 已修改：
- Android 平台禁用手动选择目录
- 显示提示对话框告知用户下载路径自动设置

**设置页面 UI** 已修改：
- Android 平台隐藏"更改下载路径"选项
