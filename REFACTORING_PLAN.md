# FMP 代码优化与重构计划

> 基于代码分析生成的综合重构计划
> 最后更新: 2026-01-12

---

## 目录

1. [项目现状](#一项目现状)
2. [已完成工作](#二已完成工作)
3. [待优化任务](#三待优化任务)
4. [实施计划](#四实施计划)
5. [技术方案详情](#五技术方案详情)
6. [注意事项](#六注意事项)

---

## 一、项目现状

### 架构评价

| 方面 | 评价 |
|------|------|
| 音频架构 | ✅ 三层架构清晰 (UI → Controller → Service) |
| 响应式布局 | ✅ 完善 (mobile/tablet/desktop) |
| 下载系统 | ✅ 合理 (并发控制、进度节流) |
| 图片优先级 | ✅ 正确 (本地 → 网络 → 占位符) |
| 代码复用 | ⚠️ 部分重复可消除 |
| 测试覆盖 | ❌ 缺少 |
| 错误处理 | ✅ 已标准化 |

### 重构进度

```
已完成: ████████████████████ 100%
进行中: ░░░░░░░░░░░░░░░░░░░░   0%
待开始: ░░░░░░░░░░░░░░░░░░░░   0%
```

---

## 二、已完成工作

### 共享组件 (5个)

| 组件 | 位置 | 使用文件数 | 状态 |
|------|------|-----------|------|
| TrackThumbnail | `lib/ui/widgets/track_thumbnail.dart` | 9 | ✅ |
| DurationFormatter | `lib/core/utils/duration_formatter.dart` | 8 | ✅ |
| getVolumeIcon | `lib/core/utils/icon_helpers.dart` | 3 | ✅ |
| TrackGroup | `lib/ui/widgets/track_group/track_group.dart` | 3 | ✅ |
| ToastService | `lib/core/services/toast_service.dart` | 15 | ✅ |

### 已修复问题

- ✅ **已下载页面重复显示问题** - 改为扫描本地文件而非依赖数据库

---

## 三、待优化任务

### 🔴 高优先级 (影响用户体验)

#### 1. 图片加载统一化
**问题：** `TrackThumbnail`、`FmpNetworkImage`、`track_detail_panel.dart` 各自实现图片加载逻辑

**方案：** 创建统一的 `ImageLoadingService`

**涉及文件：**
- `lib/ui/widgets/track_thumbnail.dart`
- `lib/ui/widgets/fmp_network_image.dart`
- `lib/ui/widgets/track_detail_panel.dart`

**工作量：** 中

---

#### 2. 本地图片内存缓存
**问题：** 本地图片每次都从文件系统读取，无缓存

**方案：** 实现 `LocalImageCache` 使用 LRU 缓存策略

**涉及文件：**
- 新建 `lib/core/services/local_image_cache.dart`

**工作量：** 小

---

#### 3. 列表性能优化
**问题：** `playlist_detail_page.dart` 中 Multi-P 分组计算在 build 中执行

**方案：** 使用 `useMemoized` 缓存分组结果

**涉及文件：**
- `lib/ui/pages/playlist_detail_page.dart`
- `lib/ui/pages/downloaded_category_page.dart`

**工作量：** 小

---

### 🟡 中优先级 (代码质量)

#### 4. 常量提取
**问题：** 魔法数字分散在代码中

**方案：** 创建 `AppConstants` 类集中管理

**示例：**
```dart
class AppConstants {
  static const commentScrollInterval = Duration(seconds: 10);
  static const maxConcurrentDownloads = 3;
  static const progressThrottleInterval = Duration(milliseconds: 500);
  static const defaultSeekBackSeconds = 10;
}
```

**涉及文件：**
- 新建 `lib/core/constants/app_constants.dart`
- 多处调用点需要更新

**工作量：** 小

---

#### 5. Provider 拆分
**问题：** `download_provider.dart` 职责过多

**方案：** 拆分为多个单一职责文件
```
download_provider.dart 拆分为：
├── download_state.dart      # 纯状态定义
├── download_notifier.dart   # 状态更新逻辑
├── download_scanner.dart    # 文件扫描逻辑
└── download_utils.dart      # 工具函数
```

**工作量：** 大

---

#### 6. 错误处理标准化
**问题：** 网络图片加载失败时处理不一致

**方案：**
- 创建统一的 `ErrorWidget` 组件
- 实现错误边界（ErrorBoundary）模式
- 添加错误日志记录

**工作量：** 中

---

### 🟢 低优先级 (长期改进)

#### 7. 测试覆盖

**单元测试：**
- [ ] `TrackExtensions` 路径计算逻辑
- [ ] `DownloadService` 任务调度逻辑
- [ ] `QueueManager` 队列操作

**Widget 测试：**
- [ ] `TrackThumbnail` 图片加载优先级
- [ ] `MiniPlayer` 进度条交互
- [ ] `TrackDetailPanel` 响应式行为

**集成测试：**
- [ ] 下载流程完整性
- [ ] 播放队列持久化
- [ ] 离线播放功能

**工作量：** 大

---

#### 8. 下载系统优化
- [ ] `_scheduleDownloads` 500ms 轮询 → 事件驱动
- [ ] `_startDownload` void async → Future<void>
- [ ] 断点续传支持
- [ ] TrackRepository 单例化

**工作量：** 大

---

#### 9. 离线模式增强
- [ ] 添加网络状态监听
- [ ] 离线时自动切换到本地内容
- [ ] 显示离线状态指示器

**工作量：** 中

---

#### 10. 类型安全增强
- [ ] 使用 `freezed` 或 `json_serializable` 生成模型
- [ ] 添加 JSON schema 验证
- [ ] 消除 `dynamic` 使用

**工作量：** 大

---

## 四、实施计划

### Phase 1: 性能优化 ✅
> 目标：提升用户体验

| 任务 | 优先级 | 状态 |
|------|--------|------|
| 本地图片缓存 | 🔴 高 | ✅ 已完成 |
| 列表性能优化 | 🔴 高 | ✅ 已完成 |
| 图片加载统一化 | 🔴 高 | ✅ 已完成 |

---

### Phase 2: 代码质量 ✅
> 目标：提高可维护性

| 任务 | 优先级 | 状态 |
|------|--------|------|
| 常量提取 | 🟡 中 | ✅ 已完成 |
| 错误处理标准化 | 🟡 中 | ✅ 已完成 |
| Provider 拆分 | 🟡 中 | ✅ 已完成 |

---

### Phase 3: 基础设施
> 目标：长期稳定性

| 任务 | 优先级 | 状态 |
|------|--------|------|
| 单元测试 | 🟢 低 | ⬜ 待开始 |
| Widget 测试 | 🟢 低 | ⬜ 待开始 |
| 下载系统优化 | 🟢 低 | ⬜ 待开始 |
| 离线模式增强 | 🟢 低 | ⬜ 待开始 |

---

## 五、技术方案详情

### 5.1 图片加载服务

```dart
// lib/core/services/image_loading_service.dart
class ImageLoadingService {
  Widget loadImage({
    required String? localPath,
    required String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    Map<String, String>? headers,
  });

  Widget loadTrackCover(Track track, {double? size});
  Widget loadAvatar(String? localPath, String? networkUrl, {double? size});
}
```

### 5.2 本地图片缓存

```dart
// lib/core/services/local_image_cache.dart
class LocalImageCache {
  static final _cache = LruCache<String, ImageProvider>(maxSize: 100);

  static ImageProvider getLocalImage(String path) {
    return _cache.putIfAbsent(path, () => FileImage(File(path)));
  }
}
```

### 5.3 列表优化

```dart
// 使用 useMemoized 缓存分组结果
final groups = useMemoized(
  () => _groupTracks(tracks),
  [tracks],
);
```

### 5.4 文件扫描优化

```dart
// 使用 compute 隔离计算
Future<List<DownloadedCategory>> scanCategories() async {
  return compute(_scanInIsolate, downloadPath);
}
```

### 5.5 图片占位符统一

```dart
// lib/ui/widgets/image_placeholder.dart
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

### 5.6 重试机制

```dart
// 图片重试
class RetryableImage extends StatefulWidget {
  final int maxRetries;
  final Duration retryDelay;
}

// 下载重试策略
class DownloadRetryPolicy {
  static const maxRetries = 3;
  static const retryDelays = [1, 5, 15]; // 秒
}
```

---

## 六、注意事项

### 编码规范

1. **使用 Serena 工具进行代码修改**
   - `find_symbol` - 查找符号
   - `replace_symbol_body` - 替换整个符号
   - `replace_content` - 正则替换

2. **修改后更新相关 Memory**
   - `audio_system` - 音频相关变更
   - `architecture` - 架构变更
   - `code_style` - 代码风格变更

### 封面图片优先级规则

```
1. 本地封面 (track.downloadedPath → parent/cover.jpg)
2. 网络封面 (track.thumbnailUrl)
3. 占位符 (Icons.music_note, centered)
```

### 关键限制

- 播放指示器必须使用 `NowPlayingIndicator` 组件
- ToastService 仅用于 UI 层消息，`app_shell.dart` 流式 Toast 保持独立
- 进度条拖动只在 `onChangeEnd` 调用 seek，避免消息队列阻塞
- UI 必须通过 `AudioController`，禁止直接调用 `AudioService`

---

## 附录：文件结构

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_constants.dart     # ✅ 已创建 (Phase 2)
│   │   └── breakpoints.dart       # ✅ 已创建
│   ├── errors/
│   │   └── app_exception.dart     # ✅ 已创建 (Phase 2)
│   ├── services/
│   │   ├── toast_service.dart           # ✅ 已创建
│   │   ├── image_loading_service.dart   # ✅ 已创建 (Phase 1)
│   │   └── local_image_cache.dart       # ✅ 已创建 (Phase 1)
│   ├── utils/
│   │   ├── duration_formatter.dart    # ✅ 已创建
│   │   └── icon_helpers.dart          # ✅ 已创建
│   └── extensions/
│       └── track_extensions.dart      # ✅ 已创建
├── ui/
│   └── widgets/
│       ├── track_thumbnail.dart       # ✅ 已创建 (Phase 1 更新)
│       ├── track_group/               # ✅ 已创建
│       ├── error_display.dart         # ✅ 已创建 (Phase 2)
│       └── image_placeholder.dart     # ✅ 已包含在 image_loading_service.dart 中
└── providers/
    ├── download_provider.dart         # ✅ 重构为重导出文件 (Phase 2)
    └── download/                      # ✅ 已拆分 (Phase 2)
        ├── download_state.dart        # ✅ 已创建
        ├── download_providers.dart    # ✅ 已创建
        ├── download_scanner.dart      # ✅ 已创建
        └── download_extensions.dart   # ✅ 已创建
```

---

*本计划将根据实际开发进度持续更新*
