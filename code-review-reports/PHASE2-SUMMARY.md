# Phase 2 性能优化 — 修复总结

**日期**: 2026-02-17
**修改文件**: 3 个
**flutter analyze**: ✅ No issues found

---

## 审查结论

Phase 2 共 5 个任务，审查代码后决定修复 2 个、跳过 3 个：

| 任务 | 判断 | 原因 |
|------|------|------|
| 2.1 PlaylistDetailPage 分组缓存 | ❌ 跳过 | 代码中已有 `_cachedTracks`/`_cachedGroups`/`_getGroupedTracks()` 缓存逻辑 |
| 2.2 HomePage 过度 rebuild | ✅ 已修复 | 确实存在：任一 provider 变化触发整页 rebuild |
| 2.3 FileExistsCache 预加载 | ❌ 跳过 | PlaylistDetailPage 已有 `_preloadCoverPaths`，其他页面收益不确定 |
| 2.4 PlayerPage const 优化 | ❌ 跳过 | PlayerPage 整体依赖 `audioControllerProvider`，可 const 化的部分已经是 const |
| 2.5 文件删除异步化 | ✅ 已修复 | 批量删除在 UI 线程逐个执行文件 I/O，确实阻塞 |

---

## 修复详情

### Task 2.2: HomePage 过度 rebuild 优化

**文件**: `lib/ui/pages/home/home_page.dart`

**问题**: `_HomePageState.build()` 中通过 `ref.watch` 监听了 6+ 个 provider（排行榜×2、缓存服务、歌单列表、电台状态、播放历史）。任何一个 provider 变化都会触发整个 `build()` 重新执行，导致所有 section 全量重建。

**修复**: 将 4 个 section 从 `_HomePageState` 的实例方法提取为独立的 `ConsumerWidget`：

```
修改前:
_HomePageState.build()
  ├── _buildMusicRankings()     ← ref.watch(bilibili + youtube + cache)
  ├── _buildRecentPlaylists()   ← ref.watch(allPlaylistsProvider)
  ├── _buildRadioSection()      ← ref.watch(radioControllerProvider)
  ├── const _NowPlayingSection()     ← 已独立
  ├── const _QueuePreviewSection()   ← 已独立
  └── _buildRecentHistory()     ← ref.watch(recentPlayHistoryProvider)

修改后:
_HomePageState.build()          ← 只保留 ref.listen（电台错误 Toast）+ 布局
  ├── const _MusicRankingsSection()    ← 独立 ConsumerWidget
  ├── const _RecentPlaylistsSection()  ← 独立 ConsumerWidget
  ├── const _RadioSection()            ← 独立 ConsumerWidget
  ├── const _NowPlayingSection()
  ├── const _QueuePreviewSection()
  └── const _RecentHistorySection()    ← 独立 ConsumerWidget
```

**效果**: 排行榜数据刷新时，歌单/电台/历史 section 不再重建；反之亦然。每个 section 只在自己监听的 provider 变化时 rebuild。

**注意事项**:
- `_RadioSection` 和 `_RecentHistorySection` 的菜单/对话框方法（`_showRadioDeleteConfirm`、`_handleHistoryMenuAction` 等）随 section 一起迁移，方法签名增加了 `WidgetRef ref` 参数
- `_HomePageState` 现在只保留 `ref.listen` 用于电台错误 Toast 显示（`ref.listen` 不触发 rebuild）

---

### Task 2.5: 文件删除异步化

**文件**:
- `lib/ui/pages/library/downloaded_category_page.dart`
- `lib/ui/pages/library/downloaded_page.dart`

**问题**: 删除下载文件时，所有文件 I/O（exists 检查、delete、目录遍历、递归删除）都在 UI 线程执行。批量删除 100 首歌时，逐个文件操作会阻塞主线程 2-3 秒，UI 完全冻结。

**修复**: 使用 `compute()` 将文件 I/O 移到独立 Isolate，DB 操作和 provider 刷新保留在主线程。

新增两个顶层函数（`downloaded_category_page.dart`）：

```dart
/// 批量删除：删除文件 + 清理父文件夹
Future<void> _deleteFilesInIsolate(List<String> paths) async { ... }

/// 单曲删除：删除音频 + metadata + 空文件夹检测
Future<void> _deleteTrackFilesInIsolate(List<String> paths) async { ... }
```

新增一个顶层函数（`downloaded_page.dart`）：

```dart
/// 删除整个分类文件夹
Future<void> _deleteFolderInIsolate(String folderPath) async { ... }
```

**调用方式变化**:

```dart
// 修改前（UI 线程阻塞）
for (final path in paths) {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

// 修改后（Isolate 执行）
await compute(_deleteFilesInIsolate, allPaths);
// DB 操作仍在主线程
for (final track in tracks) {
  await trackRepo.clearDownloadPath(track.id);
}
```

**设计决策**:
- 顶层函数而非类方法：`compute()` 要求传入顶层或 static 函数
- 文件操作异常用 `on FileSystemException catch` 静默处理：单个文件失败不应中断整个批量操作
- DB 操作不进 Isolate：Isar 实例不能跨 Isolate 传递
