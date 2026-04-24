# FMP 下载系统补充说明

核心规则已合并到 `CLAUDE.md`。此文件只记录下载系统的详细实现和边界情况。

## 核心流程

```
UI
 ├─ FileExistsCache：缓存本地文件存在性，避免 UI build 同步 IO
 └─ DownloadService：任务调度，按 savePath 去重
      │
      ├─ DownloadPathUtils：统一路径计算
      ├─ DownloadPathManager：用户选择/保存下载目录
      └─ DownloadPathSyncService：扫描本地文件并同步 DB
```

## 下载目录结构

```
{baseDir}/
├── {playlistName}/
│   └── {sourceId}_{videoTitle}/
│       ├── metadata.json          # 单 P
│       ├── metadata_P01.json      # 多 P
│       ├── cover.jpg
│       ├── avatar.jpg             # 创作者头像，存于视频文件夹内
│       ├── audio.m4a              # 单 P 音频
│       └── P01.m4a                # 多 P 音频
└── 未分类/
```

当前头像方案：`DownloadService._saveMetadata()` 下载到视频文件夹内的 `avatar.jpg`；`TrackExtensions.getLocalAvatarPath()` 从所有下载路径对应的视频文件夹查找。`DownloadPathUtils.getAvatarPath()` / `ensureAvatarDirExists()` 是旧集中式头像目录工具，避免在新代码中使用。

## 关键行为

- 下载任务按 `savePath` 去重，不按 trackId 去重。
- 下载完成后才保存 `Track.playlistInfo[].downloadPath`。
- 写入 DB 前验证文件存在。
- Windows 下载在 isolate 中执行，避免 PostMessage 队列溢出。
- 下载进度优先保存在内存 provider，完成/暂停/失败时再落 DB，避免 Isar watch 高频重建。
- `FileExistsCache` 只缓存存在的路径，最大 5000 条；UI 中用 `ref.watch(fileExistsCacheProvider)` 触发重建，用 notifier 调方法。

## 路径与权限

- `DownloadPathUtils.getDefaultBaseDir()` 优先使用 `settings.customDownloadDir`。
- Android 默认路径通过 `getExternalStorageDirectory()` 推导到 `Music/FMP`，失败时 fallback 到 app documents。
- Android 手动选择目录会先走 `StoragePermissionService.requestStoragePermission()`：Android 11+ 使用 `MANAGE_EXTERNAL_STORAGE`，旧版本使用 storage permission。
- Windows/桌面选择目录后会创建 `.fmp_test` 验证写入权限。

## 歌单重命名

歌单重命名时不自动移动文件夹：
1. 清除该歌单相关 Track 的下载路径，保留歌单关联。
2. UI 提示用户手动移动文件夹。
3. 用户从已下载页面同步本地文件以重新关联。

原因：跨盘、权限、目标已存在等文件移动失败场景复杂，保持用户主导更安全。

## 同步本地文件

`DownloadPathSyncService.syncLocalFiles()` 根据 sourceId + sourceType + cid（多 P 还看 pageNum）匹配本地 metadata/audio 到数据库。孤儿文件不会自动写入 DB，需用户明确同步。

## 常见问题

### `StateNotifierListenerError`

症状：`Tried to modify a provider while the widget tree was building`。

处理：不要在 build 中直接修改 state；改到事件回调，或用 `Future.microtask()` 延迟。

### 下载标记不显示

- Widget 要 watch `fileExistsCacheProvider`。
- 下载完成后调用 `cache.markAsExisting(path)` 或 invalidate/refresh 对应 provider。
- FutureProvider 数据源变更后必须 `ref.invalidate()`。
