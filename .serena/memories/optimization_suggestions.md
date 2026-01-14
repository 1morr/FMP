# FMP 待优化项

## 架构优化

### 1. Provider 拆分
`download_provider.dart` 职责过大，建议拆分为：
- `download_state.dart` - 纯状态定义
- `download_notifier.dart` - 状态更新逻辑

### 2. 文件扫描异步化
`scanDownloadedCategories` 在大量下载时可能阻塞 UI，建议使用 `compute()` 隔离。

## 性能优化

### 1. 本地图片内存缓存
```dart
class LocalImageCache {
  static final _cache = LruCache<String, ImageProvider>(maxSize: 100);
  static ImageProvider getLocalImage(String path) {
    return _cache.putIfAbsent(path, () => FileImage(File(path)));
  }
}
```

### 2. 列表性能
Multi-P 分组计算在 build 中执行，大型播放列表可能卡顿。
建议使用 `useMemoized` 缓存分组结果。

## 代码质量

### 1. 常量提取
魔法数字分散，建议创建 `AppConstants`：
```dart
class AppConstants {
  static const maxConcurrentDownloads = 3;
  static const progressThrottleInterval = Duration(milliseconds: 500);
  static const defaultSeekBackSeconds = 10;
}
```

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