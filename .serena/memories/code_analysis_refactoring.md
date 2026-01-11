# FMP 代码分析与重构计划

## 最后更新: 2026-01-11

## 一、重构状态总览

| 组件 | 状态 | 使用文件数 |
|------|------|-----------|
| TrackThumbnail | ✅ 完成 | 9 |
| DurationFormatter | ✅ 完成 | 8 |
| getVolumeIcon | ✅ 完成 | 3 |
| TrackGroup | ✅ 完成 | 3 |
| ToastService | ✅ 完成 | 15 |

## 二、已创建的共享组件

### 1. TrackThumbnail (`lib/ui/widgets/track_thumbnail.dart`)
- 统一封面图片显示逻辑
- 支持本地封面优先、网络回退、占位符
- 支持播放中指示器
- **使用位置：**
  - mini_player.dart
  - player_page.dart (使用 TrackCover)
  - queue_page.dart
  - search_page.dart
  - track_detail_panel.dart
  - downloaded_category_page.dart
  - playlist_detail_page.dart
  - home_page.dart (正在播放、接下来播放)
  - add_to_playlist_dialog.dart

### 2. DurationFormatter (`lib/core/utils/duration_formatter.dart`)
- `formatMs(int ms)` → "mm:ss"
- `formatLong(Duration)` → "X 小时 Y 分钟"
- **使用位置：**
  - player_page.dart
  - queue_page.dart
  - search_page.dart
  - downloaded_category_page.dart
  - playlist_detail_page.dart
  - track_extensions.dart

### 3. TrackExtensions (`lib/core/extensions/track_extensions.dart`)
- `localCoverPath` getter - 获取本地封面路径
- `formattedDuration` getter - 格式化时长

### 4. getVolumeIcon (`lib/core/utils/icon_helpers.dart`)
- 根据音量返回对应图标
- **使用位置：** mini_player.dart, player_page.dart

### 5. TrackGroup (`lib/ui/widgets/track_group/track_group.dart`)
- 分组逻辑和数据结构
- `groupTracks()` 共享函数
- **使用位置：** downloaded_category_page.dart, playlist_detail_page.dart

### 6. ToastService (`lib/core/services/toast_service.dart`)
- `show()` - 普通消息
- `success()` - 成功消息（绿色图标）
- `error()` - 错误消息（红色图标）
- `warning()` - 警告消息（橙色图标）
- **使用位置：** 15个文件，48+ 处调用

## 三、遗留项（低优先级）

### 内联图片构建（已处理）
- ✅ home_page.dart - 已转换为 TrackThumbnail
- ✅ add_to_playlist_dialog.dart - Track 封面已转换，歌单封面添加了 errorBuilder

### 模型层时长格式化（保留）
- `track.dart:formattedDuration` - 模型层格式化
- `video_detail.dart:formattedDuration` - 详情面板格式化
- 与 UI 层 DurationFormatter 职责不同，无需统一

## 四、已修复问题

### 已下载页面重复显示问题 (2026-01-11)
**问题：** 打开已下载歌单时，同一个视频显示为多个分P（2个变3个）
**根本原因：** 
- `QueueManager.copyForQueue()` 创建无ID的 Track 副本
- 每次添加到播放队列都产生新的数据库记录
- `downloadedCategoryTracksProvider` 查询数据库返回所有重复记录

**解决方案：**
- 已下载页面改为扫描本地文件，不依赖数据库
- `downloadedCategoriesProvider` - 扫描下载目录获取分类文件夹
- `downloadedCategoryTracksProvider` - 扫描文件夹内的 .m4a 文件
- `_scanFolderForTracks()` - 读取 metadata.json 创建 Track 对象
- `_trackFromMetadata()` - 从 metadata 解析 Track

**关键代码位置：** `lib/providers/download_provider.dart`

## 五、下载系统待优化（未实施）

1. ⏸️ `_scheduleDownloads` 每 500ms 轮询 → 改为事件驱动
2. ⏸️ `_startDownload` 是 void async → 改为 Future<void>
3. ⏸️ 缺少断点续传支持
4. ⏸️ TrackRepository 被创建两次实例

## 六、封面图片优先级规则

1. 本地封面 (track.downloadedPath → parent/cover.jpg)
2. 网络封面 (track.thumbnailUrl)
3. 占位符 (Icons.music_note, centered)

## 七、注意事项

- 播放指示器使用 NowPlayingIndicator 组件
- ToastService 仅用于 UI 层消息，app_shell.dart 的流式 Toast 系统保持独立
- 编辑代码时优先使用 Serena 符号编辑工具