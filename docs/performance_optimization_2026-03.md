# 性能与内存优化记录 (2026-03-19)

## 修复总览

本次优化聚焦于 UI 渲染性能和不必要的 widget 重建，共修复 4 个问题。

---

## 1. NowPlayingIndicator 动画每帧重建 widget 树

**文件:** `lib/ui/widgets/now_playing_indicator.dart`

**问题:** `AnimatedBuilder` 的 `builder` 回调中每帧（60fps）都创建 `SizedBox` → `Row` → 3 个 `Container`，产生大量短生命周期对象。该组件在歌曲列表中被大量使用，每个正在播放的列表项都有一个实例。

**修复:** 替换为 `CustomPainter`，动画帧只触发 canvas 绘制操作，不再创建/销毁 widget。同时添加 `RepaintBoundary` 隔离重绘范围，防止动画导致父级 widget 重绘。

**影响:** 每个 NowPlayingIndicator 实例从每帧创建 ~7 个 widget 降为 0，减少 GC 压力。

---

## 2. LyricsDisplay 监听整个 AudioController 状态

**文件:** `lib/ui/widgets/lyrics_display.dart`

**问题:** `_buildSyncedLyrics()` 使用 `ref.watch(audioControllerProvider)` 监听完整的 `PlayerState`，导致音量变化、播放/暂停切换、缓冲状态变化等任何状态更新都触发歌词组件重建。歌词组件包含 `ScrollablePositionedList`、字号计算、行查找等较重的逻辑。

**修复:** 改为 `ref.watch(audioControllerProvider.select((s) => s.position))` 只监听播放位置，`currentTrack` 使用已有的 `currentTrackProvider`。

**影响:** 歌词组件只在播放位置变化时重建，不再因音量调节、播放状态切换等无关变化而重建。

---

## 3. Mini Player 进度条缺少 RepaintBoundary

**文件:** `lib/ui/widgets/player/mini_player.dart`

**问题:** `_MiniPlayerProgressBar` 每 ~200ms 更新一次进度值，其重绘可能向上传播到父级 `_MiniPlayerContent`，导致整个迷你播放器（封面、歌曲信息、控制按钮）不必要地参与重绘。

**修复:** 在 `_MiniPlayerProgressBar` 外层包裹 `RepaintBoundary`，将进度条的高频重绘隔离在自身范围内。

**影响:** 进度条更新不再触发迷你播放器其他部分的重绘。

---

## 4. TrackThumbnail / TrackCover 全局监听 fileExistsCacheProvider

**文件:** `lib/ui/widgets/track_thumbnail.dart`

**问题:** `TrackThumbnail` 和 `TrackCover` 使用 `ref.watch(fileExistsCacheProvider)` 监听整个 `Set<String>` 缓存。当任何文件路径被添加到缓存时（例如异步检查发现某个文件存在），所有可见的缩略图组件都会重建。在首页/探索页等有 50+ 个缩略图的页面，一次缓存更新会触发 50+ 次不必要的重建。

**修复:** 改为 `ref.watch(fileExistsCacheProvider.select(...))` 使用选择器，每个缩略图只监听自己对应的封面路径是否在缓存中。缓存更新时，只有结果实际发生变化的缩略图才会重建。

**影响:** 缓存更新从 O(n) 次重建降为 O(1)（n = 可见缩略图数量）。

---

## 审计结论：无泄漏问题

以下方面经审计确认无问题：
- 所有 `Timer.periodic` 均在 `dispose()` 中正确 `cancel()`
- 所有 `StreamSubscription` 均在 `dispose()` 中正确 `cancel()`
- 所有 `addListener` 均有对应的 `removeListener`
- 搜索页 `_loadedPages` 在每次新搜索时清空，非无界增长
- 图片内存缓存已在 `main.dart` 中设置合理上限（移动端 50MB / 桌面端 80MB）
- `FileExistsCache` 有 5000 条上限，带 LRU 淘汰
