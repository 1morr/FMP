# FMP 代码分析与重构计划

## 分析日期: 2026-01-11

## 一、下载系统评估

### 架构：✅ 整体设计合理
- 清晰的分层：Repository → Service → Provider → UI
- Stream 监听任务变化，响应式更新
- 进度节流优化，避免 Windows 线程问题

### 待优化（未实施）：
1. ⏸️ `_scheduleDownloads` 每 500ms 轮询 → 改为事件驱动
2. ⏸️ `_startDownload` 是 void async → 改为 Future<void>
3. ⏸️ 缺少断点续传支持
4. ⏸️ TrackRepository 被创建两次实例

## 二、UI 重复代码

### 高优先级重复 - 完成状态

| 模式 | 重复次数 | 文件数 | 状态 |
|------|----------|--------|------|
| 封面图片构建 | 10+ | 7 | ✅ 已统一到 TrackThumbnail |
| 时长格式化 | 7 | 5 | ✅ 已统一到 DurationFormatter |
| TrackGroup 分组 | 2 | 2 | ✅ 已提取到共享组件 |
| _getVolumeIcon | 2 | 2 | ✅ 已提取到 icon_helpers.dart |
| SnackBar 调用 | 48→20 | 10+ | 🔄 已统一大部分到 ToastService |

### 已重构文件：✅
- `mini_player.dart` - 使用 TrackThumbnail, getVolumeIcon
- `player_page.dart` - 使用 TrackCover, DurationFormatter, getVolumeIcon
- `queue_page.dart` - 使用 TrackThumbnail, DurationFormatter
- `track_detail_panel.dart` - 使用 TrackCover, TrackThumbnail
- `downloaded_category_page.dart` - 使用 TrackThumbnail, DurationFormatter, TrackGroup
- `playlist_detail_page.dart` - 使用 TrackThumbnail, DurationFormatter, TrackGroup
- `search_page.dart` - 使用 TrackThumbnail, DurationFormatter

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

### ✅ 高优先级 - 已完成

**1. downloaded_category_page 与 playlist_detail_page 大量重复** ✅
- [x] `_TrackGroup` 类 → 提取到 `lib/ui/widgets/track_group/track_group.dart`
- [x] `_groupTracks()` 方法 → 提取到 `groupTracks()` 共享函数
- [ ] `_GroupHeader` 组件 - 保留各自实现（菜单选项不同）
- [ ] `_toggleGroup()` / `_addAllToQueue()` - 保留各自实现（依赖不同）

### ✅ 中优先级 - 已完成

**2. TrackThumbnail 未使用 TrackExtensions** ✅
- [x] 已改用 `track.localCoverPath` 扩展

**3. _getVolumeIcon 方法重复** ✅
- [x] 已提取到 `lib/core/utils/icon_helpers.dart`
- [x] mini_player.dart 和 player_page.dart 已更新使用共享方法

### ✅ 低优先级 - 已完成

**4. 代码风格问题** ✅
- [x] `queue_page.dart` - 已修复多余空行
- [x] `player_page.dart` - 已修复（在简化 switch 时一并修复）
- [x] `track_detail_panel.dart` - 已修复多余空行

**5. player_page.dart LoopMode switch 冗长** ✅
- [x] 已简化为 switch 表达式

**6. queue_page.dart:36-42 条件初始化可简化** ⏸️
- [ ] 保留现状（可读性优先，改动收益较小）

## 五、注意事项

### 封面图片优先级：
1. 本地封面 (track.downloadedPath → parent/cover.jpg)
2. 网络封面 (track.thumbnailUrl)
3. 占位符 (Icons.music_note, centered)

### 播放指示器：
使用 NowPlayingIndicator 组件，覆盖在封面上方
