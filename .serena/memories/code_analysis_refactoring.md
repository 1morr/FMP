# FMP 代码分析与重构计划

## 分析日期: 2026-01-11

## 一、下载系统评估

### 架构：✅ 整体设计合理
- 清晰的分层：Repository → Service → Provider → UI
- Stream 监听任务变化，响应式更新
- 进度节流优化，避免 Windows 线程问题

### 待优化：
1. `_scheduleDownloads` 每 500ms 轮询 → 改为事件驱动
2. `_startDownload` 是 void async → 改为 Future<void>
3. 缺少断点续传支持
4. TrackRepository 被创建两次实例

## 二、UI 重复代码

### 🔴 高优先级重复

| 模式 | 重复次数 | 文件数 |
|------|----------|--------|
| 封面图片构建 | 10+ | 6 |
| 时长格式化 | 7 | 5 |
| TrackGroup 分组 | 2 (完整复制) | 2 |
| SnackBar 调用 | 30+ | 10+ |

### 涉及文件：
- `mini_player.dart` - _buildThumbnailImage
- `player_page.dart` - _buildCoverImage
- `queue_page.dart` - _buildThumbnail
- `track_detail_panel.dart` - _buildCoverImage, _buildMainCover, _buildTrackCover
- `downloaded_category_page.dart` - _buildThumbnail (2处), _GroupHeader, _DownloadedTrackTile
- `playlist_detail_page.dart` - Image.network, _GroupHeader, _TrackListTile

## 三、重构计划

### 已创建的共享组件：

1. **TrackThumbnail** (`lib/ui/widgets/track_thumbnail.dart`)
   - 统一封面图片显示逻辑
   - 支持本地封面优先、网络回退、占位符
   - 支持播放中指示器

2. **DurationFormatter** (`lib/core/utils/duration_formatter.dart`)
   - formatMs(int ms) → "mm:ss"
   - formatLong(Duration) → "X 小时 Y 分钟"

3. **TrackExtensions** (`lib/core/extensions/track_extensions.dart`)
   - localCoverPath getter
   - formattedDuration getter

### 重构完成文件：✅
- [x] queue_page.dart
- [x] mini_player.dart  
- [x] player_page.dart
- [x] track_detail_panel.dart
- [x] downloaded_category_page.dart
- [x] playlist_detail_page.dart
- [x] search_page.dart

### Code Simplifier 修复完成：✅
- [x] TrackThumbnail 改用 TrackExtensions.localCoverPath
- [x] 提取 getVolumeIcon 到 lib/core/utils/icon_helpers.dart
- [x] 提取 TrackGroup 到 lib/ui/widgets/track_group/track_group.dart
- [x] 简化 player_page.dart 的 LoopMode switch 语句
- [x] 修复多余空行（queue_page, track_detail_panel）

## 四、Code Simplifier 审查发现 (2026-01-11)

### 🔴 高优先级

**1. downloaded_category_page 与 playlist_detail_page 大量重复**
- `_TrackGroup` 类 - 完全相同 (lines 421-431 / 484-494)
- `_groupTracks()` 方法 - 几乎相同 (lines 335-358 / 93-116)
- `_GroupHeader` 组件 - 结构相似
- `_toggleGroup()` / `_addAllToQueue()` - 相同实现

建议提取到：
```
lib/ui/widgets/track_group/
  ├── track_group.dart          # _TrackGroup 数据类
  ├── track_group_header.dart   # GroupHeader 组件
  └── grouped_track_list.dart   # 分组逻辑
```

### 🟡 中优先级

**2. TrackThumbnail 未使用 TrackExtensions**
- `track_thumbnail.dart` 第 69-84 行本地封面检测逻辑
- 与 `TrackExtensions.localCoverPath` 完全相同
- 建议改用 `track.localCoverPath` 扩展

**3. _getVolumeIcon 方法重复**
- `mini_player.dart:469-477`
- `player_page.dart:446-454`
- 建议提取到 `lib/core/utils/icon_helpers.dart`

### 🟢 低优先级

**4. 代码风格问题**
- `queue_page.dart:363` - 类结束前多余空行
- `player_page.dart:480` - 类结束前多余空行
- `track_detail_panel.dart:423` - 类结束前多余空行

**5. player_page.dart LoopMode switch 冗长**
- 第 457-478 行有两个独立的 switch 语句
- 建议合并为 mini_player.dart 的模式：
```dart
final (icon, tooltip) = switch (state.loopMode) {
  LoopMode.none => (Icons.repeat, '不循环'),
  LoopMode.all => (Icons.repeat, '列表循环'),
  LoopMode.one => (Icons.repeat_one, '单曲循环'),
};
```

**6. queue_page.dart:36-42 条件初始化可简化**
```dart
// 当前
if (autoScroll && currentIndex > 0) {
  _scrollController = ScrollController(initialScrollOffset: offset);
} else {
  _scrollController = ScrollController();
}

// 建议
final offset = (autoScroll && currentIndex > 0) ? calculated : 0.0;
_scrollController = ScrollController(initialScrollOffset: offset);
```

## 五、注意事项

### 封面图片优先级：
1. 本地封面 (track.downloadedPath → parent/cover.jpg)
2. 网络封面 (track.thumbnailUrl)
3. 占位符 (Icons.music_note, centered)

### 播放指示器：
使用 NowPlayingIndicator 组件，覆盖在封面上方
