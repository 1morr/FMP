# 下载管理系统 - 实现状态

## 更新记录
- 2026-01-14: 完成预计算路径重构，移除 sync 功能，新增 DownloadStatusCache

## 实现状态
✅ **全部功能已完成**

## 核心架构变更（2026-01-14）

### Track 模型字段变更

| 旧字段 | 新字段 | 说明 |
|--------|--------|------|
| `downloadedPath: String?` | `downloadPaths: List<String>` | 支持多歌单下载 |
| `downloadedPlaylistIds: List<int>` | `playlistIds: List<int>` | 简化命名 |

### 新增组件

| 组件 | 位置 | 功能 |
|------|------|------|
| `DownloadPathUtils` | `lib/services/download/download_path_utils.dart` | 统一路径计算 |
| `DownloadStatusCache` | `lib/providers/download/download_status_cache.dart` | 文件存在性缓存 |
| `PlaylistFolderMigrator` | `lib/services/library/playlist_folder_migrator.dart` | 歌单文件夹重命名 |

### 移除的功能

| 功能 | 原位置 | 移除原因 |
|------|--------|---------|
| `syncDownloadedFiles()` | `DownloadService` | 预计算模式无需同步 |
| `findBestMatchForRefresh()` | `TrackRepository` | 预计算模式无需匹配 |
| `getBySourceIdPrefix()` | `TrackRepository` | 不再需要前缀匹配 |

## 文件结构

### 新增文件
- `lib/services/download/download_path_utils.dart` - 路径计算工具
- `lib/providers/download/download_status_cache.dart` - 状态缓存
- `lib/services/library/playlist_folder_migrator.dart` - 文件夹迁移
- `lib/providers/download/download_scanner.dart` - 文件扫描器
- `lib/ui/pages/library/downloaded_category_page.dart` - 分类详情页

### 修改文件
- `lib/data/models/track.dart` - 字段重构
- `lib/services/download/download_service.dart` - 使用预计算路径
- `lib/services/import/import_service.dart` - 导入时计算路径
- `lib/services/library/playlist_service.dart` - 添加歌曲时计算路径
- `lib/ui/pages/library/playlist_detail_page.dart` - 使用 DownloadStatusCache

## 路由
- `/library/downloaded` → DownloadedPage
- `/library/downloaded/:folderPath` → DownloadedCategoryPage
- `/settings/download-manager` → DownloadManagerPage

## 关键实现细节

### 1. 路径预计算流程
```
导入歌单 → ImportService.importFromUrl()
         → 保存 Playlist 获取 ID
         → 对每个 Track 调用 DownloadPathUtils.computeDownloadPath()
         → track.setDownloadPath(playlistId, path)
         → 保存 Track
```

### 2. 下载状态检测流程
```
进入歌单页面 → initState/build
            → 检测 tracks.length 变化
            → WidgetsBinding.addPostFrameCallback
            → downloadStatusCache.refreshCache(tracks)
            → 异步检测文件存在性
            → 更新 state
            → ref.watch 触发 UI 重建
```

### 3. 播放时使用本地文件
```
播放歌曲 → AudioController._playTrack()
        → track.firstDownloadPath ?? track.cachedPath ?? track.audioUrl
        → 如果是本地路径，调用 audioService.playFile()
        → 否则调用 audioService.playUrl()
```

## 待优化项（参见 code_issues_2026-01-14）

1. `firstDownloadPath` 不验证文件存在性
2. `_getDownloadBaseDir` 重复实现
3. `localCoverPath` 使用同步 I/O
4. `cachedPath` 字段未使用
