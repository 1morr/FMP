# 下载管理系统 - 实现完成

## 实现状态
✅ **全部 5 个阶段已完成** (2026-01-11)

## 已实现的功能

### Phase 1: 核心下载功能
- ✅ DownloadTask 模型 (添加 playlistDownloadTaskId, priority 字段)
- ✅ PlaylistDownloadTask 模型
- ✅ Settings 扩展 (maxConcurrentDownloads, downloadImageOption)
- ✅ DownloadRepository (CRUD, 流监听)
- ✅ DownloadService (下载调度、并发控制、文件管理)
- ✅ 设置页面扩展 (下载管理入口、下载路径显示、并发数、图片选项)

### Phase 2: 下载管理页面
- ✅ DownloadManagerPage (lib/ui/pages/settings/download_manager_page.dart)
- ✅ 任务列表按状态分组显示
- ✅ 进度条和状态图标
- ✅ 暂停/继续/删除/重试操作
- ✅ 批量操作 (全部暂停/全部继续/清空队列)

### Phase 3: 歌单下载支持
- ✅ playlist_detail_page.dart 添加"下载全部"按钮
- ✅ 分组标题菜单添加"下载全部分P"选项
- ✅ 单曲菜单添加"下载"选项
- ✅ search_page.dart 添加下载选项（视频和分P）

### Phase 4: 已下载页面
- ✅ DownloadedPage (lib/ui/pages/library/downloaded_page.dart)
- ✅ 按 groupKey 分组显示（支持多P视频展开）
- ✅ 本地封面加载（回退到网络封面）
- ✅ 删除下载功能
- ✅ 播放/添加到队列/添加到歌单操作
- ✅ library_page.dart 添加"已下载"卡片入口

### Phase 5: 完善功能
- ✅ player_page.dart 添加下载菜单选项
- ✅ 程序重启恢复 (DownloadService.initialize 重置 downloading → paused)
- ✅ TrackRepository 添加 getDownloaded/watchDownloaded/clearDownloadPath

## 文件结构

### 新增文件
- lib/data/models/playlist_download_task.dart
- lib/data/repositories/download_repository.dart
- lib/services/download/download_service.dart
- lib/providers/download_provider.dart
- lib/ui/pages/settings/download_manager_page.dart
- lib/ui/pages/library/downloaded_page.dart

### 修改文件
- lib/data/models/download_task.dart (添加字段)
- lib/data/models/settings.dart (添加下载设置)
- lib/data/models/models.dart (导出新模型)
- lib/data/repositories/track_repository.dart (添加下载相关方法)
- lib/providers/database_provider.dart (注册新集合)
- lib/ui/router.dart (添加路由)
- lib/ui/pages/settings/settings_page.dart (添加存储设置区块)
- lib/ui/pages/library/library_page.dart (添加已下载卡片)
- lib/ui/pages/library/playlist_detail_page.dart (添加下载选项)
- lib/ui/pages/search/search_page.dart (添加下载选项)
- lib/ui/pages/player/player_page.dart (添加下载菜单)
- pubspec.yaml (添加 path 依赖)

## 路由
- `/library/downloaded` → DownloadedPage
- `/settings/download-manager` → DownloadManagerPage

## 关键设计决策
1. 下载文件存储在 `{下载路径}/{歌单名}_{歌单ID}/{视频标题}/` 目录
2. 每个视频文件夹包含 metadata.json 和 cover.jpg
3. 使用全角字符替换文件名中的特殊字符
4. 程序重启时将 downloading 状态的任务重置为 paused
5. 已下载页面优先加载本地封面，回退到网络封面
