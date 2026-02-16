# UI 显示与结构统一性审查报告

## 审查摘要

对 FMP 项目 `lib/ui/` 目录下的主要页面和组件进行了 UI 一致性审查。

**总体评估**：项目整体 UI 一致性较好，核心组件（TrackThumbnail、ImageLoadingService、ToastService）使用规范，图片加载已完全统一。主要不一致集中在：排行榜列表项布局违反自身规范、错误状态未使用统一组件、硬编码颜色/圆角/动画时长残留。

| 类别 | 数量 |
|------|------|
| 🔴 严重不一致 | 3 |
| 🟡 中等不一致 | 5 |
| 🟢 良好实践 | 7 |

---

## 🔴 严重不一致（视觉上明显不统一）

### 不一致 1: 排行榜列表项布局 — ExplorePage 和 HomePage 使用 ListTile + Row(leading) 违反项目规范

- **涉及文件**: `explore_page.dart` (`_ExploreTrackTile`) vs `home_page.dart` (`_RankingTrackTile`)
- **不一致描述**: CLAUDE.md 和 `ui_pages_details` 记忆明确规定排行榜项应使用 `InkWell + Padding + Row` 自定义布局，**避免在 `ListTile.leading` 中放 `Row`**（会导致滚动时布局抖动）。但两个页面的实际实现都使用了 `ListTile` + `leading: Row(...)` 的方式。
- **代码对比**:

```dart
// ❌ 当前实现 (explore_page.dart _ExploreTrackTile, 约 L220)
ListTile(
  leading: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 28, child: Text('$rank'...)),
      const SizedBox(width: 12),
      TrackThumbnail(track: track, size: AppSizes.thumbnailMedium, ...),
    ],
  ),
  title: Text(track.title, ...),
  ...
)

// ❌ 当前实现 (home_page.dart _RankingTrackTile, 约 L997)
ListTile(
  leading: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 24, child: Text('$rank'...)),
      const SizedBox(width: 12),
      TrackThumbnail(track: track, size: AppSizes.thumbnailMedium, ...),
    ],
  ),
  ...
)
```

```dart
// ✅ 规范要求的实现（来自 CLAUDE.md "ListTile Performance in Lists"）
InkWell(
  onTap: () => ...,
  child: Padding(
    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(children: [/* rank, thumbnail, info, menu */]),
  ),
)
```

- **额外差异**: 排名数字宽度不一致 — ExplorePage 用 `width: 28`，HomePage 用 `width: 24`
- **建议统一方案**:
  1. 两个页面都改为 `InkWell + Row` 自定义布局
  2. 统一排名数字宽度为 `28`（三位数排名需要更多空间）
  3. 考虑提取为共享的 `RankingTrackTile` 组件，避免代码重复

---

### 不一致 2: 错误状态显示 — 存在 `ErrorDisplay` 组件但所有页面都未使用

- **涉及文件**: `lib/ui/widgets/error_display.dart` vs 所有页面
- **不一致描述**: 项目已有完善的 `ErrorDisplay` 统一错误组件（支持 network/server/notFound/permission/empty/general 六种类型，支持 compact 模式），但所有页面的错误状态都是手动拼装 `Icon + Text + Button`，样式不统一。
- **代码对比**:

```dart
// explore_page.dart — 错误图标 size: 48
Icon(Icons.error_outline, size: 48, color: colorScheme.error),

// downloaded_category_page.dart — 错误图标 size: 64
Icon(Icons.error_outline, size: 64, color: colorScheme.error),

// downloaded_page.dart — 错误图标 size: 64
Icon(Icons.error_outline, size: 64, color: colorScheme.error),

// playlist_detail_page.dart — 错误图标 size: 64
Icon(Icons.error_outline, size: 64, color: colorScheme.error),

// download_manager_page.dart — 使用 Colors.grey 硬编码
const Icon(Icons.download_done, size: 64, color: Colors.grey),
Text(t.settings.downloadManager.noTasks, style: const TextStyle(color: Colors.grey)),
```

```dart
// ✅ 应该使用
ErrorDisplay(
  type: ErrorType.general,
  message: t.general.loadFailed,
  onRetry: onRefresh,
)

ErrorDisplay.empty(
  icon: Icons.download_done,
  title: t.settings.downloadManager.noTasks,
)
```

- **影响**: 错误图标大小不一致（48 vs 64），间距不一致（有的 SizedBox(height: 16) 有的 SizedBox(height: 24)），重试按钮样式不一致（FilledButton vs TextButton）
- **建议统一方案**: 所有页面的错误/空状态统一使用 `ErrorDisplay` 组件

---

### 不一致 3: 空状态显示样式不统一

- **涉及文件**: 多个页面的 `_buildEmptyState`
- **不一致描述**: 各页面空状态的图标大小、间距、标题样式、是否有操作按钮都不一致。

| 页面 | 图标大小 | 标题样式 | 间距 | 有操作按钮 |
|------|---------|---------|------|-----------|
| LibraryPage | 80 | headlineSmall | 24 | ✅ (2个) |
| RadioPage | 80 | headlineSmall | 24 | ✅ (1个) |
| DownloadedPage | 80 | headlineSmall | 24 | ❌ |
| QueuePage | 64 | titleMedium | 16+8+24 | ✅ (1个) |
| PlaylistDetailPage | 64 | titleMedium | 16+8 | ❌ |
| DownloadedCategoryPage | 64 | titleMedium | 16+8 | ❌ |
| DownloadManagerPage | 64 | (无标题) | 16 | ❌ |

- **建议统一方案**: 使用 `ErrorDisplay.empty()` 统一所有空状态，或至少统一图标大小和间距规范

---

## 🟡 中等不一致（代码规范不统一）

### 不一致 4: 硬编码 `Colors.xxx` 未使用主题色

- **涉及文件**: 多个页面
- **不一致描述**: 部分页面使用硬编码颜色而非 `colorScheme`。

**需要修复的硬编码颜色**:

| 文件 | 行 | 硬编码 | 应替换为 |
|------|-----|--------|---------|
| `download_manager_page.dart` | 108 | `Colors.grey` | `colorScheme.outline` |
| `download_manager_page.dart` | 110 | `Colors.grey` | `colorScheme.outline` |
| `download_manager_page.dart` | 345-351 | `Colors.orange/grey/green/red` | `colorScheme.tertiary/outline/primary/error` |
| `settings_page.dart` | 1473 | `Colors.grey` | `colorScheme.outline` |
| `settings_page.dart` | 1535 | `Colors.grey` | `colorScheme.outline` |
| `settings_page.dart` | 298 | `Color(0xFF6750A4)` | `colorScheme.primary` |

**可接受的硬编码颜色**（特殊语义）:
- `Colors.red` 用于 LIVE 标签（home_page, radio_page）— 语义明确
- `Colors.white` / `Colors.black54` 用于 SliverAppBar 展开时的遮罩 — 设计需要
- `Colors.transparent` — 无实际颜色
- `Colors.green/orange/red` 用于歌词匹配度指示 — 语义色彩

---

### 不一致 5: 硬编码 `BorderRadius.circular()` 未使用 `AppRadius` 常量

- **涉及文件**:
  - `cover_picker_dialog.dart` L320: `BorderRadius.circular(isSelected ? 5 : 8)` — 应使用 `AppRadius.borderRadiusSm` / `AppRadius.borderRadiusMd`
  - `lyrics_source_settings_page.dart` L128: `BorderRadius.circular(12)` — 应使用 `AppRadius.borderRadiusLg`

- **注意**: `track_thumbnail.dart` 中的 `BorderRadius.circular(borderRadius)` 是合理的，因为 `borderRadius` 是外部传入的参数。

---

### 不一致 6: 硬编码 `Duration(milliseconds: ...)` 未使用 `AnimationDurations` 常量

- **涉及文件**:
  - `horizontal_scroll_section.dart` L126: `Duration(milliseconds: 400)` — 介于 `AnimationDurations.normal`(300ms) 和 `AnimationDurations.slow`(500ms) 之间，建议使用 `slow` 或新增常量
  - `youtube_stream_test_page.dart` 多处 — 调试页面，可接受

- **注意**: `queue_page.dart` L126 的 `Duration(milliseconds: 50)` 用于滚动动画微调，不在标准常量范围内，可接受。

---

### 不一致 7: 菜单项样式不统一 — PopupMenuItem 内部布局

- **涉及文件**: 多个页面的 `_buildMenuItems` / `_buildContextMenuItems`
- **不一致描述**: 菜单项内部布局有两种风格：

```dart
// 风格 A: ListTile 包裹（explore_page, home_page, history_page, search_page）
PopupMenuItem(
  value: 'play',
  child: ListTile(
    leading: Icon(Icons.play_arrow),
    title: Text('播放'),
    contentPadding: EdgeInsets.zero,
  ),
),

// 风格 B: Row 包裹（library_page 的 ContextMenu）
PopupMenuItem(
  value: 'add_all',
  child: Row(
    children: [
      const Icon(Icons.play_arrow, size: 20),
      const SizedBox(width: 12),
      Text(t.library.addAll),
    ],
  ),
),
```

- **影响**: 两种风格的视觉效果略有差异（ListTile 有额外的内边距），但由于 `contentPadding: EdgeInsets.zero`，差异较小
- **建议**: 统一使用风格 A（ListTile），因为它是大多数页面的选择，且语义更清晰

---

### 不一致 8: `_HomePlaylistCard` 与 `_PlaylistCard` 大量代码重复

- **涉及文件**: `home_page.dart` (`_HomePlaylistCard`) vs `library_page.dart` (`_PlaylistCard`)
- **不一致描述**: 两个组件的菜单操作方法（`_addAllToQueue`, `_shuffleAddToQueue`, `_playMix`, `_refreshPlaylist`, `_showEditDialog`, `_showDeleteConfirm`, `_showOptionsMenu`）几乎完全相同，约 200 行重复代码。
- **建议**: 提取共享的 `PlaylistCardActions` mixin 或工具类，避免修改一处忘记同步另一处。

---

## 🟢 良好实践（已经统一的部分）

### 1. 图片加载完全统一 ✅
- 所有页面使用 `TrackThumbnail` / `TrackCover` / `ImageLoadingService.loadImage()` / `ImageLoadingService.loadAvatar()`
- **零** `Image.network()` 或 `CachedNetworkImage()` 直接调用
- `FileExistsCache` 使用模式（watch + read）在所有需要的页面中正确实现

### 2. AppBar actions 尾部 SizedBox(width: 8) 规范 ✅
- 所有检查的页面（library_page, downloaded_page, downloaded_category_page, radio_page, search_page, queue_page, history_page, settings_page）都正确添加了尾部间距
- `PopupMenuButton` 结尾的页面（player_page, radio_player_page）正确地没有添加额外间距

### 3. 播放状态判断逻辑统一 ✅
- 所有页面使用 `currentTrack.sourceId == track.sourceId && currentTrack.pageNum == track.pageNum` 比较
- 已下载分类页正确使用 `downloadedPath` 比较

### 4. 主题色使用规范 ✅（大部分）
- 文字样式统一使用 `Theme.of(context).textTheme`
- 颜色统一使用 `Theme.of(context).colorScheme`
- 仅少数特殊场景使用硬编码颜色（见不一致 4）

### 5. 卡片网格布局统一 ✅
- `LibraryPage`、`DownloadedPage`、`RadioPage` 都使用 `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200)` + `AppSizes.cardAspectRatio`
- 网格 padding 统一为 `EdgeInsets.fromLTRB(16, 16, 16, 80)`

### 6. SliverAppBar 折叠式头部统一 ✅
- `PlaylistDetailPage` 和 `DownloadedCategoryPage` 使用相同的折叠式头部模式
- `expandedHeight: 280`、`collapseThreshold: AppSizes.collapseThreshold`
- 图标颜色根据收起状态切换（展开时白色，收起时主题色）

### 7. Toast 通知统一使用 ToastService ✅
- 所有页面使用 `ToastService.success()` / `ToastService.error()` / `ToastService.warning()`
- 无直接使用 `ScaffoldMessenger.showSnackBar()` 的情况

---

## 统一化建议优先级排序

1. **[高] 排行榜列表项布局修复** — 将 `_ExploreTrackTile` 和 `_RankingTrackTile` 从 `ListTile + Row(leading)` 改为 `InkWell + Row` 自定义布局，并提取为共享组件
2. **[高] 错误/空状态统一使用 `ErrorDisplay`** — 所有页面的错误和空状态替换为 `ErrorDisplay` / `ErrorDisplay.empty()`，消除图标大小和间距不一致
3. **[中] 消除硬编码颜色** — `download_manager_page.dart` 和 `settings_page.dart` 中的 `Colors.grey` / `Color(0xFF6750A4)` 替换为主题色
4. **[中] 消除硬编码 BorderRadius** — `cover_picker_dialog.dart` 和 `lyrics_source_settings_page.dart` 使用 `AppRadius` 常量
5. **[中] 提取 PlaylistCard 共享操作** — 消除 `_HomePlaylistCard` 和 `_PlaylistCard` 的 ~200 行重复代码
6. **[低] 统一菜单项布局风格** — 选择 ListTile 或 Row 其中一种
7. **[低] 补充 AnimationDurations 常量** — `horizontal_scroll_section.dart` 的 400ms 动画时长
