# FMP 优化与重构建议

## 一、架构层面优化

### 1. 状态管理优化

**当前问题：**
- Provider 文件过大（如 `download_provider.dart` 包含文件扫描、状态管理、业务逻辑）
- 部分 Provider 职责不够单一

**建议：**
```
download_provider.dart 拆分为：
├── download_state.dart      # 纯状态定义
├── download_notifier.dart   # 状态更新逻辑
├── download_scanner.dart    # 文件扫描逻辑（可复用）
└── download_utils.dart      # 工具函数
```

### 2. 图片加载统一化

**当前问题：**
- `TrackThumbnail`、`FmpNetworkImage`、`track_detail_panel.dart` 各自实现图片加载逻辑
- 头像、封面、缩略图处理分散

**建议：**
创建统一的图片加载服务：
```dart
class ImageLoadingService {
  Widget loadImage({
    required String? localPath,
    required String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    Map<String, String>? headers,
  });
  
  // 专用方法
  Widget loadTrackCover(Track track, {double? size});
  Widget loadAvatar(String? localPath, String? networkUrl, {double? size});
}
```

### 3. 错误处理标准化

**当前问题：**
- 网络图片加载失败时处理不一致
- 部分地方静默失败，部分地方显示占位符

**建议：**
- 创建统一的 `ErrorWidget` 组件
- 实现错误边界（ErrorBoundary）模式
- 记录错误日志便于调试

## 二、性能优化

### 1. 图片缓存优化

**当前问题：**
- 网络图片依赖 `cached_network_image` 默认配置
- 本地图片每次都从文件系统读取

**建议：**
```dart
// 添加本地图片内存缓存
class LocalImageCache {
  static final _cache = LruCache<String, ImageProvider>(maxSize: 100);
  
  static ImageProvider getLocalImage(String path) {
    return _cache.putIfAbsent(path, () => FileImage(File(path)));
  }
}
```

### 2. 列表性能优化

**当前问题：**
- `playlist_detail_page.dart` 中 Multi-P 分组计算在 build 中执行
- 大型播放列表可能导致卡顿

**建议：**
```dart
// 使用 useMemoized 缓存分组结果
final groups = useMemoized(
  () => _groupTracks(tracks),
  [tracks],
);
```

### 3. 文件扫描优化

**当前问题：**
- `scanDownloadedCategories` 同步扫描文件系统
- 大量下载内容时可能阻塞 UI

**建议：**
```dart
// 使用 compute 隔离计算
Future<List<DownloadedCategory>> scanCategories() async {
  return compute(_scanInIsolate, downloadPath);
}
```

## 三、代码质量改进

### 1. 常量提取

**当前问题：**
- 魔法数字分散在代码中（如 `Duration(seconds: 10)`、`maxConcurrentDownloads: 3`）

**建议：**
```dart
// lib/core/constants/app_constants.dart
class AppConstants {
  static const commentScrollInterval = Duration(seconds: 10);
  static const maxConcurrentDownloads = 3;
  static const progressThrottleInterval = Duration(milliseconds: 500);
  static const progressThrottlePercentage = 0.05;
  static const defaultSeekBackSeconds = 10;
}
```

### 2. 扩展方法整理

**当前问题：**
- `track_extensions.dart` 中的路径逻辑与文件系统紧耦合

**建议：**
- 将文件存在性检查抽象为接口，便于测试
- 考虑缓存路径检查结果（文件不会频繁变化）

### 3. 类型安全增强

**当前问题：**
- 部分地方使用 `dynamic` 或 `Object?`
- JSON 解析缺少类型验证

**建议：**
- 使用 `freezed` 或 `json_serializable` 生成类型安全的模型
- 添加 JSON schema 验证

## 四、用户体验优化

### 1. 加载状态改进

**当前问题：**
- 图片加载时显示空白或占位符
- 缺少加载进度指示

**建议：**
- 添加 shimmer 骨架屏效果
- 渐进式图片加载（先模糊后清晰）

### 2. 错误恢复机制

**当前问题：**
- 网络图片加载失败后无法重试
- 下载失败需要手动重新开始

**建议：**
```dart
// 图片重试机制
class RetryableImage extends StatefulWidget {
  final int maxRetries;
  final Duration retryDelay;
  // ...
}

// 下载自动重试
class DownloadRetryPolicy {
  static const maxRetries = 3;
  static const retryDelays = [1, 5, 15]; // 秒
}
```

### 3. 离线模式增强

**当前问题：**
- 网络不可用时部分功能不可用
- 缺少明确的离线状态提示

**建议：**
- 添加网络状态监听
- 离线时自动切换到本地内容
- 显示离线状态指示器

## 五、代码重复消除

### 1. 图片占位符统一

**当前问题：**
- 多处实现相似的占位符 Widget
- 颜色、图标不一致

**建议：**
```dart
class ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? backgroundColor;
  final Color? iconColor;
  
  const ImagePlaceholder.track({...});
  const ImagePlaceholder.avatar({...});
  const ImagePlaceholder.category({...});
}
```

### 2. 列表项组件抽象

**当前问题：**
- `TrackListTile` 在不同页面有细微变化
- 重复的 onTap、onLongPress 逻辑

**建议：**
- 创建可配置的 `TrackListTile` 变体
- 使用 Builder 模式处理不同场景

## 六、测试覆盖

### 建议添加的测试：

1. **单元测试：**
   - `TrackExtensions` 路径计算逻辑
   - `DownloadService` 任务调度逻辑
   - `QueueManager` 队列操作

2. **Widget 测试：**
   - `TrackThumbnail` 图片加载优先级
   - `MiniPlayer` 进度条交互
   - `TrackDetailPanel` 响应式行为

3. **集成测试：**
   - 下载流程完整性
   - 播放队列持久化
   - 离线播放功能

## 七、优先级建议

### 高优先级（影响用户体验）：
1. 图片加载统一化
2. 本地图片缓存
3. 列表性能优化

### 中优先级（代码质量）：
1. 常量提取
2. Provider 拆分
3. 错误处理标准化

### 低优先级（长期改进）：
1. 测试覆盖
2. 类型安全增强
3. 离线模式增强

## 八、当前架构评价

**优点：**
- 三层音频架构清晰（UI → Controller → Service）
- 响应式布局设计完善（mobile/tablet/desktop）
- 下载系统设计合理（并发控制、进度节流）
- 图片优先级逻辑正确（本地 → 网络 → 占位符）

**改进空间：**
- 部分组件职责过大
- 代码重复可进一步消除
- 缺少测试覆盖
- 错误处理可更标准化

**总体评价：** 
当前架构设计合理，主要系统逻辑正确。建议的优化主要是代码质量和性能层面的增量改进，而非架构重构。
