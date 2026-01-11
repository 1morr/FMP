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

### 待重构文件：
- [ ] search_page.dart (可选)

## 四、注意事项

### 封面图片优先级：
1. 本地封面 (track.downloadedPath → parent/cover.jpg)
2. 网络封面 (track.thumbnailUrl)
3. 占位符 (Icons.music_note, centered)

### 播放指示器：
使用 NowPlayingIndicator 组件，覆盖在封面上方
