# FMP UI 页面详细文档

## 页面概览

| 页面 | 文件路径 | 主要功能 |
|------|----------|----------|
| 首页 | `ui/pages/home/home_page.dart` | 快捷操作、URL播放、当前播放、最近熱門排行、歌单预览、队列预览 |
| 探索 | `ui/pages/explore/explore_page.dart` | Bilibili/YouTube 音樂完整排行榜 |
| 搜索 | `ui/pages/search/search_page.dart` | 多源搜索、搜索历史、分P展开 |
| 播放队列 | `ui/pages/queue/queue_page.dart` | 队列管理、拖拽排序、当前位置定位 |
| 音乐库 | `ui/pages/library/library_page.dart` | 歌单网格、导入、刷新 |
| 歌单详情 | `ui/pages/library/playlist_detail_page.dart` | 歌曲列表、多P分组、下载 |
| 已下载 | `ui/pages/library/downloaded_page.dart` | 分类网格（按歌单分文件夹） |
| 已下载分类详情 | `ui/pages/library/downloaded_category_page.dart` | 本地文件扫描显示 |
| 全屏播放器 | `ui/pages/player/player_page.dart` | 封面、进度条、控制按钮、音量（桌面） |
| 设置 | `ui/pages/settings/settings_page.dart` | 主题、播放、存储设置 |
| 音频设置 | `ui/pages/settings/audio_settings_page.dart` | 音质等级、格式/流类型优先级 |
| 下载管理 | `ui/pages/settings/download_manager_page.dart` | 下载任务列表、进度 |

---

## 1. 首页 (HomePage)

### 功能模块

1. **快捷操作区域**
   - 搜索、音乐库、播放队列三个快捷入口卡片

2. **URL播放卡片**
   - 输入 Bilibili URL 直接播放
   - 使用 `sourceManager.parseUrl()` 解析
   - 播放成功后调用 `controller.playSingle(track)`

3. **当前播放卡片**
   - 条件：`playerState.hasCurrentTrack` 为 true 时显示
   - 显示：封面（TrackThumbnail）、标题、艺术家、播放/暂停按钮
   - 点击跳转到全屏播放器

4. **最近熱門區域**（2026-01-19 更新）
   - 標題："最近熱門" + "更多"按鈕（跳轉到探索頁）
   - 響應式佈局：
     - 窄屏（< 600dp）：堆疊顯示 Bilibili 和 YouTube
     - 寬屏：並排顯示兩個排行榜
   - 每個排行榜：
     - 簡單文字標題（"Bilibili" / "YouTube"，無 badge）
     - 前 10 首歌曲預覽
     - 使用 `_RankingTrackTile` 統一樣式
   - 項目樣式：
     - 排名數字 + 縮略圖（48x48） + 標題/藝術家 + 菜單按鈕
     - 正在播放時顯示 `NowPlayingIndicator` 替代縮略圖
     - 使用自定義 `InkWell` + `Row` 佈局（非 ListTile，避免性能問題）

5. **最近歌单横向列表**
   - 显示最多3个歌单
   - 使用 `playlistCoverProvider` 获取封面
   - 封面来源：歌单中第一首歌的 thumbnailUrl

6. **接下来播放预览**
   - 使用 `playerState.upcomingTracks.take(3)` 获取
   - **重要**：已考虑 shuffle 模式

---

## 2. 探索页 (ExplorePage)（2026-01-19 新增）

### 功能概述

顯示 Bilibili 和 YouTube 音樂排行榜的完整列表（首頁只顯示前 10 首預覽）。

### 功能模块

1. **TabBar 切換**
   - 兩個 Tab：Bilibili、YouTube
   - 無分類選擇（只顯示音樂排行）

2. **排行榜列表**
   - 使用緩存數據（`cachedBilibiliRankingProvider` / `cachedYouTubeRankingProvider`）
   - 下拉刷新觸發緩存服務刷新
   - 項目樣式與首頁統一

3. **項目樣式 `_ExploreTrackTile`**
   - 排名數字（簡單樣式，無金銀銅顏色）
   - 縮略圖 48x48（正在播放時顯示 `NowPlayingIndicator`）
   - 標題 + 藝術家 + 播放量（格式化為萬/億）
   - 菜單按鈕：播放、下一首播放、添加到隊列、添加到歌單
   - 使用 `InkWell` + `Padding` + `Row` 自定義佈局（避免 ListTile 性能問題）

### 關鍵實現

```dart
// 使用自定義佈局避免 ListTile.leading 中放 Row 的性能問題
InkWell(
  onTap: () => controller.playTemporary(track),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(
      children: [
        // 排名數字
        SizedBox(width: 24, child: Text('$rank')),
        const SizedBox(width: 12),
        // 縮略圖或播放指示器
        TrackThumbnail(track: track, size: 48, borderRadius: 4, isPlaying: isPlaying),
        const SizedBox(width: 12),
        // 標題和副標題
        Expanded(child: Column(...)),
        // 菜單按鈕
        PopupMenuButton<String>(...),
      ],
    ),
  ),
)

// 播放量格式化
String _formatViewCount(int count) {
  if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}億';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}萬';
  return count.toString();
}
```

---

## 3. 搜索页 (SearchPage)

### 功能模块

1. **搜索框**
   - 输入后调用 `searchProvider.search(query)`
   - 支持清空、提交

2. **音源筛选 + 排序**
   - 目前只有 Bilibili 音源
   - 排序选项：综合、播放量、最新、弹幕数

3. **搜索历史**
   - 空搜索框时显示
   - 使用 `searchHistoryManagerProvider`
   - 可清空全部或删除单项

4. **搜索结果列表**
   - 分为"歌单中"（本地已有）和"在线结果"
   - 支持无限滚动加载更多

5. **多P视频展开**
   - `_loadVideoPages()` 获取分P信息
   - 展开后显示各分P，可单独播放/下载/添加
   - 菜单操作时会批量处理所有分P

### 关键逻辑

```dart
// 点击歌曲 -> 临时播放
void _playVideo(Track track) async {
  controller.playTemporary(track);
  await _loadVideoPages(track); // 同时加载分P信息
}

// 菜单操作 -> 如有多P则批量处理
if (hasMultiplePages) {
  for (final page in pages) {
    controller.addNext(page.toTrack(track));
  }
}
```

---

## 4. 播放队列页 (QueuePage)

### 功能模块

1. **队列头部提示**
   - 显示"正在播放第 X 首"
   - 点击可跳转到当前位置

2. **拖拽排序列表**
   - 使用 `ReorderableListView`
   - **防闪烁机制**：维护 `_localQueue` 副本
   - 拖拽时先更新本地状态（同步），再同步到 provider（异步）

3. **自动滚动功能**
   - 由 `autoScrollToCurrentTrackProvider` 设置控制
   - 首次进入页面定位到当前播放
   - 切歌时自动滚动到新位置

4. **队列项功能**
   - Dismissible 左滑删除
   - 拖拽手柄排序
   - 点击播放该项
   - 显示封面、标题、时长

### 关键状态管理

```dart
// 本地队列副本机制
final providerQueue = playerState.queue;
if (needsSync) {
  _localQueue = List.from(providerQueue);
}

// 拖拽时更新
onReorder: (oldIndex, newIndex) {
  setState(() {
    final track = _localQueue!.removeAt(oldIndex);
    _localQueue!.insert(newIndex, track);
    // 同步调整 _localCurrentIndex
  });
  // 异步同步到 provider
  ref.read(audioControllerProvider.notifier).moveInQueue(oldIndex, newIndex);
}
```

---

## 5. 音乐库页 (LibraryPage)

### 功能模块

1. **AppBar 操作**
   - 左侧：已下载入口按钮
   - 右侧：从 URL 导入、新建歌单

2. **歌单网格**
   - 响应式列数：2-5列（根据宽度）
   - 卡片显示：封面、名称、歌曲数、导入标记

3. **长按菜单**
   - 添加所有到队列
   - 随机添加到队列
   - 编辑歌单
   - 刷新歌单（仅导入歌单）
   - 删除歌单

4. **刷新进度指示器**
   - `PlaylistRefreshProgress` 固定在底部
   - 显示当前正在刷新的歌单

### 封面获取逻辑

```dart
// playlistCoverProvider 实现
final coverAsync = ref.watch(playlistCoverProvider(playlist.id));
// 获取歌单中第一首歌的 thumbnailUrl
```

---

## 6. 歌单详情页 (PlaylistDetailPage)

### 功能模块

1. **SliverAppBar 折叠式头部**
   - 背景：封面图（带渐变遮罩）
   - 前景：小封面、歌单名、描述、歌曲数/时长、导入标记

2. **操作按钮区**
   - 添加所有（原顺序）
   - 随机添加
   - 下载全部

3. **歌曲列表（支持多P分组）**
   - 使用 `groupTracks(tracks)` 分组
   - 单P视频：普通 ListTile
   - 多P视频：可展开的 _GroupHeader

### 多P分组逻辑

```dart
// TrackGroup 结构
class TrackGroup {
  final String groupKey;      // parentTitle ?? title
  final String parentTitle;   // 父视频标题
  final List<Track> tracks;   // 该组的所有分P
}

// 多P检测：同一个 groupKey 下有多个 track
// 组标题显示：parentTitle + "NP" 标签
```

### 已下载图标显示逻辑

```dart
// 歌曲列表项中：
if (track.downloadedPath != null && File(track.downloadedPath!).existsSync())
  Icon(Icons.download_done, size: 14, color: colorScheme.primary)

// 多P组标题中：
if (group.tracks.every((t) =>
    t.downloadedPath != null && File(t.downloadedPath!).existsSync()))
  Icon(Icons.download_done, size: 14, color: colorScheme.primary)
```

---

## 7. 已下载页 (DownloadedPage)

### 功能模块

1. **分类网格**
   - 每个分类对应一个文件夹（歌单名_歌单ID）
   - 显示：封面、名称、歌曲数

2. **分类卡片**
   - 封面来源：优先 `playlist_cover.jpg`，其次第一首歌的 `cover.jpg`
   - 无封面时显示渐变背景 + 文件夹图标

3. **长按菜单**
   - 添加所有到队列
   - 随机添加到队列
   - 删除整个分类

### 分类数据获取

```dart
// downloadedCategoriesProvider
// 扫描下载目录，统计每个子文件夹中的 .m4a 文件数量
await for (final entity in downloadDir.list()) {
  if (entity is Directory) {
    final trackCount = await _countAudioFiles(entity);
    if (trackCount > 0) {
      categories.add(DownloadedCategory(...));
    }
  }
}
```

---

## 8. 已下载分类详情页 (DownloadedCategoryPage)

### 功能模块

1. **与歌单详情页类似的布局**
   - SliverAppBar 折叠式头部
   - 操作按钮（添加所有、随机添加）
   - 歌曲列表（支持多P分组）

2. **本地文件扫描显示**
   - 不依赖数据库，直接扫描文件系统
   - 读取 `metadata.json` 获取歌曲信息
   - 无 metadata 时从文件名解析

### 本地Track创建逻辑

```dart
// 从 metadata.json 创建
Track? _trackFromMetadata(Map<String, dynamic> json, String audioPath) {
  return Track()
    ..sourceId = json['sourceId']
    ..title = json['title']
    ..downloadedPath = audioPath
    ...;
}

// 无 metadata 时的回退
track = Track()
  ..sourceId = p.basename(entity.path)
  ..title = p.basenameWithoutExtension(audioFile.path)
  ..downloadedPath = audioFile.path;
```

### 当前播放比较（特殊逻辑）

```dart
// 使用 downloadedPath 比较，因为文件扫描的 Track 没有数据库 ID
final isPlaying = currentTrack?.downloadedPath == track.downloadedPath;
```

---

## 9. 全屏播放器页 (PlayerPage)

### 功能模块

1. **AppBar**
   - 下拉关闭按钮
   - 音量控制（仅桌面）
   - 更多菜单（倍速、下载）

2. **封面图**
   - 使用 `TrackCover` 组件
   - 1:1 宽高比，带阴影

3. **歌曲信息**
   - 标题（最多2行）
   - 艺术家

4. **进度条**
   - **拖动时不触发 seek**
   - 只在 `onChangeEnd` 时调用 `seekToProgress`
   - 拖动过程中显示预览位置

5. **播放控制**
   - 顺序/乱序切换
   - 上一首/下一首
   - 播放/暂停（带 loading 状态）
   - 循环模式切换

### 进度条拖动实现

```dart
bool _isDragging = false;
double _dragProgress = 0.0;

Slider(
  value: _isDragging ? _dragProgress : state.progress.clamp(0.0, 1.0),
  onChangeStart: (value) {
    setState(() { _isDragging = true; _dragProgress = value; });
  },
  onChanged: (value) {
    setState(() => _dragProgress = value);  // 只更新本地状态
  },
  onChangeEnd: (value) {
    controller.seekToProgress(value);  // 只在这里触发 seek
    setState(() => _isDragging = false);
  },
)
```

---

## 10. 迷你播放器 (MiniPlayer)

### 功能模块

1. **主内容区**
   - 封面缩略图
   - 歌曲信息
   - 控制按钮：顺序/乱序、循环、上/下一首、播放/暂停
   - 桌面端音量控制

2. **可交互进度条**
   - 位于顶部，2px 高
   - 悬停时变为 4px 并显示圆形指示器
   - 支持点击跳转和拖动

3. **桌面端音量控制**
   - 宽屏：静音按钮 + 滑块
   - 窄屏：弹出式垂直滑块

### 进度条交互

```dart
// 点击跳转
onTapUp: (details) {
  final progress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
  controller.seekToProgress(progress);
}

// 拖动
onHorizontalDragUpdate: (details) {
  final progress = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
  setState(() => _dragProgress = progress);
}
onHorizontalDragEnd: (details) {
  controller.seekToProgress(_dragProgress);
}
```

---

## 11. 歌曲详情面板 (TrackDetailPanel)

### 功能（仅桌面端显示）

1. **封面图**（16:9，带时长标签）
2. **标题 + UP主信息**（头像、名称、发布日期）
3. **统计数据**（播放、点赞、收藏）
4. **下一首预览**（使用 `upcomingTracks.first`）
5. **简介**（可展开/收起）
6. **热门评论**（自动翻页 + 手动翻页 + 动画）

### 头像获取逻辑

```dart
Widget _buildAvatar(Track? track, VideoDetail detail) {
  // 1. 优先使用本地头像
  final localAvatarPath = track?.localAvatarPath;
  if (localAvatarPath != null) {
    return CircleAvatar(backgroundImage: FileImage(File(localAvatarPath)));
  }
  // 2. 回退到网络头像
  if (detail.ownerFace.isNotEmpty) {
    return CircleAvatar(backgroundImage: NetworkImage(detail.ownerFace));
  }
  // 3. 占位符
  return CircleAvatar(child: Icon(Icons.person));
}
```

### 评论自动翻页逻辑

```dart
// 每10秒自动翻页（仅在可见时）
Timer.periodic(const Duration(seconds: 10), (timer) {
  if (_isVisible()) {
    _goToNext(wrap: true);  // wrap=true 表示到末尾回到第一条
  }
});
```

---

## 12. 音频设置页 (AudioSettingsPage)（2026-02 新增）

### 功能概述

用户可配置的音频质量设置，包括全局音质等级和各音源的格式/流类型优先级。

### 功能模块

1. **全局音质等级**
   - 标题："全局音质等级"
   - 提示："适用于所有音源"
   - 选项：高（最高码率）、中（平衡音质与流量）、低（省流量）
   - 使用 `RadioGroup<AudioQualityLevel>` 实现

2. **YouTube 格式优先级**
   - 标题："YouTube 格式优先级"
   - 提示："仅对 YouTube 生效，按顺序尝试第一个可用格式"
   - 选项：Opus (WebM)、AAC (MP4)
   - 使用 `ReorderableListView` 实现拖拽排序
   - **注意**：Bilibili 只支持 AAC，此设置对 Bilibili 无影响

3. **YouTube 流优先级**
   - 标题："YouTube 流优先级"
   - 选项：纯音频流（省流量）、混合流（兼容性好）、HLS 流（分段，适合直播）
   - 使用 `ReorderableListView` 实现拖拽排序

4. **Bilibili 流优先级**
   - 标题："Bilibili 流优先级"
   - 选项：纯音频流（DASH）、混合流（durl）
   - 使用 `ReorderableListView` 实现拖拽排序
   - **注意**：Bilibili 直播始终是混合流

### 关键组件

```dart
// 音质等级选择
class _QualityLevelSection extends StatelessWidget {
  // 使用 RadioGroup + RadioListTile
}

// 格式优先级（可拖拽）
class _FormatPrioritySection extends StatelessWidget {
  // 使用 ReorderableListView.builder
  // 每项有拖拽手柄 + 序号 + 名称 + 描述
}

// 流类型优先级（可拖拽）
class _StreamPrioritySection extends StatelessWidget {
  // 参数化支持不同音源（YouTube/Bilibili）
  // availableTypes 限制可用选项
}
```

### 数据流

```dart
// 读取设置
final audioSettings = ref.watch(audioSettingsProvider);

// 更新设置
ref.read(audioSettingsProvider.notifier).setQualityLevel(level);
ref.read(audioSettingsProvider.notifier).setFormatPriority(newPriority);
ref.read(audioSettingsProvider.notifier).setYoutubeStreamPriority(newPriority);
ref.read(audioSettingsProvider.notifier).setBilibiliStreamPriority(newPriority);
```

---

## 响应式布局 (ResponsiveScaffold)

### 三种布局

| 布局 | 宽度 | 导航 | 详情面板 |
|------|------|------|----------|
| Mobile | < 600dp | 底部 NavigationBar | 无 |
| Tablet | 600-840dp | 侧边 NavigationRail | 无 |
| Desktop | > 840dp | 可收起侧边导航 | 有（可拖动宽度） |

### 桌面端三栏布局

```dart
Row(
  children: [
    // 左侧导航（可收起，72px/256px）
    AnimatedAlign(...),
    VerticalDivider(),
    // 中间主内容
    Expanded(flex: 2, child: widget.child),
    // 右侧详情面板（仅有歌曲时显示）
    if (hasTrack) ...[
      // 可拖动分割线
      GestureDetector(onHorizontalDragUpdate: ...),
      // 详情面板（280-500px）
      SizedBox(width: _detailPanelWidth, child: TrackDetailPanel()),
    ],
  ],
)
```
