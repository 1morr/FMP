# 业务逻辑统一性审查报告

## 审查摘要

对 FMP 项目中 7 个主要页面（HomePage、ExplorePage、SearchPage、PlaylistDetailPage、DownloadedCategoryPage、PlayHistoryPage、LibraryPage）的业务逻辑统一性进行了系统审查。

- 🔴 严重不一致：3 项
- 🟡 中等不一致：6 项
- 🟢 良好实践：8 项

整体评估：核心播放逻辑（playTemporary/playTrack）使用正确，播放状态判断大部分统一。主要问题集中在菜单选项缺失、Toast 消息 i18n 命名空间混乱、以及桌面端右键菜单支持不完整。

---

## 🔴 严重不一致（影响用户体验或可能导致 bug）

### 不一致 1: 搜索页本地结果分组菜单缺少「歌词匹配」选项

- **涉及文件**: `search_page.dart` (`_LocalGroupTile._buildMenuItems` L1368, `_LocalTrackTile._buildMenuItems` L1513)
- **不一致描述**:
  - `_SearchResultTile`（在线搜索结果）有 `matchLyrics` 菜单项 ✅
  - `_LocalGroupTile`（本地搜索结果分组）缺少 `matchLyrics` 菜单项 ❌
  - `_LocalTrackTile`（本地搜索结果单曲）缺少 `matchLyrics` 菜单项 ❌
  - `_PageTile`（分P列表项）缺少 `matchLyrics` 菜单项（可理解，分P通常不需要单独匹配歌词）
- **影响**: 用户在搜索页的「歌单中」区域无法为已有歌曲匹配歌词，必须去歌单详情页操作
- **建议统一方案**: 在 `_LocalGroupTile._buildMenuItems` 和 `_LocalTrackTile._buildMenuItems` 中添加 `matchLyrics` 菜单项

### 不一致 2: 首页历史记录菜单缺少「歌词匹配」选项

- **涉及文件**: `home_page.dart` (`_buildHistoryMenuItems` L499) vs `play_history_page.dart` (`_buildHistoryItemMenuItems` L653)
- **不一致描述**:
  - 播放历史页的菜单有 `matchLyrics` 选项 ✅
  - 首页历史记录区域的菜单缺少 `matchLyrics` 选项 ❌
- **影响**: 用户在首页看到历史记录时无法直接匹配歌词
- **建议统一方案**: 在 `_buildHistoryMenuItems` 中添加 `matchLyrics` 菜单项（在 `add_to_playlist` 之后、`PopupMenuDivider` 之前）

### 不一致 3: DownloadedCategoryPage 缺少桌面端右键菜单支持

- **涉及文件**: `downloaded_category_page.dart` vs 其他所有歌曲列表页面
- **不一致描述**:
  - 其他页面（explore、home、search、playlist_detail、history）的歌曲列表项都使用 `ContextMenuRegion` 包裹，支持桌面端右键菜单 ✅
  - `downloaded_category_page.dart` 的 `_GroupHeader` 和歌曲列表项完全没有使用 `ContextMenuRegion` ❌
- **影响**: 桌面端用户在已下载分类详情页无法右键操作歌曲
- **建议统一方案**: 为 `_GroupHeader` 和歌曲列表项添加 `ContextMenuRegion` 包裹

---

## 🟡 中等不一致（代码风格/模式不统一）

### 不一致 4: Toast 消息 i18n 命名空间混乱

- **涉及文件**: 多个页面
- **不一致描述**:
  | 页面 | 添加到队列的 Toast | 添加到下一首的 Toast |
  |------|-------------------|---------------------|
  | HomePage (排行榜) | `t.home.addedToQueue` | `t.home.addedToNext` |
  | ExplorePage | `t.searchPage.toast.addedToQueue` ⚠️ | `t.searchPage.toast.addedToNext` ⚠️ |
  | SearchPage | `t.searchPage.toast.addedToQueue` | `t.searchPage.toast.addedToNext` |
  | PlaylistDetailPage | `t.library.addedToPlayQueue` | `t.library.addedToNext` |
  | DownloadedCategoryPage | `t.library.addedToPlayQueue` | `t.library.addedToNext` |
  | PlayHistoryPage | `t.playHistoryPage.toastAddedToQueue` | `t.playHistoryPage.toastAddedToNext` |

  - ExplorePage 借用了 `searchPage` 的 i18n 命名空间
  - 「添加到队列」有两种 key：`addedToQueue` 和 `addedToPlayQueue`
  - 每个页面使用自己的命名空间，但实际显示的文字应该相同
- **建议统一方案**: 将通用操作的 Toast 消息提取到 `t.common.addedToQueue` / `t.common.addedToNext` 等公共命名空间，避免重复定义和不一致

### 不一致 5: ExplorePage 菜单文字借用 SearchPage 命名空间

- **涉及文件**: `explore_page.dart` (`_buildMenuItems` L338)
- **不一致描述**:
  - ExplorePage 的菜单项使用 `t.searchPage.menu.play`、`t.searchPage.menu.playNext` 等
  - 而 HomePage 使用 `t.home.play`、`t.home.playNext`
  - 两者功能完全相同，但 i18n key 来源不同
- **影响**: 如果未来修改 searchPage 的菜单文字，会意外影响 ExplorePage
- **建议统一方案**: ExplorePage 应使用自己的 i18n 命名空间，或提取到公共命名空间

### 不一致 6: 播放状态判断逻辑 — PlayHistoryPage 使用 `cid` 而非 `pageNum`

- **涉及文件**: `play_history_page.dart` L556 vs 其他所有页面
- **不一致描述**:
  - 标准模式（其他所有页面）：`currentTrack.sourceId == track.sourceId && currentTrack.pageNum == track.pageNum`
  - 历史页面：`currentTrack.sourceId == history.sourceId && (history.cid == null || currentTrack.cid == history.cid)`
- **分析**: 这可能是有意为之，因为 `PlayHistory` 模型存储的是 `cid` 而非 `pageNum`。但如果 `cid` 和 `pageNum` 的语义不完全一致，可能导致播放状态高亮不准确
- **建议**: 确认 `PlayHistory.cid` 与 `Track.pageNum` 的对应关系，如果等价则统一使用 `pageNum`

### 不一致 7: `const` 关键字在菜单 Icon 中使用不一致

- **涉及文件**: 多个页面
- **不一致描述**:
  - `home_page.dart`、`playlist_detail_page.dart`、`downloaded_category_page.dart`：使用 `const Icon(Icons.play_arrow)` ✅
  - `explore_page.dart`、`search_page.dart`：使用 `Icon(Icons.play_arrow)` 缺少 `const` ❌
- **影响**: 不影响功能，但缺少 `const` 会导致每次 rebuild 创建新的 Icon 实例
- **建议统一方案**: 统一添加 `const` 关键字

### 不一致 8: DownloadedCategoryPage 歌曲菜单缺少「添加到歌单」和「歌词匹配」

- **涉及文件**: `downloaded_category_page.dart` 歌曲列表项菜单 (L741)
- **不一致描述**:
  - 其他页面的歌曲菜单通常包含：播放、下一首播放、添加到队列、添加到歌单、歌词匹配
  - DownloadedCategoryPage 的歌曲菜单只有：下一首播放、添加到队列、删除下载
  - 缺少「添加到歌单」和「歌词匹配」选项
- **影响**: 用户在已下载分类页无法将歌曲添加到其他歌单或匹配歌词
- **建议统一方案**: 添加 `add_to_playlist` 和 `matchLyrics` 菜单项

### 不一致 9: `mounted` vs `context.mounted` 混用

- **涉及文件**: `search_page.dart`（使用 `mounted`）vs `explore_page.dart`、`home_page.dart`（使用 `context.mounted`）
- **不一致描述**:
  - `_SearchPageState` 中的异步回调使用 `if (mounted)` 检查（StatefulWidget 的属性）
  - `_ExploreTrackTile`（ConsumerWidget）中使用 `if (context.mounted)` 检查
  - 两者功能等价，但 `context.mounted` 是更通用的写法（在 StatelessWidget/ConsumerWidget 中也可用）
- **建议统一方案**: 在 `ConsumerStatefulWidget` 中统一使用 `mounted`，在 `ConsumerWidget` 中使用 `context.mounted`（当前实际使用已基本正确，只是风格不完全统一）

---

## 🟢 良好实践（已经统一的部分）

### 1. playTemporary vs playTrack 使用正确
- 搜索/排行榜/探索/历史页面：统一使用 `controller.playTemporary(track)` ✅
- 歌单详情/已下载分类：通过 `_playTrack()` 方法间接调用 `playTemporary()` ✅
- 没有发现错误使用 `playTrack` 的情况

### 2. 播放状态判断逻辑基本统一
- 绝大多数页面使用 `sourceId + pageNum` 比较 ✅
- 搜索页面的多P视频有额外的 `isPlayingThisVideo` 逻辑，合理 ✅
- 已下载分类页使用 `sourceId + pageNum`（而非 `downloadedPath`），与其他页面一致 ✅

### 3. Provider watch/read 使用规范
- `build()` 方法中使用 `ref.watch()` ✅
- 事件回调中使用 `ref.read()` ✅
- 未发现在 `build()` 中错误使用 `ref.read()` 的情况
- `player_page.dart` L40 的 `ref.read()` 在回调方法中，正确 ✅

### 4. 菜单项顺序基本统一
- 标准顺序：播放 → 下一首播放 → 添加到队列 → 添加到歌单 → 歌词匹配 → [页面特有操作]
- 各页面基本遵循此顺序 ✅

### 5. 菜单项图标统一
| 操作 | 图标 | 统一性 |
|------|------|--------|
| 播放 | `Icons.play_arrow` | ✅ 全部统一 |
| 下一首播放 | `Icons.queue_play_next` | ✅ 全部统一 |
| 添加到队列 | `Icons.add_to_queue` | ✅ 全部统一 |
| 添加到歌单 | `Icons.playlist_add` | ✅ 全部统一 |
| 歌词匹配 | `Icons.lyrics_outlined` | ✅ 全部统一 |
| 删除 | `Icons.delete_outline` | ✅ 全部统一 |

### 6. addNext/addToQueue 返回值检查统一
- 所有页面都检查 `addNext()` / `addToQueue()` 的返回值 `added` ✅
- 只在 `added == true` 时显示 Toast ✅

### 7. GoRouter 导航模式基本统一
- 主导航使用 `context.go()` ✅
- 子页面使用 `context.push()` 或 `context.pushNamed()` ✅
- 命名路由使用 `RouteNames.*` 常量 ✅
- 路径路由使用 `RoutePaths.*` 常量 ✅

### 8. 下载操作统一
- 下载前统一检查路径配置 (`pathManager.hasConfiguredPath()`) ✅
- 未配置时显示 `DownloadPathSetupDialog` ✅
- 下载结果统一处理三种状态 (`created`/`alreadyDownloaded`/`taskExists`) ✅
- 下载操作仅在 `PlaylistDetailPage` 中触发（合理，需要歌单上下文）✅

---

## 统一化建议优先级排序

1. **[高]** DownloadedCategoryPage 添加 `ContextMenuRegion` 支持桌面右键菜单
2. **[高]** 搜索页本地结果 `_LocalGroupTile` / `_LocalTrackTile` 添加 `matchLyrics` 菜单项
3. **[高]** 首页历史记录菜单添加 `matchLyrics` 选项
4. **[中]** DownloadedCategoryPage 歌曲菜单添加 `add_to_playlist` 和 `matchLyrics`
5. **[中]** 统一 Toast 消息 i18n 命名空间（提取公共 key 或让 ExplorePage 使用自己的命名空间）
6. **[低]** 统一 `const Icon()` 使用
7. **[低]** 确认 PlayHistoryPage 的 `cid` vs `pageNum` 播放状态判断是否等价
