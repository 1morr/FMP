# 性能与内存优化记录

## 1. 图片缓存限制过低导致缓存抖动

**文件**: `lib/main.dart`

**问题**: 移动端图片缓存限制为 30 张 / 10 MB，但首页同时可见约 50 张缩略图（歌单卡片 + 历史记录 + 排行榜预览）。缓存容量不足导致图片频繁被驱逐后重新解码，浪费 CPU 并造成滚动卡顿。

**修复**:
- 移动端：30 张 / 10 MB → 100 张 / 50 MB
- 桌面端：100 张 / 30 MB → 200 张 / 80 MB

**原因**: 配合 `ThumbnailUrlUtils` 优化后，每张缩略图解码后约 160 KB（200×200×4 bytes）。100 张仅占 ~16 MB 解码内存，远低于 50 MB 上限。增大缓存消除了抖动，避免重复解码开销。

---

## 2. 后台服务在首帧渲染前初始化

**文件**: `lib/main.dart`

**问题**: `RankingCacheService` 和 `RadioRefreshService` 在 `runApp()` 之前创建和初始化。虽然 `initialize()` 未被 await，但对象创建、Timer 注册、以及 Dart 事件循环中的微任务调度仍会与首帧渲染竞争 CPU 时间。

**修复**: 使用 `WidgetsBinding.instance.addPostFrameCallback` 将这两个服务的创建延迟到首帧渲染完成后。

**原因**: 用户看到首屏 UI 的速度是启动体验的关键。排行榜缓存和电台刷新是后台任务，延迟几百毫秒对用户无感知影响。

---

## 3. QueueManager 启动时立即执行全表扫描

**文件**: `lib/services/audio/queue_manager.dart`

**问题**: `_cleanupOrphanTracks()` 在 `initialize()` 中通过 `unawaited()` 立即执行，会查询整个 Track 表来查找孤立记录。这与队列加载、设置读取等启动操作竞争数据库 I/O。

**修复**: 将 `_cleanupOrphanTracks()` 延迟 10 秒执行（`Future.delayed(Duration(seconds: 10), ...)`）。

**原因**: 孤立 Track 清理是维护性操作，不影响用户体验。延迟执行让启动阶段的数据库 I/O 集中在关键路径上（加载队列、读取设置）。

---

## 4. ListView/GridView 缺少 cacheExtent

**文件**:
- `lib/ui/pages/explore/explore_page.dart`
- `lib/ui/pages/history/play_history_page.dart`
- `lib/ui/pages/library/library_page.dart`
- `lib/ui/pages/library/downloaded_page.dart`
- `lib/ui/pages/radio/radio_page.dart`

**问题**: 使用默认 `cacheExtent`（约 250px），快速滚动时视口外的项目来不及构建，出现空白闪烁。图片密集的列表/网格尤为明显。

**修复**: 为所有图片密集的 ListView/GridView 添加 `cacheExtent: 500`。

**原因**: 预加载视口外 500px 的项目，给图片加载留出更多缓冲时间。代价是多构建几个屏幕外的 widget，但配合 RepaintBoundary 后开销可控。

---

## 5. 列表项缺少 RepaintBoundary

**文件**:
- `lib/ui/pages/explore/explore_page.dart`
- `lib/ui/pages/history/play_history_page.dart`
- `lib/ui/pages/library/playlist_detail_page.dart`

**问题**: 当某个列表项状态变化（如播放指示器动画），Flutter 可能重绘相邻的列表项。在 100+ 项的排行榜中，这会导致不必要的 GPU 开销。

**修复**: 在 `itemBuilder` 中用 `RepaintBoundary` 包裹每个列表项。

**原因**: `RepaintBoundary` 创建独立的绘制层，将重绘范围限制在单个列表项内。队列页面（`queue_page.dart`）已有此优化，现在统一应用到其他页面。
