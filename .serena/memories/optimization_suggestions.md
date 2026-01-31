# FMP 待优化项

## 架构优化

### 1. Provider 拆分 ✅ 已完成
`download_provider.dart` 已拆分为：
- `download_state.dart` - 纯状态定义
- `download_scanner.dart` - 文件扫描工具
- `file_exists_cache.dart` - 文件存在性缓存
- `download_providers.dart` - Provider 定义

### 2. 文件扫描异步化 ✅ 已完成
`downloadedCategoriesProvider` 已使用 `Isolate.run()` 在单独 isolate 中执行文件扫描。

## 性能优化

### 1. 本地图片内存缓存 ✅ 已实现
> 已实现于 `lib/core/services/local_image_cache.dart`，集成到 `ImageLoadingService` 中使用。

### 2. 列表性能 ✅ 已优化
Multi-P 分组计算已在 `playlist_detail_page.dart` 中使用 `_cachedGroups` 缓存。

### 3. 数据库查询优化 ✅ 已完成
`Track.updatedAt` 添加索引，优化已下载排序查询。

### 4. 启动时间优化 ✅ 已完成
Windows 平台 SMTC 和 WindowManager 初始化已并行化。

## 代码质量

### 1. 常量提取 ✅ 已完成
魔法数字已提取到 `lib/core/constants/app_constants.dart`

### 2. 测试覆盖
建议添加：
- `TrackExtensions` 路径计算测试
- `DownloadService` 任务调度测试
- `QueueManager` 队列操作测试

## 用户体验

### 1. 加载状态
添加 shimmer 骨架屏效果

### 2. 离线模式增强
- 网络状态监听
- 离线时自动切换本地内容
- 显示离线状态指示器