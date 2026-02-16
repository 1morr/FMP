# 性能优化审查报告

## 审查摘要

对 FMP 项目的 UI 性能进行了抽样审查，覆盖 rebuild 频率、列表性能、图片缓存、动画、Provider 粒度等关键领域。

**总体评估**：项目整体性能意识较好，已有多项优化措施（缩略图 URL 优化、memCacheWidth/Height、RepaintBoundary、ValueKey、fileExistsCache 等）。但仍存在一些可改进的点，主要集中在 MiniPlayer 的 rebuild 频率和 ExploreTrackTile 的布局方式上。

- 🔴 严重问题：2 个
- 🟡 中等问题：6 个
- 🟢 良好实践：8 个

---

## 🔴 严重问题（明显影响用户体验）

### 问题 1: MiniPlayer 整体 watch audioControllerProvider 导致高频 rebuild

- **文件**: `lib/ui/widgets/player/mini_player.dart`
- **行号**: 约第 40 行
- **问题描述**: `MiniPlayer` 是常驻 Widget（始终显示在底部），它通过 `ref.watch(audioControllerProvider)` 监听整个 `PlayerState`。`PlayerState` 包含 30+ 个字段（position、duration、bufferedPosition、volume、queue、audioDevices 等），其中 `position` 每秒更新多次。这意味着 MiniPlayer 每秒会 rebuild 多次，即使它只需要 `currentTrack`、`isPlaying`、`progress`、`volume` 等少数字段。
- **性能影响**: 每次 position 变化都会触发 MiniPlayer 及其所有子 Widget 的 rebuild，包括 `TrackThumbnail`（内部还会 watch `fileExistsCacheProvider`）、所有 `IconButton`、`MouseRegion` 等。在播放状态下，这是持续的性能开销。
- **建议修复**:
  1. 将 MiniPlayer 拆分为多个子 Widget，每个子 Widget 只 watch 需要的字段：
     ```dart
     // 进度条单独 watch position
     class _ProgressBar extends ConsumerWidget {
       Widget build(context, ref) {
         final progress = ref.watch(audioControllerProvider.select((s) => s.progress));
         // ...
       }
     }

     // 封面和歌曲信息只 watch currentTrack
     class _TrackInfo extends ConsumerWidget {
       Widget build(context, ref) {
         final track = ref.watch(currentTrackProvider);
         // ...
       }
     }
     ```
  2. 或者使用 `ref.watch(audioControllerProvider.select(...))` 精确选择需要的字段。

### 问题 2: ExploreTrackTile 使用 Row 作为 ListTile.leading

- **文件**: `lib/ui/pages/explore/explore_page.dart`
- **行号**: 约第 267-288 行
- **问题描述**: `_ExploreTrackTile` 在 `ListTile.leading` 中放置了一个 `Row`（包含排名文字 + 间距 + TrackThumbnail）。CLAUDE.md 中已明确记录此为已知问题："Avoid putting `Row` inside `ListTile.leading` - this causes layout jitter during scrolling."
- **性能影响**: 在快速滚动排行榜列表时，`ListTile` 的 leading 约束计算与 `Row` 的 intrinsic width 计算冲突，导致布局抖动（layout jitter），表现为列表项在滚动时轻微跳动。
- **建议修复**: 改用 CLAUDE.md 推荐的扁平自定义布局：
  ```dart
  InkWell(
    onTap: () => ...,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(children: [/* rank, thumbnail, info, menu */]),
    ),
  )
  ```

---

## 🟡 中等问题（可优化）

### 问题 3: HomePage watch 了整个 audioControllerProvider

- **文件**: `lib/ui/pages/home/home_page.dart`
- **行号**: 约第 52 行
- **问题描述**: `_HomePageState.build()` 中 `ref.watch(audioControllerProvider)` 监听整个 PlayerState，但只用于判断 `hasCurrentTrack` 和 `queue.isNotEmpty`，以及传递给 `_buildNowPlaying` 和 `_buildQueuePreview`。由于 HomePage 使用 `SingleChildScrollView` 包含多个 section，每次 position 变化都会触发整个页面 rebuild。
- **性能影响**: 中等。HomePage 不是常驻 Widget，但在首页可见时，播放中的 position 更新会导致不必要的 rebuild。
- **建议修复**: 将 "正在播放" 和 "队列预览" section 提取为独立的 ConsumerWidget，各自只 watch 需要的字段。外层 HomePage 只 watch `currentTrackProvider` 和 `queueProvider` 来决定是否显示这些 section。

### 问题 4: QueuePage 的 _onPositionsChanged 可能触发不必要的 setState

- **文件**: `lib/ui/pages/queue/queue_page.dart`
- **行号**: 约第 52-65 行
- **问题描述**: `_onPositionsChanged` 监听 `ItemPositionsListener`，在每次滚动时都会被调用。虽然有 `_isNearTop != isNearTop` 的守卫，但 `positions.map((p) => p.index).reduce(...)` 的计算在每次滚动事件中都会执行。
- **性能影响**: 低到中等。`reduce` 操作本身很轻量，但在快速滚动时调用频率很高。
- **建议修复**: 可以考虑添加简单的节流（throttle），或者只在 `ScrollEndNotification` 时更新 `_isNearTop` 状态。

### 问题 5: LyricsDisplay 中 _ensureRefWidth 对所有歌词行创建 TextPainter

- **文件**: `lib/ui/widgets/lyrics_display.dart`
- **行号**: 约第 84-123 行
- **问题描述**: `_ensureRefWidth` 方法为每一行歌词创建一个 `TextPainter` 来测量宽度，然后排序取中位数。虽然有缓存机制（`_cachedRefWidth`），但在歌词首次加载或切换歌曲时，如果歌词有 100+ 行，会创建 100+ 个 TextPainter。
- **性能影响**: 低到中等。只在歌词变化时执行一次，但对于长歌词可能造成短暂卡顿。
- **建议修复**: 可以只采样部分行（如每隔 N 行取一行）来估算中位数宽度，而不是测量所有行。例如：
  ```dart
  // 采样：最多测量 20 行
  final step = (lines.length / 20).ceil().clamp(1, lines.length);
  for (int i = 0; i < lines.length; i += step) { ... }
  ```

### 问题 6: NowPlayingIndicator 使用 AnimatedBuilder 每帧 rebuild 子树

- **文件**: `lib/ui/widgets/now_playing_indicator.dart`
- **行号**: 约第 78-103 行
- **问题描述**: `AnimatedBuilder` 的 `builder` 回调在每一帧都会执行，内部通过 `List.generate(3, ...)` 创建 3 个 `Container`。虽然 Widget 很轻量，但每帧都会创建新的 Widget 对象。
- **性能影响**: 低。单个 NowPlayingIndicator 影响微乎其微，但如果列表中有多个同时可见的播放指示器（理论上不会，因为只有当前播放的歌曲显示），则可能累积。
- **建议修复**: 考虑使用 `CustomPainter` 替代 Widget 树来绘制波形动画，避免每帧创建 Widget 对象。或者至少将不变的部分（如 `SizedBox`、`Row`）提取到 `child` 参数中。

### 问题 7: FileExistsCache 的 watch 模式导致级联 rebuild

- **文件**: `lib/ui/widgets/track_thumbnail.dart` 第 50 行，以及其他多处
- **问题描述**: `TrackThumbnail` 和 `TrackCover` 都 `ref.watch(fileExistsCacheProvider)` 监听整个 `Set<String>` 状态。当任何一个文件路径被添加到缓存时，所有正在显示的 `TrackThumbnail` 和 `TrackCover` 都会 rebuild。在列表页面中，如果有 20 个可见的缩略图，一次缓存更新会触发 20 次 rebuild。
- **性能影响**: 中等。在下载完成或首次进入列表页面时，`preloadPaths` 会批量更新缓存，可能触发大量 rebuild。
- **建议修复**:
  1. 使用 `ref.watch(fileExistsCacheProvider.select((state) => state.contains(specificPath)))` 只监听特定路径的变化。
  2. 或者在 `FileExistsCache` 中使用更细粒度的通知机制（如 `ChangeNotifier` + 路径级别的监听）。

### 问题 8: SearchPage 在 build 中创建 allTracks 列表

- **文件**: `lib/ui/pages/search/search_page.dart`
- **行号**: 约第 78 行
- **问题描述**: `[...searchState.localResults, ...searchState.mixedOnlineTracks]` 在每次 build 时都会创建一个新的合并列表。如果搜索结果较多（如 50+ 条），这个列表创建操作虽然不重，但在频繁 rebuild 时会产生不必要的 GC 压力。
- **性能影响**: 低。列表创建本身很快，但在搜索输入时可能频繁触发。
- **建议修复**: 将 `allTracks` 的计算移到 `searchProvider` 内部，作为一个 computed 属性缓存。

---

## 🟢 良好实践（值得肯定的做法）

### 1. 缩略图 URL 优化（ThumbnailUrlUtils）
`ThumbnailUrlUtils` 根据显示尺寸自动选择合适的缩略图质量，Bilibili 从 ~700KB 降到 ~20KB，YouTube 选择 16:9 比例的 mqdefault/maxresdefault 避免黑边。这是非常好的带宽和内存优化。

### 2. 网络图片内存缓存尺寸限制（memCacheWidth/memCacheHeight）
`_CachedNetworkImage` 根据显示尺寸和设备像素比计算 `memCacheWidth`/`memCacheHeight`，将解码后的位图内存从 ~8MB（1920×1080）降到 ~160KB（200×200）。

### 3. QueuePage 使用 RepaintBoundary 隔离重绘
队列列表的每个 `_DraggableQueueItem` 都包裹在 `RepaintBoundary` 中，有效隔离了拖拽操作时的重绘范围。

### 4. QueuePage 使用本地队列副本避免拖拽闪烁
`_localQueue` 机制在拖拽时先更新本地状态（同步），再异步同步到 provider，避免了拖拽过程中的 UI 闪烁。

### 5. 进度条拖动只在 onChangeEnd 时 seek
`PlayerPage` 和 `MiniPlayer` 的进度条在拖动过程中只更新本地状态（`_dragProgress`），只在 `onChangeEnd` 时才调用 `seekToProgress`，避免了消息队列溢出。

### 6. 路由使用 NoTransitionPage 避免不必要的动画
Shell 内的页面切换使用 `NoTransitionPage`，避免了 tab 切换时的过渡动画开销。全屏播放器使用自定义 SlideTransition，体验流畅。

### 7. 歌词滚动的用户交互检测
`LyricsDisplay` 通过 `_programmaticScrolling` 标志区分程序化滚动和用户手动滚动，避免了自动滚动与用户操作的冲突。用户停止滚动 3 秒后自动恢复。

### 8. PlaylistDetailPage 的滚动阈值优化
`_onScroll` 只在跨越 `_collapseThreshold` 时才调用 `setState`，避免了滚动过程中的频繁 rebuild。分组结果也有缓存（`_cachedGroups`），避免每次 build 重新计算。

### 9. Provider 粒度拆分
项目已经将 `audioControllerProvider` 拆分出了 `currentTrackProvider`、`isPlayingProvider`、`positionProvider`、`queueProvider` 等细粒度 Provider。部分页面（如 `_ExploreTrackTile`、`PlaylistDetailPage`）已经使用 `currentTrackProvider` 而非整个 `audioControllerProvider`。

### 10. 本地图片同步加载跳过动画
`_FadeInImage` 在 `synchronousCall` 为 true 时（从缓存加载）直接设置 `_controller.value = 1.0`，跳过淡入动画，避免了已缓存图片的闪烁。

---

## 改进建议优先级排序

1. **[高] MiniPlayer rebuild 优化** — 常驻 Widget，影响所有页面。拆分子 Widget 或使用 `.select()` 精确监听。预计可减少 80%+ 的不必要 rebuild。
2. **[高] ExploreTrackTile 布局修复** — 将 `ListTile.leading` 中的 `Row` 改为扁平自定义布局，消除滚动抖动。
3. **[中] HomePage 拆分 section** — 将 "正在播放" 和 "队列预览" 提取为独立 ConsumerWidget，减少首页 rebuild 范围。
4. **[中] FileExistsCache 细粒度监听** — 使用 `.select()` 只监听特定路径，减少缩略图的级联 rebuild。
5. **[低] LyricsDisplay 采样优化** — 对长歌词的字号计算使用采样而非全量测量。
6. **[低] NowPlayingIndicator 使用 CustomPainter** — 减少每帧的 Widget 创建开销。
7. **[低] SearchPage allTracks 缓存** — 将合并列表移到 provider 内部。
8. **[低] QueuePage 滚动位置检测节流** — 添加简单的节流逻辑。
