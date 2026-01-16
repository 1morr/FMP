# FMP 下载系统文档

## 架构概览

```
UI (playlist_detail_page, downloaded_page)
           │
           ▼
┌─────────────────────────────────────┐
│       DownloadStatusCache           │  ← 缓存文件存在性
│       DownloadService               │  ← 任务调度
└─────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│      DownloadPathUtils              │  ← 路径计算（统一入口）
└─────────────────────────────────────┘
```

---

## 核心设计：预计算路径模式

### Track 模型关键字段

```dart
class Track {
  List<int> playlistIds = [];      // 关联的歌单 ID
  List<String> downloadPaths = []; // 对应的预计算下载路径
  
  String? getDownloadPath(int playlistId);  // 获取指定歌单的路径
  void setDownloadPath(int playlistId, String path);  // 设置路径
  String? get firstDownloadPath;  // 第一个路径（不验证存在性）
}

// TrackExtensions (lib/core/extensions/track_extensions.dart)
extension TrackExtensions on Track {
  String? get localAudioPath;  // 第一个实际存在的音频路径
  bool get hasLocalAudio;      // 是否有本地音频
  bool get isDownloaded;       // 是否已下载（= hasLocalAudio）
}
```

### 路径计算规则

```
{baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a

示例：
C:\Users\xxx\Documents\FMP\我的收藏\BV1xxx_视频标题\P01.m4a
```

**路径计算时机**：歌曲加入歌单时（导入/刷新/手动添加）

---

## 关键组件

### 1. DownloadPathUtils (`lib/services/download/download_path_utils.dart`)

- `computeDownloadPath()` - 计算下载路径
- `getDefaultBaseDir()` - 获取基础目录（**唯一入口，其他文件调用此方法**）
- `sanitizeFileName()` - 清理文件名特殊字符
- `extractSourceIdFromFolderName()` - 从文件夹名提取 sourceId

### 2. DownloadStatusCache (`lib/providers/download/download_status_cache.dart`)

避免 UI build 时阻塞 I/O：

```dart
// 正确用法
ref.watch(downloadStatusCacheProvider);  // 监听状态
final cache = ref.read(downloadStatusCacheProvider.notifier);
final isDownloaded = cache.isDownloadedForPlaylist(track, playlistId);
```

### 3. DownloadService (`lib/services/download/download_service.dart`)

- 并发控制（默认 3 个）
- 进度节流（500ms 或 5%）
- 下载前检查文件是否已存在

### 4. DownloadScanner (`lib/providers/download/download_scanner.dart`)

已下载页面数据源：扫描文件系统，不依赖数据库

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

## 常见问题解决

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

## 路由

- `/library/downloaded` → DownloadedPage（已下载分类列表）
- `/library/downloaded/:folderPath` → DownloadedCategoryPage（分类详情）
- `/settings/download-manager` → DownloadManagerPage（任务管理）
